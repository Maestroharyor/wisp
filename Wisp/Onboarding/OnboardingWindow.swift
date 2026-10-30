import AppKit
import SwiftUI
import WispCore

/// The first-launch setup in its own small window: Accessibility, how the shelf opens,
/// and coding agents. Shown once; About has "Run Setup Again".
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(services: services) { [weak self] in self?.finish() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Wisp"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        return window
    }

    private func finish() {
        services.preferences.onboarded = true
        window?.close()
        // The hotkey waits for Accessibility; ask now if setup was skipped.
        if !AccessibilityPermission.isTrusted { AccessibilityPermission.requestAccess() }
    }
}

private struct OnboardingView: View {
    let services: AppServices
    let done: () -> Void

    @State private var step = OnboardingStep.accessibility
    @State private var trusted = AccessibilityPermission.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case .accessibility: AccessibilityStep(trusted: trusted)
                case .opening: OpeningStep(preferences: services.preferences, accent: services.accent)
                case .agents: AgentsStep(hub: services.agents)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .id(step)
            footer
        }
        .frame(width: 520, height: 520)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: step)
        .task {
            // Accessibility is granted in System Settings; watch for it.
            while !Task.isCancelled {
                let now = AccessibilityPermission.isTrusted
                if now != trusted { trusted = now }
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
        case .agents: "Bring your coding agents"
        }
    }

    private var subtitle: String {
        switch step {
        case .accessibility: "Your notch, for people who build. Three quick steps and you're set."
        case .opening: "You can change this any time in Settings."
        case .agents: "Watch Claude Code and Codex work, and approve their requests from the notch."
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility").font(.headline)
                    Text(
                        "Wisp reads Caps Lock + Space to open the shelf and shows its own volume and brightness. macOS asks you to allow that once."
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
                } else {
                    Button("Open System Settings") {
                        AccessibilityPermission.requestAccess()
                        AccessibilityPermission.openSettings()
                    }
                    ProgressView().controlSize(.small)
                    Text("Waiting for access…").foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 44)
            .animation(.easeOut(duration: 0.2), value: trusted)
        }
    }
}

private struct OpeningStep: View {
    @Bindable var preferences: Preferences
    let accent: Color

    var body: some View {
        VStack(spacing: 14) {
            NotchPreview(preferences: preferences, accent: accent)
            HStack(spacing: 12) {
                choice(.click, symbol: "cursorarrow.click", title: "Click", detail: "Hover peeks; a click opens.")
                choice(.hover, symbol: "cursorarrow.motionlines", title: "Hover", detail: "Opens when you rest on it.")
            }
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
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentsStep: View {
    let hub: AgentHub

    var body: some View {
        VStack(spacing: 10) {
            ForEach([AgentSource.claude, .codex], id: \.self) { source in
                HStack(spacing: 12) {
                    IconTile(symbol: source.symbol, tint: .wispViolet, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.displayName).font(.headline)
                        Text(hub.isConnected(source) ? "Connected" : "Optional").font(.caption)
                            .foregroundStyle(hub.isConnected(source) ? .green : .secondary)
                    }
                    Spacer()
                    if !hub.isConnected(source) {
                        Button("Connect") { hub.installHooks(source) }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.08)))
            }
            Text("Skip this if you don't use them. Settings › Agents has it too.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { hub.refreshInstalled() }
    }
}
