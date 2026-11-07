/// The shapes Wisp can take, as offered by the form switcher. Each shell form maps to a
/// placement; the finer choices (which corner, which side) stay in Settings. The window is
/// the shelf in an ordinary window, for every display at once (see `ShelfWindowState`).
public enum FormFactor: String, CaseIterable, Sendable, Identifiable {
    case notch
    case corner
    case bottom
    case side
    case orb
    case window

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

    /// Where the shell sits in this form; nil for the window, which leaves the shell alone.
    public var placement: Placement? {
        switch self {
        case .notch: .top
        case .corner: .topRight
        case .bottom: .bottom
        case .side: .right
        case .orb: .floating
        case .window: nil
        }
    }

    public var title: String {
        switch self {
        case .notch: "Notch"
        case .corner: "Corner"
        case .bottom: "Bottom"
        case .side: "Side"
        case .orb: "Orb"
        case .window: "Window"
        }
    }

    public var symbol: String {
        switch self {
        case .notch: "rectangle.topthird.inset.filled"
        case .corner: "rectangle.inset.topright.filled"
        case .bottom: "rectangle.bottomthird.inset.filled"
        case .side: "rectangle.righthalf.inset.filled"
        case .orb: "circle.circle"
        case .window: "macwindow"
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
        guard let placement = form.placement else { return }
        // Keep a corner or side the user already picked, rather than forcing the right one.
        let current = self.placement(for: uuid)
        let target = FormFactor(placement: current) == form ? current : placement
        returns[uuid] = nil
        overrides[uuid] = target == standard ? nil : target.rawValue
    }
}
