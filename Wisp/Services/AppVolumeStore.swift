import AppKit
import CoreAudio
import Darwin
import OSLog
import Observation
import WispCore

/// Per-app volume: lists the apps playing sound and plays the ones turned down through a
/// `ProcessTap`. Runs only while the switch is on; apps at full volume are never tapped.
/// CoreAudio's process list is followed through a listener, and so is each tapped process's
/// playing flag, so a tap's IO starts the moment its app plays. Who's playing is also polled
/// while a tap exists (a backstop), or slowly while the list is on screen.
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
    /// Playing-flag listeners on the tapped process objects.
    @ObservationIgnored private var playListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
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
        syncPlayListeners()
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
        userChanged(app)
    }

    func toggleMute(_ app: String) {
        let settings = preferences.appVolumeSettings
        preferences.appVolumeSettings.setMuted(!settings.isMuted(app), for: app)
        userChanged(app)
    }

    func reset(_ app: String) {
        preferences.appVolumeSettings.reset(app)
        userChanged(app)
    }

    /// Touching an app's slider gives a refused or lost tap another try, and starts or stops
    /// its IO for the new level straight away.
    private func userChanged(_ app: String) {
        refused[app] = nil
        apply()
        checkTaps(seconds: 0)
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
        var heard = 0
        var silent = 0
        var dropped: [String] = []
        for tap in taps.values {
            let playing = processes.contains { $0.appID == tap.app && $0.isPlaying }
            let state = tap.update(appPlaying: playing, seconds: seconds)
            // A tap that ever heard its app proves the permission, whatever it hears now.
            if tap.arming.hasHeard { heard += 1 } else if state == .silent { silent += 1 }
            if state == .lost {
                log.notice("a tap stopped hearing its app; letting the app play directly")
            }
            // Not rebuilt until the app's processes change or its slider is touched.
            if state == .lost || tap.failed {
                refused[tap.app] = tap.processes
                dropped.append(tap.app)
            }
        }
        for app in dropped { removeTap(app) }
        if !dropped.isEmpty { syncPlayListeners() }
        if let hearing = SystemAudioHearing.status(armed: heard, silent: silent), hearing != canHear {
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
        if !plan.remove.isEmpty || !plan.create.isEmpty { syncPlayListeners() }
    }

    /// Listens to the playing flag of exactly the tapped process objects.
    private func syncPlayListeners() {
        let wanted = Set(taps.values.flatMap(\.processes))
        for (object, block) in playListeners where !wanted.contains(object) {
            var address = Self.playingAddress
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
            playListeners[object] = nil
        }
        for object in wanted where playListeners[object] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.playingChanged() }
            }
            var address = Self.playingAddress
            if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
                playListeners[object] = block
            }
        }
    }

    /// A tapped app started or stopped playing: start or stop its IO now, not on the next poll.
    private func playingChanged() {
        guard pollTask != nil else { return }
        refreshPlaying(all: false)
        checkTaps(seconds: 0)
    }

    private func outputChanged() {
        let uid = Self.defaultOutputUID()
        guard uid != outputUID else { return }
        outputUID = uid
        refused = [:]
        canHear = nil
        removeAllTaps()
        syncPlayListeners()
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
    private static let playingAddress = ProcessTapAddress.global(kAudioProcessPropertyIsRunningOutput)

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
