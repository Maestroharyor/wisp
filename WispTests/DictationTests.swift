import XCTest

@testable import WispCore

final class PushToTalkTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A shared-key machine that is recording, started at 0.3 s.
    private func sharedRecording() -> PushToTalk {
        var talk = PushToTalk(sharedWithShelf: true)
        _ = talk.press(at: at(0))
        _ = talk.holdElapsed(at: at(0.3))
        return talk
    }

    // MARK: Pressing

    func testSharedKeyWaitsForTheHoldBeforeRecording() {
        var talk = PushToTalk(sharedWithShelf: true)
        XCTAssertEqual(talk.holdDelay, PushToTalk.sharedKeyHoldDelay)
        XCTAssertEqual(talk.press(at: at(0)), .none)
        XCTAssertEqual(talk.phase, .pressed(since: at(0)))
        XCTAssertEqual(talk.holdElapsed(at: at(0.1)), .none, "too early")
        XCTAssertEqual(talk.holdElapsed(at: at(0.3)), .startRecording)
        XCTAssertEqual(talk.phase, .recording(since: at(0.3)))
    }

    func testQuickPressOnASharedKeyIsATap() {
        var talk = PushToTalk(sharedWithShelf: true)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.release(at: at(0.15)), .tap)
        XCTAssertEqual(talk.phase, .idle)
    }

    func testHoldTimerAfterReleaseOrCancelDoesNothing() {
        var talk = PushToTalk(sharedWithShelf: true)
        _ = talk.press(at: at(0))
        _ = talk.release(at: at(0.1))
        XCTAssertEqual(talk.holdElapsed(at: at(0.3)), .none)
        XCTAssertEqual(talk.phase, .idle)

        _ = talk.press(at: at(1))
        _ = talk.cancel()
        XCTAssertEqual(talk.holdElapsed(at: at(1.3)), .none)
        XCTAssertEqual(talk.phase, .idle)
    }

    func testOwnKeyRecordsAtOnce() {
        var talk = PushToTalk(sharedWithShelf: false)
        XCTAssertEqual(talk.holdDelay, 0)
        XCTAssertEqual(talk.press(at: at(0)), .startRecording)
        XCTAssertEqual(talk.phase, .recording(since: at(0)))
    }

    func testSecondPressWhileHeldIsIgnored() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.press(at: at(0.5)), .none)
        XCTAssertEqual(talk.phase, .recording(since: at(0)))
    }

    func testSharedKeyStillOpensTheShelfWhileBusy() {
        var talk = sharedRecording()
        _ = talk.release(at: at(2))
        XCTAssertEqual(talk.phase, .finishing)
        XCTAssertEqual(talk.press(at: at(2.1)), .tap)
        XCTAssertEqual(talk.phase, .finishing, "the dictation in progress carries on")
        XCTAssertEqual(talk.release(at: at(2.2)), .none)

        _ = talk.transcribed("hello")
        XCTAssertEqual(talk.phase, .delivering)
        XCTAssertEqual(talk.press(at: at(2.3)), .tap)
        XCTAssertEqual(talk.phase, .delivering)
    }

    func testShelfTapWhileFinishingKeepsTheDictation() {
        var talk = sharedRecording()
        _ = talk.release(at: at(2))
        let effect = talk.press(at: at(2.5))
        XCTAssertEqual(effect, .tap, "a plain tap: the recording being transcribed isn't thrown away")
        XCTAssertNotEqual(effect, .tapDiscardingRecording)
        XCTAssertEqual(talk.transcribed("still here"), .deliver("still here"))
        talk.delivered()
        XCTAssertEqual(talk.phase, .idle)
    }

    func testQuickPressAndBlockedHoldArePlainTaps() {
        var talk = PushToTalk(sharedWithShelf: true)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.release(at: at(0.1)), .tap)
        var blocked = sharedRecording()
        _ = blocked.unavailable()
        XCTAssertEqual(blocked.release(at: at(2)), .tap, "nothing was recording, so nothing to throw away")
    }

    func testOwnKeyIgnoresPressesWhileBusy() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        _ = talk.release(at: at(2))
        XCTAssertEqual(talk.press(at: at(2.1)), .none)
        _ = talk.transcribed("hi")
        XCTAssertEqual(talk.press(at: at(3)), .none)
        XCTAssertEqual(talk.phase, .delivering)
    }

    // MARK: Releasing

    func testReleaseAfterSpeakingFinishesThenDelivers() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.release(at: at(2)), .finishRecording)
        XCTAssertEqual(talk.phase, .finishing)
        XCTAssertEqual(talk.transcribed("  hello   world "), .deliver("hello world"))
        XCTAssertEqual(talk.phase, .delivering)
        talk.delivered()
        XCTAssertEqual(talk.phase, .idle)
    }

    func testTooShortOnOwnKeyIsDiscarded() {
        var talk = PushToTalk(sharedWithShelf: false, minimumRecording: 0.5)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.release(at: at(0.2)), .discard(.tooShort))
        XCTAssertEqual(talk.phase, .idle)
    }

    func testTooShortOnSharedKeyOpensTheShelf() {
        var talk = sharedRecording()
        XCTAssertEqual(
            talk.release(at: at(0.5)), .tapDiscardingRecording, "0.2 s of recording is under the minimum")
        XCTAssertEqual(talk.phase, .idle)
    }

    func testReleaseWhileFinishingDoesNothing() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        _ = talk.release(at: at(2))
        XCTAssertEqual(talk.release(at: at(2.5)), .none)
        XCTAssertEqual(talk.phase, .finishing)
    }

    // MARK: Recording can't start

    func testUnavailableOnSharedKeyWaitsThenOpensTheShelf() {
        var talk = sharedRecording()
        XCTAssertEqual(talk.unavailable(), .none, "no error notice for the shelf key")
        XCTAssertEqual(talk.phase, .blocked)
        XCTAssertFalse(talk.phase.isListening)
        XCTAssertEqual(talk.release(at: at(3)), .tap)
        XCTAssertEqual(talk.phase, .idle)
    }

    func testUnavailableOnOwnKeyIsReported() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.unavailable(), .discard(.unavailable))
        XCTAssertEqual(talk.phase, .idle)
        XCTAssertEqual(talk.release(at: at(1)), .none)
    }

    func testUnavailableOutsideRecordingDoesNothing() {
        var talk = PushToTalk(sharedWithShelf: true)
        XCTAssertEqual(talk.unavailable(), .none)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.unavailable(), .none)
        XCTAssertEqual(talk.phase, .pressed(since: at(0)))
    }

    func testCancelWhileBlockedIsQuiet() {
        var talk = sharedRecording()
        _ = talk.unavailable()
        XCTAssertEqual(talk.cancel(), .none)
        XCTAssertEqual(talk.phase, .idle)
    }

    // MARK: Transcripts and failures

    func testNothingHeardIsDiscarded() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        _ = talk.release(at: at(2))
        XCTAssertEqual(talk.transcribed("   "), .discard(.nothingHeard))
        XCTAssertEqual(talk.phase, .idle)
    }

    func testTranscriptWhileStillRecordingIsIgnored() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.transcribed("early"), .none)
        XCTAssertEqual(talk.phase, .recording(since: at(0)))
    }

    func testCancelWhileRecordingOrFinishingDiscards() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.cancel(), .discard(.cancelled))
        XCTAssertEqual(talk.phase, .idle)
        XCTAssertEqual(talk.release(at: at(1)), .none, "the key-up after a cancel does nothing")

        _ = talk.press(at: at(2))
        _ = talk.release(at: at(4))
        XCTAssertEqual(talk.cancel(), .discard(.cancelled))
        XCTAssertEqual(talk.transcribed("late"), .none, "a transcript after a cancel is dropped")
    }

    func testCancelBeforeTheHoldIsQuiet() {
        var talk = PushToTalk(sharedWithShelf: true)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.cancel(), .none)
        XCTAssertEqual(talk.phase, .idle)
        XCTAssertEqual(talk.cancel(), .none)
    }

    func testFailureDiscards() {
        var talk = PushToTalk(sharedWithShelf: false)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.failed(), .discard(.failed))
        XCTAssertEqual(talk.phase, .idle)
        XCTAssertEqual(talk.failed(), .none)
    }

    func testFailureBeforeTheHoldDoesNothing() {
        var talk = PushToTalk(sharedWithShelf: true)
        _ = talk.press(at: at(0))
        XCTAssertEqual(talk.failed(), .none)
        XCTAssertEqual(talk.phase, .pressed(since: at(0)))
    }

    func testIsListeningOnlyWhileRecording() {
        var talk = PushToTalk(sharedWithShelf: true)
        XCTAssertFalse(talk.phase.isActive)
        _ = talk.press(at: at(0))
        XCTAssertFalse(talk.phase.isListening)
        XCTAssertTrue(talk.phase.isActive)
        _ = talk.holdElapsed(at: at(0.3))
        XCTAssertTrue(talk.phase.isListening)
        _ = talk.release(at: at(2))
        XCTAssertFalse(talk.phase.isListening)
        XCTAssertTrue(talk.phase.isActive)
    }
}

final class HoldKeyTests: XCTestCase {
    private let space = KeyCodes.space

    func testHoldStartsOnlyWithHyper() {
        var hold = HoldKey()
        XCTAssertEqual(hold.key(space, down: true, hyperDown: false, holdKey: space), .notMine)
        XCTAssertEqual(hold.key(space, down: false, hyperDown: false, holdKey: space), .notMine)
        XCTAssertEqual(hold.key(space, down: true, hyperDown: true, holdKey: space), .swallow(.down))
        XCTAssertTrue(hold.holding)
    }

    func testRepeatsAreSwallowedQuietly() {
        var hold = HoldKey()
        _ = hold.key(space, down: true, hyperDown: true, holdKey: space)
        XCTAssertEqual(hold.key(space, down: true, hyperDown: true, holdKey: space), .swallow(nil))
        XCTAssertEqual(hold.key(space, down: true, hyperDown: false, holdKey: space), .swallow(nil))
    }

    func testReleaseCountsEvenAfterHyperComesUp() {
        var hold = HoldKey()
        _ = hold.key(space, down: true, hyperDown: true, holdKey: space)
        XCTAssertEqual(hold.key(space, down: false, hyperDown: false, holdKey: space), .swallow(.up))
        XCTAssertFalse(hold.holding)
        XCTAssertEqual(hold.key(space, down: false, hyperDown: false, holdKey: space), .notMine)
    }

    func testEscapeCancelsAndItsKeyUpIsSwallowed() {
        var hold = HoldKey()
        XCTAssertEqual(hold.key(KeyCodes.escape, down: true, hyperDown: true, holdKey: space), .notMine)
        XCTAssertEqual(hold.key(KeyCodes.escape, down: false, hyperDown: true, holdKey: space), .notMine)
        _ = hold.key(space, down: true, hyperDown: true, holdKey: space)
        XCTAssertEqual(hold.key(KeyCodes.escape, down: true, hyperDown: true, holdKey: space), .swallow(.cancel))
        XCTAssertEqual(hold.key(KeyCodes.escape, down: false, hyperDown: true, holdKey: space), .swallow(nil))
        XCTAssertEqual(
            hold.key(space, down: false, hyperDown: true, holdKey: space), .swallow(.up),
            "the hold key's own release still ends the hold")
    }

    func testOtherKeysAndNoHoldKeyAreNotMine() {
        var hold = HoldKey()
        XCTAssertEqual(hold.key(KeyCodes.v, down: true, hyperDown: true, holdKey: space), .notMine)
        XCTAssertEqual(hold.key(space, down: true, hyperDown: true, holdKey: nil), .notMine)
    }

    func testResetCancelsAHold() {
        var hold = HoldKey()
        XCTAssertNil(hold.reset())
        _ = hold.key(space, down: true, hyperDown: true, holdKey: space)
        XCTAssertEqual(hold.reset(), .cancel)
        XCTAssertFalse(hold.holding)
        XCTAssertEqual(hold.key(space, down: false, hyperDown: false, holdKey: space), .notMine)
    }
}

final class DictationTargetTests: XCTestCase {
    func testOpenDraftBoxWins() {
        let question = UUID()
        XCTAssertEqual(
            DictationTarget.choose(draftSession: "s1", questionCard: question), .agentDraft(session: "s1"))
    }

    func testQuestionCardIsNext() {
        let question = UUID()
        XCTAssertEqual(DictationTarget.choose(draftSession: nil, questionCard: question), .questionAnswer(question))
    }

    func testOtherwiseTheFocusedApp() {
        XCTAssertEqual(DictationTarget.choose(draftSession: nil, questionCard: nil), .focusedApp)
        XCTAssertEqual(DictationTarget.choose(draftSession: "", questionCard: nil), .focusedApp)
    }

    func testOnlyTheFocusedAppShowsThePill() {
        XCTAssertTrue(DictationTarget.focusedApp.showsPill)
        XCTAssertFalse(DictationTarget.agentDraft(session: "s").showsPill)
        XCTAssertFalse(DictationTarget.questionAnswer(UUID()).showsPill)
    }
}

final class DraftBoxClaimTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()

    func testClaimAndRelease() {
        let claim = DraftBoxClaim.claim(nil, owner: first, session: "s1")
        XCTAssertEqual(claim, DraftBoxClaim(owner: first, session: "s1"))
        XCTAssertNil(DraftBoxClaim.release(claim, owner: first))
    }

    func testOldViewGoingAwayKeepsTheNewViewsClaim() {
        // The new view appears before the old one disappears.
        let old = DraftBoxClaim.claim(nil, owner: first, session: "s1")
        let new = DraftBoxClaim.claim(old, owner: second, session: "s1")
        XCTAssertEqual(DraftBoxClaim.release(new, owner: first), new)
    }

    func testHidingDetailsReleasesOnlyYourOwnClaim() {
        let mine = DraftBoxClaim.claim(nil, owner: first, session: "s1")
        XCTAssertNil(DraftBoxClaim.claim(mine, owner: first, session: nil))
        XCTAssertEqual(DraftBoxClaim.claim(mine, owner: second, session: nil), mine)
    }
}

final class DictationPasteTests: XCTestCase {
    func testPastesOnlyIntoTheAppThatHadFocus() {
        XCTAssertEqual(DictationPaste.action(appAtStart: 42, appNow: 42), .paste)
        XCTAssertEqual(DictationPaste.action(appAtStart: 42, appNow: 7), .copy)
        XCTAssertEqual(DictationPaste.action(appAtStart: nil, appNow: 7), .copy)
        XCTAssertEqual(DictationPaste.action(appAtStart: 42, appNow: nil), .copy)
    }

    func testClipboardIsCapturedOnlyWhenNothingWouldBeLost() {
        let text = ["public.utf8-plain-text"]
        let web = ["public.utf8-plain-text", "public.html", "public.rtf"]
        XCTAssertTrue(DictationPaste.canCapture(itemTypes: []), "an empty clipboard comes back empty")
        XCTAssertTrue(DictationPaste.canCapture(itemTypes: [text]))
        XCTAssertTrue(DictationPaste.canCapture(itemTypes: [web, ["public.jpeg"], ["com.adobe.pdf"]]))
        XCTAssertTrue(DictationPaste.canCapture(itemTypes: [["public.png", "public.tiff", "public.file-url"]]))
    }

    func testClipboardWithOtherTypesIsLeftAlone() {
        XCTAssertFalse(DictationPaste.canCapture(itemTypes: [["com.figma.design"]]), "nothing capturable")
        XCTAssertFalse(
            DictationPaste.canCapture(itemTypes: [["public.utf8-plain-text", "com.microsoft.Excel.sheet"]]),
            "a type would be left out, so it would come back partial")
        XCTAssertFalse(
            DictationPaste.canCapture(itemTypes: [["public.utf8-plain-text"], ["com.example.private"]]),
            "one item can't be captured")
        XCTAssertFalse(DictationPaste.canCapture(itemTypes: [[]]), "an item with no types can't be put back")
    }

    func testLargeClipboardsAreNotRestored() {
        XCTAssertTrue(DictationPaste.canRestore(byteCount: 0))
        XCTAssertTrue(DictationPaste.canRestore(byteCount: DictationPaste.restoreLimit))
        XCTAssertFalse(DictationPaste.canRestore(byteCount: DictationPaste.restoreLimit + 1))
    }

    func testRestoresTheClipboardUnlessSomethingNewWasCopied() {
        XCTAssertTrue(DictationPaste.shouldRestore(stagedChangeCount: 10, currentChangeCount: 10))
        XCTAssertFalse(DictationPaste.shouldRestore(stagedChangeCount: 10, currentChangeCount: 11))
    }
}

final class DictationTranscriptTests: XCTestCase {
    func testPartialResultsReplaceEachOther() {
        var transcript = DictationTranscript()
        transcript.update("hel")
        transcript.update("hello there")
        XCTAssertEqual(transcript.text, "hello there")
    }

    func testEarlyFinalResultIsKeptAndListeningGoesOn() {
        var transcript = DictationTranscript()
        transcript.update("first part")
        transcript.commit("First part.")
        XCTAssertEqual(transcript.text, "First part.")
        transcript.update("second")
        XCTAssertEqual(transcript.text, "First part. second")
        transcript.commit("Second part.")
        XCTAssertEqual(transcript.text, "First part. Second part.")
    }

    func testEmptyFinalAddsNothing() {
        var transcript = DictationTranscript()
        transcript.commit("  ")
        XCTAssertEqual(transcript.committed, [])
        XCTAssertEqual(transcript.text, "")
    }
}

final class DictationTextTests: XCTestCase {
    func testTidyCollapsesWhitespace() {
        XCTAssertEqual(DictationText.tidy("  one\n two\t\tthree  "), "one two three")
        XCTAssertEqual(DictationText.tidy(" \n "), "")
    }

    func testAppendingAddsOneSpace() {
        XCTAssertEqual(DictationText.appending("world", to: ""), "world")
        XCTAssertEqual(DictationText.appending("world", to: "hello"), "hello world")
        XCTAssertEqual(DictationText.appending("world", to: "hello "), "hello world")
        XCTAssertEqual(DictationText.appending("", to: "hello"), "hello")
    }

    func testFinishWithoutCleanupTidies() async {
        let text = await DictationText.finish("  hello  there ", cleanup: nil)
        XCTAssertEqual(text, "hello there")
    }

    func testFinishUsesCleanup() async {
        let text = await DictationText.finish("um so hello") { raw in
            raw.replacingOccurrences(of: "um so ", with: "").capitalized + "."
        }
        XCTAssertEqual(text, "Hello.")
    }

    func testFinishKeepsTheTranscriptWhenCleanupGivesNothing() async {
        let empty = await DictationText.finish("hello there") { _ in "  " }
        XCTAssertEqual(empty, "hello there")
        let failed = await DictationText.finish("hello there") { _ in nil }
        XCTAssertEqual(failed, "hello there")
    }

    func testSlowCleanupFallsBackToTheTranscript() async {
        let started = Date.now
        let text = await DictationText.finish(
            "hello there",
            cleanup: { _ in
                // Ignores cancellation on purpose: the timeout must not wait for it.
                let end = Date.now.addingTimeInterval(3)
                while Date.now < end { try? await Task.sleep(for: .milliseconds(20)) }
                return "too late"
            }, timeout: .milliseconds(100))
        XCTAssertEqual(text, "hello there")
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 2)
    }

    func testFastCleanupIsNotHeldUpByTheTimeout() async {
        let started = Date.now
        let text = await DictationText.finish("hi", cleanup: { _ in "Hi." }, timeout: .seconds(5))
        XCTAssertEqual(text, "Hi.")
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 1)
    }

    func testFinishSkipsCleanupForSilence() async {
        let text = await DictationText.finish("  ") { _ in
            XCTFail("clean-up must not run on an empty transcript")
            return "x"
        }
        XCTAssertNil(text)
    }
}

final class DictationReadinessTests: XCTestCase {
    private func check(
        speech: DictationPermission = .granted, microphone: DictationPermission = .granted,
        onDevice: Bool = true, hyperKey: Bool = true, hasMicrophone: Bool = true
    ) -> DictationReadiness {
        DictationReadiness.check(
            speech: speech, microphone: microphone, onDeviceRecognition: onDevice, hyperKey: hyperKey,
            hasMicrophone: hasMicrophone)
    }

    func testReadyWhenEverythingIsThere() {
        XCTAssertEqual(check(), .ready)
        XCTAssertTrue(check().isReady)
    }

    func testHyperKeyComesFirst() {
        XCTAssertEqual(check(speech: .denied, hyperKey: false), .needsHyperKey)
    }

    func testPermissions() {
        XCTAssertEqual(check(speech: .notAsked), .needsPermission)
        XCTAssertEqual(check(microphone: .notAsked), .needsPermission)
        XCTAssertEqual(check(speech: .denied), .speechDenied)
        XCTAssertEqual(check(microphone: .denied), .microphoneDenied)
    }

    func testNeverFallsBackToServerRecognition() {
        XCTAssertEqual(check(onDevice: false), .onDeviceUnavailable)
        XCTAssertFalse(check(onDevice: false).isReady)
    }

    func testNoMicrophone() {
        XCTAssertEqual(check(hasMicrophone: false), .noMicrophone)
    }

    func testEveryProblemHasAMessage() {
        let all: [DictationReadiness] = [
            .needsHyperKey, .needsPermission, .speechDenied, .microphoneDenied, .onDeviceUnavailable, .noMicrophone,
        ]
        for readiness in all {
            XCTAssertFalse(readiness.message.isEmpty)
            XCTAssertFalse(readiness.message.contains("—"))
        }
    }
}

final class DictationKeyTests: XCTestCase {
    func testKeysMapToKeyCodes() {
        XCTAssertEqual(DictationKey.space.keyCode, KeyCodes.space)
        XCTAssertEqual(DictationKey.d.keyCode, 2)
        XCTAssertEqual(DictationKey.m.keyCode, 46)
    }

    func testNoKeyClashesWithOtherHyperShortcuts() {
        for key in DictationKey.allCases {
            XCTAssertFalse([KeyCodes.v, KeyCodes.r, KeyCodes.f].contains(key.keyCode))
            XCTAssertNil(KeyCodes.digit(forKeyCode: key.keyCode))
        }
    }

    func testSharesTheShelfKey() {
        XCTAssertTrue(DictationKey.space.sharesShelfKey(KeyCodes.space))
        XCTAssertFalse(DictationKey.d.sharesShelfKey(KeyCodes.space))
    }
}

final class MicOwnInputTests: XCTestCase {
    func testWispIsLeftOutOnlyWhileDictating() {
        let processes = ["com.ayomideodewale.wisp", "us.zoom.xos"]
        XCTAssertEqual(
            MicState.inputProcesses(processes, ownBundleID: "com.ayomideodewale.wisp", dictating: true),
            ["us.zoom.xos"])
        XCTAssertEqual(
            MicState.inputProcesses(processes, ownBundleID: "com.ayomideodewale.wisp", dictating: false), processes)
        XCTAssertNil(MicState.inputProcesses(nil, ownBundleID: "com.ayomideodewale.wisp", dictating: true))
        XCTAssertEqual(MicState.inputProcesses(processes, ownBundleID: nil, dictating: true), processes)
    }
}
