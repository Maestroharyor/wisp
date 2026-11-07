import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Wedge segments around a centre button, with the open segment's sub-ring as an outer arc.
/// Opening, the disc springs up and the wedges fly out in turn; closing runs it backwards.
struct RingView: View {
    let model: RingModel
    let reduceMotion: Bool
    let onHover: @MainActor (RingHit, CGFloat) -> Void
    let onPick: @MainActor (RingHit, [URL]) -> Void

    var body: some View {
        let slots = model.set.slots
        let shown = model.visible
        ZStack {
            disc
                .scaleEffect(shown || reduceMotion ? 1 : 0.7)
                .opacity(shown ? 1 : 0)
                .animation(
                    shown ? .spring(response: 0.32, dampingFraction: 0.74) : .easeIn(duration: 0.14), value: shown)
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let wedge = RingGeometry.sector(index, count: slots.count)
                RingWedge(
                    start: wedge.start, end: wedge.end, inner: RingGeometry.ringInner, outer: RingGeometry.ringOuter,
                    centre: model.centre, symbol: slot.action.symbol, fill: fill(for: index, slot: slot),
                    dimmed: model.dropping && !slot.action.acceptsFiles,
                    hasMore: !model.subItems(of: index).isEmpty
                )
                // Each wedge flies out from the centre in turn, and back in on close.
                .scaleEffect(shown || reduceMotion ? 1 : 0.3, anchor: unit(model.centre))
                .opacity(shown ? 1 : 0)
                .animation(
                    shown
                        ? .spring(response: 0.34, dampingFraction: 0.72).delay(RingGeometry.delay(for: index))
                        : .easeIn(duration: 0.12),
                    value: shown)
            }
            if let expanded = model.expanded, shown {
                SubRing(model: model, parent: expanded, count: slots.count, reduceMotion: reduceMotion)
                    .id(expanded)
            }
            centre
                .position(model.centre)
                .scaleEffect(shown || reduceMotion ? 1 : 0.5, anchor: unit(model.centre))
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: model.hover)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): onHover(hit(at: location), distance(to: location))
            case .ended: onHover(.none, .greatestFiniteMagnitude)
            }
        }
        .onTapGesture(coordinateSpace: .local) { location in onPick(hit(at: location), []) }
        .onDrop(
            of: [.fileURL],
            delegate: RingDropDelegate(hit: hit(at:), distance: distance(to:), onHover: onHover, onPick: onPick)
        )
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var disc: some View {
        let size = RingGeometry.ringOuter * 2 + 16
        return Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(.black.opacity(0.62)))
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.45), radius: 22, y: 8)
            .position(model.centre)
    }

    /// The middle: the hovered action's name and key, or Wisp's glyph (which opens the shelf).
    private var centre: some View {
        let size = RingGeometry.centreRadius * 2
        let hovered = hoveredTitle
        return ZStack {
            Circle().fill(model.hover == .centre ? Color.wispViolet : .white.opacity(0.1))
            if let hovered {
                VStack(spacing: 1) {
                    Text(hovered.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    if let key = hovered.key {
                        Text(key).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(6)
                .transition(.opacity)
            } else {
                Image("MenuGlyph").resizable().renderingMode(.template).scaledToFit().padding(22)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .help("Open the shelf")
    }

    private var hoveredTitle: (title: String, key: String?)? {
        switch model.hover {
        case .slot(let index):
            guard model.set.slots.indices.contains(index) else { return nil }
            return (model.set.slots[index].action.title, index < 9 ? "\(index + 1)" : nil)
        case .sub(let item):
            let items = model.expandedItems
            return items.indices.contains(item) ? (items[item].title, nil) : nil
        case .centre:
            return ("Shelf", nil)
        case .none:
            return nil
        }
    }

    private func fill(for index: Int, slot: RingSlot) -> Color {
        if model.picked == .slot(index) { return .wispViolet }
        let hovered = model.hover == .slot(index)
        if model.dropping, slot.action.acceptsFiles, hovered { return .wispViolet }
        if hovered || model.expanded == index { return .wispViolet.opacity(hovered ? 0.95 : 0.45) }
        return .white.opacity(0.07)
    }

    private func unit(_ point: CGPoint) -> UnitPoint {
        let side = model.centre.x * 2
        guard side > 0 else { return .center }
        return UnitPoint(x: point.x / side, y: point.y / side)
    }

    private func distance(to location: CGPoint) -> CGFloat {
        hypot(location.x - model.centre.x, location.y - model.centre.y)
    }

    private func hit(at location: CGPoint) -> RingHit {
        let up = CGPoint(x: location.x, y: model.centre.y * 2 - location.y)
        return RingGeometry.hit(
            up, centre: model.centre, slots: model.set.slots.count, expanded: model.expanded,
            subItems: model.expandedItems.count)
    }
}

/// The open segment's choices, fanned out from its angle.
private struct SubRing: View {
    let model: RingModel
    let parent: Int
    let count: Int
    let reduceMotion: Bool

    @State private var fanned = false

    var body: some View {
        let items = model.expandedItems
        let parentAngle = RingGeometry.slotAngle(parent, count: count)
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let wedge = RingGeometry.subSector(index, count: items.count, around: parentAngle)
                let half = (wedge.end - wedge.start) / 2
                // Every wedge starts folded on the parent's angle and swings to its own.
                let open = fanned || reduceMotion
                RingWedge(
                    start: open ? wedge.start : parentAngle - half, end: open ? wedge.end : parentAngle + half,
                    inner: RingGeometry.subInner, outer: RingGeometry.subOuter, centre: model.centre,
                    symbol: item.symbol, fill: fill(item, index: index), dimmed: false, hasMore: false, small: true
                )
                .opacity(fanned ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { fanned = true }
        }
    }

    private func fill(_ item: RingChoice, index: Int) -> Color {
        let hovered = model.hover == .sub(index) || model.picked == .sub(index)
        switch item.tint {
        case .allow: return Color.green.opacity(hovered ? 0.9 : 0.4)
        case .deny: return Color.red.opacity(hovered ? 0.9 : 0.4)
        case .plain: return hovered ? .wispViolet : .white.opacity(0.1)
        }
    }
}

/// One annular wedge with its icon in the middle of the band.
struct RingWedge: View {
    var start: CGFloat
    var end: CGFloat
    let inner: CGFloat
    let outer: CGFloat
    let centre: CGPoint
    let symbol: String
    let fill: Color
    let dimmed: Bool
    let hasMore: Bool
    var small = false

    var body: some View {
        let shape = SectorShape(start: start, end: end, inner: inner, outer: outer, centre: centre)
        let middle = (start + end) / 2
        ZStack {
            shape.fill(fill)
            shape.stroke(.white.opacity(0.08), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: small ? 15 : 18, weight: .semibold))
                .position(position(angle: middle, radius: (inner + outer) / 2))
            if hasMore {
                Circle().fill(.white.opacity(0.55)).frame(width: 4, height: 4)
                    .position(position(angle: middle, radius: outer - 8))
            }
        }
        .opacity(dimmed ? 0.3 : 1)
    }

    private func position(angle: CGFloat, radius: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: centre.x + radius * sin(radians), y: centre.y - radius * cos(radians))
    }
}

/// An annular sector, angles clockwise from 12 o'clock, in a view whose y runs down.
struct SectorShape: Shape {
    var start: CGFloat
    var end: CGFloat
    let inner: CGFloat
    let outer: CGFloat
    let centre: CGPoint

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(start, end) }
        set {
            start = newValue.first
            end = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // SwiftUI's angles start at 3 o'clock and run clockwise in a y-down view.
        let from = Angle.degrees(Double(start) - 90)
        let to = Angle.degrees(Double(end) - 90)
        var path = Path()
        path.addArc(center: centre, radius: outer, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: centre, radius: inner, startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Files dragged onto the ring go to the segment under the pointer.
private struct RingDropDelegate: DropDelegate {
    let hit: @MainActor (CGPoint) -> RingHit
    let distance: @MainActor (CGPoint) -> CGFloat
    let onHover: @MainActor (RingHit, CGFloat) -> Void
    let onPick: @MainActor (RingHit, [URL]) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated { onHover(hit(info.location), distance(info.location)) }
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = MainActor.assumeIsolated { hit(info.location) }
        let pick = onPick
        return FileDrop.handler { urls in pick(target, urls) }(info.itemProviders(for: [.fileURL]))
    }
}
