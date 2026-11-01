import Foundation

/// The checked-out branch, read from `.git/HEAD` directly so the status bar never starts a
/// `git` process.
public enum GitHead {
    /// "ref: refs/heads/main" gives "main"; a detached HEAD (a bare SHA) gives its first seven
    /// characters. Anything else is nil.
    public static func branch(fromHead contents: String) -> String? {
        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref:") {
            let ref = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let heads = "refs/heads/"
            let name = ref.hasPrefix(heads) ? String(ref.dropFirst(heads.count)) : ref
            return name.isEmpty ? nil : name
        }
        let isSHA = line.count >= 40 && line.allSatisfy(\.isHexDigit)
        return isSHA ? String(line.prefix(7)) : nil
    }

    /// The folder a `.git` *file* points at ("gitdir: ..."), as in worktrees and submodules.
    /// Relative paths are resolved against `folder`, the one holding the `.git` file.
    public static func gitDirectory(fromDotGit contents: String, in folder: String) -> String? {
        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("gitdir:") else { return nil }
        let path = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
        if path.isEmpty { return nil }
        return path.hasPrefix("/") ? path : (folder as NSString).appendingPathComponent(path)
    }

    /// The branch for `cwd`, walking up to the repository root. `read` returns a file's
    /// contents, or nil when it isn't a readable file.
    public static func branch(cwd: String, read: (String) -> String?) -> String? {
        guard cwd.hasPrefix("/") else { return nil }
        var folder = (cwd as NSString).standardizingPath
        while true {
            let dotGit = (folder as NSString).appendingPathComponent(".git")
            if let head = read((dotGit as NSString).appendingPathComponent("HEAD")) {
                return branch(fromHead: head)
            }
            if let file = read(dotGit), let directory = gitDirectory(fromDotGit: file, in: folder) {
                return read((directory as NSString).appendingPathComponent("HEAD")).flatMap(branch(fromHead:))
            }
            if folder == "/" { return nil }
            folder = (folder as NSString).deletingLastPathComponent
        }
    }
}
