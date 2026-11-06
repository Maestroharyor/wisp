import XCTest

@testable import WispCore

final class AgentQuestionTests: XCTestCase {
    /// The shape Claude Code 2.1.319 sent in a real session.
    private let input = JSONValue.object([
        "questions": .array([
            .object([
                "question": .string("Which colour?"), "header": .string("Colour"), "multiSelect": .bool(false),
                "options": .array([
                    .object(["label": .string("Red"), "description": .string("Pick red")]),
                    .object(["label": .string("Blue"), "description": .string("Pick blue")]),
                ]),
            ]),
            .object([
                "question": .string("Which sizes?"), "header": .string("Sizes"), "multiSelect": .bool(true),
                "options": .array([.object(["label": .string("S")]), .object(["label": .string("M")])]),
            ]),
        ])
    ])

    func testParsesQuestionsAndOptions() {
        let questions = AgentQuestion.parse(input)
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions[0].question, "Which colour?")
        XCTAssertEqual(questions[0].header, "Colour")
        XCTAssertEqual(questions[0].options.map(\.label), ["Red", "Blue"])
        XCTAssertEqual(questions[0].options[0].detail, "Pick red")
        XCTAssertFalse(questions[0].multiSelect)
        XCTAssertTrue(questions[1].multiSelect)
        XCTAssertNil(questions[1].options[0].detail)
    }

    func testMissingOrMalformedInputHasNoQuestions() {
        XCTAssertEqual(AgentQuestion.parse(nil), [])
        XCTAssertEqual(AgentQuestion.parse(.object(["questions": .string("x")])), [])
        XCTAssertEqual(AgentQuestion.parse(.object(["questions": .array([.object(["header": .string("H")])])])), [])
    }

    func testAnAnswerJoinsPicksAndOtherText() {
        XCTAssertEqual(AgentQuestion.answer(picked: ["Red"], other: ""), "Red")
        XCTAssertEqual(AgentQuestion.answer(picked: ["S", "M"], other: "  "), "S, M")
        XCTAssertEqual(AgentQuestion.answer(picked: [], other: " Teal, please "), "Teal, please")
        XCTAssertEqual(AgentQuestion.answer(picked: ["S"], other: "XL"), "S, XL")
        XCTAssertNil(AgentQuestion.answer(picked: [], other: ""))
    }

    func testTheReplyAllowsWithTheQuestionsAndAnswers() throws {
        let text = try XCTUnwrap(
            QuestionReply.json(input: input, answers: ["Which colour?": "Blue", "Which sizes?": "S, M"]))
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        let decision = json["hookSpecificOutput"]?["decision"]
        XCTAssertEqual(json["hookSpecificOutput"]?["hookEventName"]?.stringValue, "PermissionRequest")
        XCTAssertEqual(decision?["behavior"]?.stringValue, "allow")
        XCTAssertEqual(decision?["updatedInput"]?["questions"], input["questions"])
        XCTAssertEqual(decision?["updatedInput"]?["answers"]?["Which colour?"]?.stringValue, "Blue")
        XCTAssertEqual(decision?["updatedInput"]?["answers"]?["Which sizes?"]?.stringValue, "S, M")
    }

    func testAQuestionKeepsItsInputSoItCanBeAnswered() {
        XCTAssertTrue(PermissionPrompt.question.keepsInput)
        XCTAssertTrue(PermissionPrompt.plan.keepsInput)
        XCTAssertFalse(PermissionPrompt.tool.keepsInput)
    }
}
