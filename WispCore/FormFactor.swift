/// The shapes Wisp can take on a display, as offered by the form switcher. Each maps to a
/// placement; the finer choices (which corner, which side) stay in Settings.
public enum FormFactor: String, CaseIterable, Sendable, Identifiable {
    case notch
    case corner
    case bottom
    case side
    case orb

    public var id: Self { self }

    public init(placement: Placement) {
        switch placement {
        case .top: self = .notch
        case .topLeft, .topRight: self = .corner
        case .bottom: self = .bottom
        case .left, .right: self = .side
        case .floating: self = .orb
        }
    }

    public var placement: Placement {
        switch self {
        case .notch: .top
        case .corner: .topRight
        case .bottom: .bottom
        case .side: .right
        case .orb: .floating
        }
    }

    public var title: String {
        switch self {
        case .notch: "Notch"
        case .corner: "Corner"
        case .bottom: "Bottom"
        case .side: "Side"
        case .orb: "Orb"
        }
    }

    public var symbol: String {
        switch self {
        case .notch: "rectangle.topthird.inset.filled"
        case .corner: "rectangle.inset.topright.filled"
        case .bottom: "rectangle.bottomthird.inset.filled"
        case .side: "rectangle.righthalf.inset.filled"
        case .orb: "circle.circle"
        }
    }

    /// The forms a display can take. Top centre belongs to Apple's island where there is one.
    public static func available(systemIsland: Bool) -> [FormFactor] {
        systemIsland ? allCases.filter { $0 != .notch } : allCases
    }

    /// The form after this one, for cycling with a key.
    public func next(systemIsland: Bool) -> FormFactor {
        let forms = Self.available(systemIsland: systemIsland)
        guard let index = forms.firstIndex(of: self) else { return forms.first ?? self }
        return forms[(index + 1) % forms.count]
    }
}

extension OrbPlacements {
    /// Switches a display to `form`. The orb remembers where the shell was, so docking it
    /// later goes back there; picking any other form forgets that.
    public mutating func set(_ form: FormFactor, for uuid: String) {
        if form == .orb {
            float(uuid)
            return
        }
        // Keep a corner or side the user already picked, rather than forcing the right one.
        let current = placement(for: uuid)
        let target = FormFactor(placement: current) == form ? current : form.placement
        returns[uuid] = nil
        overrides[uuid] = target == standard ? nil : target.rawValue
    }
}
