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

    /// Flies `window` from its frame into `shell`. `arrive` runs as it reaches the shell, for the
    /// notch to answer; `done` runs once the picture has gone. Returns false when there was no
    /// picture to fly, so the caller can fall back to a fade.
    func flyIn(
        _ window: NSWindow, to shell: CGRect, spring: SpringSpec, arrive: @escaping @MainActor () -> Void,
        done: @escaping @MainActor () -> Void
    ) -> Bool {
        fly(window, between: window.frame, and: shell, inward: true, spring: spring, arrive: arrive, done: done)
    }

    /// Flies `window` out of `shell` to `frame`, where the real window then appears.
    func flyOut(
        _ window: NSWindow, from shell: CGRect, to frame: CGRect, spring: SpringSpec,
        done: @escaping @MainActor () -> Void
    ) -> Bool {
        fly(window, between: frame, and: shell, inward: false, spring: spring, arrive: {}, done: done)
    }

    /// Drops a flight under way, leaving the real window as its caller sets it.
    func cancel() {
        ghost?.orderOut(nil)
        ghost = nil
    }

    private func fly(
        _ window: NSWindow, between frame: CGRect, and shell: CGRect, inward: Bool, spring: SpringSpec,
        arrive: @escaping @MainActor () -> Void, done: @escaping @MainActor () -> Void
    ) -> Bool {
        cancel()
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
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak panel] in
            MainActor.assumeIsolated {
                panel?.orderOut(nil)
                if let panel, self?.ghost === panel { self?.ghost = nil }
                done()
            }
        }
        layer.add(move, forKey: "move")
        layer.add(scale, forKey: "scale")
        layer.add(fade, forKey: "fade")
        CATransaction.commit()

        if inward {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration * 0.55))
                arrive()
            }
        }
        return true
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

    /// The window as drawn now, title bar included.
    private static func picture(of window: NSWindow) -> NSImage? {
        window.contentView?.layoutSubtreeIfNeeded()
        guard let view = window.contentView?.superview ?? window.contentView, view.bounds.width > 0,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
