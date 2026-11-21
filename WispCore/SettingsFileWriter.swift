import Foundation

/// Writes agent settings files Wisp edits, keeping copies the user can go back to:
/// `.wisp-backup` holds the file from before Wisp first touched it, `.wisp-previous` the
/// version each write replaced.
///
/// A settings file kept as a symlink (a dotfiles repo) is written through the link, since an
/// atomic write would otherwise replace the link with a plain file. Copies sit beside the path
/// the agent reads and keep the file's permissions, as it can hold API keys.
public enum SettingsFileWriter {
    /// Saves the file as `.wisp-backup` unless a backup is already there, so later edits
    /// never replace the user's own original.
    public static func backUpOnce(_ url: URL) throws {
        let backup = url.appendingPathExtension("wisp-backup")
        guard !FileManager.default.fileExists(atPath: backup.path),
            let current = try? Data(contentsOf: url), !current.isEmpty
        else { return }
        try saveCopy(current, of: url, to: backup)
    }

    /// Saves `data` as the file's `.wisp-backup`, replacing any backup already there.
    public static func saveBackup(_ data: Data, of url: URL) throws {
        try saveCopy(data, of: url, to: url.appendingPathExtension("wisp-backup"))
    }

    /// Writes `data` atomically, creating the folder if needed and keeping the version it
    /// replaces as `.wisp-previous`.
    public static func write(_ data: Data, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let current = try? Data(contentsOf: target), !current.isEmpty {
            try saveCopy(current, of: url, to: url.appendingPathExtension("wisp-previous"))
        }
        try data.write(to: target, options: .atomic)
    }

    /// Writes `data` atomically with no copies beside it, for files inside a project: copies
    /// there aren't covered by the file's own gitignore entry and could be committed.
    public static func replace(_ data: Data, at url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    private static func saveCopy(_ data: Data, of url: URL, to copy: URL) throws {
        try data.write(to: copy, options: .atomic)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
        guard let permissions = attributes?[.posixPermissions] else { return }
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: copy.path)
    }
}
