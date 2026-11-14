import AppKit
import SwiftUI
import WispCore

// MARK: Notes

/// The scratch note in the window: a full-height editor at a readable width.
struct NotesPage: View {
    @Bindable var store: NotesStore

    var body: some View {
        GeometryReader { proxy in
            TextEditor(text: $store.text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if store.text.isEmpty {
                        Text("Jot something down…")
                            .font(.system(size: 14)).foregroundStyle(Color.secondaryText)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: WindowLayout.readableWidth(available: proxy.size.width))
                .frame(maxHeight: .infinity)
                .padding(WindowLayout.margin)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Shortcuts

/// Shortcuts in the window: favourites first, then every Shortcut, as a searchable grid of tiles.
struct ShortcutsPage: View {
    let runner: ShortcutsRunner
    let preferences: Preferences

    @State private var query = ""

    var body: some View {
        let favourites = ShortcutList.matching(
            ShortcutList.favourites(preferences.favouriteShortcuts, available: runner.available), query: query)
        let all = ShortcutList.matching(runner.available, query: query)
        Group {
            if !runner.hasListed {
                ProgressView().controlSize(.small)
            } else if runner.available.isEmpty {
                ContentUnavailableView {
                    Label("No Shortcuts", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Shortcuts you make in the Shortcuts app show up here.")
                } actions: {
                    Button("Open Shortcuts", action: Self.openApp)
                }
            } else if all.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                WindowWidgetPage { width in
                    VStack(alignment: .leading, spacing: 12) {
                        if !favourites.isEmpty {
                            WindowSectionTitle("Favourites")
                            grid(favourites, width: width)
                            WindowSectionTitle("All Shortcuts").padding(.top, 12)
                        }
                        grid(all, width: width)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $query, placement: .toolbar, prompt: "Search Shortcuts")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise", action: runner.refresh)
                    .help("Refresh the list")
                Button("Open Shortcuts", systemImage: "square.stack.3d.up", action: Self.openApp)
                    .help("Open Shortcuts")
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
                .background(Circle().fill(running ? AnyShapeStyle(.ink.opacity(0.1)) : AnyShapeStyle(Color.pink)))
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ink.opacity(hovering ? 0.1 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.wispViolet, lineWidth: running ? 2 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        Group {
            switch camera.state {
            case .denied:
                ContentUnavailableView {
                    Label("Camera access needed", systemImage: "video.slash.fill")
                } description: {
                    Text("Allow the camera to use the mirror.")
                } actions: {
                    Button("Open System Settings") { Permission.camera.openSettings() }
                }
            case .unavailable:
                ContentUnavailableView(
                    "No camera", systemImage: "video.slash", description: Text("Connect a camera to use the mirror."))
            case .idle, .running:
                ZStack {
                    CameraPreview(session: camera.session, running: camera.state == .running)
                        .opacity(camera.state == .running ? 1 : 0)
                    if camera.state == .idle { ProgressView().controlSize(.small) }
                }
                .background(.ink.opacity(0.06))
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 1100)
                .padding(WindowLayout.margin * 1.5)
                .accessibilityLabel("Camera preview")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Group {
            if preferences.scriptCommand.isEmpty {
                ContentUnavailableView {
                    Label("No command set", systemImage: "terminal")
                } description: {
                    Text("Set a command in Settings to show its output here.")
                } actions: {
                    Button("Open Settings", action: openSettings)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(preferences.scriptCommand)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                        status
                    }
                    ScrollView(.vertical) {
                        Text(store.transcript.isEmpty ? (store.running ? "" : "No output") : output)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(store.transcript.isEmpty ? Color.secondaryText : .ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ink.opacity(0.05)))
                }
                .padding(WindowLayout.margin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Run", systemImage: "play.fill") {
                    Task { await store.refresh(command: preferences.scriptCommand, interval: 0, force: true) }
                }
                .disabled(store.running || preferences.scriptCommand.isEmpty)
                .help("Run now")
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
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(problem)
            } else if let ranAt = store.ranAt {
                Text("Ran \(ranAt, style: .relative) ago")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.secondaryText)
    }
}
