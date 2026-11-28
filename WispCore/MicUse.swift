import Foundation

/// What the microphone is being used for, judged from the apps holding it.
public enum MicActivity: Equatable, Sendable {
    case call
    case recording
}

public enum MicUse {
    /// Apps whose microphone use is a call on its own.
    static let callApps: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.FaceTime",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "Cisco-Systems.Spark", "com.cisco.webexmeetingsapp",
        "com.skype.skype",
    ]

    /// A call when a call app has the mic, or when a calendar meeting is in progress: browsers
    /// host calls (Meet, Teams on the web) but also voice notes and dictation, so they count
    /// only then, like apps macOS didn't name. Anything else is a recording.
    public static func classify(inputBundleIDs: [String], meetingInProgress: Bool) -> MicActivity {
        if inputBundleIDs.contains(where: { BundleMatch.any(callApps, matches: $0) }) { return .call }
        return meetingInProgress ? .call : .recording
    }
}

/// Whether the microphone counts as in use.
public enum MicState {
    /// Parts of macOS that hold an input stream without anyone recording: the speech
    /// listeners ("Hey Siri"), Sound Recognition, and the level meter in System Settings ›
    /// Sound, which runs for as long as that pane is open.
    static let backgroundListeners: Set<String> = [
        "com.apple.CoreSpeech", "com.apple.corespeechd", "com.apple.assistantd", "com.apple.Siri",
        "com.apple.accessibility.heard", "com.apple.Sound-Settings.extension",
    ]

    /// macOS's per-process view is the source of truth: the bundle ids of processes with an
    /// input stream running ("" for one without a bundle id, such as a command-line
    /// recorder). The device-wide running flag also turns on for playback through a headset
    /// or USB mic with an output, so it only decides when the process list can't be read
    /// (`inputProcesses` nil). No input device means nothing can be recording.
    public static func inUse(hasInputDevice: Bool, deviceRunning: Bool, inputProcesses: [String]?) -> Bool {
        guard hasInputDevice else { return false }
        guard let inputProcesses else { return deviceRunning }
        return inputProcesses.contains { !backgroundListeners.contains($0) }
    }

    /// Leaves out Wisp itself while it dictates (it shows its own pill then). Any other time
    /// Wisp holding the microphone is worth showing, so `dictating` false keeps it.
    public static func inputProcesses(_ processes: [String]?, ownBundleID: String?, dictating: Bool) -> [String]? {
        guard dictating, let ownBundleID else { return processes }
        return processes?.filter { $0 != ownBundleID }
    }

    /// When the pill's timer started. It starts when the mic goes live and stops with it, and
    /// starts again when the apps holding it now share none with the ones before (a call
    /// after a recording), so one session's time isn't added to the next one's.
    public static func since(previous: Date?, previousApps: [String], apps: [String], inUse: Bool, now: Date) -> Date? {
        guard inUse else { return nil }
        guard let previous else { return now }
        if !previousApps.isEmpty, !apps.isEmpty, Set(previousApps).isDisjoint(with: apps) { return now }
        return previous
    }

    /// The apps worth naming: background listeners and unnamed processes left out.
    public static func apps(_ inputProcesses: [String]) -> [String] {
        inputProcesses.filter { !$0.isEmpty && !backgroundListeners.contains($0) }.sorted()
    }
}

/// Matches bundle ids against a list, counting an app's helper processes as the app:
/// Chromium and Electron apps record from `<app id>.helper` and the like.
enum BundleMatch {
    static func any(_ ids: Set<String>, matches id: String) -> Bool {
        ids.contains(id) || ids.contains { id.hasPrefix($0 + ".") }
    }
}
