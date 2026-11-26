import AppKit
import SwiftUI
import WispCore

/// The first-launch setup in its own small window: Accessibility, how the shelf opens (and
/// trying it), the ring, coding agents, and launch at login. Shown once; About has "Run Setup
/// Again", which starts it over from the first step.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private let services: AppServices
    /// Long enough for the setup window to go before the shelf opens.
    private static let shelfDelay = Duration.milliseconds(400)

    init(services: AppServices) {
        self.services = services
    }

    isolated deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    func show(at first: OnboardingStep = .accessibility) {
        let window = window ?? makeWindow()
        self.window = window
        // A fresh view each time, so running setup again starts at `first`, not where it was left.
        window.contentViewController = NSHostingController(rootView: makeView(at: first))
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeView(at first: OnboardingStep) -> OnboardingView {
        OnboardingView(
            services: services, granted: { [weak self] in self?.bringForward() },
            done: { [weak self] in self?.finish() }, step: first)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        window.title = "Welcome to Wisp"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // The close button counts as finishing; otherwise setup would return on every launch.
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        return window
    }

    private func finish() {
        services.preferences.onboarded = true
        // orderOut rather than close, which would post willClose and call this again.
        window?.orderOut(nil)
        // Show where Wisp lives, once the window has gone.
        Task { [services] in
            try? await Task.sleep(for: Self.shelfDelay)
            services.openShelf(.home)
        }
    }

    /// Accessibility is switched on in System Settings, which covers this window, and a menu
    /// bar app has no Dock icon to get back with.
    fileprivate func bringForward() {
        guard let window, window.isVisible else { return }
        window.orderFrontRegardless()
        NSApp.activate()
    }
}

private struct OnboardingView: View {
    let services: AppServices
    let granted: () -> Void
    let done: () -> Void

    @State var step: OnboardingStep
    @State private var trusted = AccessibilityPermission.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case .accessibility:
                    AccessibilityStep(trusted: trusted, shortcut: services.preferences.hotkey.description)
                case .opening: OpeningStep(preferences: services.preferences, accent: services.accent, trusted: trusted)
                case .ring: RingStep(preferences: services.preferences)
                case .agents: AgentsStep(hub: services.agents)
                case .finish: FinishStep(preferences: services.preferences)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .wispTransition(.opacity.combined(with: .offset(y: 6)))
            .id(step)
            footer
        }
        .frame(width: 520, height: 520)
        .wispAnimation(.wispSmooth, value: step)
        .task {
            // Accessibility is granted in System Settings; watch for it.
            while !Task.isCancelled {
                let now = AccessibilityPermission.isTrusted
                if now != trusted {
                    trusted = now
                    if now { granted() }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text(title).font(.system(size: 22, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 36)
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }

    private var title: String {
        switch step {
        case .accessibility: "Welcome to Wisp"
        case .opening: "How should the shelf open?"
        case .ring: "Meet the ring"
        case .agents: "Bring your coding agents"
        case .finish: "You're set"
        }
    }

    private var subtitle: String {
        switch step {
        case .accessibility:
            "A shelf, live activities and your coding agents, in the notch. A few short steps to set it up."
        case .opening: "You can change this any time in Settings."
        case .ring: "Your apps and actions in a circle at the pointer. Pick one with a flick, a click or a number."
        case .agents: "See your coding agents work, and answer their requests from the notch."
        case .finish: "Two last things, both optional."
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Color.wispViolet : Color.secondary.opacity(0.3))
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if let previous = step.previous {
                Button("Back") { step = previous }.controlSize(.large)
            }
            Button(step.primaryAction(accessibilityGranted: trusted)) {
                if let next = step.next { step = next } else { done() }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }
}

private struct AccessibilityStep: View {
    let trusted: Bool
    let shortcut: String
    /// The first press shows the macOS prompt; later ones open System Settings, in case the
    /// prompt was dismissed.
    @State private var asked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility").font(.headline)
                    Text(
                        "Wisp reads \(shortcut) to open the shelf and shows its own volume and brightness. macOS asks you to allow that once."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                IconTile(symbol: "hand.raised.fill", tint: .wispViolet, size: 32)
            }
            HStack(spacing: 10) {
                if trusted {
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if asked {
                    Button("Open System Settings") { AccessibilityPermission.openSettings() }
                    ProgressView().controlSize(.small)
                    Text("Waiting for access…").foregroundStyle(.secondary)
                } else {
                    Button("Allow Accessibility…") {
                        AccessibilityPermission.requestAccess()
                        asked = true
                    }
                }
            }
            .padding(.leading, 44)
            .wispAnimation(.easeOut(duration: 0.2), value: trusted)
            .wispAnimation(.easeOut(duration: 0.2), value: asked)
        }
    }
}

private struct OpeningStep: View {
    @Bindable var preferences: Preferences
    let accent: Color
    let trusted: Bool
    /// The shelf opened for real while this step showed.
    @State private var tried = false

    var body: some View {
        VStack(spacing: 14) {
            NotchPreview(preferences: preferences, accent: accent)
            HStack(spacing: 12) {
                choice(.click, symbol: "cursorarrow.click", title: "Click", detail: "Hover peeks; a click opens.")
                choice(.hover, symbol: "cursorarrow.motionlines", title: "Hover", detail: "Opens when you rest on it.")
            }
            tryIt
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchShelfOpened)) { _ in tried = true }
        .wispAnimation(.easeOut(duration: 0.2), value: tried)
    }

    /// The step's hands-on part: open the real shelf the way just chosen.
    @ViewBuilder private var tryIt: some View {
        if tried {
            Label("That's it. The shelf opens the same way from now on.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            let gesture = preferences.openTrigger == .hover ? "Rest the pointer on the notch" : "Click the notch"
            let key = trusted ? ", or press \(preferences.hotkey.description)" : ""
            Label("Try it: \(gesture)\(key).", systemImage: "hand.point.up.left")
                .foregroundStyle(.secondary)
        }
    }

    private func choice(_ trigger: OpenTrigger, symbol: String, title: String, detail: String) -> some View {
        let selected = preferences.openTrigger == trigger
        return Button {
            preferences.openTrigger = trigger
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22)).frame(height: 30)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.wispViolet.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.wispViolet : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The ring: what it looks like, how to open it, and (optionally) window previews.
private struct RingStep: View {
    @Bindable var preferences: Preferences
    @Environment(\.colorScheme) private var colorScheme
    @State private var canPreview = CGPreflightScreenCaptureAccess()
    /// macOS may only hand the grant to a fresh launch, so once asked, say so rather than wait.
    @State private var askedForPreviews = Permission.askedScreenRecording

    private static let scale: CGFloat = 0.4

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            picture
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Shortcut") {
                    if let key = preferences.shortcuts.key(for: .ring, shelf: preferences.hotkey) {
                        KeyCap(key.description)
                    } else {
                        Text("Off").foregroundStyle(.secondary)
                    }
                }
                Picker("Mouse button", selection: $preferences.ringButton) {
                    ForEach(RingButton.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if canPreview {
                        Label("Window previews are on", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.wispViolet)
                    } else {
                        Button("Show window previews…") {
                            Permission.screenRecording.request()
                            askedForPreviews = true
                        }
                        Text(
                            askedForPreviews
                                ? "Turned on Screen Recording? Previews start the next time Wisp opens."
                                : "Optional: a live picture of a window when you point at it. Needs Screen Recording."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            // The grant happens in System Settings; look again now and then.
            while !Task.isCancelled, !canPreview {
                try? await Task.sleep(for: .seconds(1))
                canPreview = CGPreflightScreenCaptureAccess()
            }
        }
    }

    /// The ring as it looks, drawn at full size and scaled down.
    private var picture: some View {
        let slots = preferences.ringConfig.standard.slots
        let full = (RingGeometry.ringOuter + 10) * 2
        let centre = CGPoint(x: full / 2, y: full / 2)
        return ZStack {
            RingDisc(centre: centre, dark: colorScheme == .dark, shown: true, hoverAngle: nil, reduceMotion: true)
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let angle = RingGeometry.slotAngle(index, count: slots.count)
                let radians = angle * .pi / 180
                RingIconCell(
                    icon: slot.action.icon, tileHex: slot.action.tileHex, side: RingGeometry.iconSize, angle: angle,
                    lit: false, dimmed: false, hasMore: false
                )
                .position(
                    x: centre.x + RingGeometry.ringRadius * sin(radians),
                    y: centre.y - RingGeometry.ringRadius * cos(radians))
            }
            Image("MenuGlyph").resizable().renderingMode(.template).scaledToFit().frame(width: 24, height: 24)
                .foregroundStyle(Color.wispViolet)
        }
        .frame(width: full, height: full)
        .scaleEffect(Self.scale)
        .frame(width: full * Self.scale, height: full * Self.scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The ring, with \(slots.count) apps and actions around Wisp's flame")
    }
}

private struct AgentsStep: View {
    let hub: AgentHub
    /// Agents whose settings folder is on this Mac, listed first.
    @State private var present: Set<AgentSource> = []
    @State private var showsAll = false

    var body: some View {
        VStack(spacing: 10) {
            // The window has a fixed size; once the agents outgrow it, the list scrolls.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
            }
            if !present.isEmpty, present.count < all.count {
                Button(showsAll ? "Show only agents on this Mac" : "Show all agents") { showsAll.toggle() }
                    .buttonStyle(.link)
            }
            Text("Skip this if you don't use them. Settings › Agents has it too.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            hub.refreshInstalled()
            present = Self.agentsOnThisMac()
        }
    }

    private var all: [AgentSource] { AgentAdapters.all.map(\.source) }

    /// The agents on this Mac, or every agent when none is (or when asked).
    private var shown: [AgentSource] {
        showsAll || present.isEmpty
            ? all.sorted { present.contains($0) && !present.contains($1) } : all.filter(present.contains)
    }

    private static func agentsOnThisMac() -> Set<AgentSource> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Set(
            AgentAdapters.all.compactMap { adapter in
                guard let folder = adapter.hookFile.agentFolder else { return nil }
                let exists = FileManager.default.fileExists(atPath: home.appendingPathComponent(folder).path)
                return exists ? adapter.source : nil
            })
    }

    private var rows: some View {
        VStack(spacing: 8) {
            ForEach(shown, id: \.self) { source in
                let status = hub.integrationStatus(source)
                let connected = status == .connected || status == .ready
                HStack(spacing: 12) {
                    IconTile(symbol: source.symbol, tint: .wispViolet, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.displayName).font(.headline)
                        Text(Self.label(status)).font(.caption).foregroundStyle(connected ? .green : .secondary)
                    }
                    Spacer()
                    if let action = Self.action(status) {
                        Button(action) { hub.installHooks(source) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.08)))
            }
        }
    }

    private static func label(_ status: IntegrationStatus) -> String {
        switch status {
        case .connected, .ready: "Connected"
        case .needsUpdate: "Connected, from an older version of Wisp"
        case .otherCopy: "Connected to another copy of Wisp"
        case .monitor: "Watched while it runs"
        case .notInstalled: "Not connected"
        }
    }

    /// Every button goes through the same install, which asks before it changes a file.
    private static func action(_ status: IntegrationStatus) -> String? {
        switch status {
        case .connected, .ready, .monitor: nil
        case .needsUpdate: "Update"
        case .otherCopy: "Use this Wisp"
        case .notInstalled: "Connect"
        }
    }
}

/// Launch at login, and the one permission a feature that's on from the start needs.
private struct FinishStep: View {
    let preferences: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var fullDiskAccess = Permission.hasFullDiskAccess
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Open Wisp when you log in", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.orange)
                    }
                }
            } icon: {
                IconTile(symbol: "power", tint: .wispViolet, size: 32)
            }
            if preferences.notificationsEnabled {
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notifications in the notch").font(.headline)
                        Text(
                            "Wisp shows your Mac's notifications as cards. Reading them needs Full Disk Access, "
                                + "which you can also allow later in Settings › Permissions."
                        )
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        if fullDiskAccess {
                            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Allow Full Disk Access…") { Permission.fullDiskAccess.request() }
                        }
                    }
                } icon: {
                    IconTile(symbol: "bell.badge.fill", tint: .wispViolet, size: 32)
                }
            }
        }
        .task {
            // Full Disk Access is switched on in System Settings; look again now and then.
            while !Task.isCancelled, !fullDiskAccess {
                try? await Task.sleep(for: .seconds(1))
                fullDiskAccess = Permission.hasFullDiskAccess
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            loginError = nil
            if LaunchAtLogin.needsApproval { LaunchAtLogin.openSystemSettings() }
        } catch {
            loginError = "Couldn't change it here. Try Settings › General."
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
