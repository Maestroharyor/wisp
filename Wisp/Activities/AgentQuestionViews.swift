import SwiftUI
import WispCore

/// A question from Claude (AskUserQuestion) under the notch: the question, then its options
/// as buttons, "Other…" for a typed answer, and Terminal to answer it there instead.
struct AgentQuestionCard: View {
    let approval: AgentApproval
    let model: NotchModel

    var body: some View {
        let hub = model.services.agents
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            QuestionAnswers(approval: approval, hub: hub, model: model) { step in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.project(approval.project))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.project(approval.project).opacity(0.18)))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(step.header).font(.system(size: 13, weight: .bold)).lineLimit(1)
                            if let position = step.position {
                                Text(position)
                                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(.ink.opacity(0.14)))
                            }
                            Button {
                                hub.focus(session: approval.sessionID)
                            } label: {
                                Label(approval.project, systemImage: "arrow.up.forward.app")
                                    .font(.system(size: 11)).foregroundStyle(Color.project(approval.project))
                            }
                            .buttonStyle(.plain)
                            .help("Show the terminal")
                        }
                        Text(step.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.ink.opacity(0.85))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .frame(height: SurfaceSizing.notificationCardHeight - 8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
    }
}

/// What the question card shows above its answers for the current question.
struct QuestionStep {
    let header: String
    let text: String
    /// "1 of 2" when Claude asked several questions at once.
    let position: String?
}

/// Steps through the questions in one request, collects an answer for each and sends them
/// together after the last. Single-choice questions answer on a click; multiple choice and
/// typed answers need Send. In private mode the question and options stay hidden until Show.
struct QuestionAnswers<Header: View>: View {
    let approval: AgentApproval
    let hub: AgentHub
    let model: NotchModel
    @ViewBuilder let header: (QuestionStep) -> Header

    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var picked: [String] = []
    @State private var other = ""
    @State private var typing = false
    @State private var revealed = false
    @State private var ready = false
    @FocusState private var fieldFocused: Bool

    private var questions: [AgentQuestion] { approval.questions }
    private var hyper: Bool { hub.keysUseHyper() }
    private var hidden: Bool { hub.detailsHidden && !revealed }
    private var listening: Bool {
        let dictation = model.services.dictation
        return dictation.phase.isActive && dictation.target == .questionAnswer(approval.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let question = questions.indices.contains(index) ? questions[index] : nil {
                header(step(for: question))
                answerRow(for: question)
                    .padding(.horizontal, 18)
                    .frame(height: SurfaceSizing.questionRowHeight)
            }
        }
        .task(id: approval.id) {
            index = 0
            answers = [:]
            reset()
            ready = false
            // A click aimed at the previous card mustn't answer this one.
            try? await Task.sleep(for: .milliseconds(400))
            ready = true
        }
        .onChange(of: index) { _, _ in hub.questionStepChanged() }
        .onChange(of: hub.keyAnswer) { _, key in
            guard let key, key.approval == approval.id else { return }
            answer(key.action)
        }
        .onChange(of: model.dictatedAnswer) { _, dictated in
            guard let dictated, dictated.approval == approval.id else { return }
            model.dictatedAnswer = nil
            // The user spoke the answer, so show it, ready to check and send.
            revealed = true
            other = DictationText.appending(dictated.text, to: other)
            typing = true
        }
        .onChange(of: typing) { _, now in
            if now {
                model.onWantsKey()
                fieldFocused = true
            } else {
                model.onKeyDone()
            }
        }
    }

    private func step(for question: AgentQuestion) -> QuestionStep {
        QuestionStep(
            // Claude writes the header too, so private mode hides it with the question.
            header: question.header.isEmpty || hidden ? "Question" : question.header,
            text: hidden ? "Question hidden" : question.question,
            position: questions.count > 1 ? "\(index + 1) of \(questions.count)" : nil)
    }

    @ViewBuilder private func answerRow(for question: AgentQuestion) -> some View {
        HStack(spacing: 6) {
            if listening {
                Label("Listening…", systemImage: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.ink.opacity(0.85))
            } else if hidden {
                Button("Show") { revealed = true }
                    .buttonStyle(QuestionChipStyle(selected: false))
                    .help("Show the question and its answers")
            } else if typing {
                TextField("Your answer", text: $other)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($fieldFocused)
                    .onSubmit { submit(question) }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(.ink.opacity(0.1)))
                Button("Cancel") {
                    typing = false
                    other = ""
                }
                .buttonStyle(QuestionChipStyle(selected: false))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(question.options.enumerated()), id: \.element.label) { index, option in
                            let hint = ApprovalKeys.hint(.pick(index), hyper: hyper)
                            Button {
                                pick(option.label, in: question)
                            } label: {
                                HStack(spacing: 5) {
                                    // Only options 1 to 9 have a key.
                                    if hint != nil { OptionNumber(number: index + 1) }
                                    Text(option.label)
                                }
                            }
                            .buttonStyle(QuestionChipStyle(selected: picked.contains(option.label)))
                            .help([option.detail ?? option.label, hint].compactMap { $0 }.joined(separator: " · "))
                        }
                        Button("Other…") { typing = true }
                            .buttonStyle(QuestionChipStyle(selected: false))
                    }
                }
            }
            Spacer(minLength: 4)
            if typing || (question.multiSelect && !picked.isEmpty) {
                Button {
                    submit(question)
                } label: {
                    // The send key only answers a multiple choice; a typed answer is sent with Return.
                    KeyHintLabel(title: "Send", hint: typing ? nil : ApprovalKeys.hint(.send, hyper: hyper))
                }
                .buttonStyle(QuestionChipStyle(selected: true))
                .disabled(AgentQuestion.answer(picked: picked, other: other) == nil)
            }
            Button("Terminal") {
                typing = false
                hub.answer(approval.id, allow: nil)
            }
            .buttonStyle(QuestionChipStyle(selected: false))
            .help("Answer in the terminal instead")
        }
        .disabled(!ready)
        .opacity(ready ? 1 : 0.6)
    }

    /// A shortcut does what clicking the matching chip would, once the card is ready and shown.
    private func answer(_ action: ApprovalKeys.Action) {
        guard ready, !hidden, !typing, questions.indices.contains(index) else { return }
        let question = questions[index]
        switch action {
        case .pick(let option) where question.options.indices.contains(option):
            pick(question.options[option].label, in: question)
        case .send where question.multiSelect && !picked.isEmpty:
            submit(question)
        default:
            break
        }
    }

    private func pick(_ label: String, in question: AgentQuestion) {
        if question.multiSelect {
            if let at = picked.firstIndex(of: label) { picked.remove(at: at) } else { picked.append(label) }
        } else {
            picked = [label]
            submit(question)
        }
    }

    private func submit(_ question: AgentQuestion) {
        guard let answer = AgentQuestion.answer(picked: picked, other: other) else { return }
        answers[question.question] = answer
        typing = false
        reset()
        if index + 1 < questions.count {
            index += 1
        } else {
            hub.answerQuestion(approval.id, answers: answers)
        }
    }

    private func reset() {
        picked = []
        other = ""
    }
}

/// The option's number, matching its Hyper+digit (or ⌃⌥⌘digit) key.
private struct OptionNumber: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 9, weight: .bold)).monospacedDigit()
            .frame(width: 14, height: 14)
            .background(Circle().fill(.ink.opacity(0.2)))
            .accessibilityHidden(true)
    }
}

/// An answer chip: violet when picked or when it sends.
private struct QuestionChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(selected ? Color.white : Color.ink)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Color.wispViolet : .ink.opacity(0.14)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
