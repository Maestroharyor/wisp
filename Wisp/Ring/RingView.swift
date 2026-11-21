import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// A frosted disc with a band of icons around a lighter middle, like a dock bent into a circle.
/// The icon under the pointer lifts with a halo and its name shows in the middle; the open
/// segment's choices fan out as smaller icons outside the band. Opening, the disc springs up
/// and the icons fly out from the middle in turn; closing runs it backwards.
struct RingView: View {
    let model: RingModel
    /// Read live, since the panel is built once and kept.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let onHover: @MainActor (RingHit, CGFloat) -> Void
    let onPick: @MainActor (RingHit, [URL]) -> Void
    let onPickResult: @MainActor (Int) -> Void
    /// A file started dragging out of a folder's sub-ring.
    let onDragOut: @MainActor () -> Void
    /// An icon is being dragged to a new place: where the drag began, and where it is now.
    let onLift: @MainActor (RingHit, CGPoint) -> Void
    /// The dragged icon was let go here.
    let onLand: @MainActor (CGPoint) -> Void

    var body: some View {
        let slots = model.set.slots
        let shown = model.visible
        ZStack {
            RingDisc(centre: model.centre, dark: colorScheme == .dark)
                .scaleEffect(shown || reduceMotion ? 1 : 0.85, anchor: unit(model.centre))
                .opacity(shown ? 1 : 0)
                .animation(
                    shown ? .spring(response: 0.34, dampingFraction: 0.78) : .easeIn(duration: 0.14), value: shown)
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let angle = RingGeometry.slotAngle(index, count: slots.count)
                let isLifted = model.lifted == index
                RingIconCell(
                    icon: slot.action.icon, tileHex: slot.action.tileHex, side: RingGeometry.iconSize,
                    angle: angle, lit: lit(.slot(index)) || model.expanded == index || isLifted,
                    dimmed: model.dropping && !slot.action.acceptsFiles,
                    hasMore: !model.subItems(of: index).isEmpty, dot: model.dot(for: slot.action)
                )
                .overlay(alignment: .topTrailing) {
                    if isLifted, model.removing {
                        Image(systemName: "minus.circle.fill").font(.system(size: 18))
                            .symbolRenderingMode(.palette).foregroundStyle(.white, Color.red)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                // Running apps that aren't the ring's own sit a little quieter.
                .opacity(index >= model.pinnedCount ? 0.82 : 1)
                .opacity(isLifted && model.removing ? 0.55 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(slot.action.title)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onPick(.slot(index), []) }
                // Each icon flies out from the middle in turn, and back in on close.
                .scaleEffect(shown || reduceMotion ? 1 : 0.3)
                .position(
                    isLifted
                        ? model.liftPoint : shown || reduceMotion ? place(angle, RingGeometry.ringRadius) : model.centre
                )
                .zIndex(isLifted ? 1 : 0)
                .opacity(shown ? (searching ? 0.15 : 1) : 0)
                .animation(
                    shown
                        ? .spring(response: 0.36, dampingFraction: 0.76).delay(RingGeometry.delay(for: index))
                        : .easeIn(duration: 0.12),
                    value: shown)
            }
            if let expanded = model.expanded, shown {
                SubRing(
                    model: model, parent: expanded, count: slots.count, reduceMotion: reduceMotion,
                    onPick: onPick, onDragOut: onDragOut
                )
                .id(expanded)
            }
            centre
                .position(model.centre)
                .scaleEffect(shown || reduceMotion ? 1 : 0.5, anchor: unit(model.centre))
                .opacity(shown && !searching ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shown)
            if searching, shown {
                RingSearchCard(model: model, onPick: onPickResult)
                    .position(model.centre)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.85), value: searching)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: model.hover)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // While searching, the ring under the card is asleep.
                if searching {
                    onHover(.none, .greatestFiniteMagnitude)
                } else {
                    onHover(hit(at: location), distance(to: location))
                }
            case .ended: onHover(.none, .greatestFiniteMagnitude)
            }
        }
        .onTapGesture(coordinateSpace: .local) { location in
            if !searching { onPick(hit(at: location), []) }
        }
        // Dragging an icon moves it round the ring, or off it to remove it.
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .onChanged { drag in
                    guard !searching else { return }
                    onLift(hit(at: drag.startLocation), drag.location)
                }
                .onEnded { drag in onLand(drag.location) }
        )
        .onDrop(
            of: [.fileURL],
            delegate: RingDropDelegate(hit: hit(at:), distance: distance(to:), onHover: onHover, onPick: onPick)
        )
    }

    private var searching: Bool { !model.query.isEmpty }

    private func lit(_ hit: RingHit) -> Bool { model.hover == hit || model.picked == hit }

    /// The middle: the hovered icon's name and key in a pill, or Wisp's glyph (which opens the
    /// shelf).
    @ViewBuilder private var centre: some View {
        if let hovered = hoveredTitle {
            let onCentre = model.hover == .centre && model.lifted == nil
            HStack(spacing: 6) {
                Text(hovered.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let key = hovered.key {
                    Text(key).font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(onCentre ? Color.white.opacity(0.7) : Color.secondary)
                }
            }
            .foregroundStyle(onCentre ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: RingGeometry.innerRadius * 1.8)
            .background(Capsule().fill(onCentre ? AnyShapeStyle(Color.wispViolet) : AnyShapeStyle(.regularMaterial)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .fixedSize()
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .id(hovered.title)
            .help(model.canUndo ? "Undo the removal" : "Open the shelf")
        } else {
            Image("MenuGlyph").resizable().renderingMode(.template).scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.wispViolet.opacity(0.75))
                .frame(width: RingGeometry.centreRadius * 2, height: RingGeometry.centreRadius * 2)
                .transition(.opacity)
                .accessibilityLabel("Open the shelf")
        }
    }

    private var hoveredTitle: (title: String, key: String?)? {
        if let lifted = model.lifted, model.set.slots.indices.contains(lifted) {
            let title = model.set.slots[lifted].action.title
            return (model.removing ? "Remove \(title)" : title, nil)
        }
        if model.hover == .none, let hint = model.hint { return (hint, model.canUndo ? "⌘Z" : nil) }
        switch model.hover {
        case .slot(let index):
            guard model.set.slots.indices.contains(index) else { return nil }
            return (model.set.slots[index].action.title, Self.key(for: index))
        case .sub(let item):
            let items = model.expandedItems
            return items.indices.contains(item) ? (items[item].title, nil) : nil
        case .centre:
            return model.canUndo ? ("Undo", "⌘Z") : ("Shelf", nil)
        case .none:
            return nil
        }
    }

    /// The number key that picks a segment: 1 to 9, then 0 for the tenth.
    private static func key(for index: Int) -> String? {
        switch index {
        case 0..<9: "\(index + 1)"
        case 9: "0"
        default: nil
        }
    }

    private func place(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: model.centre.x + radius * sin(radians), y: model.centre.y - radius * cos(radians))
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

/// The frosted disc under the icons: a band of material with a faint violet wash, and a lighter
/// middle, each edged with a hairline. Follows Light and Dark mode.
struct RingDisc: View {
    let centre: CGPoint
    let dark: Bool

    var body: some View {
        let outer = (RingGeometry.ringOuter + 8) * 2
        let inner = RingGeometry.innerRadius * 2
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().fill(
                LinearGradient(
                    colors: [
                        Color.wispViolet.opacity(dark ? 0.16 : 0.08), Color.wispViolet.opacity(dark ? 0.06 : 0.02),
                    ],
                    startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Color.white.opacity(dark ? 0.14 : 0.6), lineWidth: 1)
            Circle()
                .fill(Color.wispViolet.opacity(dark ? 0.14 : 0.09))
                .overlay(Circle().strokeBorder(Color.white.opacity(dark ? 0.12 : 0.7), lineWidth: 1))
                .frame(width: inner, height: inner)
        }
        .frame(width: outer, height: outer)
        .shadow(color: .black.opacity(dark ? 0.45 : 0.16), radius: 28, y: 10)
        .position(centre)
    }
}

/// One icon on the ring: lifted, with a frosted halo and a violet glow, when it's under the
/// pointer; a dot below for a running app; a small mark on the outside when it opens choices.
struct RingIconCell: View {
    let icon: RingIcon
    let tileHex: String
    let side: CGFloat
    /// Where it sits round the ring, for the outside mark.
    let angle: CGFloat
    let lit: Bool
    let dimmed: Bool
    let hasMore: Bool
    var dot: RingRunState = .none

    var body: some View {
        let radians = angle * .pi / 180
        ZStack {
            if lit {
                Circle()
                    .fill(.thinMaterial)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    .frame(width: side * 1.5, height: side * 1.5)
                    .shadow(color: Color.wispViolet.opacity(0.5), radius: 18)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            RingTileIcon(icon: icon, tileHex: tileHex, side: side)
                .scaleEffect(lit ? 1.12 : 1)
            if dot != .none {
                // Like the Dock: a dot under a running app, violet for the one in front.
                Circle().fill(dot == .frontmost ? Color.wispViolet : Color.primary.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .offset(y: side / 2 + (lit ? 9 : 6))
            }
            if hasMore {
                Circle().fill(Color.primary.opacity(0.4)).frame(width: 4, height: 4)
                    .offset(x: sin(radians) * (side / 2 + 9), y: -cos(radians) * (side / 2 + 9))
            }
        }
        .frame(width: side * 1.5, height: side * 1.5)
        .opacity(dimmed ? 0.3 : 1)
    }
}

/// Typing on the ring: what was typed, and the ring actions and apps it finds. Return or a
/// click runs the highlighted one.
private struct RingSearchCard: View {
    let model: RingModel
    let onPick: @MainActor (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(model.query).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.head)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            if model.results.isEmpty {
                Text("Nothing found").font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                Button {
                    onPick(index)
                } label: {
                    HStack(spacing: 8) {
                        RingTileIcon(icon: result.action.icon, tileHex: result.action.tileHex, side: 20)
                        Text(result.action.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            .foregroundStyle(index == model.selectedResult ? Color.white : Color.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(index == model.selectedResult ? Color.wispViolet : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: model.selectedResult)
    }
}

/// The open segment's choices: smaller icons on a frosted arc outside the band, fanned out
/// from the segment's angle.
private struct SubRing: View {
    let model: RingModel
    let parent: Int
    let count: Int
    let reduceMotion: Bool
    let onPick: @MainActor (RingHit, [URL]) -> Void
    let onDragOut: @MainActor () -> Void

    @State private var fanned = false

    var body: some View {
        let items = model.expandedItems
        let parentAngle = RingGeometry.slotAngle(parent, count: count)
        let open = fanned || reduceMotion
        let first = RingGeometry.subSector(0, count: items.count, around: parentAngle)
        let last = RingGeometry.subSector(max(items.count - 1, 0), count: items.count, around: parentAngle)
        let half = RingGeometry.subStep / 2
        let parentHex = model.set.slots.indices.contains(parent) ? model.set.slots[parent].action.tileHex : "#8E8E93"
        ZStack {
            if !items.isEmpty {
                // Every choice starts folded on the parent's angle and swings to its own.
                SectorShape(
                    start: open ? first.start - 2 : parentAngle - half, end: open ? last.end + 2 : parentAngle + half,
                    inner: RingGeometry.subInner, outer: RingGeometry.subOuter, centre: model.centre
                )
                .fill(.regularMaterial)
                .overlay(
                    SectorShape(
                        start: open ? first.start - 2 : parentAngle - half,
                        end: open ? last.end + 2 : parentAngle + half,
                        inner: RingGeometry.subInner, outer: RingGeometry.subOuter, centre: model.centre
                    )
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                .opacity(fanned || reduceMotion ? 1 : 0)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angle = open ? RingGeometry.subAngle(index, count: items.count, around: parentAngle) : parentAngle
                RingIconCell(
                    icon: item.icon, tileHex: Self.hex(for: item.tint, parent: parentHex),
                    side: RingGeometry.subIconSize, angle: angle,
                    lit: model.hover == .sub(index) || model.picked == .sub(index), dimmed: false, hasMore: false
                )
                .modifier(FileDragOut(path: FolderPeek.path(of: item), onDragOut: onDragOut))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onPick(.sub(index), []) }
                .position(place(angle))
                .opacity(fanned ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { fanned = true }
        }
    }

    private static func hex(for tint: RingChoice.Tint, parent: String) -> String {
        switch tint {
        case .allow: "#30D158"
        case .deny: "#FF453A"
        case .plain: parent
        }
    }

    private func place(_ angle: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: model.centre.x + RingGeometry.subRadius * sin(radians),
            y: model.centre.y - RingGeometry.subRadius * cos(radians))
    }
}

/// Lets a folder's file be dragged out of its icon, like from a Finder window.
private struct FileDragOut: ViewModifier {
    let path: String?
    let onDragOut: @MainActor () -> Void

    func body(content: Content) -> some View {
        if let path {
            content
                .contentShape(Circle())
                .onDrag {
                    onDragOut()
                    return NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
                }
        } else {
            content
        }
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
