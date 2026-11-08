import Foundation

/// What About › Copy diagnostics puts on the clipboard for a bug report: Wisp's version, the
/// macOS version, the Dynamic Island setting and what notch detection reads from each display.
/// Nothing personal: no names, files, tokens, prompts or other settings.
public enum Diagnostics {
    /// `displays` are `SystemIsland.report` texts, one per display.
    public static func report(
        appVersion: String, systemVersion: String, islandSetting: IslandSetting, displays: [String]
    ) -> String {
        let header = [
            "Wisp \(appVersion)",
            "macOS \(systemVersion)",
            "Dynamic Island detection: \(islandSetting.title)",
        ]
        .joined(separator: "\n")
        let blocks = displays.enumerated().map { index, display in "Display \(index + 1)\n\(display)" }
        return ([header] + blocks).joined(separator: "\n\n")
    }
}
