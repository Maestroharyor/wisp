import AppKit
import SwiftUI

/// Moves a panel to a new origin on a spring, one display frame at a time, so a dropped orb
/// settles the way the shell itself moves rather than on a fixed ease-out.
@MainActor
final class PanelGlide: NSObject {
    private weak var panel: NSPanel?
    private var link: CADisplayLink?
    private var started: CFTimeInterval = 0
    private var from: CGPoint = .zero
    private var to: CGPoint = .zero
    private var spring = Spring()

    var isRunning: Bool { link != nil }

    /// Places the panel at `from` and springs it to `to`. Without a view to time it by, it
    /// goes straight there.
    func run(_ panel: NSPanel, from: CGPoint, to: CGPoint, spring: Spring) {
        stop()
        guard let view = panel.contentView else {
            panel.setFrameOrigin(to)
            return
        }
        self.panel = panel
        self.from = from
        self.to = to
        self.spring = spring
        panel.setFrameOrigin(from)
        started = CACurrentMediaTime()
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Leaves the panel where it is now.
    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let panel else { return stop() }
        let time = link.targetTimestamp - started
        guard time < spring.settlingDuration else {
            panel.setFrameOrigin(to)
            return stop()
        }
        let progress = spring.value(target: 1.0, time: time)
        panel.setFrameOrigin(
            CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress))
    }
}
