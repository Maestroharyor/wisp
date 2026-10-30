/// What the notch is showing.
public enum NotchPhase: Sendable, Equatable {
    case closed
    /// Pointer is over the notch: the shape grows slightly while the open dwell runs.
    case peek
    case open
}

public enum NotchEvent: Sendable, Equatable {
    case pointerEntered
    case pointerExited
    case dwellElapsed
    case closeDelayElapsed
    case clicked
    case clickedOutside
    case hotkey
    case escape
    /// A file drag reached the notch: open without pinning so leaving closes it.
    case dragEntered
}

/// Timers the owner must start or cancel after an event.
public enum NotchEffect: Sendable, Equatable {
    case scheduleDwell
    case cancelDwell
    case scheduleClose
    case cancelClose
}

/// Pure state machine for open/close behaviour, kept free of timers and UI so it is testable.
public struct NotchMachine: Sendable, Equatable {
    public private(set) var phase: NotchPhase = .closed
    /// Opened from the keyboard: stays open until dismissed explicitly, not on pointer exit.
    public private(set) var pinned = false
    /// When false, hovering only peeks; a click opens the shelf.
    public var opensOnHover: Bool
    /// When false, an open shelf stays until a click outside, Esc or the hotkey.
    public var closesOnPointerExit = true
    /// Opened by a file drag: leaving closes it whatever `closesOnPointerExit` says.
    private var openedByDrag = false

    public init(opensOnHover: Bool = true) {
        self.opensOnHover = opensOnHover
    }

    public mutating func handle(_ event: NotchEvent) -> [NotchEffect] {
        switch (phase, event) {
        case (.closed, .pointerEntered):
            phase = .peek
            return opensOnHover ? [.scheduleDwell] : []

        case (.peek, .dwellElapsed), (.peek, .clicked):
            phase = .open
            return [.cancelDwell]

        case (.peek, .pointerExited):
            phase = .closed
            return [.cancelDwell]

        case (.open, .pointerExited):
            return pinned || (!closesOnPointerExit && !openedByDrag) ? [] : [.scheduleClose]

        case (.open, .pointerEntered):
            return [.cancelClose]

        case (.open, .closeDelayElapsed), (.open, .clickedOutside):
            return close()

        case (.closed, .hotkey), (.peek, .hotkey):
            phase = .open
            pinned = true
            return [.cancelDwell, .cancelClose]

        case (.closed, .dragEntered), (.peek, .dragEntered):
            phase = .open
            openedByDrag = true
            return [.cancelDwell, .cancelClose]

        case (.open, .dragEntered):
            return [.cancelClose]

        case (.open, .hotkey), (_, .escape):
            return phase == .closed ? [] : close()

        default:
            return []
        }
    }

    private mutating func close() -> [NotchEffect] {
        phase = .closed
        pinned = false
        openedByDrag = false
        return [.cancelDwell, .cancelClose]
    }
}
