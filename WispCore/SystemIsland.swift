import CoreGraphics

/// Whether this Mac has Apple's own Dynamic Island, as chosen in Settings.
public enum IslandSetting: String, CaseIterable, Sendable {
    case automatic
    case yes
    case no
}

/// The Dynamic Island on the OLED MacBook Pro sits where Wisp would draw its notch, so on
/// those Macs Wisp moves out of its way.
public enum SystemIsland {
    /// Model identifiers known to have one. Empty until they're confirmed on real hardware;
    /// until then the setting decides. A guessed identifier could hide the notch on a Mac
    /// that needs it.
    public static let knownModels: Set<String> = []

    public static func present(
        setting: IslandSetting, modelIdentifier: String?, builtIn: Bool, known: Set<String> = knownModels
    ) -> Bool {
        guard builtIn else { return false }
        switch setting {
        case .yes: return true
        case .no: return false
        case .automatic: return modelIdentifier.map(known.contains) ?? false
        }
    }

    /// What detection reads from a display, to paste into a bug report. Nothing personal.
    public static func report(modelIdentifier: String?, builtIn: Bool, metrics: ScreenMetrics) -> String {
        [
            "Model: \(modelIdentifier ?? "unknown")",
            "Built in: \(builtIn ? "yes" : "no")",
            "Safe area top: \(number(metrics.safeAreaTop))",
            "Left of camera: \(metrics.auxiliaryTopLeft.map(rect) ?? "none")",
            "Right of camera: \(metrics.auxiliaryTopRight.map(rect) ?? "none")",
            "Frame: \(rect(metrics.frame))",
            "Visible: \(rect(metrics.visibleFrame))",
        ]
        .joined(separator: "\n")
    }

    private static func rect(_ rect: CGRect) -> String {
        "\(number(rect.minX)), \(number(rect.minY)), \(number(rect.width)) × \(number(rect.height))"
    }

    private static func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", Double(value))
    }
}

extension Placement {
    /// Top centre belongs to the system island on Macs that have one; the top right corner
    /// sits below the menu bar instead.
    public func clear(ofSystemIsland present: Bool) -> Placement {
        present && self == .top ? .topRight : self
    }
}
