import CoreGraphics
import Foundation
import OSLog
import Observation
import WispCore

/// Runs one region watch at a time: a frame every few seconds, paused on low battery,
/// until the rule fires or the user stops it. Frames live only for the length of a check.
@MainActor
@Observable
final class RegionWatcher {
    private(set) var target: RegionTarget?
    private(set) var rule: RegionWatchRule?

    var isWatching: Bool { target != nil }

    @ObservationIgnored var onActivity: (Activity?) -> Void = { _ in }
    /// The rule fired: the app name and what happened.
    @ObservationIgnored var onFired: (String, String) -> Void = { _, _ in }
    /// The watch ended without firing, with the reason.
    @ObservationIgnored var onEnded: (String) -> Void = { _ in }
    @ObservationIgnored var battery: () -> BatteryState? = { nil }

    @ObservationIgnored private var loop: Task<Void, Never>?
    private static let maximumFailures = 3
    private static let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "RegionWatch")

    func start(_ target: RegionTarget, rule: RegionWatchRule) {
        stop()
        self.target = target
        self.rule = rule
        publish(paused: false)
        loop = Task { [weak self] in await self?.run(target, rule: rule) }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        target = nil
        rule = nil
        onActivity(nil)
    }

    private func run(_ target: RegionTarget, rule: RegionWatchRule) async {
        var monitor = RegionWatchMonitor(rule: rule)
        let capture = RegionCaptureSession(target: target, readsText: rule.needsText)
        var failures = 0
        var wasPaused = false
        while !Task.isCancelled {
            switch RegionWatchSchedule.next(for: rule, battery: battery()) {
            case .paused(let wait):
                if !wasPaused { publish(paused: true) }
                wasPaused = true
                try? await Task.sleep(for: .seconds(wait))
                continue
            case .capture(let wait):
                if wasPaused {
                    wasPaused = false
                    monitor.resume(at: .now)
                    publish(paused: false)
                }
                do {
                    let sample = try await capture.sample()
                    guard !Task.isCancelled else { return }
                    failures = 0
                    if monitor.observe(sample) == .fired {
                        finish { $0.onFired(target.appName, rule.firedText) }
                        return
                    }
                } catch RegionCaptureError.windowGone {
                    guard !Task.isCancelled else { return }
                    finish { $0.onEnded("The watched window closed") }
                    return
                } catch RegionCaptureError.regionGone {
                    guard !Task.isCancelled else { return }
                    finish { $0.onEnded("The watched region is off the window") }
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    failures += 1
                    Self.log.error("Region capture failed: \(error.localizedDescription, privacy: .public)")
                    // Turning Screen Recording off makes every capture fail; say so straight away.
                    if !CGPreflightScreenCaptureAccess() {
                        finish { $0.onEnded("Screen Recording is off") }
                        return
                    }
                    if failures >= Self.maximumFailures {
                        finish { $0.onEnded("Can't capture the watched window") }
                        return
                    }
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func finish(_ report: (RegionWatcher) -> Void) {
        loop = nil
        target = nil
        rule = nil
        onActivity(nil)
        report(self)
    }

    private func publish(paused: Bool) {
        guard let target, let rule else { return }
        onActivity(.regionWatch(RegionWatchStatus(appName: target.appName, rule: rule, paused: paused)))
    }
}
