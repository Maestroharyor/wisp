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
                    shown ? .wispPopover : .wispDismiss, value: shown)
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
                    } else if let badge = windowBadge(index) {
                        RingBadge(text: badge).offset(x: -4, y: 4)
                    }
                }
                // Running apps that aren't the ring's own sit a little quieter.
                .opacity(index >= model.pinnedCount ? 0.82 : 1)
                .opacity(isLifted && model.removing ? 0.55 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(slot.action.title)
                .accessibilityValue(slotValue(index, slot.action))
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
                        ? .wispPopover.delay(RingGeometry.delay(for: index))
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
                .animation(.wispPopover, value: shown)
            if searching, shown {
                RingSearchCard(model: model, onPick: onPickResult)
                    .position(model.centre)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.wispSmooth, value: searching)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.wispControl, value: model.hover)
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

    private var pillFill: Color {
        colorScheme == .dark ? Color(white: 0.11) : .white
    }

    private func lit(_ hit: RingHit) -> Bool { model.hover == hit || model.picked == hit }

    /// The middle: the hovered icon's name and key in a pill, or Wisp's glyph (which opens the
    /// shelf).
    @ViewBuilder private var centre: some View {
        if let preview = model.preview, model.lifted == nil {
            RingPreviewCard(preview: preview)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                .id(preview.key)
        } else if let hovered = hoveredTitle {
            let onCentre = model.hover == .centre && model.lifted == nil
            HStack(spacing: 6) {
                Text(hovered.title).font(.title3.weight(.semibold)).lineLimit(1)
                if let key = hovered.key {
                    Text(key).font(.callout.weight(.medium).monospacedDigit())
                        .foregroundStyle(onCentre ? Color.white.opacity(0.7) : Color.secondary)
                }
            }
            .foregroundStyle(onCentre ? Color.white : Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .frame(maxWidth: RingGeometry.innerRadius * 1.8)
            // Solid, as on the reference: white in Light, near-black in Dark.
            .background {
                // Solid on a filled centre; glass over an open one, so it sits with the desktop.
                if onCentre {
                    Capsule().fill(Color.wispViolet)
                } else if clearCentre {
                    Color.clear.wispSurface(Capsule(), glass: .frosted)
                } else {
                    Capsule().fill(pillFill)
                }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 10, y: 3)
            .fixedSize()
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .id(hovered.title)
            .help(model.canUndo ? "Undo the removal" : "Open the shelf")
        } else {
            Image("MenuGlyph").resizable().renderingMode(.template).scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.wispViolet.opacity(clearCentre ? 0.85 : 0.6))
                .frame(width: 48, height: 48)
                // Over an open centre the glyph sits on a small chip, so it reads on any wallpaper.
                .background {
                    if clearCentre { Color.clear.wispSurface(Circle(), glass: .frosted) }
                }
                .frame(width: RingGeometry.centreRadius * 2, height: RingGeometry.centreRadius * 2)
                .transition(.opacity)
                .accessibilityLabel("Open the shelf")
        }
    }

    private var clearCentre: Bool { Preferences.shared.ringLook.centre == .clear }

    private func windowBadge(_ index: Int) -> String? {
        model.windowCounts[index].flatMap(AppWindows.badge(count:))
    }

    /// What VoiceOver reads after a segment's name: whether its app is open, and how many windows.
    private func slotValue(_ index: Int, _ action: RingAction) -> String {
        var parts: [String] = []
        switch model.dot(for: action) {
        case .frontmost: parts.append("In front")
        case .running: parts.append("Open")
        case .none: break
        }
        if let count = model.windowCounts[index], count > 1 { parts.append("\(count) windows") }
        return parts.joined(separator: ", ")
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

/// The disc under the icons, kept airy: a nearly clear band of glass with a soft violet glow
/// toward the middle, one wide shadow and no hard edge. The middle is a hole onto the desktop,
/// plain glass or a soft violet disc, as chosen in Settings › Ring. Follows Light and Dark mode
/// (smoky glass in Dark rather than a flat grey).
struct RingDisc: View {
    let centre: CGPoint
    let dark: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    /// The glass, tint and centre chosen in Settings › Ring.
    private var look: RingLook { Preferences.shared.ringLook.clamped() }

    var body: some View {
        let outer = (RingGeometry.ringOuter + 10) * 2
        let inner = RingGeometry.innerRadius * 2
        let tint = look.tintFactor
        let band = RingBand(innerRadius: RingGeometry.innerRadius)
        let rim = Color.white.opacity(contrast == .increased ? 0.95 : dark ? 0.16 : 0.85)
        ZStack {
            Color.clear.wispSurface(band, glass: look.glass)
            // The band: a glow that rises toward the middle and is gone by the rim.
            band.fill(
                RadialGradient(
                    colors: [
                        Color.wispViolet.opacity((dark ? 0.20 : 0.12) * tint),
                        Color.wispViolet.opacity((dark ? 0.07 : 0.035) * tint),
                        .clear,
                    ],
                    center: .center, startRadius: RingGeometry.innerRadius, endRadius: outer / 2))
            Circle().strokeBorder(Color.white.opacity(dark ? 0.12 : 0.55), lineWidth: 1)
            middle(tint: tint)
                .overlay(Circle().strokeBorder(rim, lineWidth: 1))
                .frame(width: inner, height: inner)
        }
        .frame(width: outer, height: outer)
        .compositingGroup()
        .shadow(color: .black.opacity(dark ? 0.30 : 0.08), radius: 40, y: 12)
        .position(centre)
    }

    @ViewBuilder private func middle(tint: Double) -> some View {
        switch look.centre {
        case .clear:
            // Open: the desktop shows through, and only the rim marks the edge.
            Color.clear
        case .frosted:
            Color.clear.wispSurface(Circle(), glass: .frosted)
        case .tinted:
            // Soft and even: a pale violet wash, a touch lighter in the middle.
            Circle()
                .fill(
                    RadialGradient(
                        colors: dark
                            ? [Color.wispViolet.opacity(0.20 * tint), Color.wispViolet.opacity(0.12 * tint)]
                            : [Color.wispViolet.opacity(0.08 * tint), Color.wispViolet.opacity(0.14 * tint)],
                        center: .center, startRadius: 0, endRadius: RingGeometry.innerRadius)
                )
                .background(Color.clear.wispSurface(Circle(), glass: .clear))
        }
    }
}

/// The ring's band: the disc with its middle cut out, so a clear centre is a real hole.
struct RingBand: InsettableShape {
    let innerRadius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - inset
        // Insetting moves both edges into the band, so the hole grows.
        let hole = innerRadius + inset
        var path = Path()
        path.addArc(center: centre, radius: outer, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        path.closeSubpath()
        guard hole < outer else { return path }
        // Drawn the other way round, so the default fill leaves it empty.
        path.addArc(center: centre, radius: hole, startAngle: .degrees(360), endAngle: .zero, clockwise: true)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> RingBand {
        var copy = self
        copy.inset += amount
        return copy
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
    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        let radians = angle * .pi / 180
        ZStack {
            if lit {
                // A frosted halo with a violet bloom that spills into the disc.
                Circle()
                    .fill(.thinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(dark ? 0.08 : 0.55)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(dark ? 0.25 : 0.9), lineWidth: 1))
                    .frame(width: side * 1.45, height: side * 1.45)
                    .shadow(color: Color.wispViolet.opacity(0.35), radius: 28)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            RingTileIcon(icon: icon, tileHex: tileHex, side: side)
                .scaleEffect(lit ? 1.08 : 1)
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
        .wispSurface(cornerRadius: SurfaceRadius.card, role: .card)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .animation(.wispControl, value: model.selectedResult)
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
                .fill(.ultraThinMaterial)
                .overlay(
                    SectorShape(
                        start: open ? first.start - 2 : parentAngle - half,
                        end: open ? last.end + 2 : parentAngle + half,
                        inner: RingGeometry.subInner, outer: RingGeometry.subOuter, centre: model.centre
                    )
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .opacity(fanned || reduceMotion ? 1 : 0)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angle = open ? RingGeometry.subAngle(index, count: items.count, around: parentAngle) : parentAngle
                RingIconCell(
                    icon: item.icon, tileHex: Self.hex(for: item.tint, parent: parentHex),
                    side: RingGeometry.subIconSize, angle: angle,
                    lit: model.hover == .sub(index) || model.picked == .sub(index), dimmed: false, hasMore: false
                )
                .overlay(alignment: .topTrailing) {
                    if ConvertTargets.format(of: item) != nil { RingBadge(text: "\(index + 1)").offset(x: -2, y: 2) }
                }
                .overlay(alignment: .bottom) {
                    if let format = ConvertTargets.format(of: item) {
                        Text(format.title).font(.system(size: 9, weight: .bold)).foregroundStyle(.primary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(.regularMaterial))
                            .offset(y: 4)
                    }
                }
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
            withAnimation(.wispPopover) { fanned = true }
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

/// A small violet count on a ring icon: an app's windows, or a format's number key.
private struct RingBadge: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(Capsule().fill(Color.wispVioletText(contrast: contrast)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

/// The hovered window's live picture in the ring's middle, with its title under it.
private struct RingPreviewCard: View {
    let preview: RingPreview
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let size = WindowPreview.size(
            for: CGSize(width: preview.image.width, height: preview.image.height), fitting: RingController.previewSide)
        VStack(spacing: 8) {
            Image(decorative: preview.image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: SurfaceRadius.control, style: .continuous))
                .padding(5)
                .wispSurface(cornerRadius: SurfaceRadius.control + 5)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.16), radius: 12, y: 4)
            Text(preview.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: RingGeometry.innerRadius * 1.7)
                .wispSurface(Capsule(), glass: .frosted)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(preview.title)")
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
