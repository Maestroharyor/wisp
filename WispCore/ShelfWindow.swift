import CoreGraphics
import Foundation

/// Whether the shelf lives under the shell (notch, island, orb) or in an ordinary window.
///
/// "Open as Window" and tearing the open shelf off give a one-off window: putting it away
/// (minimise or close) goes back to the shell, which opens its own shelf again. The Window
/// form keeps the shelf in the window until another form is picked: putting the window away
/// still collapses to the shell the display had, and the shell brings the window back. The
/// shell's placement is never touched, so there's always a shell to go back to.
public struct ShelfWindowState: Equatable, Sendable {
    /// The Window form is chosen.
    public private(set) var windowForm: Bool
    /// The window is on screen.
    public private(set) var isOpen: Bool

    public init(windowForm: Bool = false, isOpen: Bool = false) {
        self.windowForm = windowForm
        self.isOpen = isOpen
    }

    public enum Event: Equatable, Sendable {
        /// The menu's "Open as Window", or the open shelf torn off.
        case openAsWindow
        /// The window's minimise or close button.
        case putAway
        /// A click or swipe on the shell, or a page opened from the menu or a link.
        case activateShell
        /// The open-or-close shortcut.
        case toggle(windowInFront: Bool)
        /// A form picked from the menu, the page pill, the ring or Hyper+F.
        case pick(FormFactor)
        /// The Window form switched in Settings.
        case setWindowForm(Bool)
    }

    public enum Effect: Equatable, Sendable {
        case closeShelves
        case showWindow
        case focusWindow
        case hideWindow
        /// Open the shelf under the shell, as without a window.
        case openShelf
        /// Switch the display's shell to this form.
        case applyShellForm(FormFactor)
    }

    /// Hovering, clicking or the shortcut open the shelf under the shell, rather than reaching
    /// for the window.
    public var opensUnderShell: Bool { !isOpen && !windowForm }

    /// The form to show as current, given the display's shell form.
    public func form(shell: FormFactor) -> FormFactor { windowForm ? .window : shell }

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .openAsWindow:
            return show()
        case .putAway:
            return hide()
        case .activateShell:
            if isOpen { return [.focusWindow] }
            return windowForm ? show() : [.openShelf]
        case .toggle(let inFront):
            if isOpen { return inFront ? hide() : [.focusWindow] }
            return windowForm ? show() : [.openShelf]
        case .pick(.window), .setWindowForm(true):
            windowForm = true
            return show()
        case .pick(let form):
            windowForm = false
            return hide() + [.applyShellForm(form)]
        case .setWindowForm(false):
            guard windowForm else { return [] }
            windowForm = false
            return hide()
        }
    }

    private mutating func show() -> [Effect] {
        if isOpen { return [.focusWindow] }
        isOpen = true
        return [.closeShelves, .showWindow]
    }

    private mutating func hide() -> [Effect] {
        guard isOpen else { return [] }
        isOpen = false
        return [.hideWindow]
    }
}

/// Where the shelf window goes: its remembered frame kept on a connected display, or where
/// the pointer tore it off.
public enum ShelfWindowFrame {
    public static let defaultSize = CGSize(width: 960, height: 640)
    public static let minimumSize = CGSize(width: 720, height: 480)
    /// How far below the window's top edge the pointer holds a torn-off window: in its title bar.
    public static let grabDepth: CGFloat = 14
    /// Less of a saved frame than this on any display, and it's treated as on a missing one.
    private static let minimumOverlap: CGFloat = 0.1

    /// "x,y,width,height", whole points.
    public static func encode(_ frame: CGRect) -> String {
        [frame.minX, frame.minY, frame.width, frame.height].map { String(Int($0.rounded())) }
            .joined(separator: ",")
    }

    public static func decode(_ text: String) -> CGRect? {
        let parts = text.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// The saved frame on the display holding most of it, at least the minimum size, no
    /// bigger than that display and wholly on it. A frame on a display that's gone keeps its
    /// size and is centred on the main one; with no saved frame the default size is.
    /// `screens` and `main` are visible frames.
    public static func fitted(_ saved: CGRect?, screens: [CGRect], main: CGRect) -> CGRect {
        guard let saved else { return clamped(centred(defaultSize, on: main), to: main) }
        let overlaps = screens.map { ($0, area($0.intersection(saved))) }
        guard let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 >= area(saved) * minimumOverlap else {
            return clamped(centred(saved.size, on: main), to: main)
        }
        return clamped(saved, to: best.0)
    }

    /// A window of `size` hanging from the pointer by its title bar, kept on the display.
    public static func tornOff(at pointer: CGPoint, size: CGSize, in visible: CGRect) -> CGRect {
        let frame = CGRect(
            x: pointer.x - size.width / 2, y: pointer.y + grabDepth - size.height, width: size.width,
            height: size.height)
        return clamped(frame, to: visible)
    }

    private static func centred(_ size: CGSize, on screen: CGRect) -> CGRect {
        CGRect(
            x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func clamped(_ frame: CGRect, to screen: CGRect) -> CGRect {
        let width = min(max(frame.width, minimumSize.width), screen.width)
        let height = min(max(frame.height, minimumSize.height), screen.height)
        let x = min(max(frame.minX, screen.minX), screen.maxX - width)
        let y = min(max(frame.minY, screen.minY), screen.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}

/// Dragging the open shelf off into the window.
public enum ShelfTearOff {
    /// A press on the open shelf outside its pages: the strip above them and the margins
    /// beside them, where nothing takes clicks. The bottom margin is left out, since the
    /// approval bar sits over it. `insets` are the shelf's content insets.
    public static func mayStart(at press: CGPoint, surface: CGRect, insets: EdgeInsetsValue) -> Bool {
        guard surface.contains(press) else { return false }
        let pages = CGRect(
            x: surface.minX + insets.leading, y: surface.minY,
            width: surface.width - insets.leading - insets.trailing, height: surface.height - insets.top)
        return !pages.contains(press)
    }

    /// The same deliberate pull as tearing the notch off into the orb.
    public static func tearsOff(from start: CGPoint, to point: CGPoint) -> Bool {
        OrbGeometry.startsDrag(from: start, to: point, floating: false)
    }
}
