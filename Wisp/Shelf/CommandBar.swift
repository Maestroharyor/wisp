import AppKit
import SwiftUI
import WispCore

/// ⌘K in the window: one field that finds pages, clips, notes, reminders, events and apps,
/// and makes a timer, reminder or event from a Quick add sentence. Only what's already loaded
/// is searched, so it never asks for access; nothing typed is logged.
struct CommandBar: View {
    let model: NotchModel
    @Bindable var navigation: WindowNavigation

    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var services: AppServices { model.services }
    private var query: String { navigation.commandQuery }

    var body: some View {
        let groups = CommandSearch.results(
            query: query, candidates: candidates, now: .now, calendar: .autoupdatingCurrent)
        let items = CommandSearch.flat(groups)
        VStack(spacing: 0) {
            field(items)
            Divider().opacity(0.5)
            if items.isEmpty {
                Text("Nothing found. Try \u{201C}25 min\u{201D} or \u{201C}remind me to call Sam at 5\u{201D}.")
                    .wispFont(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                list(groups, items: items)
            }
        }
        .frame(width: 560)
        .wispSurface(cornerRadius: WindowShell.panelRadius, role: .card)
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .onAppear {
            services.appCatalog.refreshIfStale()
            focused = true
        }
        .onChange(of: navigation.commandQuery) { highlighted = 0 }
    }

    private func field(_ items: [CommandItem]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .wispFont(.title3)
                .foregroundStyle(.secondary)
            TextField("Ask, create, find anything\u{2026}", text: $navigation.commandQuery)
                .textFieldStyle(.plain)
                .wispFont(.title3)
                .focused($focused)
                .onSubmit { run(items) }
                .onKeyPress(.upArrow) {
                    highlighted = CommandSearch.stepped(highlighted, by: -1, count: items.count)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    highlighted = CommandSearch.stepped(highlighted, by: 1, count: items.count)
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                .accessibilityLabel("Ask, create, find anything")
            Text("esc")
                .wispFont(.caption, weight: .medium)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func list(_ groups: [CommandResultGroup], items: [CommandItem]) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { group in
                        Text(group.kind.title)
                            .wispFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.items) { item in
                            let index = items.firstIndex(of: item) ?? 0
                            row(item, highlighted: index == highlighted) { run(item) }
                                .id(item.id)
                                .onHover { if $0 { highlighted = index } }
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: highlighted) { _, index in
                if items.indices.contains(index) { reader.scrollTo(items[index].id) }
            }
        }
    }

    private func row(_ item: CommandItem, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon(item, highlighted: highlighted).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .wispFont(.body, weight: item.kind == .create ? .semibold : .regular)
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .wispFont(.caption)
                            .foregroundStyle(
                                highlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary)
                            )
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if highlighted {
                    Image(systemName: "return")
                        .wispFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if highlighted {
                    RoundedRectangle(cornerRadius: SurfaceRadius.control, style: .continuous).fill(Color.wispViolet)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    /// An app's own icon; a violet symbol for everything else.
    @ViewBuilder private func icon(_ item: CommandItem, highlighted: Bool) -> some View {
        if item.kind == .app, let image = AppIcon.image(forAppID: String(item.id.dropFirst("app:".count))) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: item.symbol)
                .wispFont(.body)
                .foregroundStyle(highlighted ? Color.white : Color.wispViolet)
        }
    }

    // MARK: Sources

    private var candidates: [CommandItem] {
        actions + pages + apps + clips + notes + reminders + events
    }

    private var actions: [CommandItem] {
        [
            CommandItem(
                kind: .action, id: "action:newNote", title: "New note", subtitle: "", symbol: "square.and.pencil"),
            CommandItem(
                kind: .action, id: "action:customiseHome", title: "Customise Home", subtitle: "",
                symbol: "square.grid.2x2"),
            CommandItem(
                kind: .action, id: "action:settings", title: "Open Settings", subtitle: "", symbol: "gearshape"),
        ]
    }

    private var pages: [CommandItem] {
        navigation.sections(services: services).flatMap(\.rows).map { row in
            CommandItem(
                kind: .page, id: "page:" + row.rawValue, title: WindowRow.title(of: row, services: services),
                subtitle: "", symbol: WindowRow.symbol(of: row, services: services))
        }
    }

    private var apps: [CommandItem] {
        services.appCatalog.apps.map {
            CommandItem(kind: .app, id: "app:" + $0.bundleID, title: $0.name, subtitle: "", symbol: "app")
        }
    }

    private var clips: [CommandItem] {
        services.clipboard.history.items.compactMap { clip in
            guard let text = clip.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return CommandItem(
                kind: .clip, id: "clip:" + clip.id.uuidString, title: String(line.prefix(80)),
                subtitle: clip.sourceApp ?? "", symbol: clip.pinned ? "pin.fill" : "doc.on.clipboard",
                keywords: String(text.prefix(2000)))
        }
    }

    private var notes: [CommandItem] {
        services.notes.book.sorted.map { note in
            CommandItem(
                kind: .note, id: "note:" + note.id.uuidString, title: note.title, subtitle: note.preview,
                symbol: "note.text", keywords: String(note.body.prefix(4000)))
        }
    }

    private var reminders: [CommandItem] {
        services.reminders.items.filter { !$0.isCompleted }.map { reminder in
            CommandItem(
                kind: .reminder, id: "reminder:" + reminder.id, title: reminder.title, subtitle: reminder.list,
                symbol: "checklist")
        }
    }

    private var events: [CommandItem] {
        services.calendar.events.map { event in
            CommandItem(
                kind: .event, id: "event:" + event.id, title: event.title,
                subtitle: event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()), symbol: "calendar")
        }
    }

    // MARK: Running

    private func run(_ items: [CommandItem]) {
        guard items.indices.contains(highlighted) else { return }
        run(items[highlighted])
    }

    private func run(_ item: CommandItem) {
        let value = String(item.id.drop { $0 != ":" }.dropFirst())
        switch item.kind {
        case .create:
            services.quickInput.text = query
            services.quickInput.submit()
            // The card to confirm it on, with Add and Cancel.
            navigation.open(.widget(WidgetKind.quickInput.rawValue))
        case .action:
            runAction(value)
        case .page:
            if let row = WindowDestination(rawValue: value) { navigation.select(row) }
        case .app:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case .clip:
            if let clip = services.clipboard.history.items.first(where: { $0.id.uuidString == value }) {
                services.clipboard.copy(clip)
            }
        case .note:
            services.notes.selectedID = UUID(uuidString: value)
            navigation.open(.widget(WidgetKind.notes.rawValue))
        case .reminder:
            navigation.open(.widget(WidgetKind.reminders.rawValue))
        case .event:
            navigation.open(.widget(WidgetKind.calendar.rawValue))
        }
        close()
    }

    private func runAction(_ action: String) {
        switch action {
        case "newNote":
            _ = services.notes.newNote()
            navigation.open(.widget(WidgetKind.notes.rawValue))
        case "customiseHome":
            navigation.select(.home)
            navigation.customisingHome = true
        case "settings":
            services.openSettings()
        default:
            break
        }
    }

    private func close() {
        navigation.showsCommandBar = false
    }
}
