/// Where a click on the closed notch takes the user: the view that belongs to the activity
/// on the pill, or the page the shelf usually opens on when there isn't one.
public enum PillDestination: Equatable, Sendable {
    /// The page the shelf usually opens on.
    case home
    case agents
    case timer
    case nowPlaying
    case battery
    case tray
    case downloads
    case regionWatch
    case externalDetails

    public init(slot: ActivitySlot?) {
        guard let slot else {
            self = .home
            return
        }
        switch slot {
        case .agent: self = .agents
        case .timer, .timerDone: self = .timer
        case .media: self = .nowPlaying
        case .battery: self = .battery
        case .tray: self = .tray
        case .download: self = .downloads
        case .regionWatch: self = .regionWatch
        case .external: self = .externalDetails
        // Calls already open their own controls from the pill, the finished download card has
        // its own Open and Show in Finder and the quick add card its own Add; the rest are short
        // alerts or HUDs with nothing more to show.
        case .notice, .notification, .focus, .capsLock, .level, .agentApproval, .meeting, .meetingSoon, .device,
            .dictation, .downloadDone, .quickInput:
            self = .home
        }
    }
}
