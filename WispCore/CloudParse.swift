import Foundation

// Shapes this file relies on, checked 2026-11-07 (fixtures in WispTests/CloudTaskTests.swift):
// - `codex cloud list --json [--limit 1-20]` prints `{"tasks": [...], "cursor": ...}`; each task
//   has `id`, `url`, `title`, `status` (pending, ready, applied or error), `updated_at` (RFC 3339),
//   `environment_label`, `summary`, `attempt_total`. `codex cloud apply <id>` applies a task's
//   diff to the git checkout it runs in. Source: openai/codex `codex-rs/cloud-tasks`.
// - `gh agent-task list --json <fields>` (gh 2.100.0, preview) prints an array; `repository` and
//   `user` are strings, `state` is queued, in_progress, completed, failed, idle,
//   waiting_for_user, timed_out or cancelled, and `pullRequestState` is OPEN, CLOSED or MERGED.
//   Source: `gh agent-task list --help` and cli/cli `pkg/cmd/agent-task`.
// - Cursor: `GET https://api.cursor.com/v1/agents` returns `{"items": [...], "nextCursor"}` with
//   `id`, `name`, `status` (ACTIVE, IDLE or ARCHIVED), `url`, `updatedAt`, `latestRunId`;
//   `GET /v1/agents/{id}/runs/{runId}` returns `status` (CREATING, RUNNING,
//   WAITING_FOR_BACKGROUND_WORK, FINISHED, ERROR, CANCELLED, EXPIRED) and
//   `git.branches[].prUrl`. Basic auth with the key as the user name. Source:
//   cursor.com/docs/cloud-agent/api/endpoints.
// - `gh pr checks <url> --json bucket` prints an array whose `bucket` is pass, fail, pending,
//   skipping or cancel; it exits 8 while checks are pending and 1 when one failed, still
//   printing the JSON.

/// Turns each source's output into `CloudTask`s.
public enum CloudParse {
    public enum Problem: Error, Equatable {
        /// Not the JSON the source prints.
        case unexpected
    }

    public static func codex(_ data: Data) throws -> [CloudTask] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .array(let items)? = root["tasks"]
        else { throw Problem.unexpected }
        return items.compactMap { item in
            guard let id = item["id"]?.stringValue, let status = codexStatus(item["status"]?.stringValue) else {
                return nil
            }
            return CloudTask(
                source: .codex, taskID: id, title: item["title"]?.stringValue ?? "", status: status,
                url: link(item["url"]?.stringValue, hosts: codexHosts), pullRequest: nil,
                repository: item["environment_label"]?.stringValue,
                updatedAt: item["updated_at"]?.stringValue.flatMap(date) ?? .distantPast)
        }
    }

    static func codexStatus(_ value: String?) -> CloudStatus? {
        switch value {
        case "pending": .running
        // Applied means the user already took the diff; it's still a finished task.
        case "ready", "applied": .ready
        case "error": .failed
        default: nil
        }
    }

    public static func copilot(_ data: Data) throws -> [CloudTask] {
        guard case .array(let items)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw Problem.unexpected
        }
        return items.compactMap { item in
            guard let id = item["id"]?.stringValue, let status = copilotStatus(item["state"]?.stringValue) else {
                return nil
            }
            let pullRequest = link(item["pullRequestUrl"]?.stringValue, hosts: githubHosts)
            let name = item["name"]?.stringValue ?? ""
            return CloudTask(
                source: .copilot, taskID: id,
                title: name.isEmpty ? item["pullRequestTitle"]?.stringValue ?? "" : name, status: status,
                url: pullRequest, pullRequest: pullRequest, repository: item["repository"]?.stringValue,
                updatedAt: item["updatedAt"]?.stringValue.flatMap(date) ?? .distantPast,
                pullRequestOpen: (item["pullRequestState"]?.stringValue ?? "OPEN") == "OPEN")
        }
    }

    static func copilotStatus(_ value: String?) -> CloudStatus? {
        switch value {
        case "queued": .queued
        case "in_progress": .running
        case "waiting_for_user": .waiting
        // gh shows completed as "Ready for review"; idle is a session that stopped without failing.
        case "completed", "idle": .ready
        case "failed", "timed_out": .failed
        case "cancelled": .cancelled
        default: nil
        }
    }

    /// Archived agents are left out.
    public static func cursorAgents(_ data: Data) throws -> [CursorAgent] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .array(let items)? = root["items"]
        else { throw Problem.unexpected }
        return items.compactMap { item in
            guard let id = item["id"]?.stringValue, let status = item["status"]?.stringValue, status != "ARCHIVED"
            else { return nil }
            return CursorAgent(
                id: id, name: item["name"]?.stringValue ?? "", active: status == "ACTIVE",
                url: link(item["url"]?.stringValue, hosts: cursorHosts),
                updatedAt: item["updatedAt"]?.stringValue.flatMap(date) ?? .distantPast,
                latestRunID: item["latestRunId"]?.stringValue)
        }
    }

    public static func cursorRun(_ data: Data) throws -> CursorRun {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), root["id"] != nil else {
            throw Problem.unexpected
        }
        var branch: JSONValue?
        if case .array(let branches)? = root["git"]?["branches"] {
            branch = branches.first { $0["prUrl"]?.stringValue != nil } ?? branches.first
        }
        return CursorRun(
            status: cursorRunStatus(root["status"]?.stringValue),
            // GitHub only: Cursor can also open GitLab merge requests, which Wisp doesn't link to.
            pullRequest: link(branch?["prUrl"]?.stringValue, hosts: githubHosts),
            repository: branch?["repoUrl"]?.stringValue.map(repository(fromRepoURL:)))
    }

    static func cursorRunStatus(_ value: String?) -> CloudStatus? {
        switch value {
        case "CREATING": .queued
        case "RUNNING", "WAITING_FOR_BACKGROUND_WORK": .running
        case "FINISHED": .ready
        case "ERROR", "EXPIRED": .failed
        case "CANCELLED": .cancelled
        default: nil
        }
    }

    /// The agent with what its latest run adds, when that was read.
    public static func cursorTask(_ agent: CursorAgent, run: CursorRun?) -> CloudTask {
        CloudTask(
            source: .cursor, taskID: agent.id, title: agent.name,
            status: run?.status ?? (agent.active ? .running : .ready), url: agent.url, pullRequest: run?.pullRequest,
            repository: run?.repository, updatedAt: agent.updatedAt, statusKnown: run?.status != nil)
    }

    public static let codexHosts = ["chatgpt.com"]
    public static let githubHosts = ["github.com"]
    public static let cursorHosts = ["cursor.com"]

    /// Links from a response are opened in the browser, so only https on the source's own host
    /// (or a subdomain of it), with no user name or password in it, is kept.
    public static func link(_ text: String?, hosts: [String]) -> URL? {
        guard let text, let components = URLComponents(string: text), components.scheme == "https",
            components.user == nil, components.password == nil, let host = components.host?.lowercased(),
            hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return nil }
        return components.url
    }

    /// "github.com/acme/web" (or with a scheme) to "acme/web".
    static func repository(fromRepoURL value: String) -> String {
        var text = value
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        let parts = text.split(separator: "/")
        return parts.count >= 3 ? parts[1...2].joined(separator: "/") : text
    }

    /// Nil when there are no checks, or the output isn't the JSON (gh prints a sentence then).
    public static func checks(_ data: Data) -> CloudChecks? {
        guard case .array(let items)? = try? JSONDecoder().decode(JSONValue.self, from: data), !items.isEmpty else {
            return nil
        }
        var checks = CloudChecks(passed: 0, failed: 0, pending: 0)
        for item in items {
            switch item["bucket"]?.stringValue {
            case "pass", "skipping": checks.passed += 1
            // A cancelled run leaves the pull request unmergeable under required checks, so it counts as red.
            case "fail", "cancel": checks.failed += 1
            case "pending": checks.pending += 1
            default: break
            }
        }
        return checks
    }

    public static func isGitHubPullRequest(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.host == "github.com" else { return false }
        let parts = url.path.split(separator: "/")
        return parts.count >= 4 && parts[2] == "pull"
    }

    /// RFC 3339, with any fraction of a second (Go prints up to nine digits) dropped.
    public static func date(_ text: String) -> Date? {
        var trimmed = text
        if let dot = trimmed.firstIndex(of: "."), let time = trimmed.firstIndex(of: "T"), dot > time {
            let end = trimmed[dot...].dropFirst().firstIndex { !$0.isNumber } ?? trimmed.endIndex
            trimmed.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}

/// The commands and requests Wisp makes, and finding the CLIs on the login shell's PATH.
public enum CloudCLI {
    public static let limit = 20

    public static let codexList = ["cloud", "list", "--json", "--limit", "\(limit)"]

    public static let copilotList = [
        "agent-task", "list", "--limit", "\(limit)", "--json",
        "id,name,state,repository,updatedAt,pullRequestNumber,pullRequestUrl,pullRequestTitle,pullRequestState",
    ]

    public static func checks(_ pullRequest: URL) -> [String] {
        ["pr", "checks", pullRequest.absoluteString, "--json", "bucket"]
    }

    /// Nil unless the id is plain letters, digits, `_` and `-` and doesn't start with `-`, so it
    /// can't be read as a flag.
    public static func codexApply(_ taskID: String) -> [String]? {
        guard isPlainID(taskID), !taskID.hasPrefix("-") else { return nil }
        return ["cloud", "apply", taskID]
    }

    private static func isPlainID(_ text: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return !text.isEmpty && text.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Cursor requests carry the key, so a redirect is followed only within the API's own host.
    public static func allowsCursorRedirect(to url: URL?) -> Bool {
        url?.scheme == "https" && url?.host == "api.cursor.com"
    }

    /// gh's exit code while checks are pending, and its usual failure code; both still print the JSON.
    public static let checksExitCodes: Set<Int32> = [1, 8]

    public static let cursorAgentsURL = URL(
        string: "https://api.cursor.com/v1/agents?limit=\(limit)&includeArchived=false")

    /// Nil for ids that aren't plain, so nothing from a response can change the path.
    public static func cursorRunURL(agent: String, run: String) -> URL? {
        guard isPlainID(agent), isPlainID(run) else { return nil }
        return URL(string: "https://api.cursor.com/v1/agents/\(agent)/runs/\(run)")
    }

    /// Basic auth: the key as the user name and an empty password, as Cursor's examples use.
    public static func cursorAuthorization(key: String) -> String {
        "Basic " + Data("\(key):".utf8).base64EncodedString()
    }

    /// The first `name` on `path` (a PATH value) that `isExecutable` accepts.
    public static func find(
        _ name: String, path: String, home: String, isExecutable: (String) -> Bool
    ) -> String? {
        for entry in path.split(separator: ":") {
            var folder = String(entry)
            if folder.hasPrefix("~/") { folder = home + folder.dropFirst() }
            if folder.hasPrefix("$HOME/") { folder = home + folder.dropFirst(5) }
            let candidate = (folder.hasSuffix("/") ? folder : folder + "/") + name
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}
