import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Segments around a centre button, with the open segment's sub-ring outside it.
struct RingView: View {
    let model: RingModel
    let reduceMotion: Bool
    let onHover: @MainActor (RingHit) -> Void
    let onPick: @MainActor (RingHit, [URL]) -> Void

    @State private var appeared = false

    var body: some View {
        let slots = model.set.slots
        ZStack {
            // As wide as the segments' reach, so the whole band reads as one control.
            let disc = (RingGeometry.ringRadius + RingGeometry.subRadius)
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(.black.opacity(0.72)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
                .frame(width: disc, height: disc)
                .position(model.centre)
                .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                let angle = RingGeometry.slotAngle(index, count: slots.count)
                RingBubble(
                    symbol: slot.action.symbol, title: slot.action.title,
                    selected: model.hover == .slot(index) || model.expanded == index,
                    dimmed: model.dropping && !slot.action.acceptsFiles, tint: nil,
                    hasMore: !model.subItems(of: index).isEmpty
                )
                .position(position(angle: angle, radius: RingGeometry.ringRadius))
            }
            if let expanded = model.expanded {
                let items = model.expandedItems
                let parent = RingGeometry.slotAngle(expanded, count: slots.count)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let angle = RingGeometry.subAngle(index, count: items.count, around: parent)
                    RingBubble(
                        symbol: item.symbol, title: item.title, selected: model.hover == .sub(index),
                        dimmed: false, tint: tint(item.tint), hasMore: false, small: true
                    )
                    .position(position(angle: angle, radius: RingGeometry.subRadius))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            centreButton.position(model.centre)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: model.expanded)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): onHover(hit(at: location))
            case .ended: onHover(.none)
            }
        }
        .onTapGesture(coordinateSpace: .local) { location in onPick(hit(at: location), []) }
        .onDrop(of: [.fileURL], delegate: RingDropDelegate(hit: hit(at:), onHover: onHover, onPick: onPick))
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.72)) {
                appeared = true
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var centreButton: some View {
        ZStack {
            Circle().fill(model.hover == .centre ? Color.wispViolet : .white.opacity(0.12))
            Image("MenuGlyph").resizable().renderingMode(.template).scaledToFit().padding(18)
        }
        .frame(width: RingGeometry.centreRadius * 2, height: RingGeometry.centreRadius * 2)
        .help("Open the shelf")
    }

    /// The view's y runs down; the ring's geometry runs up like AppKit.
    private func position(angle: CGFloat, radius: CGFloat) -> CGPoint {
        let flipped = CGPoint(x: model.centre.x, y: model.centre.y)
        let point = RingGeometry.point(at: angle, radius: radius, from: flipped)
        return CGPoint(x: point.x, y: model.centre.y * 2 - point.y)
    }

    private func hit(at location: CGPoint) -> RingHit {
        let up = CGPoint(x: location.x, y: model.centre.y * 2 - location.y)
        return RingGeometry.hit(
            up, centre: model.centre, slots: model.set.slots.count, expanded: model.expanded,
            subItems: model.expandedItems.count)
    }

    private func tint(_ tint: RingChoice.Tint) -> Color? {
        switch tint {
        case .plain: nil
        case .allow: .green
        case .deny: .red
        }
    }
}

/// One segment: a round icon with its name under it while the pointer is on it.
private struct RingBubble: View {
    let symbol: String
    let title: String
    let selected: Bool
    let dimmed: Bool
    let tint: Color?
    let hasMore: Bool
    var small = false

    var body: some View {
        let size: CGFloat = small ? 44 : 52
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: small ? 16 : 19, weight: .semibold))
                    .frame(width: size, height: size)
                    .background(Circle().fill(fill))
                if hasMore {
                    Circle().fill(.white.opacity(0.6)).frame(width: 5, height: 5).offset(x: -6, y: 6)
                }
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.75)))
                .opacity(selected ? 1 : 0)
        }
        .offset(y: 9)
        .opacity(dimmed ? 0.3 : 1)
        .scaleEffect(selected ? 1.1 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: selected)
        .accessibilityLabel(title)
    }

    private var fill: Color {
        if selected { return tint ?? .wispViolet }
        return (tint ?? .white).opacity(tint == nil ? 0.14 : 0.35)
    }
}

/// Files dragged onto the ring go to the segment under the pointer.
private struct RingDropDelegate: DropDelegate {
    let hit: @MainActor (CGPoint) -> RingHit
    let onHover: @MainActor (RingHit) -> Void
    let onPick: @MainActor (RingHit, [URL]) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated { onHover(hit(info.location)) }
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = MainActor.assumeIsolated { hit(info.location) }
        let pick = onPick
        return FileDrop.handler { urls in pick(target, urls) }(info.itemProviders(for: [.fileURL]))
    }
}
