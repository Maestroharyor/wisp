import Foundation

/// The first-launch setup: grant Accessibility, choose how the shelf opens and try it, meet
/// the ring, connect agents, and finish with launch at login.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case accessibility
    case opening
    case ring
    case agents
    case finish

    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// The main button. Accessibility can be skipped, but the button says so until it's granted.
    public func primaryAction(accessibilityGranted: Bool) -> String {
        switch self {
        case .accessibility: accessibilityGranted ? "Continue" : "Skip for now"
        case .opening, .ring, .agents: "Continue"
        case .finish: "Done"
        }
    }

    /// Where setup opens at launch: the step it was on when Wisp last quit (often to apply
    /// Screen Recording), or the first.
    public static func resume(stored: Int?) -> OnboardingStep {
        stored.flatMap(OnboardingStep.init(rawValue:)) ?? .accessibility
    }

    /// Setup shows once. People who used Wisp before it existed have settings already
    /// and never see it; "Run Setup Again" opens it without changing the flag.
    public static func needsSetup(storedFlag: Bool?, hasEarlierSettings: Bool) -> Bool {
        if let storedFlag { return !storedFlag }
        return !hasEarlierSettings
    }
}

/// What the ring's live window previews still need, first thing first; nil when they work.
public enum RingPreviews {
    public enum Need: Equatable, Sendable {
        /// "Show an app's windows" is off, so there are no windows to preview.
        case windowsOff
        /// Listing an app's windows needs Accessibility.
        case accessibility
        /// The picture itself needs Screen Recording.
        case screenRecording
    }

    public static func need(showsWindows: Bool, accessibility: Bool, screenRecording: Bool) -> Need? {
        if !showsWindows { return .windowsOff }
        if !accessibility { return .accessibility }
        if !screenRecording { return .screenRecording }
        return nil
    }
}
