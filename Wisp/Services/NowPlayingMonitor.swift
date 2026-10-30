import AppKit
import CoreImage
import Observation
import SwiftUI
import WispCore

/// System-wide Now Playing (any app, including browsers) through the media bridge.
/// Falls back to polling Music and Spotify through AppleScript if the bridge cannot
/// run. Never launches a player that is not running.
@MainActor
@Observable
final class NowPlayingMonitor {
    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    /// Dominant artwork colour, for the waveform and progress tint.
    private(set) var tint: Color = .white
    /// When `info.position` was read, to extrapolate the playhead between polls.
    private(set) var readAt = Date.now

    @ObservationIgnored var onChange: (NowPlayingInfo?) -> Void = { _ in }
    /// Whether to fetch album art online for tracks that arrive without any.
    @ObservationIgnored var looksUpArtwork: () -> Bool = { false }
    /// Looked-up art per track, so replays and bridge restarts don't search again.
    @ObservationIgnored private var foundArtwork: [String: NSImage] = [:]
    @ObservationIgnored private var searchedTracks: Set<String> = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var scripts: [String: NSAppleScript] = [:]
    @ObservationIgnored private var artworkTrackID: String?
    @ObservationIgnored private let bridge = MediaBridge()
    @ObservationIgnored private var usingBridge = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    func start() {
        bridge.onEvent = { [weak self] event in self?.handle(event) }
        bridge.onUnavailable = { [weak self] in self?.bridgeFailed() }
        // The bridge can drop around sleep; start it fresh on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartBridge() }
        }
        usingBridge = bridge.start()
        if !usingBridge { bridgeFailed() }
    }

    func stop() {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        retryTask?.cancel()
        bridge.stop()
        pollTask?.cancel()
        pollTask = nil
    }

    /// Falls back to Music and Spotify via AppleScript, and keeps trying the bridge every
    /// 20 seconds, so browsers and other apps come back without relaunching Wisp.
    private func bridgeFailed() {
        usingBridge = false
        startPolling()
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self else { return }
                if bridge.start() {
                    usingBridge = true
                    pollTask?.cancel()
                    pollTask = nil
                    return
                }
            }
        }
    }

    private func restartBridge() {
        retryTask?.cancel()
        bridge.stop()
        if bridge.start() {
            usingBridge = true
            pollTask?.cancel()
            pollTask = nil
        } else {
            bridgeFailed()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func handle(_ event: MediaBridgeEvent) {
        readAt = .now
        switch event {
        case .nowPlaying(let next, let artworkData):
            let changedTrack = next.trackID != info?.trackID
            if let artworkData {
                artworkTrackID = next.trackID
                setArtwork(NSImage(data: artworkData))
            } else if changedTrack {
                artworkTrackID = next.trackID
                setArtwork(nil)
            }
            if artwork == nil { lookUpArtwork(for: next) }
            guard next != info else { return }
            info = next
            onChange(next)
        case .cleared:
            guard info != nil else { return }
            info = nil
            setArtwork(nil)
            onChange(nil)
        case .invalid:
            break
        }
    }

    func position(at date: Date) -> Double {
        guard let info else { return 0 }
        let elapsed = info.isPlaying ? date.timeIntervalSince(readAt) : 0
        return min(info.position + elapsed, info.duration)
    }

    func togglePlayPause() { command(.togglePlayPause, script: "playpause") }
    func next() { command(.next, script: "next track") }
    func previous() { command(.previous, script: "previous track") }

    func seek(to seconds: Double) {
        guard let info else { return }
        if usingBridge {
            bridge.send(.seek(seconds))
            return
        }
        run("tell application id \"\(info.source.bundleID)\" to set player position to \(Int(seconds))")
        poll()
    }

    func openPlayer() {
        guard let id = info?.appBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func command(_ bridgeCommand: MediaBridgeCommand, script verb: String) {
        if usingBridge {
            bridge.send(bridgeCommand)
            return
        }
        guard let info else { return }
        run("tell application id \"\(info.source.bundleID)\" to \(verb)")
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.poll()
        }
    }

    private func poll() {
        let readings = NowPlayingSource.scriptable.compactMap { source -> NowPlayingInfo? in
            guard isRunning(source), let raw = run(Self.statusScript(for: source)) else { return nil }
            return NowPlayingParser.parse(raw, source: source)
        }
        // Prefer whichever player is actually playing.
        let next = readings.first(where: \.isPlaying) ?? readings.first
        readAt = .now
        if next != info {
            let changedTrack = next?.trackID != info?.trackID
            info = next
            if changedTrack { loadArtwork(for: next) }
            onChange(next)
        }
    }

    private func isRunning(_ source: NowPlayingSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    @discardableResult
    private func run(_ source: String) -> String? {
        runDescriptor(source)?.stringValue
    }

    private func runDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        let script = scripts[source] ?? NSAppleScript(source: source)
        scripts[source] = script
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private func loadArtwork(for info: NowPlayingInfo?) {
        artworkTrackID = info?.trackID
        guard let info else {
            setArtwork(nil)
            return
        }
        switch info.source {
        case .system:
            setArtwork(nil)
        case .music:
            let data = runDescriptor(
                "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track")?.data
            setArtwork(data.flatMap(NSImage.init(data:)))
        case .spotify:
            guard let url = info.artworkURL else {
                setArtwork(nil)
                return
            }
            let trackID = info.trackID
            Task { [weak self] in
                let data = try? await URLSession.shared.data(from: url).0
                guard let self, self.artworkTrackID == trackID else { return }
                self.setArtwork(data.flatMap(NSImage.init(data:)))
            }
        }
    }

    /// Browsers often hand macOS no picture; search iTunes once per track instead.
    private func lookUpArtwork(for info: NowPlayingInfo) {
        let trackID = info.trackID
        if let found = foundArtwork[trackID] {
            setArtwork(found)
            return
        }
        guard looksUpArtwork(), !searchedTracks.contains(trackID),
            let url = ArtworkQuery.url(title: info.title, artist: info.artist)
        else { return }
        searchedTracks.insert(trackID)
        Task { [weak self] in
            let image = await Self.fetchArtwork(from: url, artist: info.artist)
            guard let self else { return }
            guard let image else {
                // A failed request (offline, a firewall prompt) may work next time.
                self.searchedTracks.remove(trackID)
                return
            }
            if self.foundArtwork.count > 50 { self.foundArtwork.removeAll() }
            self.foundArtwork[trackID] = image
            // Only if the same song is still on and nothing better arrived meanwhile.
            guard self.artworkTrackID == trackID, self.artwork == nil else { return }
            self.setArtwork(image)
        }
    }

    private static func fetchArtwork(from searchURL: URL, artist: String) async -> NSImage? {
        let session = URLSession.shared
        guard let data = try? await session.data(for: URLRequest(url: searchURL, timeoutInterval: 10)).0,
            let response = try? JSONDecoder().decode(ArtworkSearchResponse.self, from: data),
            let imageURL = response.artworkURL(artist: artist),
            let imageData = try? await session.data(for: URLRequest(url: imageURL, timeoutInterval: 10)).0
        else { return nil }
        return NSImage(data: imageData)
    }

    private func setArtwork(_ image: NSImage?) {
        artwork = image
        tint = image.flatMap(Self.averageColor) ?? .white
    }

    private static func averageColor(of image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard
            let filter = CIFilter(
                name: "CIAreaAverage",
                parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
            let output = filter.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(
                output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8, colorSpace: nil)
        // Lift dark averages so the tint stays visible on black.
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        let hsb = color.usingColorSpace(.deviceRGB)
        let brightened = NSColor(
            hue: hsb?.hueComponent ?? 0,
            saturation: min((hsb?.saturationComponent ?? 0) * 1.2, 1),
            brightness: max(hsb?.brightnessComponent ?? 1, 0.75),
            alpha: 1
        )
        return Color(nsColor: brightened)
    }

    private static func statusScript(for source: NowPlayingSource) -> String {
        let artwork = source == .spotify ? " & d & (artwork url of t)" : ""
        return """
            tell application id "\(source.bundleID)"
                set s to player state as string
                if s is "stopped" then return "stopped"
                set t to current track
                set d to character id 31
                return s & d & (name of t) & d & (artist of t) & d & (album of t) & d & (duration of t) & d & (player position)\(artwork)
            end tell
            """
    }
}
