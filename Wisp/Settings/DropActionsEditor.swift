import SwiftUI
import WispCore

/// Settings list of Drop Actions with an inline editor.
struct DropActionsEditor: View {
    @Bindable var preferences: Preferences
    let shortcuts: ShortcutsRunner

    @State private var editing: DropAction?

    private static let symbols = [
        "bolt.fill", "photo", "arrow.down.right.and.arrow.up.left", "doc.on.doc", "paperplane.fill",
        "terminal", "folder.fill", "wand.and.stars", "text.viewfinder", "icloud.and.arrow.up",
    ]

    var body: some View {
        ForEach(preferences.dropActions) { action in
            HStack {
                Image(systemName: action.symbol).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.name)
                    Text(summary(action)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Edit") { editing = action }
                Button("Remove", role: .destructive) { preferences.dropActions.removeAll { $0.id == action.id } }
            }
        }
        Button("Add action…") {
            editing = DropAction(name: "", kind: .command(""))
        }
        Text(
            "Drop files on an action's tile to run it. Commands run directly, not in a shell: {file} runs once per file, {files} passes them all, otherwise the files go at the end. The first two actions appear as tiles."
        )
        .font(.caption).foregroundStyle(.secondary)
        .sheet(item: $editing) { action in
            ActionSheet(
                action: action, shortcuts: shortcuts, symbols: Self.symbols,
                save: { saved in
                    if let index = preferences.dropActions.firstIndex(where: { $0.id == saved.id }) {
                        preferences.dropActions[index] = saved
                    } else {
                        preferences.dropActions.append(saved)
                    }
                    editing = nil
                },
                cancel: { editing = nil })
        }
    }

    private func summary(_ action: DropAction) -> String {
        switch action.kind {
        case .command(let line): line
        case .shortcut(let name): "Shortcut: \(name)"
        }
    }
}

private struct ActionSheet: View {
    @State var action: DropAction
    let shortcuts: ShortcutsRunner
    let symbols: [String]
    let save: (DropAction) -> Void
    let cancel: () -> Void

    @State private var usesShortcut = false
    @State private var command = ""
    @State private var shortcut = ""

    var body: some View {
        Form {
            TextField("Name", text: $action.name)
            Picker("Icon", selection: $action.symbol) {
                ForEach(symbols, id: \.self) { Image(systemName: $0).tag($0) }
            }
            Picker("Runs", selection: $usesShortcut) {
                Text("A command").tag(false)
                Text("A Shortcut").tag(true)
            }
            .pickerStyle(.segmented)
            if usesShortcut {
                Picker("Shortcut", selection: $shortcut) {
                    Text("Choose…").tag("")
                    ForEach(shortcuts.available, id: \.self) { Text($0).tag($0) }
                }
            } else {
                TextField("Command", text: $command, prompt: Text("sips -Z 1200 {file}"))
                    .font(.system(.body, design: .monospaced))
            }
            if let problem = draft.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") { save(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.problem != nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear {
            shortcuts.refresh()
            switch action.kind {
            case .command(let line):
                command = line
            case .shortcut(let name):
                usesShortcut = true
                shortcut = name
            }
        }
    }

    private var draft: DropAction {
        var copy = action
        copy.kind = usesShortcut ? .shortcut(shortcut) : .command(command)
        return copy
    }
}
