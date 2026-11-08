import SwiftUI
import WispCore

/// Settings › Agents › Cloud agents: which cloud sources to show in the Agents widget, and the
/// Cursor key.
struct CloudAgentsSection: View {
    let cloud: CloudAgentStore
    @Bindable var preferences: Preferences
    @State private var key = ""

    var body: some View {
        Section {
            Toggle("Show cloud agent tasks", isOn: $preferences.cloudEnabled)
            if preferences.cloudEnabled {
                ForEach(CloudSource.allCases, id: \.self) { source in
                    sourceRow(source)
                }
                cursorKey
                Toggle("Show pull request checks", isOn: $preferences.cloudChecks)
                    .disabled(cloud.availability[.copilot] == .missing)
                HStack {
                    Button("Check again") { cloud.checkTools() }.disabled(cloud.refreshing)
                    if cloud.refreshing { ProgressView().controlSize(.small) }
                }
            }
        } header: {
            Text("Cloud agents")
        } footer: {
            Text(
                "When on, the Agents widget lists your Codex, Copilot and Cursor cloud tasks, using the codex and gh commands' own logins and your Cursor API key. Finished, failed and red tasks get a notice, and go to your phone too when Cloud tasks is on under Phone alerts."
            )
        }
    }

    private func sourceRow(_ source: CloudSource) -> some View {
        Toggle(isOn: sourceBinding(source)) {
            Text(source.title)
            if let detail = detail(for: source) {
                Text(detail)
            }
        }
    }

    private func detail(for source: CloudSource) -> String? {
        if let problem = cloud.problems[source] { return problem }
        guard cloud.availability[source] == .missing else { return nil }
        switch source {
        case .codex: return "Install the codex command to see these."
        case .copilot: return "Install the GitHub CLI (gh) to see these."
        case .cursor: return "Add an API key below to see these."
        }
    }

    private func sourceBinding(_ source: CloudSource) -> Binding<Bool> {
        Binding(
            get: { preferences.cloudSources.contains(source) },
            set: { on in
                if on { preferences.cloudSources.insert(source) } else { preferences.cloudSources.remove(source) }
            })
    }

    private var cursorKey: some View {
        LabeledContent("Cursor API key") {
            HStack {
                SecureField("Cursor API key", text: $key, prompt: Text(cloud.hasCursorKey ? "Saved" : "key_..."))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Button("Save") {
                    cloud.setCursorKey(key)
                    key = ""
                }
                .disabled(key.isEmpty)
                if cloud.hasCursorKey {
                    Button("Remove") { cloud.setCursorKey("") }
                }
            }
        }
    }
}

extension CloudSource {
    /// The source's row in Settings.
    fileprivate var title: String {
        switch self {
        case .codex: "Codex cloud tasks"
        case .copilot: "Copilot coding agent"
        case .cursor: "Cursor Cloud Agents"
        }
    }
}
