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
                                    .background(Capsule().fill(.white.opacity(0.14)))
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
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .frame(height: SurfaceSizing.notificationCardHeight - 8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
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
    private var hidden: Bool { hub.detailsHidden && !revealed }

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
            header: question.header.isEmpty ? "Question" : question.header,
            text: hidden ? "Question hidden" : question.question,
            position: questions.count > 1 ? "\(index + 1) of \(questions.count)" : nil)
    }

    @ViewBuilder private func answerRow(for question: AgentQuestion) -> some View {
        HStack(spacing: 6) {
            if hidden {
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
                    .background(Capsule().fill(.white.opacity(0.1)))
                Button("Cancel") {
                    typing = false
                    other = ""
                }
                .buttonStyle(QuestionChipStyle(selected: false))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(question.options, id: \.label) { option in
                            Button(option.label) { pick(option.label, in: question) }
                                .buttonStyle(QuestionChipStyle(selected: picked.contains(option.label)))
                                .help(option.detail ?? option.label)
                        }
                        Button("Other…") { typing = true }
                            .buttonStyle(QuestionChipStyle(selected: false))
                    }
                }
            }
            Spacer(minLength: 4)
            if typing || (question.multiSelect && !picked.isEmpty) {
                Button("Send") { submit(question) }
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

/// An answer chip: violet when picked or when it sends.
private struct QuestionChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Color.wispViolet : .white.opacity(0.14)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
