import Foundation

/// Writes agent settings files Wisp edits, keeping copies the user can go back to:
/// `.wisp-backup` holds the file from before Wisp first touched it, `.wisp-previous` the
/// version each write replaced.
public enum SettingsFileWriter {
    /// Saves the file as `.wisp-backup` unless a backup is already there, so later edits
    /// never replace the user's own original.
    public static func backUpOnce(_ url: URL) throws {
        let backup = url.appendingPathExtension("wisp-backup")
        guard !FileManager.default.fileExists(atPath: backup.path),
            let current = try? Data(contentsOf: url), !current.isEmpty
        else { return }
        try current.write(to: backup, options: .atomic)
    }

    /// Writes `data` atomically, creating the folder if needed and keeping the version it
    /// replaces as `.wisp-previous`.
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let current = try? Data(contentsOf: url), !current.isEmpty {
            try current.write(to: url.appendingPathExtension("wisp-previous"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }

    /// Writes `data` atomically with no copies beside it, for files inside a project: copies
    /// there aren't covered by the file's own gitignore entry and could be committed.
    public static func replace(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
