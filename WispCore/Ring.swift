import CoreGraphics
import Foundation

/// One thing a ring segment does.
public struct RingAction: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// An action this version doesn't know (saved by a newer Wisp) reads as nothing, so
        /// the rest of the ring still loads.
        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .none
        }

        case home
        case tray
        case mediaPage
        /// A widget on its own; `value` is the widget's identifier.
        case widget
        case agents
        case playPause
        case nextTrack
        case previousTrack
        case clipboard
        case miniPlayer
        /// Starts a countdown; `value` is the minutes.
        case timer
        case keepAwake
        case darkMode
        case focus
        case screenshot
        case pickColour
        case lockScreen
        /// Runs a Shortcut; `value` is its name.
        case shortcut
        /// Runs a custom drop action; `value` is its identifier.
        case dropAction
        case airDrop
        case transform
        case zip
        case none
    }

    public var kind: Kind
    public var value: String?

    public init(_ kind: Kind, value: String? = nil) {
        self.kind = kind
        self.value = value
    }

    public var title: String {
        switch kind {
        case .home: "Home"
        case .tray: "Tray"
        case .mediaPage: "Media"
        case .widget: value ?? "Widget"
        case .agents: "Agents"
        case .playPause: "Play or pause"
        case .nextTrack: "Next"
        case .previousTrack: "Previous"
        case .clipboard: "Clipboard"
        case .miniPlayer: "Mini player"
        case .timer: "\(minutes) min timer"
        case .keepAwake: "Keep awake"
        case .darkMode: "Dark mode"
        case .focus: "Focus"
        case .screenshot: "Screenshot"
        case .pickColour: "Pick colour"
        case .lockScreen: "Lock screen"
        case .shortcut: value ?? "Shortcut"
        case .dropAction: "Drop action"
        case .airDrop: "AirDrop"
        case .transform: "Transform"
        case .zip: "Zip"
        case .none: "Nothing"
        }
    }

    public var symbol: String {
        switch kind {
        case .home: "house"
        case .tray: "tray.and.arrow.down"
        case .mediaPage: "music.note"
        case .widget: "square.grid.2x2"
        case .agents: "sparkles"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .clipboard: "doc.on.clipboard"
        case .miniPlayer: "pip"
        case .timer: "timer"
        case .keepAwake: "cup.and.saucer"
        case .darkMode: "circle.lefthalf.filled"
        case .focus: "moon"
        case .screenshot: "camera.viewfinder"
        case .pickColour: "eyedropper"
        case .lockScreen: "lock"
        case .shortcut: "square.stack.3d.up"
        case .dropAction: "terminal"
        case .airDrop: "airplayaudio"
        case .transform: "wand.and.stars"
        case .zip: "doc.zipper"
        case .none: "circle.dashed"
        }
    }

    /// Takes files dropped on it.
    public var acceptsFiles: Bool {
        switch kind {
        case .tray, .airDrop, .transform, .zip, .dropAction: true
        default: false
        }
    }

    /// The timer length, 25 minutes when unset or unreadable.
    public var minutes: Int { value.flatMap(Int.init).map { max($0, 1) } ?? 25 }
}

/// A ring segment: one action, and optionally a sub-ring that opens beside it.
public struct RingSlot: Codable, Equatable, Hashable, Sendable {
    public static let maxSubItems = 9

    public var action: RingAction
    public private(set) var group: [RingAction]

    public init(_ action: RingAction, group: [RingAction] = []) {
        self.action = action
        self.group = Array(group.prefix(Self.maxSubItems))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(RingAction.self, forKey: .action),
            group: try container.decodeIfPresent([RingAction].self, forKey: .group) ?? [])
    }
}

/// A full ring. The default one, or one for a list of apps.
public struct RingSet: Codable, Equatable, Hashable, Sendable, Identifiable {
    public static let maxSlots = 8

    public var id: UUID
    public var name: String
    public private(set) var slots: [RingSlot]
    /// Bundle identifiers of the apps this set is for; empty for the default set.
    public var bundleIDs: [String]

    public init(id: UUID = UUID(), name: String, slots: [RingSlot], bundleIDs: [String] = []) {
        self.id = id
        self.name = name
        self.slots = Array(slots.prefix(Self.maxSlots))
        self.bundleIDs = bundleIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            slots: try container.decode([RingSlot].self, forKey: .slots),
            bundleIDs: try container.decodeIfPresent([String].self, forKey: .bundleIDs) ?? [])
    }

    public mutating func setSlots(_ slots: [RingSlot]) {
        self.slots = Array(slots.prefix(Self.maxSlots))
    }
}

/// The default ring plus any per-app rings.
public struct RingConfig: Codable, Equatable, Sendable {
    public var standard: RingSet
    public var perApp: [RingSet]

    public init(standard: RingSet, perApp: [RingSet] = []) {
        self.standard = standard
        self.perApp = perApp
    }

    /// The ring for the app in front: the first set listing it, else the default.
    public func set(forFrontApp bundleID: String?) -> RingSet {
        guard let bundleID else { return standard }
        return perApp.first { $0.bundleIDs.contains(bundleID) } ?? standard
    }

    public static let defaults = RingConfig(
        standard: RingSet(
            name: "Default",
            slots: [
                RingSlot(RingAction(.home)),
                RingSlot(RingAction(.agents)),
                RingSlot(
                    RingAction(.playPause),
                    group: [RingAction(.previousTrack), RingAction(.playPause), RingAction(.nextTrack)]),
                RingSlot(RingAction(.clipboard)),
                RingSlot(RingAction(.timer, value: "25")),
                RingSlot(RingAction(.tray)),
                RingSlot(RingAction(.focus)),
                RingSlot(RingAction(.screenshot)),
            ]))
}

/// A sub-ring entry built at the moment the ring opens, such as one per agent session.
public struct RingChoice: Equatable, Sendable, Identifiable {
    public enum Tint: Equatable, Sendable { case plain, allow, deny }

    public let id: String
    public let title: String
    public let symbol: String
    public let tint: Tint

    public init(id: String, title: String, symbol: String, tint: Tint = .plain) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }
}

/// A coding agent session, as the Agents segment lists it.
public struct RingAgentEntry: Equatable, Sendable {
    public let sessionID: String
    public let project: String
    /// The request waiting for an answer, if there is one.
    public let approvalID: UUID?

    public init(sessionID: String, project: String, approvalID: UUID? = nil) {
        self.sessionID = sessionID
        self.project = project
        self.approvalID = approvalID
    }
}

public enum RingAgentChoices {
    /// Allow and Deny for each waiting request, first; otherwise one entry per session that
    /// shows its terminal. Only project names appear, so private mode leaks nothing.
    public static func choices(for entries: [RingAgentEntry]) -> [RingChoice] {
        let waiting = entries.compactMap { entry in entry.approvalID.map { (entry.project, $0) } }
        let choices: [RingChoice]
        if waiting.isEmpty {
            choices = entries.map {
                RingChoice(id: "focus:\($0.sessionID)", title: $0.project, symbol: "terminal")
            }
        } else {
            choices = waiting.flatMap { project, id in
                [
                    RingChoice(
                        id: "allow:\(id.uuidString)", title: "Allow \(project)", symbol: "checkmark", tint: .allow),
                    RingChoice(id: "deny:\(id.uuidString)", title: "Deny \(project)", symbol: "xmark", tint: .deny),
                ]
            }
        }
        return Array(choices.prefix(RingSlot.maxSubItems))
    }
}

/// Where a point lands on an open ring.
public enum RingHit: Equatable, Sendable {
    case centre
    case slot(Int)
    case sub(Int)
    case none
}

/// The ring's shape: a centre button, a band of segments around it, and a sub-ring arc
/// outside the segment that owns it. Angles run clockwise from 12 o'clock, in degrees.
public enum RingGeometry {
    public static let centreRadius: CGFloat = 34
    public static let ringRadius: CGFloat = 112
    public static let subRadius: CGFloat = 172
    /// Angle between neighbouring sub-ring items.
    public static let subStep: CGFloat = 28
    public static let margin: CGFloat = 12

    public static func slotAngle(_ index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(index) * 360 / CGFloat(count)
    }

    public static func subAngle(_ index: Int, count: Int, around parent: CGFloat) -> CGFloat {
        parent + (CGFloat(index) - CGFloat(count - 1) / 2) * subStep
    }

    /// A point `radius` from `centre` at `angle`, in AppKit coordinates (y up).
    public static func point(at angle: CGFloat, radius: CGFloat, from centre: CGPoint) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: centre.x + radius * sin(radians), y: centre.y + radius * cos(radians))
    }

    /// What the pointer is on. Past the segments it reaches the open sub-ring, if any.
    public static func hit(
        _ point: CGPoint, centre: CGPoint, slots: Int, expanded: Int? = nil, subItems: Int = 0
    ) -> RingHit {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let distance = hypot(dx, dy)
        if distance < centreRadius { return .centre }
        guard slots > 0 else { return .none }
        let angle = normalised(atan2(dx, dy) * 180 / .pi)
        let band = (ringRadius + subRadius) / 2
        if distance <= band {
            let step = 360 / CGFloat(slots)
            return .slot(Int((angle / step).rounded()) % slots)
        }
        guard let expanded, subItems > 0, distance <= subRadius + subStep else { return .none }
        let parent = slotAngle(expanded, count: slots)
        for index in 0..<subItems {
            let target = subAngle(index, count: subItems, around: parent)
            if abs(difference(angle, target)) <= subStep / 2 { return .sub(index) }
        }
        return .none
    }

    /// Moves the ring so its sub-rings stay on screen and, on a Mac with a system island, off
    /// the strip below it.
    public static func fittedCentre(_ requested: CGPoint, in visible: CGRect, avoidsTopCentre: Bool = false)
        -> CGPoint
    {
        let reach = subRadius + subStep + margin
        let usable = visible.insetBy(dx: min(reach, visible.width / 2), dy: min(reach, visible.height / 2))
        var point = CGPoint(
            x: min(max(requested.x, usable.minX), usable.maxX), y: min(max(requested.y, usable.minY), usable.maxY))
        let zone = OrbGeometry.islandZone(in: visible)
        if avoidsTopCentre, abs(point.x - zone.midX) < zone.width / 2 + reach {
            point.y = min(point.y, max(zone.minY - reach, usable.minY))
        }
        return point
    }

    static func normalised(_ angle: CGFloat) -> CGFloat {
        let value = angle.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// The signed shortest turn from `b` to `a`.
    static func difference(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let value = normalised(a - b)
        return value > 180 ? value - 360 : value
    }
}

/// How a press that opened the ring ends. A long hold picks what the pointer is on when it
/// lets go; a quick press leaves the ring open for clicking.
public enum RingGesture {
    public static let holdThreshold: TimeInterval = 0.25

    public enum Outcome: Equatable, Sendable {
        case stayOpen
        case pick(RingHit)
        case close
    }

    public static func release(after held: TimeInterval, on hit: RingHit) -> Outcome {
        guard held >= holdThreshold else { return .stayOpen }
        switch hit {
        case .slot, .sub, .centre: return .pick(hit)
        case .none: return .close
        }
    }
}

/// The extra mouse button that opens the ring.
public enum RingButton: String, CaseIterable, Sendable {
    case off
    case middle
    case back
    case forward

    /// CGEvent's button number; nil when off.
    public var number: Int64? {
        switch self {
        case .off: nil
        case .middle: 2
        case .back: 3
        case .forward: 4
        }
    }

    public var title: String {
        switch self {
        case .off: "Off"
        case .middle: "Middle button"
        case .back: "Back button"
        case .forward: "Forward button"
        }
    }
}

/// What the ring does as the pointer moves and when something is picked.
public enum RingInteraction {
    /// The segment whose sub-ring shows after the pointer moved to `hit`, `distance` from
    /// the centre. Past the segments the pointer is on its way out to the open sub-ring,
    /// whose outer items lie beyond the neighbouring segments, so the sub-ring stays put.
    public static func expanded(
        current: Int?, hit: RingHit, distance: CGFloat, hasSubItems: (Int) -> Bool
    ) -> Int? {
        switch hit {
        case .centre:
            return nil
        case .slot(let index):
            if current != nil, distance >= RingGeometry.ringRadius { return current }
            return hasSubItems(index) ? index : nil
        case .sub, .none:
            return current
        }
    }

    public enum Outcome: Equatable, Sendable {
        case openShelf
        case keepFiles
        /// Shows the segment's sub-ring rather than running anything.
        case expand(Int)
        case run(slot: Int)
        case runSub(slot: Int, item: Int)
        case close
    }

    /// What picking `hit` does. Agents has nothing to run itself, so a first pick opens its
    /// sessions; files dropped on the centre go to the tray.
    public static func outcome(
        of hit: RingHit, slots: [RingSlot], expanded: Int?, subItemCount: Int, hasFiles: Bool
    ) -> Outcome {
        switch hit {
        case .centre:
            return hasFiles ? .keepFiles : .openShelf
        case .slot(let index):
            guard slots.indices.contains(index) else { return .close }
            if slots[index].action.kind == .agents, !hasFiles, expanded != index, subItemCount > 0 {
                return .expand(index)
            }
            return .run(slot: index)
        case .sub(let item):
            guard let expanded, slots.indices.contains(expanded), item < subItemCount else { return .close }
            return .runSub(slot: expanded, item: item)
        case .none:
            return .close
        }
    }
}
