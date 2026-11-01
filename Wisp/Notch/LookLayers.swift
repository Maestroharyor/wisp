import AppKit
import SwiftUI
import WispCore

/// A glow around the closed shell: breathing while something works, beating with music,
/// or lighting up as the pointer arrives.
struct RimGlow<S: Shape>: View {
    let model: NotchModel
    let shape: S

    var body: some View {
        let look = model.preferences.appearance
        let mode = model.glowMode
        let hovering = model.phase == .peek && look.hoverFeedback == .glow
        if mode != .off || hovering {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: mode == .off)) { context in
                let pulse = GlowPulse.level(time: context.date.timeIntervalSinceReferenceDate, mode: mode)
                let hover = hovering ? 0.5 * look.hoverStrength : 0
                shape
                    .stroke(model.accent, lineWidth: 1.5)
                    .shadow(color: model.accent, radius: 6)
                    .opacity(min(max(pulse * look.glowIntensity, hover), 1))
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

/// One bright flash of the rim when a timer or agent run finishes, for the breathing glow.
struct FinishFlash<S: Shape>: View {
    let model: NotchModel
    let shape: S

    var body: some View {
        let on = model.preferences.appearance.breathingGlow && !model.reduceMotion
        shape
            .stroke(model.accent, lineWidth: 2)
            .shadow(color: model.accent, radius: 8)
            .keyframeAnimator(initialValue: 0.0, trigger: model.services.finishes) { view, level in
                view.opacity(on ? level : 0)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1, duration: 0.15)
                    LinearKeyframe(1, duration: 0.25)
                    CubicKeyframe(0, duration: 0.7)
                }
            }
            .allowsHitTesting(false)
    }
}

/// Squash and stretch as the pointer reaches the closed notch.
struct HoverWobble: ViewModifier {
    let model: NotchModel

    func body(content: Content) -> some View {
        let look = model.preferences.appearance
        let amount = look.hoverFeedback == .wobble && !model.reduceMotion ? 0.07 * look.hoverStrength : 0
        let side = model.layout.edge.isSide
        let anchor = anchor
        content.keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: model.hoverPulses) {
            view, scale in
            // Along the edge stretches, away from it squashes; swapped on the sides.
            view.scaleEffect(
                x: side ? scale.height : scale.width, y: side ? scale.width : scale.height, anchor: anchor)
        } keyframes: { _ in
            KeyframeTrack(\.width) {
                SpringKeyframe(1 + amount, duration: 0.12)
                SpringKeyframe(1 - amount * 0.4, duration: 0.14)
                SpringKeyframe(1, duration: 0.3)
            }
            KeyframeTrack(\.height) {
                SpringKeyframe(1 - amount * 0.6, duration: 0.12)
                SpringKeyframe(1 + amount * 0.3, duration: 0.14)
                SpringKeyframe(1, duration: 0.3)
            }
        }
    }

    private var anchor: UnitPoint {
        switch model.layout.edge {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }
}

/// Film grain over the open surface: one small noise tile, drawn once and repeated.
struct GrainTexture: View {
    @MainActor private static let tile = makeTile()

    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
    }

    private static func makeTile() -> CGImage? {
        let side = 128
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 1,
                hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: side, bitsPerPixel: 8),
            let bytes = rep.bitmapData
        else { return nil }
        // A fixed seed keeps the grain identical between launches.
        var seed: UInt32 = 0x9E37_79B9
        for index in 0..<(side * side) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        return rep.cgImage
    }
}

/// Small text either side of the idle notch, on black wings that extend it.
struct IdleEarsLayer: View {
    let model: NotchModel

    var body: some View {
        let look = model.preferences.appearance
        let context = model.services.earContext
        let left = IdleEars.text(for: look.leftEar, context: context)
        let right = IdleEars.text(for: look.rightEar, context: context)
        let showing = model.spec == .closed && !model.layout.edge.isSide && (left != nil || right != nil)
        let closed = model.local(model.layout.closedRect)
        let leftWidth = left.map(Self.width) ?? 0
        let rightWidth = right.map(Self.width) ?? 0
        let wings = CGRect(
            x: closed.minX - leftWidth, y: closed.minY, width: closed.width + leftWidth + rightWidth,
            height: closed.height)

        ZStack(alignment: .topLeading) {
            if showing {
                wingShape
                    .fill(.black)
                    .frame(width: wings.width, height: wings.height)
                    .position(x: wings.midX, y: wings.midY)
                if let left {
                    ear(left).frame(width: leftWidth, height: closed.height)
                        .position(x: closed.minX - leftWidth / 2 + 3, y: closed.midY)
                }
                if let right {
                    ear(right).frame(width: rightWidth, height: closed.height)
                        .position(x: closed.maxX + rightWidth / 2 - 3, y: closed.midY)
                }
            }
        }
        .animation(model.surfaceAnimation, value: showing)
        .allowsHitTesting(false)
    }

    private func ear(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: model.preferences.appearance.valueFont.design))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
            .transition(.opacity)
    }

    private var wingShape: AnyShape {
        let radius = model.notchHeight / 2
        guard model.drawsNotch else { return AnyShape(Capsule()) }
        return model.layout.edge == .bottom
            ? AnyShape(UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius))
            : AnyShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
    }

    private static func width(_ text: String) -> CGFloat { max(44, CGFloat(text.count) * 7 + 18) }
}

/// The Wisp sprite: a small flame that peeks out from under the idle notch.
struct NotchPetLayer: View {
    let model: NotchModel
    @State private var lastBusy = Date.now
    /// Set once the pet dozes off; its animation stops until something happens.
    @State private var asleep = false

    var body: some View {
        let busy = model.activity != nil || model.phase != .closed
        let showing = model.preferences.appearance.pet && model.phase != .open
        ZStack(alignment: .topLeading) {
            if showing {
                let spot = position
                TimelineView(.animation(minimumInterval: 1 / 15, paused: asleep)) { context in
                    let mood = currentMood(now: context.date)
                    // A fixed time holds the sprite still under Reduce Motion; its mood still shows.
                    let time = model.reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    WispSprite(mood: mood, time: time, tint: model.accent)
                        .frame(width: 14, height: 18)
                        .rotationEffect(rotation)
                        .position(spot)
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: busy) { wake() }
        .onChange(of: model.services.agents.sessions.anyNeedsUser) { wake() }
        .onChange(of: model.services.celebrations) { wake() }
        // Restarts the doze countdown on each wake, and when the pet is switched on.
        .task(id: [lastBusy.timeIntervalSinceReferenceDate, showing ? 1 : 0]) {
            guard showing else { return }
            try? await Task.sleep(for: .seconds(PetMood.sleepAfter))
            if !Task.isCancelled { asleep = true }
        }
    }

    private func wake() {
        lastBusy = .now
        asleep = false
    }

    private func currentMood(now: Date) -> PetMood {
        let celebrating = model.services.lastCelebration.map { now.timeIntervalSince($0) < 3 } ?? false
        return PetMood.mood(
            needsAttention: model.services.agents.sessions.anyNeedsUser, celebrating: celebrating,
            idleFor: now.timeIntervalSince(lastBusy))
    }

    /// Just past the closed shape's far corner, half tucked under the shell.
    private var position: CGPoint {
        let closed = model.local(model.layout.closedRect)
        switch model.layout.edge {
        case .top: return CGPoint(x: closed.maxX - 12, y: closed.maxY + 6)
        case .bottom: return CGPoint(x: closed.maxX - 12, y: closed.minY - 6)
        case .left: return CGPoint(x: closed.maxX + 6, y: closed.maxY - 12)
        case .right: return CGPoint(x: closed.minX - 6, y: closed.maxY - 12)
        }
    }

    /// The flame always points away from the edge.
    private var rotation: Angle {
        switch model.layout.edge {
        case .top: .degrees(180)
        case .bottom: .zero
        case .left: .degrees(90)
        case .right: .degrees(-90)
        }
    }
}

/// An original flame with two eyes, drawn pointing up.
private struct WispSprite: View {
    let mood: PetMood
    let time: Double
    let tint: Color

    var body: some View {
        let bob: CGFloat =
            switch mood {
            case .asleep: 0
            case .awake: CGFloat(sin(time * 2)) * 1.2
            case .alert: CGFloat(abs(sin(time * 9))) * -2.5
            case .happy: CGFloat(abs(sin(time * 6))) * -4
            }
        ZStack {
            Flame()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .bottom, endPoint: .top))
                .shadow(color: tint.opacity(mood == .asleep ? 0.2 : 0.7), radius: 3)
            eyes.offset(y: 3)
        }
        .scaleEffect(mood == .alert ? 1.15 : 1)
        .opacity(mood == .asleep ? 0.6 : 1)
        .offset(y: bob)
    }

    @ViewBuilder private var eyes: some View {
        // A blink every four seconds while awake.
        let blinking = mood == .awake && time.truncatingRemainder(dividingBy: 4) < 0.12
        HStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { _ in
                if mood == .asleep || blinking {
                    Capsule().fill(.black).frame(width: 3, height: 1)
                } else {
                    Capsule().fill(.black).frame(width: 2, height: mood == .happy ? 1.5 : 3)
                }
            }
        }
    }
}

/// A teardrop flame: round at the bottom, a curled tip at the top.
private struct Flame: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: rect.minX + width * 0.55, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.66),
            control1: CGPoint(x: rect.minX + width * 0.7, y: rect.minY + height * 0.25),
            control2: CGPoint(x: rect.maxX, y: rect.minY + height * 0.4))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + height * 0.66), radius: width / 2, startAngle: .zero,
            endAngle: .degrees(180), clockwise: false)
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.55, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + height * 0.35),
            control2: CGPoint(x: rect.minX + width * 0.35, y: rect.minY + height * 0.3))
        path.closeSubpath()
        return path
    }
}

/// A short burst of confetti from the notch for a celebration.
struct ConfettiLayer: View {
    let model: NotchModel
    @State private var start: Date?

    static let duration = 1.4
    private static let count = 40

    var body: some View {
        ZStack {
            if let start {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(start)
                    Canvas { canvas, _ in draw(in: &canvas, elapsed: elapsed) }
                }
            }
        }
        .onChange(of: model.services.celebrations) {
            guard model.showsActivities, !model.reduceMotion else { return }
            let began = Date.now
            start = began
            Task {
                try? await Task.sleep(for: .seconds(Self.duration))
                if start == began { start = nil }
            }
        }
    }

    private func draw(in canvas: inout GraphicsContext, elapsed: Double) {
        let closed = model.local(model.layout.closedRect)
        let (origin, away) = launch(from: closed)
        let colors: [Color] = [model.accent, model.glow, .white, .wispAmber, .pink]
        let fade = max(0, min(1, (Self.duration - elapsed) / 0.4))
        for index in 0..<Self.count {
            // Fixed per-particle spread, so every burst has the same lively shape.
            let unit = Double((index * 37) % Self.count) / Double(Self.count)
            let angle = away + (unit - 0.5) * 2.1
            let speed = 170 + Double((index * 53) % 150)
            let x = origin.x + cos(angle) * speed * elapsed
            let y = origin.y + sin(angle) * speed * elapsed + 0.5 * 520 * elapsed * elapsed
            var piece = canvas
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(elapsed * (4 + unit * 8)))
            piece.opacity = fade
            piece.fill(
                Path(CGRect(x: -2.5, y: -1.5, width: 5, height: 3)), with: .color(colors[index % colors.count]))
        }
    }

    /// Where the burst starts and the direction (radians, y down) it flies.
    private func launch(from closed: CGRect) -> (CGPoint, Double) {
        switch model.layout.edge {
        case .top: (CGPoint(x: closed.midX, y: closed.maxY), .pi / 2)
        case .bottom: (CGPoint(x: closed.midX, y: closed.minY), -.pi / 2)
        case .left: (CGPoint(x: closed.maxX, y: closed.midY), 0)
        case .right: (CGPoint(x: closed.minX, y: closed.midY), .pi)
        }
    }
}
