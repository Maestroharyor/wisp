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

    /// Setup shows once. People who used Wisp before it existed have settings already
    /// and never see it; "Run Setup Again" opens it without changing the flag.
    public static func needsSetup(storedFlag: Bool?, hasEarlierSettings: Bool) -> Bool {
        if let storedFlag { return !storedFlag }
        return !hasEarlierSettings
    }
}
