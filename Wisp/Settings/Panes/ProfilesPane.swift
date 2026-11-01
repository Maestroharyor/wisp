import AppKit
import SwiftUI
import WispCore

struct ProfileSettings: View {
    @Bindable var preferences: Preferences
    let context: ContextEngine
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Profiles") {
                ForEach(Array(preferences.profiles.enumerated()), id: \.element.name) { index, profile in
                    HStack {
                        Image(
                            systemName: profile.name == preferences.activeProfile ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(profile.name == preferences.activeProfile ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                            Text(summary(profile)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Opens on", selection: page(for: profile.name)) {
                            Text("Home").tag("home")
                            Text("Tray").tag("tray")
                            Text("Media").tag("media")
                            Text("Widgets").tag("widgets")
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        if index < 9 {
                            Text("Hyper+\(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 56)
                        }
                        Button("Use") { context.choose(profile) }
                            .disabled(profile.name == preferences.activeProfile)
                        if profile.name != ContextEngineState.baseProfile {
                            Button(role: .destructive) {
                                preferences.deleteProfile(named: profile.name)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(profile.name)")
                            .help("Delete profile")
                        }
                    }
                }
                HStack {
                    TextField("New profile name", text: $newName)
                    Button("Save current setup") {
                        preferences.saveCurrentAsProfile(named: newName)
                        newName = ""
                    }
                }
                Text(
                    "A profile is a Home layout, the page the shelf opens on, and the surface style. Changes you make to Home while a profile is active are saved into it."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Switch automatically") {
                Toggle("Change profile to fit what you're doing", isOn: $preferences.contextAware)
                ForEach($preferences.contextRules) { $rule in
                    Toggle(isOn: $rule.enabled) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title(rule.trigger))
                            Text("Switches to \(rule.profile)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!preferences.contextAware)
                }
                Text("A profile you pick yourself stays for 30 minutes before rules take over again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func summary(_ profile: Profile) -> String {
        let widgets = profile.home.ids.compactMap(WidgetKind.init(rawValue:)).map(\.title)
        return (widgets.isEmpty ? "No widgets" : widgets.joined(separator: ", ")) + " · " + profile.surface.capitalized
    }

    private func page(for name: String) -> Binding<String> {
        Binding(
            get: { preferences.profile(named: name)?.defaultPage ?? "home" },
            set: { preferences.setDefaultPage($0, for: name) })
    }

    private func title(_ trigger: ContextTrigger) -> String {
        switch trigger {
        case .frontApp: "When a coding app is in front"
        case .mediaPlaying: "When music is playing"
        case .focus(let name): "When the \(name) Focus is on"
        case .agentWaiting: "When Claude Code needs you"
        case .externalDisplay: "When an external display is connected"
        }
    }
}
