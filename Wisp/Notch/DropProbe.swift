#if DEBUG
    import AppKit
    import SwiftUI
    import os

    /// Debug builds only: drives a whole file drag with posted mouse events (Wisp Dev has
    /// Accessibility, the terminal doesn't), from a small window holding the file to the shell and
    /// onto a drop tile, and logs where the drop went. Logs window numbers and counts, never names.
    @MainActor
    final class DropProbe {
        nonisolated static let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "dropprobe")
        private var source: NSPanel?

        /// `shell` is where the drag first goes to open the tiles; `tile` is asked once they're open.
        func run(
            file: URL, from origin: CGPoint?, shakes: Bool = false, shell: CGPoint,
            tile: @escaping @MainActor () -> CGPoint?
        ) {
            // A source in another app (as Finder would be) when given; Wisp's own window otherwise.
            let start = origin ?? showSource(file)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                Self.post(.mouseMoved, at: start)
                try? await Task.sleep(for: .milliseconds(100))
                Self.post(.leftMouseDown, at: start)
                try? await Task.sleep(for: .milliseconds(150))
                await Self.glide(from: start, to: shell, steps: 40)
                await Self.hover(at: shell, for: .milliseconds(900))
                let board = NSPasteboard(name: .drag)
                Self.log.debug(
                    "probe: drag board change \(board.changeCount, privacy: .public) file \(board.types?.contains(.fileURL) ?? false, privacy: .public)"
                )
                guard let target = tile() else {
                    Self.log.debug("probe: no tile point")
                    Self.post(.leftMouseUp, at: shell)
                    return
                }
                await Self.glide(from: shell, to: target, steps: 25)
                // Waving the file about over the tiles, as a hand does, which can count as a shake.
                if shakes {
                    for _ in 0..<4 {
                        await Self.glide(from: target, to: CGPoint(x: target.x + 90, y: target.y), steps: 3)
                        await Self.glide(from: CGPoint(x: target.x + 90, y: target.y), to: target, steps: 3)
                    }
                }
                await Self.hover(at: target, for: .milliseconds(600))
                let under = NSWindow.windowNumber(at: target, belowWindowWithWindowNumber: 0)
                let own = NSApp.windows.first { $0.windowNumber == under }
                Self.log.debug(
                    "probe: window under drop \(under, privacy: .public) own \(own != nil, privacy: .public) \(own.map { String(describing: type(of: $0)) } ?? "-", privacy: .public)"
                )
                Self.post(.leftMouseUp, at: target)
                try? await Task.sleep(for: .seconds(1.5))
                self.source?.orderOut(nil)
                self.source = nil
                Self.log.debug("probe: done")
            }
        }

        /// A small window at the left of the main screen holding the file to drag.
        private func showSource(_ file: URL) -> CGPoint {
            let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
            let frame = CGRect(x: visible.minX + 40, y: visible.midY - 60, width: 120, height: 120)
            let panel = NSPanel(
                contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.contentView = NSHostingView(
                rootView: Image(systemName: "doc.fill").font(.system(size: 48))
                    .frame(width: 120, height: 120)
                    .background(Color.gray.opacity(0.3))
                    .onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() })
            panel.orderFrontRegardless()
            source = panel
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        private static func glide(from: CGPoint, to: CGPoint, steps: Int) async {
            for step in 1...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                post(
                    .leftMouseDragged,
                    at: CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction))
                try? await Task.sleep(for: .milliseconds(25))
            }
        }

        /// Drag updates only come with movement, so it jiggles a point while it waits.
        private static func hover(at point: CGPoint, for duration: Duration) async {
            let end = ContinuousClock.now + duration
            var flip: CGFloat = 1
            while ContinuousClock.now < end {
                post(.leftMouseDragged, at: CGPoint(x: point.x + flip, y: point.y))
                flip = -flip
                try? await Task.sleep(for: .milliseconds(40))
            }
        }

        /// `point` is in AppKit's global space (bottom left); events take the top-left one.
        private static func post(_ type: CGEventType, at point: CGPoint) {
            let height = NSScreen.screens.first?.frame.height ?? 0
            let flipped = CGPoint(x: point.x, y: height - point.y)
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: flipped, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
#endif
