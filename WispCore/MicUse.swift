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
        if inputBundleIDs.contains(where: callApps.contains) { return .call }
        return meetingInProgress ? .call : .recording
    }
}

/// Whether the microphone counts as in use.
public enum MicState {
    /// macOS's always-on speech listeners ("Hey Siri"): they hold an input stream all day,
    /// which isn't anyone recording.
    static let backgroundListeners: Set<String> = ["com.apple.CoreSpeech", "com.apple.corespeechd"]

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

    /// The apps worth naming: background listeners and unnamed processes left out.
    public static func apps(_ inputProcesses: [String]) -> [String] {
        inputProcesses.filter { !$0.isEmpty && !backgroundListeners.contains($0) }.sorted()
    }
}
