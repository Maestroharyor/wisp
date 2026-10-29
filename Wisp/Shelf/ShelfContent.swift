import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Content of the open shelf: Home widgets, the tray, or the drop tiles during a drag.
struct ShelfContent: View {
    let model: NotchModel

    var body: some View {
        let insets = ShellMetrics.shelfInsets(notchStyle: model.isNotchStyle, notchHeight: model.notchHeight)
        Group {
            if model.dragging {
                DropTiles(model: model)
            } else {
                switch model.page {
                case .home: HomePage(model: model)
                case .tray: TrayPage(model: model)
                case .media: MediaPage(model: model)
                case .widgets: WidgetsPage(model: model)
                }
            }
        }
        .padding(EdgeInsets(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            let hub = model.services.agents
            if let approval = hub.approvals.first {
                ApprovalBar(approval: approval, hub: hub)
                    .padding(.horizontal, insets.leading)
                    .padding(.bottom, 10)
            }
        }
        .animation(model.surfaceAnimation, value: model.services.agents.approvals.first?.id)
        .foregroundStyle(.white)
    }
}

/// Reads file URLs from drop providers and hands them over once all have loaded.
enum FileDrop {
    static func handler(_ action: @escaping @MainActor @Sendable ([URL]) -> Void) -> ([NSItemProvider]) -> Bool {
        { providers in
            let loadable = providers.filter { $0.canLoadObject(ofClass: URL.self) }
            guard !loadable.isEmpty else { return false }
            let collector = URLCollector(expected: loadable.count, action: action)
            for provider in loadable {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    Task { await collector.add(url) }
                }
            }
            return true
        }
    }
}

private actor URLCollector {
    private var urls: [URL] = []
    private var remaining: Int
    private let action: @MainActor @Sendable ([URL]) -> Void

    init(expected: Int, action: @escaping @MainActor @Sendable ([URL]) -> Void) {
        remaining = expected
        self.action = action
    }

    func add(_ url: URL?) async {
        if let url, url.isFileURL { urls.append(url) }
        remaining -= 1
        guard remaining == 0, !urls.isEmpty else { return }
        await action(urls)
    }
}

/// Card background shared by widgets and tiles.
struct CardBackground: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: ShellMetrics.widgetCornerRadius, style: .continuous)
                .fill(.white.opacity(highlighted ? 0.14 : 0.06))
        )
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardBackground(highlighted: highlighted)) }
}
