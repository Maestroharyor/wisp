import SwiftUI
import WispCore

/// Extra live activities as round bubbles beside the pill, as on iPhone. A bubble pinches
/// off the pill's end like a drop of ink and merges back the same way. Drawn under the
/// shell, so a bubble tucked inside the pill stays hidden.
struct BubbleLayer: View {
    let model: NotchModel

    /// How far each side has split off.
    @State private var split = BubbleSides.tucked
    /// What each side last showed, kept while it merges back after the activity ended and
    /// cleared once it has.
    @State private var shown: [ActivityBubble?] = [nil, nil]
    /// The compact pill the bubbles hang off (global coordinates), kept while the shell opens
    /// so they merge into where the pill was rather than jumping to the shelf's edge.
    @State private var pill: CGRect = .zero
    /// Bumped by every new split or merge, so a completion that a newer one overtook does nothing.
    @State private var generation = 0

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
        if !bubbles.isEmpty { follow(model.surfaceRect, animated: animated) }
        let target = BubbleSides.target(count: bubbles.count)
        guard animated, !model.reduceMotion else {
            generation += 1
            split = target
            shown = BubbleMotion.settled(shown: shown, live: bubbles, split: split)
            return
        }
        if BubbleMotion.swapped(shown: shown.map { $0?.slot }, live: bubbles.map(\.slot)), split.total > 0 {
            run(merge, to: .tucked) { swapIn() }
            return
        }
        shown = BubbleMotion.showing(shown: shown, live: bubbles)
        // Nothing new to animate: a split or merge already on its way settles the glyphs.
        guard target != split else { return }
        run(target.total > split.total ? pinch : merge, to: target) { settle() }
    }

    /// Animates the split, then runs `done` unless a newer split or merge has started since.
    private func run(_ animation: Animation, to target: BubbleSides, then done: @escaping () -> Void) {
        generation += 1
        let current = generation
        withAnimation(animation) {
            split = target
        } completion: {
            guard current == generation else { return }
            done()
        }
    }

    /// After a swap's merge: the sides come out again with what's live now, which is nothing
    /// if the shelf opened or a card took over meanwhile.
    private func swapIn() {
        let live = model.bubbles
        shown = BubbleMotion.settled(shown: shown, live: live, split: split)
        let target = BubbleSides.target(count: live.count)
        guard target != split else { return }
        run(pinch, to: target) { settle() }
    }

    /// Forgets the glyph of a side that has merged back in, so it can't come back as an empty circle.
    private func settle() {
        shown = BubbleMotion.settled(shown: shown, live: model.bubbles, split: split)
    }

    /// Moves the bubbles with the shell on its own spring, rather than jumping ahead of it.
    private func follow(_ rect: CGRect, animated: Bool) {
        guard rect != pill else { return }
        guard animated, pill != .zero else {
            pill = rect
            return
        }
        withAnimation(model.surfaceAnimation) { pill = rect }
    }

    private var pinch: Animation {
        model.reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.68)
    }

    private var merge: Animation {
        model.reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.92)
    }
}

/// Draws the bubbles at a given split progress. Animatable, so the goo is recomputed on
/// every frame of the spring.
private struct GooBubbles: View, Animatable {
    var pill: CGRect
    var split: BubbleSides
    let bubbles: [ActivityBubble?]
    let firstOnLeft: Bool
    let reduceMotion: Bool
    let model: NotchModel

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, CGRect.AnimatableData> {
        get { AnimatablePair(AnimatablePair(split.first, split.second), pill.animatableData) }
        set {
            split = BubbleSides(first: newValue.first.first, second: newValue.first.second)
            pill.animatableData = newValue.second
        }
    }

    var body: some View {
        let local = model.local(pill)
        let rests = SurfaceSizing.bubbleRects(
            beside: pill, count: 2, firstOnLeft: firstOnLeft, placement: model.layout.anchor, flare: model.bubbleFlare
        ).map(model.local)
        // A side with nothing to show draws nothing, not even its circle or its part of the goo.
        let drops = (0..<2).compactMap { index in
            bubbles[index].flatMap {
                drop(side: index, pill: local, rest: rests[index], progress: split[index], bubble: $0)
            }
        }
        ZStack(alignment: .topLeading) {
            if !reduceMotion {
                goo(drops)
            }
            ForEach(drops, id: \.side) { drop in
                // Flat black like the closed shell, which casts no shadow either.
                Circle()
                    .fill(.black)
                    .frame(width: drop.radius * 2, height: drop.radius * 2)
                    .overlay {
                        BubbleGlyph(bubble: drop.bubble, size: min(local.width, local.height), model: model)
                            .opacity(max(0, (drop.progress - 0.6) / 0.4))
                            .blur(radius: 4 * (1 - min(drop.progress, 1)))
                    }
                    .overlay { RimGlow(model: model, shape: Circle()).opacity(min(max(drop.progress, 0), 1)) }
                    .opacity(reduceMotion ? drop.progress : 1)
                    .position(drop.center)
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
                for drop in drops {
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
        let side: Int
        let bubble: ActivityBubble
        let center: CGPoint
        let radius: CGFloat
        let progress: Double
        /// A round end inside the pill for the bubble to pull away from.
        let stub: CGRect
    }

    /// A bubble travelling from inside the pill's nearest end (`pill` and `rest` in panel
    /// coordinates) out to its resting place.
    private func drop(side: Int, pill: CGRect, rest: CGRect, progress: Double, bubble: ActivityBubble) -> Drop? {
        guard progress > 0.001 else { return nil }
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
            side: side,
            bubble: bubble,
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
            case .custom(let custom):
                ZStack {
                    if let progress = custom.progress {
                        ProgressRing(progress: progress, tint: .wispViolet, lineWidth: 2.5)
                    }
                    Image(systemName: custom.symbol)
                        .font(.system(size: glyph * (custom.progress == nil ? 0.6 : 0.42), weight: .bold))
                        .foregroundStyle(Color.wispViolet)
                }
                .frame(width: glyph, height: glyph)
            case .regionWatch(let status):
                RegionWatchGlyph(paused: status.paused).font(.system(size: glyph * 0.6, weight: .semibold))
            default:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }
}
