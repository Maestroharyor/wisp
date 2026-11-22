import AppKit
import Combine
import SwiftUI
import WispCore

// MARK: Notes

/// Notes in the window: the notes down the side, pinned first then newest, with search, and
/// the chosen one in a roomy editor. Everything stays on this Mac.
struct NotesPage: View {
    @Bindable var store: NotesStore
    @State private var query = ""
    @State private var width: CGFloat = 0
    /// The window's undo stack, which holds note deletes and pins as well as typing.
    @Environment(\.undoManager) private var undoManager
    /// The name of the note action Undo would reverse next, if it's one of this page's.
    @State private var undoName: String?
    @FocusState private var editing: Bool
    @FocusState private var searching: Bool

    var body: some View {
        let notes = store.book.search(query)
        WindowPageFrame {
            WindowPageHeader(
                symbol: "note.text", tint: .yellow, title: "Notes",
                subtitle: "Jot it down, find it later. Kept on this Mac.",
                count: store.book.notes.count == 1 ? "1 note" : "\(store.book.notes.count) notes"
            ) {
                if let undoName {
                    Button("Undo \(undoName.lowercased())") { undoManager?.undo() }
                        // While typing, ⌘Z stays the text field's own undo.
                        .keyboardShortcut(editing || searching ? nil : KeyboardShortcut("z", modifiers: .command))
                }
                WindowPrimaryButton(title: "New note", symbol: "square.and.pencil") {
                    store.newNote()
                    editing = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        } content: {
            HStack(alignment: .top, spacing: WindowLayout.spacing) {
                if WindowLayout.masterDetail(width: width) || store.selected == nil {
                    list(notes)
                        .frame(width: WindowLayout.masterDetail(width: width) ? WindowLayout.masterWidth : nil)
                }
                if WindowLayout.masterDetail(width: width) || store.selected != nil {
                    editor
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
        }
        .onReceive(undoChanges) { _ in readUndoName() }
        .onAppear(perform: readUndoName)
    }

    /// Every change to the undo stack, so the Undo button follows what ⌘Z would do.
    private var undoChanges: some Publisher<Notification, Never> {
        let center = NotificationCenter.default
        return Publishers.Merge3(
            center.publisher(for: .NSUndoManagerDidCloseUndoGroup, object: undoManager),
            center.publisher(for: .NSUndoManagerDidUndoChange, object: undoManager),
            center.publisher(for: .NSUndoManagerDidRedoChange, object: undoManager))
    }

    private func readUndoName() {
        guard let undoManager, undoManager.canUndo else {
            undoName = nil
            return
        }
        let name = undoManager.undoActionName
        undoName = NoteUndo.names.contains(name) ? name : nil
    }

    private func list(_ notes: [Note]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryText)
                TextField("Search notes", text: $query).textFieldStyle(.plain)
                    .focused($searching)
                    .onKeyPress(.escape) {
                        guard !query.isEmpty else { return .ignored }
                        query = ""
                        return .handled
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(.primary.opacity(0.08)))
            .findShortcut($searching)
            if notes.isEmpty {
                WindowEmptyState(
                    symbol: query.isEmpty ? "note.text" : "magnifyingglass",
                    title: query.isEmpty ? "No notes yet" : "No matches",
                    message: query.isEmpty ? "Start one with New note." : "Try another word."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        ForEach(notes) { note in
                            Button {
                                store.selectedID = note.id
                            } label: {
                                NoteRow(note: note, selected: note.id == store.selectedID)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(note) }
                        }
                    }
                }
                .scrollFade()
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .windowCardBackground()
    }

    @ViewBuilder private var editor: some View {
        if let note = store.selected {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    if !WindowLayout.masterDetail(width: width) {
                        Button("All notes", systemImage: "chevron.left") { store.selectedID = nil }
                            .buttonStyle(.borderless)
                    }
                    TimelineView(.everyMinute) { context in
                        Text("Edited \(RelativeAge.long(from: note.updated, to: context.date))")
                            .wispFont(.subheadline).foregroundStyle(Color.secondaryText)
                    }
                    Spacer()
                    Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") {
                        togglePin(note)
                    }
                    .labelStyle(.iconOnly)
                    .help(note.pinned ? "Unpin" : "Pin to the top")
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.body, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .help("Copy the note")
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(note) }
                        .labelStyle(.iconOnly)
                        .help("Delete the note")
                        // Only outside the editor, where ⌘⌫ deletes to the start of the line.
                        .keyboardShortcut(editing || searching ? nil : KeyboardShortcut(.delete, modifiers: .command))
                }
                .buttonStyle(.borderless)
                TextEditor(text: $store.text)
                    // A fresh text view per note, so undoing typing can't change a different note.
                    .id(note.id)
                    .wispFont(.title3)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .focused($editing)
                    .overlay(alignment: .topLeading) {
                        if store.text.isEmpty {
                            Text("Start typing. The first line is the title.")
                                .wispFont(.title3).foregroundStyle(Color.secondaryText)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: WindowLayout.readableCap, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .windowCardBackground()
        } else {
            WindowEmptyState(
                symbol: "note.text", title: "No note open", message: "Pick a note on the left, or start a new one."
            ) {
                WindowPrimaryButton(title: "New note", symbol: "square.and.pencil") { store.newNote() }
            }
            .frame(maxHeight: .infinity)
            .windowCardBackground()
        }
    }

    @ViewBuilder private func menu(_ note: Note) -> some View {
        Button(note.pinned ? "Unpin" : "Pin") { togglePin(note) }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.body, forType: .string)
        }
        Divider()
        Button("Delete", role: .destructive) { delete(note) }
    }

    private func delete(_ note: Note) {
        NoteUndo.delete(note.id, in: store, undoManager: undoManager)
    }

    private func togglePin(_ note: Note) {
        NoteUndo.togglePin(note.id, in: store, undoManager: undoManager)
    }
}

/// Note deletes and pins that Undo and Redo can reverse in turn, however many there are.
@MainActor
private enum NoteUndo {
    static let names: Set<String> = ["Delete", "Pin", "Unpin"]

    static func delete(_ id: UUID, in store: NotesStore, undoManager: UndoManager?) {
        guard let note = store.remove(id) else { return }
        undoManager?.registerUndo(withTarget: store) { store in
            restore(note, in: store, undoManager: undoManager)
        }
        undoManager?.setActionName("Delete")
    }

    private static func restore(_ note: Note, in store: NotesStore, undoManager: UndoManager?) {
        store.restore(note)
        undoManager?.registerUndo(withTarget: store) { store in
            delete(note.id, in: store, undoManager: undoManager)
        }
        undoManager?.setActionName("Delete")
    }

    static func togglePin(_ id: UUID, in store: NotesStore, undoManager: UndoManager?) {
        let wasPinned = store.book.note(id)?.pinned ?? false
        store.togglePin(id)
        undoManager?.registerUndo(withTarget: store) { store in
            togglePin(id, in: store, undoManager: undoManager)
        }
        undoManager?.setActionName(wasPinned ? "Unpin" : "Pin")
    }
}

/// A note in the list: a tinted glyph, the title with a pin, its second line and when it changed.
private struct NoteRow: View {
    let note: Note
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: note.pinned ? "pin.fill" : "note.text")
                .wispFont(.callout, weight: .semibold)
                .foregroundStyle(note.pinned ? Color.orange : Color.yellow)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                        .fill((note.pinned ? Color.orange : Color.yellow).opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.title).wispFont(.body, weight: .semibold).lineLimit(1)
                    Spacer(minLength: 4)
                    TimelineView(.everyMinute) { context in
                        Text(RelativeAge.short(from: note.updated, to: context.date))
                            .wispFont(.caption).foregroundStyle(Color.secondaryText)
                    }
                }
                Text(note.preview.isEmpty ? "No more text" : note.preview)
                    .wispFont(.subheadline).foregroundStyle(Color.secondaryText).lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: SurfaceRadius.row + 2, style: .continuous)
                .fill(selected ? Color.wispViolet.opacity(0.22) : .primary.opacity(hovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: Shortcuts

/// Shortcuts in the window: favourites first, then every Shortcut, as a searchable grid of tiles.
struct ShortcutsPage: View {
    let runner: ShortcutsRunner
    let preferences: Preferences

    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        let favourites = ShortcutList.matching(
            ShortcutList.favourites(preferences.favouriteShortcuts, available: runner.available), query: query)
        let all = ShortcutList.matching(runner.available, query: query)
        WindowWidgetPage {
            WindowPageHeader(
                symbol: "square.stack.3d.up.fill", tint: .pink, title: "Shortcuts",
                subtitle: "Run your Shortcuts with a click. Favourites come first.",
                count: runner.hasListed ? "\(runner.available.count) shortcuts" : nil
            ) {
                Button("Refresh", systemImage: "arrow.clockwise", action: runner.refresh)
                    .labelStyle(.iconOnly)
                    .help("Refresh the list")
                Button("Open Shortcuts", systemImage: "arrow.up.forward.app", action: Self.openApp)
            }
        } content: { width in
            VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryText)
                    TextField("Search Shortcuts", text: $query).textFieldStyle(.plain)
                        .focused($searching)
                        .onKeyPress(.escape) {
                            guard !query.isEmpty else { return .ignored }
                            query = ""
                            return .handled
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.primary.opacity(0.08)))
                .frame(maxWidth: 520)
                .findShortcut($searching)
                if !runner.hasListed {
                    LoadingLabel("Reading your Shortcuts…").frame(minHeight: 200).windowCardBackground()
                } else if runner.available.isEmpty {
                    WindowEmptyState(
                        symbol: "square.stack.3d.up", title: "No Shortcuts yet",
                        message: "Shortcuts you make in the Shortcuts app show up here, ready to run."
                    ) {
                        WindowPrimaryButton(
                            title: "Open Shortcuts", symbol: "arrow.up.forward.app", action: Self.openApp)
                    }
                    .windowCardBackground()
                } else if all.isEmpty {
                    WindowEmptyState(
                        symbol: "magnifyingglass", title: "No results for \u{201C}\(query)\u{201D}",
                        message: "Check the spelling or try another word."
                    )
                    .windowCardBackground()
                } else {
                    if !favourites.isEmpty {
                        WindowCard(title: "Favourites", symbol: "star.fill", tint: .yellow, count: favourites.count) {
                            grid(favourites, width: width - 32)
                        }
                    }
                    WindowCard(title: "All Shortcuts", symbol: "square.stack.3d.up", tint: .pink, count: all.count) {
                        grid(all, width: width - 32)
                    }
                }
            }
        }
        .onAppear { runner.refreshIfStale() }
    }

    private func grid(_ names: [String], width: CGFloat) -> some View {
        LazyVGrid(columns: windowGridColumns(width: width, minimum: 180), spacing: WindowLayout.spacing) {
            ForEach(names, id: \.self) { name in
                ShortcutTile(name: name, running: runner.running == name, busy: runner.running != nil) {
                    runner.run(name)
                }
            }
        }
    }

    private static func openApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
    }
}

/// A Shortcut as a tile: an icon and its name, outlined in Wisp violet while it runs.
private struct ShortcutTile: View {
    let name: String
    let running: Bool
    /// Another Shortcut is running; the runner takes one at a time.
    let busy: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if running {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                            .wispFont(.body, weight: .semibold)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
                .background(Circle().fill(running ? AnyShapeStyle(.ink.opacity(0.1)) : AnyShapeStyle(Color.pink)))
                Text(name)
                    .wispFont(.body, weight: .medium)
                    .foregroundStyle(.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: SurfaceRadius.row + 2, style: .continuous).fill(
                    .primary.opacity(hovering ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                    .strokeBorder(Color.wispViolet, lineWidth: running ? 2 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy && !running)
        .help("Run \(name)")
        .accessibilityValue(running ? "Running" : "")
        .onHover { hovering = $0 }
    }
}

// MARK: Mirror

/// The camera mirror in the window: a large preview in the middle. The camera runs only while
/// the page shows.
struct MirrorPage: View {
    let camera: CameraMirror

    var body: some View {
        WindowPageFrame {
            WindowPageHeader(
                symbol: "person.crop.square", tint: .teal, title: "Mirror",
                subtitle: "Check your hair before the call. Nothing is recorded or saved.")
        } content: {
            Group {
                switch camera.state {
                case .denied:
                    WindowEmptyState(
                        symbol: "video.slash.fill", title: "Camera access needed",
                        message: "Allow the camera to use the mirror. The picture stays on this Mac."
                    ) {
                        WindowPrimaryButton(title: "Open System Settings", symbol: "gearshape") {
                            Permission.camera.openSettings()
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .windowCardBackground()
                case .unavailable:
                    WindowEmptyState(
                        symbol: "video.slash", title: "No camera", message: "Connect a camera to use the mirror."
                    )
                    .frame(maxHeight: .infinity)
                    .windowCardBackground()
                case .idle, .running:
                    ZStack {
                        CameraPreview(session: camera.session, running: camera.state == .running)
                            .opacity(camera.state == .running ? 1 : 0)
                        if camera.state == .idle { LoadingLabel("Starting the camera…") }
                    }
                    .background(.primary.opacity(0.06))
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: SurfaceRadius.largePanel, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Camera preview")
                }
            }
        }
        .onAppear { camera.attach() }
        .onDisappear { camera.detach() }
        // Coming back from System Settings with access granted starts the camera without a page switch.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard camera.state == .denied else { return }
            camera.detach()
            camera.attach()
        }
    }
}

// MARK: Script

/// The Script widget in the window: the command's whole output in a monospaced scroll view,
/// with when it last ran. Runs on the widget's interval while the page shows; Run runs it now.
struct ScriptPage: View {
    let store: ScriptStore
    let preferences: Preferences
    let openSettings: () -> Void

    var body: some View {
        WindowPageFrame {
            WindowPageHeader(
                symbol: "terminal", tint: .green, title: "Script",
                subtitle: preferences.scriptCommand.isEmpty
                    ? "Run a command now and then and see what it prints"
                    : "Every \(Int(ScriptOutput.clampedInterval(preferences.scriptInterval))) seconds while this page shows"
            ) {
                Button("Script settings", systemImage: "gearshape", action: openSettings)
                    .labelStyle(.iconOnly)
                    .help("Script settings")
                if !preferences.scriptCommand.isEmpty {
                    WindowPrimaryButton(title: "Run", symbol: "play.fill") {
                        Task { await store.refresh(command: preferences.scriptCommand, interval: 0, force: true) }
                    }
                    .disabled(store.running)
                }
            }
        } content: {
            if preferences.scriptCommand.isEmpty {
                WindowEmptyState(
                    symbol: "terminal", title: "No command set",
                    message:
                        "Set a shell command in Settings, such as uptime or a script of yours, to show its output here."
                ) {
                    WindowPrimaryButton(title: "Open Settings", symbol: "gearshape", action: openSettings)
                }
                .frame(maxHeight: .infinity)
                .windowCardBackground()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").wispFont(.caption, weight: .bold).foregroundStyle(.green)
                        Text(preferences.scriptCommand)
                            .wispFont(.callout, design: .monospaced)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                        status
                    }
                    Divider()
                    ScrollView(.vertical) {
                        Text(store.transcript.isEmpty ? (store.running ? "" : "No output") : output)
                            .wispFont(.callout, design: .monospaced)
                            .foregroundStyle(store.transcript.isEmpty ? Color.secondaryText : .ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .overlay { if store.running, store.transcript.isEmpty { LoadingLabel("Running…") } }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .windowCardBackground()
            }
        }
        // Restarts when the saved command or the interval changes, like the widget.
        .task(id: "\(preferences.scriptCommand)|\(preferences.scriptInterval)") {
            let interval = ScriptOutput.clampedInterval(preferences.scriptInterval)
            while !Task.isCancelled {
                await store.refresh(command: preferences.scriptCommand, interval: interval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private var output: String { store.transcript.joined(separator: "\n") }

    @ViewBuilder private var status: some View {
        HStack(spacing: 4) {
            if store.running {
                ProgressView().controlSize(.mini)
                Text("Running")
            } else if let problem = store.problem {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(problem)
            } else if let ranAt = store.ranAt {
                Text("Ran \(ranAt, style: .relative) ago")
            }
        }
        .wispFont(.subheadline)
        .foregroundStyle(Color.secondaryText)
    }
}
