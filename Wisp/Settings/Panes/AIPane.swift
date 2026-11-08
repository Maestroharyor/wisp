import SwiftUI
import WispCore

/// Settings › AI: the on-device engine and model, its status, and a box to try it.
struct AISettings: View {
    let ai: AIService
    @Bindable var preferences: Preferences
    @State private var sample = ""
    @State private var task: AITask = .summarise
    @State private var answer: AIAnswer?
    @State private var failure: String?
    @State private var running = false

    /// Changes that need the engine checked again.
    private var checkKey: String {
        [
            String(preferences.aiEnabled), preferences.aiEngine.rawValue, preferences.ollamaAddress,
            preferences.ollamaModel,
        ]
        .joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use on-device AI", isOn: $preferences.aiEnabled)
            } footer: {
                Text(
                    "Off by default. Wisp uses a language model on your Mac to summarise, translate and tidy text. What you send it never leaves your Mac."
                )
            }
            if preferences.aiEnabled {
                engine
                actions
                tryIt
            }
        }
        .formStyle(.grouped)
        .task(id: checkKey) {
            // Typing an address shouldn't check on every key.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await ai.refresh()
        }
    }

    private var engine: some View {
        Section {
            Picker("Engine", selection: $preferences.aiEngine) {
                ForEach(AIEngineKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if preferences.aiEngine == .ollama {
                LabeledContent("Address") {
                    TextField("Address", text: $preferences.ollamaAddress, prompt: Text(OllamaEndpoint.defaultAddress))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                }
                if OllamaEndpoint.base(preferences.ollamaAddress) == nil {
                    Label(
                        "Use an address on this Mac, such as \(OllamaEndpoint.defaultAddress).",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.orange)
                }
                Picker("Model", selection: $preferences.ollamaModel) {
                    Text("First available").tag("")
                    ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
                }
            }
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    statusIcon
                    Text(ai.status.message)
                    Button("Check again") { Task { await ai.refresh() } }
                        .controlSize(.small)
                }
            }
        } header: {
            Text("Engine")
        } footer: {
            Text(engineFooter)
        }
    }

    /// Pulled models, plus the saved one if it's gone, so the picker can still show it.
    private var modelChoices: [String] {
        let names = ai.ollamaModels.map(\.name)
        let saved = preferences.ollamaModel
        return saved.isEmpty || names.contains(saved) ? names : [saved] + names
    }

    private var engineFooter: String {
        switch preferences.aiEngine {
        case .apple:
            "Needs macOS 26 or later on a Mac that supports Apple Intelligence, with Apple Intelligence turned on in System Settings."
        case .ollama:
            "Ollama runs open models on your Mac. Install it from ollama.com and pull a model, such as \"ollama pull llama3.2\". Wisp only connects to Ollama on this Mac."
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch ai.status {
        case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wispViolet)
        case .checking: ProgressView().controlSize(.small)
        default: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var actions: some View {
        Section {
            LabeledContent("Translate to") {
                TextField("Translate to", text: $preferences.aiTranslateLanguage, prompt: Text("English"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
        } header: {
            Text("Text actions")
        } footer: {
            Text(
                "Right-click a text item in the clipboard panel and choose AI, or press ⌘1 to ⌘8. Add an AI action to the ring to work on the text selected in any app, or else on the clipboard. Reading the selection needs Accessibility."
            )
        }
    }

    private var tryIt: some View {
        Section {
            TextField("Text", text: $sample, prompt: Text("Paste some text"), axis: .vertical)
                .lineLimit(3...6)
                .labelsHidden()
            HStack {
                Picker("Task", selection: $task) {
                    ForEach(AITask.menu, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button("Try it", action: run)
                    .disabled(running || !ai.status.isReady || sample.trimmingCharacters(in: .whitespaces).isEmpty)
                if running { ProgressView().controlSize(.small) }
            }
            if let answer {
                Text(answer.text).textSelection(.enabled)
                if answer.truncated {
                    Text("The text was too long, so only its start and end were used.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Try it")
        }
    }

    private func run() {
        running = true
        answer = nil
        failure = nil
        Task {
            do throws(AIError) {
                answer = try await ai.run(task, on: sample)
            } catch {
                failure = error.message
            }
            running = false
        }
    }
}
