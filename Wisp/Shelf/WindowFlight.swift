import AppKit
import QuartzCore
import WispCore

/// The shelf window flying into the notch it belongs to, or out of it: a picture of the window
/// shrinks into the shell on the surface spring and fades as it arrives, so minimising reads as
/// the window going back where it came from. The real window is ordered out (or kept hidden)
/// while the picture moves, so nothing is laid out again on every frame.
@MainActor
final class WindowFlight {
    private var ghost: NSPanel?
    /// Counts flights, so a flight that was cut short never runs its ending.
    private var flights = 0

    /// Flies `window` from its frame into `shell`; `done` runs once the picture has gone. The
    /// notch doesn't answer with a swell: the window settling into it is the whole motion.
    /// Returns false when there was no picture to fly, so the caller can fall back to a fade.
    func flyIn(
        _ window: NSWindow, to shell: CGRect, spring: SpringSpec, done: @escaping @MainActor () -> Void
    ) -> Bool {
        fly(window, between: window.frame, and: shell, inward: true, spring: spring, done: done)
    }

    /// Flies `window` out of `shell` to `frame`, where the real window then appears.
    func flyOut(
        _ window: NSWindow, from shell: CGRect, to frame: CGRect, spring: SpringSpec,
        done: @escaping @MainActor () -> Void
    ) -> Bool {
        fly(window, between: frame, and: shell, inward: false, spring: spring, done: done)
    }

    /// Drops a flight under way, leaving the real window as its caller sets it. Its `done`
    /// doesn't run.
    func cancel() {
        flights += 1
        ghost?.orderOut(nil)
        ghost = nil
    }

    private func fly(
        _ window: NSWindow, between frame: CGRect, and shell: CGRect, inward: Bool, spring: SpringSpec,
        done: @escaping @MainActor () -> Void
    ) -> Bool {
        cancel()
        // A trip between displays would cross a gap macOS may not draw across (each display has
        // its own Spaces), so the window seems to vanish halfway; the caller fades instead.
        guard Self.sameScreen(frame, shell) else { return false }
        guard let picture = Self.picture(of: window), frame.width > 0, shell.width > 0 else { return false }

        // Room for the whole trip, so the picture is never cut off on its way.
        let area = frame.union(shell).insetBy(dx: -24, dy: -24)
        let panel = NSPanel(
            contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        let host = NSView(frame: CGRect(origin: .zero, size: area.size))
        host.wantsLayer = true
        panel.contentView = host

        let layer = CALayer()
        layer.contents = picture
        layer.contentsGravity = .resize
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        let windowCentre = CGPoint(x: frame.midX - area.minX, y: frame.midY - area.minY)
        let shellCentre = CGPoint(x: shell.midX - area.minX, y: shell.midY - area.minY)
        let shrunk = max(min(shell.width / frame.width, 1), 0.05)
        host.layer?.addSublayer(layer)

        let from = inward ? (windowCentre, 1.0, 1.0) : (shellCentre, shrunk, 0.0)
        let to = inward ? (shellCentre, shrunk, 0.0) : (windowCentre, 1.0, 1.0)
        layer.position = to.0
        layer.transform = CATransform3DMakeScale(to.1, to.1, 1)
        layer.opacity = Float(to.2)

        let duration = SpringSolver(spring).settleTime(epsilon: 0.002)
        let move = Self.spring("position", from: NSValue(point: from.0), spring: spring, duration: duration)
        let scale = Self.spring("transform.scale", from: NSNumber(value: from.1), spring: spring, duration: duration)
        // The picture is gone by the time it reaches the notch, or there before the window shows.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = inward ? [1, 1, 0] : [0, 1, 1]
        fade.keyTimes = inward ? [0, 0.35, 0.8] : [0, 0.3, 1]
        fade.duration = duration

        panel.orderFrontRegardless()
        ghost = panel
        let flight = flights
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                guard let self, self.flights == flight else { return }
                self.ghost = nil
                done()
            }
        }
        layer.add(move, forKey: "move")
        layer.add(scale, forKey: "scale")
        layer.add(fade, forKey: "fade")
        CATransaction.commit()
        return true
    }

    private static func sameScreen(_ a: CGRect, _ b: CGRect) -> Bool {
        let first = NSScreen.screens.first { $0.frame.contains(CGPoint(x: a.midX, y: a.midY)) }
        let second = NSScreen.screens.first { $0.frame.intersects(b) }
        return first != nil && first == second
    }

    private static func spring(_ keyPath: String, from: Any, spring: SpringSpec, duration: Double)
        -> CASpringAnimation
    {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.mass = 1
        animation.stiffness = spring.stiffness
        animation.damping = spring.damping
        animation.duration = duration
        return animation
    }

    /// Whether a picture has visible pixels, sampled on a coarse grid.
    private static func showsSomething(_ rep: NSBitmapImageRep) -> Bool {
        let step = max(min(rep.pixelsWide, rep.pixelsHigh) / 24, 1)
        var visible = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                if let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.05 { visible += 1 }
                if visible > 40 { return true }
            }
        }
        return false
    }

    /// The window as drawn now, title bar included.
    private static func picture(of window: NSWindow) -> NSImage? {
        window.contentView?.layoutSubtreeIfNeeded()
        guard let view = window.contentView?.superview ?? window.contentView, view.bounds.width > 0,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Materials and content not yet drawn can come out clear; flying nothing would look like
        // the window vanishing, so the caller fades instead.
        guard showsSomething(rep) else { return nil }
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
