import AppKit
import CoreAudio
import Darwin
import OSLog
import Observation
import WispCore

/// Per-app volume: lists the apps playing sound and plays the ones turned down through a
/// `ProcessTap`. Runs only while the switch is on; apps at full volume are never tapped.
/// CoreAudio's process list is followed through a listener. Who's playing is polled only
/// while a tap exists, or slowly while the list is on screen.
@MainActor
@Observable
final class AppVolumeStore {
    private(set) var rows: [AppVolumeRow] = []
    /// Whether the taps can hear apps; see `SystemAudioHearing`.
    private(set) var canHear: Bool? {
        didSet { SystemAudioPermission.status = canHear }
    }
    /// False on macOS before 14.2, which has no process taps.
    let isSupported: Bool

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var processes: [AudioProcess] = []
    @ObservationIgnored private var cache = AudioAppCache()
    @ObservationIgnored private var taps: [String: ProcessTap] = [:]
    /// Taps CoreAudio refused, so they're tried again only when the app's processes change.
    @ObservationIgnored private var refused: [String: Set<UInt32>] = [:]
    @ObservationIgnored private var outputUID: String?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var outputListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var listListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var names: [String: String] = [:]
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    /// Lists on screen; while any is, who's playing is refreshed even with no taps.
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "app-volume")
    /// While a tap exists: soon enough to start its IO shortly after the app starts playing.
    private static let tapInterval = 0.5
    /// While only the list is on screen, or nothing needs checking.
    private static let listInterval = 2.0

    init(preferences: Preferences) {
        self.preferences = preferences
        if #available(macOS 14.2, *) { isSupported = true } else { isSupported = false }
    }

    func start() {
        guard isSupported, pollTask == nil else { return }
        outputUID = Self.defaultOutputUID()
        let system = AudioObjectID(kAudioObjectSystemObject)
        // A new output device needs every tap rebuilt on it.
        let outputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
        self.outputListener = outputListener
        var outputAddress = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(system, &outputAddress, .main, outputListener)
        let listListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshList() }
        }
        self.listListener = listListener
        var listAddress = Self.processListAddress
        AudioObjectAddPropertyListenerBlock(system, &listAddress, .main, listListener)
        refreshList()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.tick() ?? Self.listInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Takes every tap down, so each app plays directly again, and forgets what was learned.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let outputListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, outputListener)
            self.outputListener = nil
        }
        if let listListener {
            var address = Self.processListAddress
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, listListener)
            self.listListener = nil
        }
        removeAllTaps()
        refused = [:]
        processes = []
        cache = AudioAppCache()
        rows = []
        canHear = nil
    }

    /// The list came on screen: refresh who's playing now, and keep doing so while it shows.
    func listAppeared() {
        viewers += 1
        guard pollTask != nil else { return }
        refreshPlaying(all: true)
    }

    func listDisappeared() { viewers = max(viewers - 1, 0) }

    func setLevel(_ level: Double, for app: String) {
        preferences.appVolumeSettings.setLevel(level, for: app)
        apply()
    }

    func toggleMute(_ app: String) {
        let settings = preferences.appVolumeSettings
        preferences.appVolumeSettings.setMuted(!settings.isMuted(app), for: app)
        apply()
    }

    func reset(_ app: String) {
        preferences.appVolumeSettings.reset(app)
        apply()
    }

    func icon(for app: String) -> NSImage? {
        if let icon = icons[app] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[app] = icon
        return icon
    }

    // MARK: Updates

    /// One pass of the loop; returns the seconds until the next.
    private func tick() -> Double {
        if !taps.isEmpty {
            refreshPlaying(all: viewers > 0)
            checkTaps(seconds: Self.tapInterval)
            return Self.tapInterval
        }
        if viewers > 0 { refreshPlaying(all: true) }
        return Self.listInterval
    }

    /// Runs each tap's IO while its app plays, hands sound over once a tap hears it, and takes
    /// down taps that failed or went quiet while their app played.
    private func checkTaps(seconds: Double) {
        var armed = 0
        var silent = 0
        var dropped: [String] = []
        for tap in taps.values {
            let playing = processes.contains { $0.appID == tap.app && $0.isPlaying }
            switch tap.update(appPlaying: playing, seconds: seconds) {
            case .armed: armed += 1
            case .silent: silent += 1
            case .lost:
                log.notice("a tap stopped hearing its app; letting the app play directly")
                dropped.append(tap.app)
            case .listening: break
            }
            if tap.failed {
                refused[tap.app] = tap.processes
                dropped.append(tap.app)
            }
        }
        for app in dropped { removeTap(app) }
        // Rebuilds a lost tap unmuted, to listen again.
        if !dropped.isEmpty { apply() }
        if let hearing = SystemAudioHearing.status(armed: armed, silent: silent), hearing != canHear {
            canHear = hearing
        }
    }

    /// CoreAudio's process list changed: resolve new processes (cached), then refresh.
    private func refreshList() {
        let objects = Self.processObjects()
        cache.keep(objects: Set(objects))
        let playing = Dictionary(processes.map { ($0.objectID, $0.isPlaying) }, uniquingKeysWith: { first, _ in first })
        processes = objects.map { object in
            let pid: pid_t = SystemVolume.read(object, ProcessTapAddress.global(kAudioProcessPropertyPID)) ?? 0
            let app = cache.appID(object: object, pid: pid) { pid in Self.resolveApp(object: object, pid: pid) }
            return AudioProcess(objectID: object, appID: app, isPlaying: playing[object] ?? false)
        }
        refreshPlaying(all: true)
    }

    /// Re-reads who's playing: every process, or only the tapped ones.
    private func refreshPlaying(all: Bool) {
        let tapped = Set(taps.values.flatMap(\.processes))
        for index in processes.indices where all || tapped.contains(processes[index].objectID) {
            let running: UInt32? = SystemVolume.read(
                processes[index].objectID, ProcessTapAddress.global(kAudioProcessPropertyIsRunningOutput))
            processes[index].isPlaying = running == 1
        }
        apply()
    }

    /// Rebuilds the rows and brings the taps in line with the levels.
    private func apply() {
        let settings = preferences.appVolumeSettings
        let own = Bundle.main.bundleIdentifier
        for app in Set(processes.compactMap(\.appID)) where names[app] == nil {
            names[app] = Self.name(of: app)
        }
        let next = AppVolumeList.rows(processes: processes, settings: settings, ownAppID: own, names: names)
        if next != rows { rows = next }
        guard isSupported, let outputUID else { return }
        let wanted = AppVolumeTaps.wanted(processes: processes, settings: settings, ownAppID: own)
        var current: [String: Set<UInt32>] = [:]
        for tap in taps.values { current[tap.app] = tap.processes }
        let plan = AppVolumeTaps.plan(current: current, wanted: wanted)
        for app in plan.remove { removeTap(app) }
        for (app, members) in plan.create where refused[app] != members {
            let tap = ProcessTap(app: app, processes: members, outputUID: outputUID, gain: settings.gain(for: app))
            guard let tap else {
                refused[app] = members
                log.error("couldn't tap an app")
                continue
            }
            taps[app] = tap
        }
        for tap in taps.values { tap.setGain(settings.gain(for: tap.app)) }
    }

    private func outputChanged() {
        let uid = Self.defaultOutputUID()
        guard uid != outputUID else { return }
        outputUID = uid
        refused = [:]
        canHear = nil
        removeAllTaps()
        apply()
    }

    private func removeTap(_ app: String) {
        taps[app]?.teardown()
        taps[app] = nil
    }

    private func removeAllTaps() {
        for app in Array(taps.keys) { removeTap(app) }
    }

    // MARK: CoreAudio

    private static func processObjects() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = processListAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    /// The app a process plays for, from its bundle id and the apps above it.
    private static func resolveApp(object: AudioObjectID, pid: pid_t) -> String? {
        let bundle: Unmanaged<CFString>? = SystemVolume.read(
            object, ProcessTapAddress.global(kAudioProcessPropertyBundleID))
        let bundleID = bundle.map { $0.takeRetainedValue() as String } ?? ""
        return AudioAppGrouping.appID(process: bundleID, ancestors: pid > 0 ? appAncestors(of: pid) : [])
    }

    /// The regular apps at and above `pid`, nearest first: a browser's audio helper is its child.
    private static func appAncestors(of pid: pid_t) -> [String] {
        var ancestors: [String] = []
        var current = pid
        for _ in 0..<4 where current > 1 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular,
                let id = app.bundleIdentifier
            {
                ancestors.append(id)
            }
            guard let parent = parentPID(of: current), parent != current else { break }
            current = parent
        }
        return ancestors
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private static func name(of app: String) -> String? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.localizedName {
            return running
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static let defaultOutputAddress = ProcessTapAddress.global(kAudioHardwarePropertyDefaultOutputDevice)
    private static let processListAddress = ProcessTapAddress.global(kAudioHardwarePropertyProcessObjectList)

    private static func defaultOutputUID() -> String? {
        guard let device = SystemVolume.defaultOutput,
            let uid: Unmanaged<CFString> = SystemVolume.read(
                device, ProcessTapAddress.global(kAudioDevicePropertyDeviceUID))
        else { return nil }
        return uid.takeRetainedValue() as String
    }
}

/// System Audio Recording has no public status check, so Wisp reports what its taps have
/// heard (`SystemAudioHearing`): nil until they can tell, and again after a stop.
@MainActor
enum SystemAudioPermission {
    static var status: Bool?
}
