import Foundation

/// The first-launch setup: grant Accessibility, choose how the shelf opens, connect agents.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case accessibility
    case opening
    case agents

    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// The main button. Accessibility can be skipped, but the button says so until it's granted.
    public func primaryAction(accessibilityGranted: Bool) -> String {
        switch self {
        case .accessibility: accessibilityGranted ? "Continue" : "Skip for Now"
        case .opening: "Continue"
        case .agents: "Done"
        }
    }

    /// Setup shows once. People who used Wisp before it existed have settings already
    /// and never see it; "Run Setup Again" stores false to bring it back.
    public static func needsSetup(storedFlag: Bool?, hasEarlierSettings: Bool) -> Bool {
        if let storedFlag { return !storedFlag }
        return !hasEarlierSettings
    }
}
