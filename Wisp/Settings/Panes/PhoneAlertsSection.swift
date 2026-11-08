import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import WispCore

/// Settings › Agents › Phone alerts: agent alerts and approvals pushed through ntfy. One switch
/// while off; the server, tokens, details and waits are in `PhoneAlertsAdvanced`.
struct PhoneAlertsSection: View {
    let push: PushService
    let hub: AgentHub
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            // A closure, not `set: setEnabled`: Swift 6.3's optimiser crashes converting a method
            // reference to Binding's @isolated(any) setter, which broke the 0.1.8 and 0.1.9 releases.
            Toggle(
                "Send agent alerts to my phone",
                isOn: Binding(get: { preferences.pushEnabled }, set: { setEnabled($0) }))
            if preferences.pushEnabled {
                topic
            }
        } header: {
            Text("Phone alerts")
        } footer: {
            Text(
                preferences.pushEnabled
                    ? "Anyone who knows a topic on a public server can read it and post to it. Topics are long and random, and each Allow or Deny works once; your own ntfy server or an access token, under Advanced, keeps alerts private."
                    : "Off by default. When on, Wisp sends short alerts to an ntfy server, and the ntfy app shows them on your phone and Apple Watch. Commands, file paths, diffs and prompts stay on your Mac."
            )
        }
        if preferences.pushEnabled {
            Section("Send to the phone") {
                ForEach(PushKind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: kindBinding(kind))
                }
                Picker("Send", selection: $preferences.pushMode) {
                    ForEach(PushMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
    }

    private func setEnabled(_ on: Bool) {
        if on { push.ensureTopics() }
        preferences.pushEnabled = on
        PhoneAlerts.applyTimeout(hub: hub, preferences: preferences)
    }

    @ViewBuilder private var topic: some View {
        if push.server == nil {
            Label(
                "The server under Advanced needs an https address, such as \(PushTopic.defaultServer).",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption).foregroundStyle(.orange)
        }
        LabeledContent("Topic") {
            HStack {
                Text(preferences.pushTopic).font(.caption.monospaced()).textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(preferences.pushTopic, forType: .string)
                }
                Button("Regenerate") { push.regenerateTopics() }
            }
        }
        if let url = push.subscribeURL, let image = QRCode.image(for: url.absoluteString) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 120, height: 120)
                    .accessibilityLabel("QR code for the topic")
                Text(
                    "Install the ntfy app on your phone and subscribe to this topic, or scan the code to open it. Your Apple Watch shows the iPhone's notifications."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        HStack {
            Button("Send test") { Task { await push.sendTest() } }
                .disabled(push.testing || push.server == nil)
            if let problem = push.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func kindBinding(_ kind: PushKind) -> Binding<Bool> {
        Binding(
            get: { preferences.pushKinds.contains(kind) },
            set: { on in
                if on { preferences.pushKinds.insert(kind) } else { preferences.pushKinds.remove(kind) }
            })
    }
}

/// The phone alert options under Agents › Advanced, shown while phone alerts are on.
struct PhoneAlertsAdvanced: View {
    let push: PushService
    let hub: AgentHub
    @Bindable var preferences: Preferences
    @State private var token = ""
    @State private var replyToken = ""

    private static let timeoutChoices = [2, 5, 10, 15, 30, 60]

    var body: some View {
        Group {
            Text("Phone alerts").font(.headline).padding(.top, 6)
            Toggle("Add the command or file name", isOn: $preferences.pushDetails)
            Text(
                "Adds the command or file name to permission requests, with secrets masked, and the session summary to Done. Hidden while agent details are hidden in the notch."
            )
            .font(.caption).foregroundStyle(.secondary)
            if preferences.pushMode == .away {
                Stepper(value: $preferences.pushIdleMinutes, in: PushPolicy.idleMinutesRange) {
                    LabeledContent("Away after", value: "\(preferences.pushIdleMinutes) min idle")
                }
                Text("Also when the screen is locked.").font(.caption).foregroundStyle(.secondary)
            }
            Picker(
                "Wait for an answer",
                selection: Binding(
                    get: { preferences.pushTimeoutMinutes },
                    set: { minutes in
                        preferences.pushTimeoutMinutes = minutes
                        PhoneAlerts.applyTimeout(hub: hub, preferences: preferences)
                    })
            ) {
                ForEach(Self.timeoutChoices, id: \.self) { Text("\($0) min").tag($0) }
            }
            Text(
                "Permission prompts wait this long for Allow or Deny from the notch or your phone, then go back to the terminal. Changing it updates your agents' hooks; Codex asks you to trust them again in /hooks."
            )
            .font(.caption).foregroundStyle(.secondary)
            Text("Your own ntfy server").font(.headline).padding(.top, 6)
            LabeledContent("Server") {
                TextField("Server", text: $preferences.pushServer, prompt: Text(PushTopic.defaultServer))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
            if push.server == nil {
                Label(
                    "Use an https address, such as \(PushTopic.defaultServer).", systemImage: "exclamationmark.triangle"
                )
                .font(.caption).foregroundStyle(.orange)
            }
            tokenRow(
                "Access token", draft: $token, saved: push.hasToken,
                save: { push.setToken($0) })
            tokenRow(
                "Reply token", draft: $replyToken, saved: push.hasReplyToken,
                save: { push.setReplyToken($0) })
            Text(
                "Tokens are for a server that needs a login, and are kept in your Keychain. Wisp uses the access token to send alerts and read replies; it never leaves your Mac except to your server. The Allow and Deny buttons carry only the reply token, which is stored with each notification, so give it write access to the reply topic and nothing else."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tokenRow(
        _ title: String, draft: Binding<String>, saved: Bool, save: @escaping (String) -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack {
                SecureField(title, text: draft, prompt: Text(saved ? "Saved" : "tk_..."))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Button("Save") {
                    save(draft.wrappedValue)
                    draft.wrappedValue = ""
                }
                .disabled(draft.wrappedValue.isEmpty)
                if saved {
                    Button("Remove") { save("") }
                }
            }
        }
    }
}

@MainActor
enum PhoneAlerts {
    /// The hub follows Preferences on the next run loop; set it now so the hooks dialog uses it.
    static func applyTimeout(hub: AgentHub, preferences: Preferences) {
        hub.approvalTimeout = preferences.approvalTimeout
        hub.applyApprovalTimeout()
    }
}

/// A QR code for `text`, drawn with Core Image.
enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
            let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
