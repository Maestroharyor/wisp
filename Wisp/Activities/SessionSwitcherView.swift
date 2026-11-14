import SwiftUI
import WispCore

/// The live sessions in the notch, opened with Hyper+G or ⌃⌥⌘G: Up and Down move, Return jumps
/// to the session's terminal, Esc closes (keys in `NotchCoordinator`). A click jumps too.
struct SessionSwitcherView: View {
    let model: NotchModel

    var body: some View {
        let sessions = model.switcherSessions
        let selected = model.switcher.selected(in: sessions.map(\.id))
        let hidden = model.services.agents.detailsHidden
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Jump to a session").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("↑↓ to move, ↩ to jump, esc to close")
                    .font(.system(size: 10)).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
            // Room for the back chevron the solo card puts at its top left.
            .padding(.leading, 26)
            .frame(height: 20)

            if sessions.isEmpty {
                Text("No live sessions")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 3) {
                            ForEach(sessions) { session in
                                SwitcherRow(session: session, selected: session.id == selected, hidden: hidden)
                                    .id(session.id)
                                    .onTapGesture { model.jumpFromSwitcher(to: session.id) }
                            }
                        }
                    }
                    .onChange(of: selected) { _, id in
                        guard let id else { return }
                        withAnimation(model.surfaceAnimation) { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SwitcherRow: View {
    let session: AgentSession
    let selected: Bool
    let hidden: Bool

    var body: some View {
        HStack(spacing: 7) {
            AgentGlyph(
                state: session.state, source: session.source, project: session.project,
                context: session.contextPercent
            )
            .font(.system(size: 11))
            Text(session.project).font(.system(size: 12, weight: .semibold)).lineLimit(1).layoutPriority(1)
            if !hidden, let branch = session.branch {
                Text(branch).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(SessionSwitcher.status(session))
                .font(.system(size: 10)).foregroundStyle(Color.secondaryText).lineLimit(1).fixedSize()
            Text(session.source.displayName)
                .font(.system(size: 10)).foregroundStyle(Color.secondaryText).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.wispViolet.opacity(0.35) : Color.project(session.project).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(selected ? Color.wispViolet : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Jumps to the session's terminal")
    }
}
