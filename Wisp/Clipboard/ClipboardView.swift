import AppKit
import SwiftUI
import WispCore

/// Clipboard history: type tabs, search, and a row of typed cards.
struct ClipboardView: View {
    @Bindable var model: ClipboardPanelModel
    let ai: AITextActions
    let paste: (ClipItem) -> Void
    let pasteTogether: ([ClipItem]) -> Void
    let runAI: (AITask, ClipItem) -> Void
    let close: () -> Void

    @FocusState private var searchFocused: Bool

    init(
        model: ClipboardPanelModel, ai: AITextActions, paste: @escaping (ClipItem) -> Void,
        pasteTogether: @escaping ([ClipItem]) -> Void, runAI: @escaping (AITask, ClipItem) -> Void,
        close: @escaping () -> Void
    ) {
        self.model = model
        self.ai = ai
        self.paste = paste
        self.pasteTogether = pasteTogether
        self.runAI = runAI
        self.close = close
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            cards
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wispSurface(cornerRadius: SurfaceRadius.largePanel)
        .tint(.wispViolet)
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        let all = model.store.history.items
        let counts = ClipCounts(all)
        return HStack(spacing: 10) {
            HStack(spacing: 2) {
                chip("All", count: counts.all, kind: nil)
                chip("Text", count: counts[.text], kind: .text)
                chip("Links", count: counts[.link], kind: .link)
                chip("Images", count: counts[.image], kind: .image)
                chip("Colours", count: counts[.color], kind: .color)
            }
            .padding(3)
            .background(Capsule().fill(.primary.opacity(0.08)))
            appMenu(all)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryText)
                TextField(all.count == 1 ? "Search 1 clip" : "Search among \(all.count) clips", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .frame(width: 200)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.primary.opacity(0.08)))
            Menu {
                Button("Clear History (keeps pinned)") { model.store.clear() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
            .accessibilityLabel("More")
        }
        .font(.callout)
    }

    /// Narrows the cards to one app's clips.
    private func appMenu(_ all: [ClipItem]) -> some View {
        Menu {
            Button("All apps") { pickApp(nil) }
            Divider()
            ForEach(ClipCounts.apps(all)) { entry in
                Button("\(entry.name)  \(entry.count)") { pickApp(entry.name) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "app.badge")
                Text(model.app ?? "All apps").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(model.app == nil ? Color.primary.opacity(0.07) : Color.wispViolet.opacity(0.3)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show clips from one app")
        .accessibilityLabel("App, \(model.app ?? "all apps")")
    }

    private func pickApp(_ app: String?) {
        model.app = app
        model.selectedID = model.items.first?.id
    }

    private func chip(_ title: String, count: Int, kind: ClipKind?) -> some View {
        let on = model.kind == kind
        return Button {
            kindSelection.wrappedValue = kind
        } label: {
            HStack(spacing: 5) {
                Text(title).fontWeight(on ? .semibold : .regular)
                Text("\(count)").foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondaryText)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(on ? Color.white : .primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(on ? Color.wispViolet : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Picking a kind starts on its first item.
    private var kindSelection: Binding<ClipKind?> {
        Binding(
            get: { model.kind },
            set: { kind in
                model.kind = kind
                model.selectedID = model.items.first?.id
            })
    }

    private var cards: some View {
        let items = model.items
        let selected = model.selectedItem?.id
        return Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 26))
                    Text(model.query.isEmpty ? "Copy something and it shows up here" : "No matches")
                        .font(.body).foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(items) { item in
                                ClipTile(
                                    item: item, store: model.store,
                                    selected: item.id == selected || model.picked.contains(item.id),
                                    pickNumber: model.pickedItems.firstIndex { $0.id == item.id }.map { $0 + 1 }
                                )
                                .frame(width: 210, height: 228)
                                .id(item.id)
                                .onTapGesture(count: 2) { paste(item) }
                                .onTapGesture {
                                    // ⌘-click picks several to paste together; a plain click starts over.
                                    if NSEvent.modifierFlags.contains(.command) {
                                        model.togglePick(item)
                                    } else {
                                        model.picked = []
                                        model.selectedID = item.id
                                    }
                                }
                                .contextMenu {
                                    let picked = model.pickedItems
                                    // Images are left out of a paste together, so only text counts.
                                    let texts = picked.filter { $0.text != nil }.count
                                    if picked.count > 1, texts > 0, model.picked.contains(item.id) {
                                        Button("Paste \(texts) together") { pasteTogether(picked) }
                                        Divider()
                                    }
                                    Button("Paste") { paste(item) }
                                    Button("Copy") { model.store.copy(item) }
                                    Button(item.pinned ? "Unpin" : "Pin") { model.store.togglePin(item) }
                                    if item.kind == .image {
                                        Button("Copy text") { model.copyText(item) }
                                    }
                                    aiMenu(for: item)
                                    Divider()
                                    Button("Delete") { model.store.remove(item) }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .onChange(of: selected) { _, id in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }
}

extension ClipboardView {
    /// AI tasks for a text item, with ⌘1 to ⌘8 matching the panel's keys. Shown only while AI
    /// is on; while the engine isn't ready the tasks are disabled under its status line.
    @ViewBuilder fileprivate func aiMenu(for item: ClipItem) -> some View {
        if ai.isEnabled, AIClipboardText.offers(item) {
            Menu("AI") {
                if !ai.isReady { Text(ai.statusMessage) }
                ForEach(Array(ai.tasks.enumerated()), id: \.offset) { index, task in
                    Button(task.title) { runAI(task, item) }
                        // ⌘1 to ⌘9; "10" isn't one character.
                        .keyboardShortcut(
                            index < 9
                                ? KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                                : nil
                        )
                        .disabled(!ai.isReady)
                }
            }
        }
    }
}
