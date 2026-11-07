import AppKit
import Foundation
import Observation
import WispCore

/// On-device AI for the features that offer it (clipboard actions, session summaries, quick
/// input). Off until turned on in Settings › AI. Runs a task through the chosen engine: Apple's
/// Foundation Models or Ollama on this Mac. Nothing is sent off the Mac, and prompts and answers
/// are never logged.
@MainActor
@Observable
final class AIService {
    /// The chosen engine's state, for Settings and for features deciding whether to offer AI.
    private(set) var status: AIAvailability = .off
    /// Ollama's chat models, filled in by `refresh` while Ollama is chosen.
    private(set) var ollamaModels: [OllamaModel] = []

    @ObservationIgnored private let preferences: Preferences
    /// Bumped by every check, so a slow one that finishes after a newer one can't overwrite it
    /// (switching engine or editing the Ollama address while a check is out).
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    /// Seconds between checks while AI is on but not ready: Ollama may start after Wisp, and
    /// Apple's model may still be downloading.
    private static let retryDelays: [Double] = [10, 30, 60, 300]

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Checks at launch and after every wake, retrying a few times while the engine isn't ready.
    func start() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkUntilReady() }
        }
        checkUntilReady()
    }

    func stop() {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        retryTask?.cancel()
        retryTask = nil
    }

    private func checkUntilReady() {
        retryTask?.cancel()
        guard preferences.aiEnabled else { return }
        retryTask = Task { [weak self] in
            for delay in [0] + Self.retryDelays {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, let self, self.preferences.aiEnabled else { return }
                await self.refresh()
                if self.status.isReady { return }
            }
        }
    }

    /// AI is on and the engine answered the last check.
    var isReady: Bool { preferences.aiEnabled && status.isReady }

    /// Checks the chosen engine again. Call at launch, when Settings opens or an AI setting changes.
    func refresh() async {
        generation += 1
        let current = generation
        guard preferences.aiEnabled else {
            status = .off
            return
        }
        if !status.isReady { status = .checking }
        switch preferences.aiEngine {
        case .apple:
            let state = await FoundationModelsEngine().availability()
            if current == generation { status = state }
        case .ollama:
            let engine = ollama()
            let models: [OllamaModel]
            let state: AIAvailability
            do {
                models = try await engine.models()
                state = engine.status(models: models)
            } catch {
                models = []
                if case .unavailable(let reason) = error { state = reason } else { state = .ollamaNotRunning }
            }
            guard current == generation else { return }
            ollamaModels = models
            status = state
        }
    }

    /// Runs `task` on `input`, trimmed to fit the model, and returns the tidied answer. An answer
    /// that stopped part way throws `.cutOff` for tasks that replace text (translate, fix,
    /// rewrite) or need JSON (quick input); for the rest it comes back marked as truncated.
    func run(_ task: AITask, on input: String) async throws(AIError) -> AIAnswer {
        guard preferences.aiEnabled else { throw .unavailable(.off) }
        generation += 1
        let current = generation
        let engine = currentEngine()
        let state = await engine.availability()
        if current == generation { status = state }
        guard state.isReady else { throw .unavailable(state) }
        guard let prompt = await fit(task, input: input, engine: engine), !prompt.prompt.isEmpty else {
            throw .tooLong
        }
        return try AIOutput.answer(try await engine.respond(to: prompt), for: task, prompt: prompt)
    }

    private func currentEngine() -> any AIEngine {
        switch preferences.aiEngine {
        case .apple: FoundationModelsEngine()
        case .ollama: ollama()
        }
    }

    private func ollama() -> OllamaEngine {
        OllamaEngine(address: preferences.ollamaAddress, model: preferences.ollamaModel)
    }

    /// Trims by the character estimate, then once more if the model's own count says it's still
    /// too long. Nil when even a shorter input can't fit.
    private func fit(_ task: AITask, input: String, engine: any AIEngine) async -> AIPrompt? {
        let context = await engine.contextTokens()
        let prompt = AIBudget.prompt(for: task, input: input, contextTokens: context)
        guard let count = await engine.countTokens(prompt) else { return prompt }
        return AIBudget.refit(prompt, task: task, input: input, contextTokens: context, count: count)
    }
}
