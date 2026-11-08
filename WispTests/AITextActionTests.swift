import Foundation
import XCTest

@testable import WispCore

final class AITextInputTests: XCTestCase {
    func testTheSelectionComesFirst() {
        let input = AITextInput.pick(selection: "picked", clipboard: "copied", app: 42)
        XCTAssertEqual(input, AITextInput(text: "picked", source: .selection, app: 42))
    }

    func testABlankSelectionFallsBackToTheClipboard() {
        XCTAssertEqual(
            AITextInput.pick(selection: " \n\t", clipboard: "copied", app: 1),
            AITextInput(text: "copied", source: .clipboard, app: 1))
        XCTAssertEqual(AITextInput.pick(selection: nil, clipboard: "copied", app: nil)?.source, .clipboard)
    }

    func testNothingToWorkOnGivesNil() {
        XCTAssertNil(AITextInput.pick(selection: nil, clipboard: nil, app: 1))
        XCTAssertNil(AITextInput.pick(selection: "", clipboard: "  ", app: 1))
    }

    func testTheTextIsKeptAsIs() {
        XCTAssertEqual(AITextInput.pick(selection: "  a b\n", clipboard: nil, app: 1)?.text, "  a b\n")
    }

    func testReplaceNeedsTheSameSelection() {
        let input = AITextInput(text: "teh cat", source: .selection, app: 7)
        XCTAssertTrue(input.selectionUnchanged("teh cat"))
        XCTAssertFalse(input.selectionUnchanged("the cat"))
        XCTAssertFalse(input.selectionUnchanged(nil))
        XCTAssertTrue(AITextInput(text: "a", source: .clipboard, app: 7).selectionUnchanged(nil))
    }

    func testPastesOnlyIntoTheSameApp() {
        let input = AITextInput(text: "a", source: .selection, app: 7)
        XCTAssertTrue(input.canPaste(appNow: 7))
        XCTAssertFalse(input.canPaste(appNow: 8))
        XCTAssertFalse(input.canPaste(appNow: nil))
        XCTAssertFalse(AITextInput(text: "a", source: .selection, app: nil).canPaste(appNow: nil))
    }
}

final class AIClipboardTextTests: XCTestCase {
    func testPlainClipboardTextIsRead() {
        XCTAssertEqual(AIClipboardText.text("hello", types: ["public.utf8-plain-text"]), "hello")
    }

    func testConcealedAndTransientClipboardsAreSkipped() {
        for marker in ClipClassifier.privateTypes {
            XCTAssertNil(AIClipboardText.text("hunter2", types: ["public.utf8-plain-text", marker]), marker)
        }
    }

    func testBlankOrMissingTextIsSkipped() {
        XCTAssertNil(AIClipboardText.text(nil, types: ["public.png"]))
        XCTAssertNil(AIClipboardText.text(" \n", types: ["public.utf8-plain-text"]))
    }

    func testOnlyTextItemsAreOffered() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(AIClipboardText.offers(ClipItem(kind: .text, text: "notes", date: date)))
        XCTAssertFalse(AIClipboardText.offers(ClipItem(kind: .text, text: "  ", date: date)))
        XCTAssertFalse(AIClipboardText.offers(ClipItem(kind: .link, text: "https://example.com", date: date)))
        XCTAssertFalse(AIClipboardText.offers(ClipItem(kind: .color, text: "#7A6BFF", date: date)))
        XCTAssertFalse(AIClipboardText.offers(ClipItem(kind: .image, imageFile: "a.png", date: date)))
    }
}

final class AITextActionTests: XCTestCase {
    func testTextActionsAddTranslateAfterSummarise() {
        let tasks = AITask.textActions(language: "French")
        XCTAssertEqual(tasks.count, AITask.menu.count + 1)
        XCTAssertEqual(tasks.first, .summarise)
        XCTAssertEqual(tasks[1], .translate(language: "French"))
        XCTAssertFalse(tasks.contains(.sessionSummary))
    }

    func testEveryTextActionRoundTripsThroughItsID() {
        for task in AITask.textActions(language: "German") {
            XCTAssertEqual(task.actionID.flatMap { AITask(actionID: $0, language: "German") }, task)
        }
        let ids = AITask.textActions(language: "").compactMap(\.actionID)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTranslateTakesTheLanguageFromSettings() {
        XCTAssertEqual(AITask(actionID: "translate", language: "Spanish"), .translate(language: "Spanish"))
    }

    func testUnknownIDsAndOtherTasksGiveNothing() {
        XCTAssertNil(AITask(actionID: "poem", language: ""))
        XCTAssertNil(AITask.sessionSummary.actionID)
        XCTAssertNil(AITask.quickInput(now: .now, timeZone: .current).actionID)
        XCTAssertNil(AITask.actionTitle(id: "poem"))
    }

    func testActionTitlesLeaveOutTheLanguage() {
        XCTAssertEqual(AITask.actionTitle(id: "translate"), "Translate")
        XCTAssertEqual(AITask.actionTitle(id: "rewrite.shorter"), "Make shorter")
        XCTAssertEqual(AITask.actionTitle(id: "summarise"), "Summarise")
    }

    func testProgressTitles() {
        XCTAssertEqual(AITask.summarise.progressTitle, "Summarising")
        XCTAssertEqual(AITask.translate(language: " ").progressTitle, "Translating to English")
        XCTAssertEqual(AITask.translate(language: "Yoruba").progressTitle, "Translating to Yoruba")
    }

    func testOnlySameLengthTasksReplaceText() {
        XCTAssertTrue(AITask.fixGrammar.replacesText)
        XCTAssertTrue(AITask.rewrite(tone: .friendly).replacesText)
        XCTAssertTrue(AITask.translate(language: "French").replacesText)
        XCTAssertFalse(AITask.summarise.replacesText)
        XCTAssertFalse(AITask.explain.replacesText)
    }
}

final class AIResultButtonTests: XCTestCase {
    func testASelectionGetsReplace() {
        XCTAssertEqual(AIResultButton.buttons(task: .fixGrammar, source: .selection), [.copy, .replace])
        XCTAssertEqual(AIResultButton.buttons(task: .summarise, source: .selection), [.replace, .copy])
    }

    func testClipboardTextGetsPaste() {
        XCTAssertEqual(AIResultButton.buttons(task: .fixGrammar, source: .clipboard), [.copy, .paste])
        XCTAssertEqual(AIResultButton.buttons(task: .explain, source: .clipboard), [.paste, .copy])
    }

    func testSubtitles() {
        XCTAssertEqual(
            AIResultButton.subtitle(source: .selection, working: true, truncated: false), "Working on the selection")
        XCTAssertEqual(
            AIResultButton.subtitle(source: .clipboard, working: false, truncated: false), "From the clipboard")
        XCTAssertEqual(
            AIResultButton.subtitle(source: .selection, working: false, truncated: true),
            "From the selection, only its start and end")
    }
}

final class AIRingActionTests: XCTestCase {
    func testTheRingActionNamesItsTask() {
        XCTAssertEqual(RingAction(.ai, value: "fixGrammar").title, "Fix grammar")
        XCTAssertEqual(RingAction(.ai, value: "translate").title, "Translate")
        XCTAssertEqual(RingAction(.ai).title, "AI action")
        XCTAssertEqual(RingAction(.ai, value: "gone").title, "AI action")
    }

    func testAnUnsetTaskSummarises() {
        XCTAssertEqual(RingAction(.ai).aiTaskID, "summarise")
        XCTAssertEqual(RingAction(.ai, value: "explain").aiTaskID, "explain")
    }

    func testTheRingActionRoundTrips() throws {
        let action = RingAction(.ai, value: "rewrite.professional")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(RingAction.self, from: data), action)
    }

    func testItDoesNotTakeFiles() {
        XCTAssertFalse(RingAction(.ai).acceptsFiles)
        XCTAssertFalse(RingAction(.ai).opensChoices)
    }
}
