import Foundation
import Observation
import WispCore

/// The rest of Music's playlist, read through AppleScript while an Up Next view is open and
/// the switch is on. Nothing leaves the Mac, and Music is never launched.
@MainActor
@Observable
final class UpNextStore {
    private(set) var upNext: UpNext?

    @ObservationIgnored private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Reads what's next for `info`. Call from a view's `.task(id:)` keyed on the track.
    func load(for info: NowPlayingInfo?) async {
        guard preferences.upNext, UpNext.applies(to: info) else {
            upNext = nil
            return
        }
        let output = await AppleScriptRunner.run(UpNext.script(count: 5))
        guard !Task.isCancelled else { return }
        upNext = UpNext.parse(output)
    }
}
