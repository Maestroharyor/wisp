import SwiftUI
import WispCore

/// Extra live activities as round bubbles beside the pill, as on iPhone. A bubble pinches
/// off the pill's end like a drop of ink and merges back the same way. Drawn under the
/// shell, so a bubble tucked inside the pill stays hidden.
struct BubbleLayer: View {
    let model: NotchModel

    /// How far each side has split off: 0 tucked inside the pill, 1 at rest beside it.
    @State private var split = Sides(right: 0, left: 0)
    /// What each side last showed, kept while it merges back after the activity ended.
    @State private var shown: [ActivityBubble?] = [nil, nil]
    /// The compact pill the bubbles hang off (global coordinates), kept while the shell opens
    /// so they merge into where the pill was rather than jumping to the shelf's edge.
    @State private var pill: CGRect = .zero

    var body: some View {
        GooBubbles(
            pill: pill, split: split, bubbles: shown, firstOnLeft: model.preferences.firstBubbleOnLeft,
            reduceMotion: model.reduceMotion, model: model
        )
        .allowsHitTesting(false)
        .onAppear { sync(animated: false) }
        .onChange(of: model.bubbles) { sync(animated: true) }
        .onChange(of: model.surfaceRect) { sync(animated: true) }
    }

    private func sync(animated: Bool) {
        let bubbles = model.bubbles
        if !bubbles.isEmpty { pill = model.surfaceRect }
        let target = Sides(right: bubbles.count > 0 ? 1 : 0, left: bubbles.count > 1 ? 1 : 0)
        // A bubble showing something else (a swap with the pill) merges back in first,
        // then splits out again with its new glyph.
        let swapped = (0..<min(bubbles.count, 2)).contains { index in
            shown[index].map { $0.slot != bubbles[index].slot } ?? false
        }
        guard animated, !model.reduceMotion else {
            show(bubbles)
            split = target
            return
        }
        if swapped, split.right + split.left > 0 {
            withAnimation(merge) {
                split = Sides(right: 0, left: 0)
            } completion: {
                show(model.bubbles)
                withAnimation(pinch) { split = target }
            }
            return
        }
        show(bubbles)
        guard target != split else { return }
        withAnimation(target.right + target.left > split.right + split.left ? pinch : merge) { split = target }
    }

    /// Keeps the last glyph on a side that is merging away.
    private func show(_ bubbles: [ActivityBubble]) {
        for index in 0..<2 where index < bubbles.count { shown[index] = bubbles[index] }
    }

    private var pinch: Animation {
        model.reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.68)
    }

    private var merge: Animation {
        model.reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.92)
    }
}

/// Split progress for the first bubble (`right`, unless Settings put it on the left)
/// and the second.
struct Sides: Equatable, Sendable {
    var right: Double
    var left: Double
}

/// Draws the bubbles at a given split progress. Animatable, so the goo is recomputed on
/// every frame of the spring.
private struct GooBubbles: View, Animatable {
    var pill: CGRect
    var split: Sides
    let bubbles: [ActivityBubble?]
    let firstOnLeft: Bool
    let reduceMotion: Bool
    let model: NotchModel

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, CGRect.AnimatableData> {
        get { AnimatablePair(AnimatablePair(split.right, split.left), pill.animatableData) }
        set {
            split = Sides(right: newValue.first.first, left: newValue.first.second)
            pill.animatableData = newValue.second
        }
    }

    var body: some View {
        let local = model.local(pill)
        let rests = SurfaceSizing.bubbleRects(
            beside: pill, count: 2, firstOnLeft: firstOnLeft, placement: model.placement
        ).map(model.local)
        let drops = zip(rests, [split.right, split.left]).map { drop(pill: local, rest: $0.0, progress: $0.1) }
        ZStack(alignment: .topLeading) {
            if !reduceMotion {
                goo(drops)
            }
            ForEach(0..<2, id: \.self) { index in
                let drop = drops[index]
                if drop.progress > 0.001 {
                    Circle()
                        .fill(.black)
                        .frame(width: drop.radius * 2, height: drop.radius * 2)
                        .shadow(color: .black.opacity(0.5 * drop.progress), radius: 6, y: 2)
                        .overlay {
                            if let bubble = bubbles[index] {
                                BubbleGlyph(bubble: bubble, size: min(local.width, local.height), model: model)
                                    .opacity(max(0, (drop.progress - 0.6) / 0.4))
                                    .blur(radius: 4 * (1 - min(drop.progress, 1)))
                            }
                        }
                        .opacity(reduceMotion ? drop.progress : 1)
                        .position(drop.center)
                }
            }
        }
    }

    /// The stretching neck between the pill's end and each bubble: soft black shapes,
    /// blurred, then cut at half opacity so nearby shapes fuse and pull apart.
    private func goo(_ drops: [Drop]) -> some View {
        Canvas { context, _ in
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: 3.5))
            context.drawLayer { layer in
                for drop in drops where drop.progress > 0.001 {
                    layer.fill(Path(ellipseIn: drop.stub), with: .color(.black))
                    layer.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: drop.center.x - drop.radius, y: drop.center.y - drop.radius,
                                width: drop.radius * 2, height: drop.radius * 2)),
                        with: .color(.black))
                }
            }
        }
    }

    private struct Drop {
        let center: CGPoint
        let radius: CGFloat
        let progress: Double
        /// A round end inside the pill for the bubble to pull away from.
        let stub: CGRect
    }

    /// A bubble travelling from inside the pill's nearest end (`pill` and `rest` in panel
    /// coordinates) out to its resting place.
    private func drop(pill: CGRect, rest: CGRect, progress: Double) -> Drop {
        // As thick as the pill, so side-edge bubbles match the upright pill's width.
        let size = min(pill.width, pill.height)
        let radius = size / 2
        let target = CGPoint(x: rest.midX, y: rest.midY)
        let tucked = CGPoint(
            x: min(max(target.x, pill.minX + radius), pill.maxX - radius),
            y: min(max(target.y, pill.minY + radius), pill.maxY - radius))
        let amount = CGFloat(progress)
        let center =
            reduceMotion
            ? target
            : CGPoint(x: tucked.x + (target.x - tucked.x) * amount, y: tucked.y + (target.y - tucked.y) * amount)
        let stub = CGRect(x: tucked.x - radius, y: tucked.y - radius, width: size, height: size)
        return Drop(
            center: center,
            radius: radius * (reduceMotion ? 1 : 0.55 + 0.45 * min(amount, 1)),
            progress: progress,
            stub: stub)
    }
}

/// The one glyph that sums up an activity inside its bubble.
private struct BubbleGlyph: View {
    let bubble: ActivityBubble
    let size: CGFloat
    let model: NotchModel

    var body: some View {
        let glyph = size * 0.58
        Group {
            switch bubble.activity {
            case .media:
                ArtworkView(image: model.services.nowPlaying.artwork, size: glyph, radius: glyph * 0.25)
            case .timer(_, let countdown):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ZStack {
                        ProgressRing(
                            progress: 1 - countdown.progress(now: context.date), tint: .wispAmber, lineWidth: 2.5)
                        Image(systemName: "timer").font(.system(size: glyph * 0.42, weight: .bold))
                            .foregroundStyle(.wispAmber)
                    }
                    .frame(width: glyph, height: glyph)
                }
            case .agent(let status):
                AgentGlyph(
                    state: status.state, source: status.source, project: status.project, context: status.contextPercent,
                    others: status.others)
            case .meeting:
                Image(systemName: model.services.microphone.muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: glyph * 0.6, weight: .semibold))
                    .foregroundStyle(model.services.microphone.muted ? Color.secondaryText : .red)
            default:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }
}
