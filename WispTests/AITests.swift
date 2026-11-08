import XCTest

@testable import WispCore

final class AITaskTests: XCTestCase {
    func testEveryMenuTaskHasTitleAndInstructions() {
        for task in AITask.menu {
            XCTAssertFalse(task.title.isEmpty)
            XCTAssertFalse(task.instructions.isEmpty)
            XCTAssertGreaterThan(AIBudget.answerTokens(for: task), 0)
        }
        XCTAssertEqual(
            AITask.menu.map(\.title),
            [
                "Summarise", "Fix grammar", "Make friendlier", "Make more professional", "Make shorter",
                "Action items", "Explain",
            ])
    }

    func testTranslateNamesTheLanguage() {
        let task = AITask.translate(language: "French")
        XCTAssertEqual(task.title, "Translate to French")
        XCTAssertTrue(task.instructions.contains("French"))
        // A blank language falls back to English rather than an empty instruction.
        XCTAssertTrue(AITask.translate(language: "  ").instructions.contains("English"))
    }

    func testToneShapesTheRewrite() {
        XCTAssertTrue(AITask.rewrite(tone: .friendly).instructions.contains("friendly"))
        XCTAssertTrue(AITask.rewrite(tone: .professional).instructions.contains("professional"))
        XCTAssertNotEqual(
            AITask.rewrite(tone: .shorter).instructions, AITask.rewrite(tone: .friendly).instructions)
    }

    func testQuickInputCarriesTheDateAndAsksForJSON() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let zone = TimeZone(identifier: "Europe/Paris") ?? .current
        let task = AITask.quickInput(now: now, timeZone: zone)
        XCTAssertTrue(task.instructions.contains("JSON"))
        XCTAssertTrue(task.instructions.contains("2027-01-15T09:00:00+01:00"))
        XCTAssertTrue(task.instructions.contains("Europe/Paris"))
        XCTAssertTrue(task.instructions.contains("in the future"))
        XCTAssertEqual(task.temperature, 0)
    }

    func testTextTasksKeepTemperatureLow() {
        XCTAssertLessThanOrEqual(AITask.fixGrammar.temperature, 0.2)
        XCTAssertLessThanOrEqual(AITask.summarise.temperature, 0.5)
    }
}

final class AIBudgetTests: XCTestCase {
    func testEstimateIsConservative() {
        XCTAssertEqual(AIBudget.estimateTokens(""), 0)
        // Three ASCII characters count as a token, rounded up.
        XCTAssertEqual(AIBudget.estimateTokens("abc"), 1)
        XCTAssertEqual(AIBudget.estimateTokens("abcd"), 2)
        // Digits and punctuation split densely, so each counts as a token.
        XCTAssertEqual(AIBudget.estimateTokens("2026"), 4)
        XCTAssertEqual(AIBudget.estimateTokens("a.b"), 2)
        // Everything else counts a token per character (CJK, emoji, accented letters).
        XCTAssertEqual(AIBudget.estimateTokens("日本語"), 3)
        XCTAssertEqual(AIBudget.estimateTokens("ab日"), 2)
    }

    func testShortInputIsUntouched() {
        let prompt = AIBudget.prompt(for: .summarise, input: "  Hello there.  ")
        XCTAssertEqual(prompt.prompt, "Hello there.")
        XCTAssertFalse(prompt.truncated)
        XCTAssertEqual(prompt.instructions, AITask.summarise.instructions)
        XCTAssertEqual(prompt.maximumResponseTokens, AITask.summarise.answerTokens)
    }

    func testLongInputFitsTheWindowWithRoomForInstructionsAndOutput() {
        let line = "The build failed because the cache was stale and the linker could not find symbols.\n"
        let input = String(repeating: line, count: 2_000)
        let prompt = AIBudget.prompt(for: .summarise, input: input)
        XCTAssertTrue(prompt.truncated)
        let used =
            AIBudget.estimateTokens(prompt.instructions) + AIBudget.estimateTokens(prompt.prompt)
            + prompt.maximumResponseTokens + AIBudget.overheadTokens
        XCTAssertLessThanOrEqual(used, AIBudget.contextTokens)
        // Most of the room still goes to the input.
        XCTAssertGreaterThan(AIBudget.estimateTokens(prompt.prompt), 2_000)
    }

    func testTrimKeepsTheStartAndTheEnd() {
        let lines = (1...3_000).map { "line \($0) of the log" }
        let prompt = AIBudget.prompt(for: .explain, input: lines.joined(separator: "\n"))
        XCTAssertTrue(prompt.truncated)
        XCTAssertTrue(prompt.prompt.hasPrefix("line 1 of the log\n"))
        XCTAssertTrue(prompt.prompt.hasSuffix("line 3000 of the log"))
        XCTAssertTrue(prompt.prompt.contains(AIBudget.gapMarker))
        // Cuts land on line breaks, so no line is cut in half.
        let kept = prompt.prompt.components(separatedBy: "\n").filter { !$0.isEmpty && $0 != "[...]" }
        XCTAssertTrue(kept.allSatisfy { $0.hasPrefix("line ") && $0.hasSuffix(" of the log") })
    }

    func testTrimWithoutLineBreaksStillFits() {
        let input = String(repeating: "a", count: 50_000)
        let trimmed = AIBudget.trim(input, toTokens: 100)
        XCTAssertTrue(trimmed.truncated)
        XCTAssertLessThanOrEqual(AIBudget.estimateTokens(trimmed.text), 100)
    }

    func testTinyBudgetGivesNothingRatherThanOverflowing() {
        XCTAssertEqual(AIBudget.trim("hello world", toTokens: 0).text, "")
        XCTAssertEqual(AIBudget.inputTokens(for: .summarise, contextTokens: 100), 0)
    }

    func testLargerWindowAllowsMoreInput() {
        XCTAssertGreaterThan(
            AIBudget.inputTokens(for: .summarise, contextTokens: 8_192),
            AIBudget.inputTokens(for: .summarise, contextTokens: 4_096))
    }

    func testSameLengthTasksLeaveAsMuchRoomForTheAnswerAsTheInput() {
        let tasks: [AITask] = [
            .fixGrammar, .translate(language: "French"), .rewrite(tone: .friendly), .rewrite(tone: .professional),
            .rewrite(tone: .shorter),
        ]
        let line = "the build faild becuase the cache was stale and the linker could not find symbols\n"
        let input = String(repeating: line, count: 400)
        for task in tasks {
            XCTAssertLessThanOrEqual(
                AIBudget.inputTokens(for: task), AIBudget.answerTokens(for: task), task.title)
            let prompt = AIBudget.prompt(for: task, input: input)
            XCTAssertTrue(prompt.truncated, task.title)
            XCTAssertLessThanOrEqual(
                AIBudget.estimateTokens(prompt.prompt), prompt.maximumResponseTokens, task.title)
            let used =
                AIBudget.estimateTokens(prompt.instructions) + AIBudget.estimateTokens(prompt.prompt)
                + prompt.maximumResponseTokens + AIBudget.overheadTokens
            XCTAssertLessThanOrEqual(used, AIBudget.contextTokens, task.title)
        }
    }

    func testShortSameLengthInputGetsTheRestOfTheWindowForItsAnswer() {
        let prompt = AIBudget.prompt(for: .fixGrammar, input: "i has a cat")
        XCTAssertFalse(prompt.truncated)
        XCTAssertGreaterThanOrEqual(prompt.maximumResponseTokens, AIBudget.answerTokens(for: .fixGrammar))
        let used =
            AIBudget.estimateTokens(prompt.instructions) + AIBudget.estimateTokens(prompt.prompt)
            + prompt.maximumResponseTokens + AIBudget.overheadTokens
        XCTAssertLessThanOrEqual(used, AIBudget.contextTokens)
    }

    func testAnswerAtTheLimitCountsAsCutOff() {
        let prompt = AIBudget.prompt(for: .summarise, input: "Hello")
        XCTAssertTrue(prompt.isCutOff(outputTokens: prompt.maximumResponseTokens))
        XCTAssertFalse(prompt.isCutOff(outputTokens: prompt.maximumResponseTokens - 1))
    }

    func testRefitLeavesAPromptThatFits() {
        let prompt = AIBudget.prompt(for: .summarise, input: "Hello")
        let count = AITokenCount(instructions: 70, input: 3)
        XCTAssertEqual(
            AIBudget.refit(prompt, task: .summarise, input: "Hello", contextTokens: 4_096, count: count), prompt)
    }

    func testRefitTrimsInputTheEstimateLetThroughWhole() throws {
        // Dense text the estimate undercounted: not trimmed at first, but the model counts too many.
        let input = String(repeating: "0x7aef3d7000 ", count: 200)
        let prompt = AIBudget.prompt(for: .summarise, input: input)
        XCTAssertFalse(prompt.truncated)
        let allowed = AIBudget.contextTokens - prompt.maximumResponseTokens - AIBudget.overheadTokens
        let count = AITokenCount(instructions: 80, input: allowed)
        let next = try XCTUnwrap(
            AIBudget.refit(prompt, task: .summarise, input: input, contextTokens: 4_096, count: count))
        XCTAssertTrue(next.truncated)
        XCTAssertLessThan(next.prompt.count, prompt.prompt.count)
        XCTAssertEqual(next.maximumResponseTokens, prompt.maximumResponseTokens)
        // The model's count, scaled to the shorter input, now fits beside the instructions.
        let scaled = Double(count.input) * Double(next.prompt.count) / Double(prompt.prompt.count)
        XCTAssertLessThanOrEqual(Double(count.instructions) + scaled, Double(allowed))
    }

    func testRefitGivesUpWhenNothingCanFit() {
        let prompt = AIBudget.prompt(for: .summarise, input: "Hello there")
        let instructionsAlone = AITokenCount(instructions: 4_000, input: 5)
        XCTAssertNil(
            AIBudget.refit(
                prompt, task: .summarise, input: "Hello there", contextTokens: 4_096, count: instructionsAlone))
    }

    /// The model counting `extra` tokens more than estimated for `prompt`.
    private func undercount(_ prompt: AIPrompt, by extra: Int) -> AITokenCount {
        AITokenCount(
            instructions: AIBudget.estimateTokens(prompt.instructions) + extra,
            input: AIBudget.estimateTokens(prompt.prompt))
    }

    func testSameLengthRefitGivesUpAnswerRoomBeforeInput() throws {
        let input = "I has a apple and it are red."
        let prompt = AIBudget.prompt(for: .fixGrammar, input: input)
        let next = try XCTUnwrap(
            AIBudget.refit(
                prompt, task: .fixGrammar, input: input, contextTokens: 4_096, count: undercount(prompt, by: 25)))
        XCTAssertEqual(next.prompt, prompt.prompt)
        XCTAssertFalse(next.truncated)
        XCTAssertEqual(next.maximumResponseTokens, prompt.maximumResponseTokens - 25)
        XCTAssertGreaterThanOrEqual(next.maximumResponseTokens, AIBudget.answerTokens(for: .fixGrammar))
    }

    func testSameLengthRefitFitsAMediumInputByLoweringTheAnswerRoomAlone() throws {
        let input = String(repeating: "the cache was stale so the linker faild to find symbols\n", count: 50)
        let prompt = AIBudget.prompt(for: .translate(language: "French"), input: input)
        XCTAssertFalse(prompt.truncated)
        let next = try XCTUnwrap(
            AIBudget.refit(
                prompt, task: .translate(language: "French"), input: input, contextTokens: 4_096,
                count: undercount(prompt, by: 300)))
        XCTAssertEqual(next.prompt, prompt.prompt)
        XCTAssertEqual(next.maximumResponseTokens, prompt.maximumResponseTokens - 300)
        let used = undercount(prompt, by: 300)
        XCTAssertLessThanOrEqual(
            used.instructions + used.input + next.maximumResponseTokens + AIBudget.overheadTokens, 4_096)
    }

    func testSameLengthRefitTrimsOnlyOnceTheAnswerRoomIsAtItsFloor() throws {
        let input = String(repeating: "the cache was stale so the linker faild to find symbols\n", count: 400)
        let prompt = AIBudget.prompt(for: .fixGrammar, input: input)
        XCTAssertTrue(prompt.truncated)
        let next = try XCTUnwrap(
            AIBudget.refit(
                prompt, task: .fixGrammar, input: input, contextTokens: 4_096, count: undercount(prompt, by: 400)))
        XCTAssertLessThan(next.prompt.count, prompt.prompt.count)
        XCTAssertEqual(next.maximumResponseTokens, AIBudget.answerTokens(for: .fixGrammar))
        XCTAssertLessThanOrEqual(AIBudget.estimateTokens(next.prompt), next.maximumResponseTokens)
    }

    func testShrinkScalesDownByTheMeasuredOverrun() {
        // The model counted 25% more than allowed, so the limit drops by a bit more than that.
        let next = AIBudget.shrink(limit: 3_000, measured: 4_000, allowed: 3_200)
        XCTAssertLessThan(next, 2_400)
        XCTAssertGreaterThan(next, 2_000)
        XCTAssertEqual(AIBudget.shrink(limit: 3_000, measured: 3_000, allowed: 3_200), 3_000)
        XCTAssertEqual(AIBudget.shrink(limit: 3_000, measured: 0, allowed: 0), 0)
    }
}

final class AIOutputTests: XCTestCase {
    func testTrimsAndDropsThinking() {
        let raw = "<think>\nThe user wants a summary.\n</think>\n\n  The build is green.  \n"
        XCTAssertEqual(AIOutput.clean(raw, for: .summarise, input: ""), "The build is green.")
    }

    func testDropsAPreambleLine() {
        XCTAssertEqual(
            AIOutput.clean("Here is the corrected text:\n\nI went to the shop.", for: .fixGrammar, input: ""),
            "I went to the shop.")
        XCTAssertEqual(AIOutput.clean("Sure! Here's a summary:\nIt works.", for: .summarise, input: ""), "It works.")
        // A real first line that ends with a colon stays.
        XCTAssertEqual(
            AIOutput.clean("Steps to reproduce:\n1. Open it", for: .explain, input: ""),
            "Steps to reproduce:\n1. Open it")
    }

    func testUnwrapsFencesAndQuotesForPlainTextTasks() {
        XCTAssertEqual(AIOutput.clean("```\nBonjour\n```", for: .translate(language: "French"), input: ""), "Bonjour")
        XCTAssertEqual(AIOutput.clean("\"I went to the shop.\"", for: .fixGrammar, input: ""), "I went to the shop.")
        XCTAssertEqual(AIOutput.clean("“Hi there.”", for: .rewrite(tone: .friendly), input: ""), "Hi there.")
        // Explanations keep their code blocks.
        let explained = "It means:\n```swift\nlet x = 1\n```"
        XCTAssertEqual(AIOutput.clean(explained, for: .explain, input: ""), explained)
    }

    func testKeepsTheUsersOwnPreambleLikeFirstLine() {
        let input = "here is my plan:\nship it monday"
        XCTAssertEqual(
            AIOutput.clean("Here is my plan:\nShip it Monday.", for: .fixGrammar, input: input),
            "Here is my plan:\nShip it Monday.")
        // A model's own lead-in is still dropped when the input didn't start with one.
        XCTAssertEqual(
            AIOutput.clean("Here is the corrected text:\nShip it Monday.", for: .fixGrammar, input: "ship it monday"),
            "Ship it Monday.")
    }

    func testKeepsTheUsersOwnFenceAndQuotes() {
        let fenced = "```\nlet x = 1\n```"
        XCTAssertEqual(AIOutput.clean(fenced, for: .fixGrammar, input: "```\nlet x = 1\n```"), fenced)
        XCTAssertEqual(
            AIOutput.clean("\"Hi,\" she said.", for: .fixGrammar, input: "\"hi,\" she said"), "\"Hi,\" she said.")
        XCTAssertEqual(
            AIOutput.clean(
                "\u{201C}Ship it.\u{201D}", for: .rewrite(tone: .shorter), input: "\u{201C}Ship it now please.\u{201D}"),
            "\u{201C}Ship it.\u{201D}")
        XCTAssertEqual(
            AIOutput.clean("\"I went to the shop.\"", for: .fixGrammar, input: "i goed to the shop"),
            "I went to the shop.")
    }

    func testKeepsThinkTagsTheUserWrote() {
        let input = "Explain <think> tags in prompts"
        XCTAssertEqual(
            AIOutput.clean("Use <think>...</think> to mark reasoning.", for: .summarise, input: input),
            "Use <think>...</think> to mark reasoning.")
    }

    func testActionItemsBecomeDashBullets() {
        let raw = "* Ship the build\n• Email Sam\n1. Book the room\n2) Pay the bill\n\n- Already fine"
        XCTAssertEqual(
            AIOutput.clean(raw, for: .actionItems, input: ""),
            "- Ship the build\n- Email Sam\n- Book the room\n- Pay the bill\n- Already fine")
    }

    func testCollapsesBlankRunsAndLineEndings() {
        XCTAssertEqual(AIOutput.clean("One\r\n\r\n\r\n\r\nTwo", for: .summarise, input: ""), "One\n\nTwo")
    }

    func testCutOffAnswerIsRefusedOnlyWhereItWouldReplaceText() throws {
        let cut = AIReply(text: "Je suis all", cutOff: true)
        for task: AITask in [.fixGrammar, .translate(language: "French"), .rewrite(tone: .shorter)] {
            let prompt = AIBudget.prompt(for: task, input: "I am going")
            XCTAssertThrowsError(try AIOutput.answer(cut, for: task, prompt: prompt), task.title)
        }
        // Half a JSON object can't be read, so quick input refuses it too.
        let now = Date(timeIntervalSince1970: 0)
        let quick = AITask.quickInput(now: now, timeZone: .current)
        XCTAssertThrowsError(
            try AIOutput.answer(
                AIReply(text: "{\"kind\": \"tim", cutOff: true), for: quick,
                prompt: AIBudget.prompt(for: quick, input: "25 min")))
        for task: AITask in [.summarise, .explain, .actionItems, .sessionSummary] {
            let prompt = AIBudget.prompt(for: task, input: "Some text")
            let answer = try AIOutput.answer(AIReply(text: "The build", cutOff: true), for: task, prompt: prompt)
            XCTAssertTrue(answer.truncated, task.title)
            XCTAssertFalse(answer.text.isEmpty)
        }
    }

    func testWholeAnswerKeepsTheInputsTruncation() throws {
        let short = AIBudget.prompt(for: .fixGrammar, input: "i has a cat")
        let answer = try AIOutput.answer(AIReply(text: "I have a cat.", cutOff: false), for: .fixGrammar, prompt: short)
        XCTAssertEqual(answer, AIAnswer(text: "I have a cat.", truncated: false))
        var long = short
        long.truncated = true
        XCTAssertTrue(try AIOutput.answer(AIReply(text: "x", cutOff: false), for: .summarise, prompt: long).truncated)
    }

    func testQuickInputKeepsOnlyTheJSONObject() {
        let raw = "Here you go:\n```json\n{\"kind\": \"timer\", \"minutes\": 25}\n```"
        XCTAssertEqual(
            AIOutput.clean(raw, for: .quickInput(now: .now, timeZone: .current), input: ""),
            "{\"kind\": \"timer\", \"minutes\": 25}")
    }
}

final class AIAvailabilityTests: XCTestCase {
    func testStatusLines() {
        XCTAssertEqual(AIAvailability.appleIntelligenceOff.message, "Apple Intelligence is off")
        XCTAssertEqual(AIAvailability.ollamaNotRunning.message, "Ollama isn't running")
        XCTAssertEqual(AIAvailability.ready(model: "llama3.2:3b").message, "Ready with llama3.2:3b")
        XCTAssertEqual(AIAvailability.ready(model: nil).message, "Ready")
        XCTAssertTrue(AIAvailability.ready(model: nil).isReady)
        XCTAssertFalse(AIAvailability.modelNotReady.isReady)
        for status in [AIAvailability.deviceNotEligible, .needsNewerMacOS, .ollamaNoModels, .notLocal, .off] {
            XCTAssertFalse(status.message.isEmpty)
        }
        XCTAssertEqual(AIError.cutOff.message, "The answer was too long and got cut off")
    }
}

final class OllamaTests: XCTestCase {
    func testOnlyThisMacIsAllowed() {
        for text in [
            "http://127.0.0.1:11434", "http://localhost:11434", "http://[::1]:11434", "localhost:11434",
            "http://127.0.0.1:11434/", " http://LOCALHOST:8080 ",
        ] {
            XCTAssertNotNil(OllamaEndpoint.base(text), text)
        }
        for text in [
            "http://192.168.1.10:11434", "https://ollama.example.com", "http://localhost.evil.com",
            "http://127.0.0.1.nip.io", "http://user@localhost:11434", "ftp://localhost", "file:///tmp",
            "http://localhost:11434/api?x=1", "",
        ] {
            XCTAssertNil(OllamaEndpoint.base(text), text)
        }
    }

    func testDefaultAddressAndPaths() throws {
        let base = try XCTUnwrap(OllamaEndpoint.base(OllamaEndpoint.defaultAddress))
        XCTAssertEqual(OllamaEndpoint.chatURL(base).absoluteString, "http://127.0.0.1:11434/api/chat")
        XCTAssertEqual(OllamaEndpoint.tagsURL(base).absoluteString, "http://127.0.0.1:11434/api/tags")
        XCTAssertTrue(OllamaEndpoint.isLocal(OllamaEndpoint.chatURL(base)))
        XCTAssertFalse(OllamaEndpoint.isLocal(try XCTUnwrap(URL(string: "http://10.0.0.2:11434/api/chat"))))
    }

    func testChatRequestEncoding() throws {
        let prompt = AIPrompt(
            instructions: "Fix the grammar.", prompt: "i has a cat", maximumResponseTokens: 300, temperature: 0.1,
            truncated: false)
        let data = try OllamaChat.body(model: "llama3.2:3b", prompt: prompt)
        let object = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(object["model"], .string("llama3.2:3b"))
        XCTAssertEqual(object["stream"], .bool(false))
        XCTAssertEqual(
            object["messages"],
            .array([
                .object(["role": .string("system"), "content": .string("Fix the grammar.")]),
                .object(["role": .string("user"), "content": .string("i has a cat")]),
            ]))
        XCTAssertEqual(object["options"]?["num_predict"]?.intValue, 300)
        XCTAssertEqual(object["options"]?["num_ctx"]?.intValue, AIBudget.contextTokens)
        XCTAssertEqual(object["options"]?["temperature"]?.doubleValue, 0.1)
    }

    /// Shape from the Ollama API docs (`docs/api.md`, "Chat request (no streaming)").
    func testChatResponseDecoding() throws {
        let json = """
            {"model":"llama3.2","created_at":"2023-12-12T14:13:43.416799Z",
             "message":{"role":"assistant","content":"Hello! How are you today?"},
             "done":true,"done_reason":"stop","total_duration":5191566416,"load_duration":2154458,
             "prompt_eval_count":26,"prompt_eval_duration":383809000,"eval_count":298,"eval_duration":4799921000}
            """
        XCTAssertEqual(
            OllamaChat.content(from: Data(json.utf8)),
            .success(AIReply(text: "Hello! How are you today?", cutOff: false)))
    }

    func testAnswerStoppedAtTheTokenLimitIsCutOff() {
        let json = """
            {"model":"llama3.2","message":{"role":"assistant","content":"Je suis all"},"done":true,
             "done_reason":"length","eval_count":300}
            """
        XCTAssertEqual(OllamaChat.content(from: Data(json.utf8)), .success(AIReply(text: "Je suis all", cutOff: true)))
    }

    func testThinkingModelsAnswerInContent() throws {
        let json = """
            {"model":"qwen3","message":{"role":"assistant","content":"Done.","thinking":"Let me see."},"done":true}
            """
        XCTAssertEqual(OllamaChat.content(from: Data(json.utf8)), .success(AIReply(text: "Done.", cutOff: false)))
    }

    func testErrorBodyIsReported() {
        let json = #"{"error":"model 'nope' not found"}"#
        XCTAssertEqual(OllamaChat.content(from: Data(json.utf8)), .failure(.server("model 'nope' not found")))
        XCTAssertEqual(OllamaChat.content(from: Data("not json".utf8)), .failure(.unreadable))
        XCTAssertEqual(OllamaChat.content(from: Data(#"{"message":{"role":"assistant"}}"#.utf8)), .failure(.unreadable))
    }

    /// Shape from the Ollama API docs (`docs/api.md`, "List Local Models").
    func testModelListParsing() throws {
        let json = """
            {"models":[
              {"name":"llama3.2:3b","model":"llama3.2:3b","modified_at":"2025-05-04T17:37:44.706015396-07:00",
               "size":2019393189,"digest":"a80c4f17acd55265feec403c7aef86be0c25983ab279d83f3bcd3abbcb5b8b72",
               "details":{"parent_model":"","format":"gguf","family":"llama","families":["llama"],
                          "parameter_size":"3.2B","quantization_level":"Q4_K_M"}},
              {"name":"deepseek-r1:latest","model":"deepseek-r1:latest","modified_at":"2025-05-10T08:06:48.639712648-07:00",
               "size":4683075271,"digest":"0a8c266910232fd3291e71e5ba1e058cc5af9d411192cf88b6d30e92b6e73163",
               "details":{"parent_model":"","format":"gguf","family":"qwen2","families":["qwen2"],
                          "parameter_size":"7.6B","quantization_level":"Q4_K_M"}},
              {"name":"nomic-embed-text:latest","model":"nomic-embed-text:latest","size":274302450,
               "details":{"family":"nomic-bert","families":["nomic-bert"],"parameter_size":"137M"}}
            ]}
            """
        let models = try OllamaTags.models(from: Data(json.utf8))
        // Sorted by name; embedding-only models can't chat, so they're left out.
        XCTAssertEqual(models.map(\.name), ["deepseek-r1:latest", "llama3.2:3b"])
        XCTAssertEqual(models.last?.detail, "3.2B")
        XCTAssertEqual(try OllamaTags.models(from: Data(#"{"models":[]}"#.utf8)), [])
    }

    func testModelChoiceKeepsTheSavedOneOrPicksTheFirst() {
        let models = [OllamaModel(name: "a:1", detail: nil), OllamaModel(name: "b:2", detail: nil)]
        XCTAssertEqual(OllamaTags.choose(saved: "b:2", from: models), "b:2")
        XCTAssertEqual(OllamaTags.choose(saved: "", from: models), "a:1")
        XCTAssertNil(OllamaTags.choose(saved: "", from: []))
        // A saved model that's gone is kept, so the status can say it's missing.
        XCTAssertEqual(OllamaTags.choose(saved: "gone:1", from: models), "gone:1")
    }

    func testModelNamesWithoutATagMeanLatest() {
        let models = [OllamaModel(name: "llama3.2:latest", detail: nil), OllamaModel(name: "qwen3:8b", detail: nil)]
        XCTAssertTrue(OllamaTags.has("llama3.2", in: models))
        XCTAssertTrue(OllamaTags.has("llama3.2:latest", in: models))
        XCTAssertTrue(OllamaTags.has("qwen3:8b", in: models))
        XCTAssertFalse(OllamaTags.has("qwen3", in: models))
        XCTAssertFalse(OllamaTags.has("mistral", in: models))
    }
}
