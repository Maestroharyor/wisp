import XCTest

@testable import WispCore

// Fixtures, with where each shape comes from (checked 2026-11-07):
// - Codex: `codex cloud list --json` in openai/codex `codex-rs/cloud-tasks/src/lib.rs`
//   (`run_list_command`), statuses from `cloud-tasks-client/src/api.rs` (`TaskStatus`, kebab-case).
//   Codex wasn't installed here, so this is built from the source, not a recorded run.
// - Copilot: `gh agent-task list --json` (gh 2.100.0 `--help` lists the fields; values from
//   cli/cli `pkg/cmd/agent-task/capi/sessions.go` `ExportData` and `shared/display.go` states).
// - Cursor: the examples on cursor.com/docs/cloud-agent/api/endpoints (List Agents, Get A Run).
// - Checks: `gh pr checks --json bucket,name,state,link` (gh 2.100.0 `--help`: bucket is pass,
//   fail, pending, skipping or cancel).

final class CloudParseTests: XCTestCase {
    static let codexList = """
        {
          "tasks": [
            {
              "id": "task_e_1",
              "url": "https://chatgpt.com/codex/tasks/task_e_1",
              "title": "Fix the flaky login test",
              "status": "pending",
              "updated_at": "2026-11-07T10:00:00.123456Z",
              "environment_id": "env_1",
              "environment_label": "acme/web",
              "summary": { "files_changed": 0, "lines_added": 0, "lines_removed": 0 },
              "is_review": false,
              "attempt_total": 1
            },
            {
              "id": "task_e_2",
              "url": "https://chatgpt.com/codex/tasks/task_e_2",
              "title": "Add a README",
              "status": "ready",
              "updated_at": "2026-11-07T09:00:00Z",
              "environment_id": null,
              "environment_label": null,
              "summary": { "files_changed": 1, "lines_added": 40, "lines_removed": 2 },
              "is_review": false,
              "attempt_total": 2
            },
            { "id": "task_e_3", "url": "https://chatgpt.com/codex/tasks/task_e_3", "title": "Bump deps",
              "status": "error", "updated_at": "2026-11-07T08:00:00Z", "summary": {} },
            { "id": "task_e_4", "url": "https://chatgpt.com/codex/tasks/task_e_4", "title": "Done already",
              "status": "applied", "updated_at": "2026-11-07T07:00:00Z", "summary": {} }
          ],
          "cursor": null
        }
        """

    static let copilotList = """
        [
          {
            "completedAt": null,
            "createdAt": "2026-11-07T09:58:00Z",
            "id": "e2fa49d2-f164-4a56-ab99-498090b8fcdf",
            "name": "Improve the data pipeline",
            "pullRequestNumber": 123,
            "pullRequestState": "OPEN",
            "pullRequestTitle": "[WIP] Improve the data pipeline",
            "pullRequestUrl": "https://github.com/acme/web/pull/123",
            "repository": "acme/web",
            "state": "in_progress",
            "updatedAt": "2026-11-07T10:01:02.123456789+01:00",
            "user": "octocat"
          },
          {
            "completedAt": "2026-11-06T12:00:00Z",
            "createdAt": "2026-11-06T11:00:00Z",
            "id": "s2",
            "name": "",
            "pullRequestNumber": 7,
            "pullRequestState": "MERGED",
            "pullRequestTitle": "Fix typo",
            "pullRequestUrl": "https://github.com/acme/docs/pull/7",
            "repository": "acme/docs",
            "state": "completed",
            "updatedAt": "2026-11-06T12:00:00Z",
            "user": "octocat"
          },
          { "id": "s3", "name": "Waits", "state": "waiting_for_user", "updatedAt": "2026-11-06T12:00:00Z",
            "repository": null, "pullRequestUrl": null },
          { "id": "s4", "name": "Slow", "state": "timed_out", "updatedAt": "2026-11-06T12:00:00Z" },
          { "id": "s5", "name": "Stopped", "state": "cancelled", "updatedAt": "2026-11-06T12:00:00Z" },
          { "id": "s6", "name": "Queued", "state": "queued", "updatedAt": "2026-11-06T12:00:00Z" }
        ]
        """

    static let cursorAgents = """
        {
          "items": [
            {
              "id": "bc-00000000-0000-0000-0000-000000000001",
              "name": "Add README with setup instructions",
              "status": "ACTIVE",
              "env": { "type": "cloud" },
              "url": "https://cursor.com/agents/bc-00000000-0000-0000-0000-000000000001",
              "createdAt": "2026-04-13T18:30:00.000Z",
              "updatedAt": "2026-04-13T18:45:00.000Z",
              "latestRunId": "run-00000000-0000-0000-0000-000000000001"
            },
            {
              "id": "bc-2", "name": "Old one", "status": "ARCHIVED",
              "url": "https://cursor.com/agents/bc-2", "createdAt": "2026-04-01T00:00:00.000Z",
              "updatedAt": "2026-04-01T00:00:00.000Z"
            },
            {
              "id": "bc-3", "name": "Idle one", "status": "IDLE",
              "url": "https://cursor.com/agents/bc-3", "createdAt": "2026-04-02T00:00:00.000Z",
              "updatedAt": "2026-04-02T00:00:00.000Z", "latestRunId": "run-3"
            }
          ],
          "nextCursor": "bc-00000000-0000-0000-0000-000000000002"
        }
        """

    static let cursorRun = """
        {
          "id": "run-00000000-0000-0000-0000-000000000001",
          "agentId": "bc-00000000-0000-0000-0000-000000000001",
          "status": "FINISHED",
          "createdAt": "2026-04-13T18:30:00.000Z",
          "updatedAt": "2026-04-13T18:45:00.000Z",
          "durationMs": 12357,
          "result": "Added README.md with installation instructions and usage examples.",
          "git": {
            "branches": [
              {
                "repoUrl": "github.com/your-org/your-repo",
                "branch": "cursor/add-readme-a1b2",
                "prUrl": "https://github.com/your-org/your-repo/pull/123"
              }
            ]
          }
        }
        """

    static let checks = """
        [
          { "bucket": "pass", "name": "test", "state": "SUCCESS", "link": "https://github.com/a/b/runs/1" },
          { "bucket": "fail", "name": "lint", "state": "FAILURE", "link": "https://github.com/a/b/runs/2" },
          { "bucket": "pending", "name": "build", "state": "IN_PROGRESS", "link": "" },
          { "bucket": "skipping", "name": "deploy", "state": "SKIPPED", "link": "" }
        ]
        """

    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testCodexListMapsEveryStatus() throws {
        let tasks = try CloudParse.codex(data(Self.codexList))
        XCTAssertEqual(tasks.map(\.status), [.running, .ready, .failed, .ready])
        let first = try XCTUnwrap(tasks.first)
        XCTAssertEqual(first.source, .codex)
        XCTAssertEqual(first.taskID, "task_e_1")
        XCTAssertEqual(first.id, "codex:task_e_1")
        XCTAssertEqual(first.title, "Fix the flaky login test")
        XCTAssertEqual(first.url?.absoluteString, "https://chatgpt.com/codex/tasks/task_e_1")
        XCTAssertEqual(first.repository, "acme/web")
        XCTAssertNil(first.pullRequest)
        XCTAssertEqual(first.updatedAt.timeIntervalSince1970, 1_794_045_600, accuracy: 1)
        XCTAssertNil(tasks[1].repository)
        XCTAssertTrue(tasks[1].canApply)
        XCTAssertFalse(tasks[0].canApply)
        XCTAssertFalse(tasks[2].canApply)
    }

    func testCodexRejectsSomethingElse() {
        XCTAssertThrowsError(try CloudParse.codex(data("No tasks found.")))
        XCTAssertThrowsError(try CloudParse.codex(data("[]")))
    }

    func testCopilotListMapsStatesAndPullRequests() throws {
        let tasks = try CloudParse.copilot(data(Self.copilotList))
        XCTAssertEqual(tasks.map(\.status), [.running, .ready, .waiting, .failed, .cancelled, .queued])
        let first = try XCTUnwrap(tasks.first)
        XCTAssertEqual(first.source, .copilot)
        XCTAssertEqual(first.title, "Improve the data pipeline")
        XCTAssertEqual(first.repository, "acme/web")
        XCTAssertEqual(first.pullRequest?.absoluteString, "https://github.com/acme/web/pull/123")
        XCTAssertEqual(first.url, first.pullRequest)
        XCTAssertTrue(first.pullRequestOpen)
        // 10:01:02 at +01:00 is 09:01:02 UTC.
        XCTAssertEqual(first.updatedAt.timeIntervalSince1970, 1_794_042_062, accuracy: 1)
        // An empty name falls back to the pull request's title.
        XCTAssertEqual(tasks[1].title, "Fix typo")
        XCTAssertFalse(tasks[1].pullRequestOpen)
        XCTAssertNil(tasks[2].pullRequest)
        XCTAssertFalse(tasks[0].canApply)
    }

    func testCursorAgentsSkipArchived() throws {
        let agents = try CloudParse.cursorAgents(data(Self.cursorAgents))
        XCTAssertEqual(agents.map(\.id), ["bc-00000000-0000-0000-0000-000000000001", "bc-3"])
        XCTAssertEqual(agents.first?.latestRunID, "run-00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(
            agents.first?.url?.absoluteString, "https://cursor.com/agents/bc-00000000-0000-0000-0000-000000000001")
    }

    func testCursorRunGivesStatusAndPullRequest() throws {
        let run = try CloudParse.cursorRun(data(Self.cursorRun))
        XCTAssertEqual(run.status, .ready)
        XCTAssertEqual(run.pullRequest?.absoluteString, "https://github.com/your-org/your-repo/pull/123")
        XCTAssertEqual(run.repository, "your-org/your-repo")
    }

    func testCursorRunStatuses() {
        XCTAssertEqual(CloudParse.cursorRunStatus("CREATING"), .queued)
        XCTAssertEqual(CloudParse.cursorRunStatus("RUNNING"), .running)
        XCTAssertEqual(CloudParse.cursorRunStatus("WAITING_FOR_BACKGROUND_WORK"), .running)
        XCTAssertEqual(CloudParse.cursorRunStatus("FINISHED"), .ready)
        XCTAssertEqual(CloudParse.cursorRunStatus("ERROR"), .failed)
        XCTAssertEqual(CloudParse.cursorRunStatus("EXPIRED"), .failed)
        XCTAssertEqual(CloudParse.cursorRunStatus("CANCELLED"), .cancelled)
        XCTAssertNil(CloudParse.cursorRunStatus("SOMETHING_NEW"))
    }

    func testCursorTaskUsesTheRunWhenThereIsOne() throws {
        let agents = try CloudParse.cursorAgents(data(Self.cursorAgents))
        let run = try CloudParse.cursorRun(data(Self.cursorRun))
        let withRun = CloudParse.cursorTask(agents[0], run: run)
        XCTAssertEqual(withRun.status, .ready)
        XCTAssertEqual(withRun.pullRequest, run.pullRequest)
        XCTAssertEqual(withRun.repository, "your-org/your-repo")
        XCTAssertEqual(withRun.id, "cursor:bc-00000000-0000-0000-0000-000000000001")
        // Without a run, the agent's own status is all there is.
        XCTAssertEqual(CloudParse.cursorTask(agents[0], run: nil).status, .running)
        XCTAssertEqual(CloudParse.cursorTask(agents[1], run: nil).status, .ready)
        XCTAssertTrue(withRun.statusKnown)
        XCTAssertFalse(CloudParse.cursorTask(agents[0], run: nil).statusKnown)
    }

    func testLinksOnlyToTheExpectedHosts() {
        XCTAssertNotNil(CloudParse.link("https://chatgpt.com/codex/tasks/t", hosts: CloudParse.codexHosts))
        XCTAssertNotNil(CloudParse.link("https://github.com/a/b/pull/1", hosts: CloudParse.githubHosts))
        XCTAssertNotNil(CloudParse.link("https://www.cursor.com/agents/x", hosts: CloudParse.cursorHosts))
        XCTAssertNil(CloudParse.link("http://chatgpt.com/codex/tasks/t", hosts: CloudParse.codexHosts))
        XCTAssertNil(CloudParse.link("file:///Applications/Calculator.app", hosts: CloudParse.codexHosts))
        XCTAssertNil(CloudParse.link("https://chatgpt.com.evil.example/x", hosts: CloudParse.codexHosts))
        XCTAssertNil(CloudParse.link("https://evilchatgpt.com/x", hosts: CloudParse.codexHosts))
        XCTAssertNil(CloudParse.link("https://github.com/a/b/pull/1", hosts: CloudParse.cursorHosts))
        XCTAssertNil(CloudParse.link("https://user@github.com/a/b/pull/1", hosts: CloudParse.githubHosts))
    }

    func testRemoteLinksAreChecked() throws {
        let codex = #"{"tasks":[{"id":"t","url":"file:///etc/passwd","title":"x","status":"ready"}]}"#
        XCTAssertNil(try CloudParse.codex(data(codex)).first?.url)
        let copilot = #"[{"id":"s","state":"completed","pullRequestUrl":"https://example.com/pull/1"}]"#
        XCTAssertNil(try CloudParse.copilot(data(copilot)).first?.pullRequest)
        let cursor = #"{"items":[{"id":"bc","status":"IDLE","url":"javascript:alert(1)"}]}"#
        XCTAssertNil(try CloudParse.cursorAgents(data(cursor)).first?.url)
        let run =
            #"{"id":"r","status":"FINISHED","git":{"branches":[{"prUrl":"https://gitlab.com/a/b/-/merge_requests/1"}]}}"#
        XCTAssertNil(try CloudParse.cursorRun(data(run)).pullRequest)
    }

    func testChecksSummary() throws {
        let checks = try XCTUnwrap(CloudParse.checks(data(Self.checks)))
        XCTAssertEqual(checks.passed, 2)
        XCTAssertEqual(checks.failed, 1)
        XCTAssertEqual(checks.pending, 1)
        XCTAssertEqual(checks.state, .failing)
        XCTAssertNil(CloudParse.checks(data("[]")))
        XCTAssertNil(CloudParse.checks(data("no checks reported on the 'x' branch")))
        let green = try XCTUnwrap(CloudParse.checks(data(#"[{"bucket":"pass"},{"bucket":"skipping"}]"#)))
        XCTAssertEqual(green.state, .passing)
        let waiting = try XCTUnwrap(CloudParse.checks(data(#"[{"bucket":"pass"},{"bucket":"pending"}]"#)))
        XCTAssertEqual(waiting.state, .pending)
        let cancelled = try XCTUnwrap(CloudParse.checks(data(#"[{"bucket":"cancel"}]"#)))
        XCTAssertEqual(cancelled.state, .failing)
    }

    func testDatesWithAndWithoutFractions() {
        XCTAssertEqual(CloudParse.date("2026-04-13T18:30:00.000Z"), Date(timeIntervalSince1970: 1_776_105_000))
        XCTAssertEqual(CloudParse.date("2026-04-13T18:30:00Z"), Date(timeIntervalSince1970: 1_776_105_000))
        XCTAssertEqual(
            CloudParse.date("2026-04-13T19:30:00.123456789+01:00"), Date(timeIntervalSince1970: 1_776_105_000))
        XCTAssertNil(CloudParse.date("yesterday"))
    }

    func testGitHubPullRequestsOnly() {
        XCTAssertTrue(CloudParse.isGitHubPullRequest(URL(string: "https://github.com/a/b/pull/1")))
        XCTAssertFalse(CloudParse.isGitHubPullRequest(URL(string: "https://gitlab.com/a/b/-/merge_requests/1")))
        XCTAssertFalse(CloudParse.isGitHubPullRequest(URL(string: "https://github.com/a/b/issues/1")))
        XCTAssertFalse(CloudParse.isGitHubPullRequest(nil))
    }
}

final class CloudPollScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func task(_ status: CloudStatus, checks: CloudChecks? = nil) -> CloudTask {
        CloudTask(
            source: .codex, taskID: UUID().uuidString, title: "t", status: status, url: nil, pullRequest: nil,
            repository: nil, updatedAt: now, checks: checks)
    }

    func testFastWhileATaskRuns() {
        var schedule = CloudPollSchedule()
        XCTAssertEqual(schedule.next(tasks: [task(.running), task(.ready)], now: now), .seconds(120))
        XCTAssertEqual(schedule.next(tasks: [task(.queued)], now: now), .seconds(120))
    }

    func testFastWhileChecksArePending() {
        var schedule = CloudPollSchedule()
        let pending = CloudChecks(passed: 1, failed: 0, pending: 1)
        XCTAssertEqual(schedule.next(tasks: [task(.ready, checks: pending)], now: now), .seconds(120))
    }

    func testSlowForAWhileAfterThenStops() {
        var schedule = CloudPollSchedule()
        _ = schedule.next(tasks: [task(.running)], now: now)
        XCTAssertEqual(schedule.next(tasks: [task(.ready)], now: now.addingTimeInterval(60)), .seconds(900))
        XCTAssertEqual(
            schedule.next(tasks: [task(.ready)], now: now.addingTimeInterval(CloudPollSchedule.idleWindow - 1)),
            .seconds(900))
        XCTAssertNil(schedule.next(tasks: [task(.ready)], now: now.addingTimeInterval(CloudPollSchedule.idleWindow)))
    }

    func testFirstLookWithNothingRunningStillChecksAgainLater() {
        var schedule = CloudPollSchedule()
        // A fresh start counts as activity, so a task started elsewhere soon after is seen.
        XCTAssertEqual(schedule.next(tasks: [], now: now), .seconds(900))
    }

    func testPendingChecksAloneStayFastForAnHourOnly() {
        var schedule = CloudPollSchedule()
        let pending = [task(.ready, checks: CloudChecks(passed: 0, failed: 0, pending: 1))]
        XCTAssertEqual(schedule.next(tasks: pending, now: now), .seconds(120))
        let hourLater = now.addingTimeInterval(CloudPollSchedule.checksCap)
        XCTAssertEqual(schedule.next(tasks: pending, now: hourLater - 1), .seconds(120))
        XCTAssertEqual(schedule.next(tasks: pending, now: hourLater), .seconds(900))
        // Stuck checks don't keep it polling forever.
        XCTAssertNil(schedule.next(tasks: pending, now: hourLater.addingTimeInterval(CloudPollSchedule.idleWindow)))
        // A running task is fast whatever the checks do.
        XCTAssertEqual(schedule.next(tasks: pending + [task(.running)], now: hourLater), .seconds(120))
    }

    func testANewPendingPullRequestGetsItsOwnHour() {
        var schedule = CloudPollSchedule()
        let pending = CloudChecks(passed: 0, failed: 0, pending: 1)
        let stuck = task(.ready, checks: pending)
        _ = schedule.next(tasks: [stuck], now: now)
        let later = now.addingTimeInterval(CloudPollSchedule.checksCap + 60)
        XCTAssertEqual(schedule.next(tasks: [stuck], now: later), .seconds(900))
        // Another pull request starts its checks: quick again, though the first is past its hour.
        let fresh = task(.ready, checks: pending)
        XCTAssertEqual(schedule.next(tasks: [stuck, fresh], now: later), .seconds(120))
    }

    func testWakeRestartsTheIdleWindow() {
        var schedule = CloudPollSchedule()
        _ = schedule.next(tasks: [], now: now)
        let later = now.addingTimeInterval(CloudPollSchedule.idleWindow * 2)
        XCTAssertNil(schedule.next(tasks: [], now: later))
        schedule.wake(now: later)
        XCTAssertEqual(schedule.next(tasks: [], now: later), .seconds(900))
    }
}

final class CloudChangesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func task(_ id: String, _ status: CloudStatus, checks: CloudChecks? = nil) -> CloudTask {
        CloudTask(
            source: .copilot, taskID: id, title: "Title \(id)", status: status, url: nil, pullRequest: nil,
            repository: "acme/web", updatedAt: now, checks: checks)
    }

    func testAGuessedStatusIsNeverABaseline() {
        var changes = CloudChanges()
        var guessed = task("a", .running)
        guessed.statusKnown = false
        _ = changes.update(source: .copilot, tasks: [guessed], now: now)
        // The real status arrives: it's only remembered, since "running" was a guess.
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("a", .failed)], now: now), [])
        // A guessed status itself never raises anything.
        var guessedDone = task("b", .ready)
        guessedDone.statusKnown = false
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("a", .failed), guessedDone], now: now), [])
    }

    func testOldTasksAreQuiet() {
        var changes = CloudChanges()
        var old = task("a", .running)
        old.updatedAt = now.addingTimeInterval(-CloudLane.recentWindow - 1)
        _ = changes.update(source: .copilot, tasks: [old], now: now)
        old.status = .failed
        XCTAssertEqual(changes.update(source: .copilot, tasks: [old], now: now), [])
    }

    func testForgettingChecksKeepsAlreadyRedPullRequestsQuiet() {
        var changes = CloudChanges()
        let red = CloudChecks(passed: 0, failed: 1, pending: 0)
        _ = changes.update(source: .copilot, tasks: [task("a", .ready)], now: now)
        changes.forgetChecks()
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("a", .ready, checks: red)], now: now), [])
        // Task status changes still count.
        _ = changes.update(source: .copilot, tasks: [task("b", .running)], now: now)
        XCTAssertEqual(
            changes.update(source: .copilot, tasks: [task("b", .ready)], now: now).map(\.kind), [.finished])
    }

    func testAMissingTimeBecomesWhenItWasFirstSeen() {
        var firstSeen = CloudFirstSeen()
        var undated = task("a", .running)
        undated.updatedAt = .distantPast
        let dated = task("b", .running)
        let stamped = firstSeen.stamp([undated, dated], now: now)
        XCTAssertEqual(stamped.map(\.updatedAt), [now, now])
        // The first sighting sticks; a dated task keeps its own time.
        let later = now.addingTimeInterval(600)
        XCTAssertEqual(firstSeen.stamp([undated], now: later).first?.updatedAt, now)
        // So a task without a time still raises its notice.
        var changes = CloudChanges()
        _ = changes.update(source: .copilot, tasks: firstSeen.stamp([undated], now: later), now: later)
        undated.status = .ready
        XCTAssertEqual(
            changes.update(source: .copilot, tasks: firstSeen.stamp([undated], now: later), now: later).map(\.kind),
            [.finished])
    }

    func testFirstLookIsQuiet() {
        var changes = CloudChanges()
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("a", .ready), task("b", .failed)], now: now), [])
    }

    func testFinishedAndFailedAfterRunning() {
        var changes = CloudChanges()
        _ = changes.update(
            source: .copilot, tasks: [task("a", .running), task("b", .running), task("c", .ready)], now: now)
        let events = changes.update(
            source: .copilot, tasks: [task("a", .ready), task("b", .failed), task("c", .ready)], now: now)
        XCTAssertEqual(events.map(\.kind), [.finished, .failed])
        XCTAssertEqual(events.map(\.task.taskID), ["a", "b"])
        // Nothing new the next time.
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("a", .ready), task("b", .failed)], now: now), [])
    }

    func testANewTaskThatAlreadyFinishedIsReported() {
        var changes = CloudChanges()
        _ = changes.update(source: .copilot, tasks: [], now: now)
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("n", .ready)], now: now).map(\.kind), [.finished])
    }

    func testCancelledIsQuiet() {
        var changes = CloudChanges()
        _ = changes.update(source: .copilot, tasks: [task("a", .running)], now: now)
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("a", .cancelled)], now: now), [])
    }

    func testChecksTurningRedOnce() {
        var changes = CloudChanges()
        let pending = CloudChecks(passed: 1, failed: 0, pending: 1)
        let red = CloudChecks(passed: 1, failed: 1, pending: 0)
        _ = changes.update(source: .copilot, tasks: [task("a", .ready, checks: pending)], now: now)
        XCTAssertEqual(
            changes.update(source: .copilot, tasks: [task("a", .ready, checks: red)], now: now).map(\.kind),
            [.checksFailed])
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("a", .ready, checks: red)], now: now), [])
    }

    func testChecksFirstSeenRedOnAKnownTaskAreReported() {
        var changes = CloudChanges()
        _ = changes.update(source: .copilot, tasks: [task("a", .ready)], now: now)
        let red = CloudChecks(passed: 0, failed: 1, pending: 0)
        XCTAssertEqual(
            changes.update(source: .copilot, tasks: [task("a", .ready, checks: red)], now: now).map(\.kind),
            [.checksFailed])
    }

    func testSourcesAreSeparate() {
        var changes = CloudChanges()
        _ = changes.update(source: .copilot, tasks: [task("a", .running)], now: now)
        // Codex's first look is quiet even though Copilot has been seen.
        let codex = CloudTask(
            source: .codex, taskID: "x", title: "x", status: .ready, url: nil, pullRequest: nil, repository: nil,
            updatedAt: now)
        XCTAssertEqual(changes.update(source: .codex, tasks: [codex], now: now), [])
    }

    func testForgetMakesTheNextLookQuiet() {
        var changes = CloudChanges()
        _ = changes.update(source: .copilot, tasks: [task("a", .running)], now: now)
        changes.forget(.copilot)
        XCTAssertEqual(changes.update(source: .copilot, tasks: [task("a", .ready)], now: now), [])
    }

    func testNoticeTextIsMaskedWhenHidden() {
        let event = CloudEvent(kind: .finished, task: task("a", .ready))
        XCTAssertEqual(event.notice(hidden: false), "Copilot task ready: Title a")
        XCTAssertEqual(event.notice(hidden: true), "Copilot task ready")
        let failed = CloudEvent(kind: .checksFailed, task: task("a", .ready))
        XCTAssertEqual(failed.notice(hidden: false), "Checks failed: Title a")
    }

    func testPushNeverCarriesTheTitle() {
        let event = CloudEvent(kind: .failed, task: task("a", .failed))
        let open = PushMessage.cloud(event, hidden: false)
        XCTAssertEqual(open.title, "Cloud task failed")
        XCTAssertEqual(open.message, "A Copilot task failed in acme/web.")
        XCTAssertFalse(open.message.contains("Title"))
        XCTAssertEqual(PushMessage.cloud(event, hidden: true).message, "A Copilot task failed.")
        let moment = AgentMoment.cloud(event)
        XCTAssertEqual(moment.kind, .cloud)
        XCTAssertEqual(moment.key, "failed|copilot:a")
    }
}

final class CloudLaneTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func task(_ id: String, _ status: CloudStatus, age: TimeInterval) -> CloudTask {
        CloudTask(
            source: .codex, taskID: id, title: id, status: status, url: nil, pullRequest: nil, repository: nil,
            updatedAt: now.addingTimeInterval(-age))
    }

    func testRunningFirstThenRecentFinished() {
        let tasks = [
            task("old", .ready, age: CloudLane.recentWindow + 1), task("done", .ready, age: 60),
            task("run", .running, age: 3600), task("newer", .failed, age: 10),
        ]
        XCTAssertEqual(CloudLane.visible(tasks, now: now).map(\.taskID), ["run", "newer", "done"])
    }

    func testCapped() {
        let tasks = (0..<20).map { task("t\($0)", .ready, age: Double($0)) }
        XCTAssertEqual(CloudLane.visible(tasks, now: now).count, CloudLane.limit)
    }

    func testChecksPlanPicksRecentOpenGitHubPullRequests() {
        let pr = URL(string: "https://github.com/a/b/pull/1")
        var open = task("open", .ready, age: 60)
        open.pullRequest = pr
        var merged = task("merged", .ready, age: 60)
        merged.pullRequest = pr
        merged.pullRequestOpen = false
        var stale = task("stale", .ready, age: CloudLane.recentWindow + 1)
        stale.pullRequest = pr
        let none = task("none", .ready, age: 60)
        XCTAssertEqual(CloudLane.needingChecks([open, merged, stale, none], now: now).map(\.taskID), ["open"])
    }

    func testCursorRunsToFetch() {
        let agents = [
            CursorAgent(id: "a", name: "a", active: true, url: nil, updatedAt: now, latestRunID: "r1"),
            CursorAgent(id: "b", name: "b", active: false, url: nil, updatedAt: now, latestRunID: "r2"),
            CursorAgent(id: "c", name: "c", active: false, url: nil, updatedAt: now, latestRunID: "r3"),
            CursorAgent(id: "d", name: "d", active: false, url: nil, updatedAt: now, latestRunID: nil),
        ]
        // Active, or not seen at this update yet; never one without a run.
        let known = ["b": now, "c": now.addingTimeInterval(-60)]
        XCTAssertEqual(CloudLane.cursorRunsToFetch(agents, fetched: known), ["a", "c"])
    }
}

final class CloudCLITests: XCTestCase {
    func testFindsTheFirstExecutableOnPath() {
        let found = CloudCLI.find(
            "codex", path: "/usr/bin:/opt/homebrew/bin:~/.npm/bin", home: "/Users/me",
            isExecutable: { $0 == "/opt/homebrew/bin/codex" || $0 == "/Users/me/.npm/bin/codex" })
        XCTAssertEqual(found, "/opt/homebrew/bin/codex")
        XCTAssertEqual(
            CloudCLI.find("gh", path: "$HOME/bin", home: "/Users/me", isExecutable: { $0 == "/Users/me/bin/gh" }),
            "/Users/me/bin/gh")
        XCTAssertNil(CloudCLI.find("gh", path: "/usr/bin", home: "/Users/me", isExecutable: { _ in false }))
        XCTAssertNil(CloudCLI.find("gh", path: "", home: "/Users/me", isExecutable: { _ in true }))
    }

    func testCommands() throws {
        XCTAssertEqual(CloudCLI.codexList, ["cloud", "list", "--json", "--limit", "20"])
        XCTAssertEqual(
            CloudCLI.copilotList,
            [
                "agent-task", "list", "--limit", "20", "--json",
                "id,name,state,repository,updatedAt,pullRequestNumber,pullRequestUrl,pullRequestTitle,pullRequestState",
            ])
        let pullRequest = try XCTUnwrap(URL(string: "https://github.com/a/b/pull/1"))
        XCTAssertEqual(
            CloudCLI.checks(pullRequest), ["pr", "checks", "https://github.com/a/b/pull/1", "--json", "bucket"])
        XCTAssertEqual(CloudCLI.codexApply("task_e_2"), ["cloud", "apply", "task_e_2"])
        // Never something codex could read as a flag or a path.
        XCTAssertNil(CloudCLI.codexApply("--attempt"))
        XCTAssertNil(CloudCLI.codexApply("-x"))
        XCTAssertNil(CloudCLI.codexApply("a b"))
        XCTAssertNil(CloudCLI.codexApply("../t"))
        XCTAssertNil(CloudCLI.codexApply(""))
    }

    func testCursorRedirectsStayOnTheAPIHost() throws {
        XCTAssertTrue(CloudCLI.allowsCursorRedirect(to: URL(string: "https://api.cursor.com/v1/agents?cursor=x")))
        XCTAssertFalse(CloudCLI.allowsCursorRedirect(to: URL(string: "https://evil.example/v1/agents")))
        XCTAssertFalse(CloudCLI.allowsCursorRedirect(to: URL(string: "http://api.cursor.com/v1/agents")))
        XCTAssertFalse(CloudCLI.allowsCursorRedirect(to: nil))
    }

    func testCursorRequests() throws {
        let list = try XCTUnwrap(CloudCLI.cursorAgentsURL)
        XCTAssertEqual(list.absoluteString, "https://api.cursor.com/v1/agents?limit=20&includeArchived=false")
        XCTAssertEqual(
            CloudCLI.cursorRunURL(agent: "bc-1", run: "run-1")?.absoluteString,
            "https://api.cursor.com/v1/agents/bc-1/runs/run-1")
        XCTAssertNil(CloudCLI.cursorRunURL(agent: "../x", run: "run-1"))
        // Basic auth: the key as the user name and an empty password.
        XCTAssertEqual(CloudCLI.cursorAuthorization(key: "key_abc"), "Basic a2V5X2FiYzo=")
    }
}
