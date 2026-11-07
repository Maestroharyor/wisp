import CoreGraphics
import Foundation

/// What a window region watch waits for.
public enum RegionWatchRule: Equatable, Sendable {
    /// Anything in the region looks different from when the watch started.
    case changed
    /// The region shows this text, ignoring case and accents.
    case containsText(String)
    /// The region changed, then held still for this many seconds.
    case stoppedChanging(seconds: TimeInterval)

    /// Only the text rule reads the region with OCR; the others compare pixels.
    public var needsText: Bool {
        if case .containsText = self { true } else { false }
    }

    /// The watch pill's short description.
    public var summary: String {
        switch self {
        case .changed: "Any change"
        case .containsText(let text): "Shows “\(text)”"
        case .stoppedChanging(let seconds): "Still for \(Self.duration(seconds))"
        }
    }

    /// What the alert says once the rule fires.
    public var firedText: String {
        switch self {
        case .changed: "Changed"
        case .containsText(let text): "Shows “\(text)”"
        case .stoppedChanging: "Stopped changing"
        }
    }

    /// OCR splits text over lines, so line breaks and runs of spaces count as one space.
    public func matches(text: String) -> Bool {
        guard case .containsText(let needle) = self else { return false }
        let wanted = Self.collapsed(needle)
        guard !wanted.isEmpty else { return false }
        return Self.collapsed(text).range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return whole < 60 ? "\(whole) s" : "\(Int((Double(whole) / 60).rounded())) min"
    }
}

/// A small grayscale copy of the region, enough to tell whether it changed.
public struct LuminanceFrame: Equatable, Sendable {
    /// A square region is drawn at this size; long thin ones keep more of their short side.
    public static let longSide: CGFloat = 128
    public static let minimumShortSide: CGFloat = 16
    public static let pixelBudget = 128 * 128
    /// A change needs at least this many pixels, and this share of a big region.
    public static let minimumChangedPixels = 6
    public static let changedShare = 0.001

    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The pixel size to draw a region of this many points at: about 128 on the long side,
    /// at least 16 on the short side so a one-line status bar keeps its text legible,
    /// never upscaled and never over the pixel budget.
    public static func gridSize(for points: CGSize) -> CGSize {
        let long = max(points.width, points.height)
        let short = min(points.width, points.height)
        guard short > 0 else { return CGSize(width: 1, height: 1) }
        var scale = min(1, max(longSide / long, minimumShortSide / short))
        let area = points.width * points.height
        if area * scale * scale > CGFloat(pixelBudget) { scale = (CGFloat(pixelBudget) / area).squareRoot() }
        return CGSize(
            width: max(1, (points.width * scale).rounded()), height: max(1, (points.height * scale).rounded()))
    }

    /// Pixels that moved more than `tolerance` levels, so scaling noise and subpixel shimmer
    /// don't count.
    /// Pixels flagged in `ignoring` (blinking ones) are skipped; an empty mask skips none.
    public func changedPixels(from other: LuminanceFrame, ignoring mask: [Bool] = [], tolerance: UInt8 = 24) -> Int {
        guard width == other.width, height == other.height else { return pixels.count }
        let masked = mask.count == pixels.count
        var count = 0
        for index in pixels.indices where !(masked && mask[index]) {
            if Self.differ(pixels[index], other.pixels[index], tolerance: tolerance) { count += 1 }
        }
        return count
    }

    /// Judged on the region's own size, so one digit in a status line counts while a speck
    /// in a large panel doesn't. A different size (the window shrank) always counts.
    public func isChanged(from other: LuminanceFrame, ignoring mask: [Bool] = []) -> Bool {
        guard width == other.width, height == other.height else { return true }
        let needed = max(Self.minimumChangedPixels, Int((Double(pixels.count) * Self.changedShare).rounded(.up)))
        return changedPixels(from: other, ignoring: mask) >= needed
    }

    /// Pixels that changed and then flipped back over three frames in a row, such as a
    /// blinking text cursor. Nil when the frames aren't all the same size.
    public static func flickering(
        older: LuminanceFrame, previous: LuminanceFrame, current: LuminanceFrame, tolerance: UInt8 = 24
    ) -> [Bool]? {
        guard older.width == current.width, older.height == current.height, previous.width == current.width,
            previous.height == current.height
        else { return nil }
        return current.pixels.indices.map { index in
            let before = older.pixels[index]
            let between = previous.pixels[index]
            let now = current.pixels[index]
            return !differ(before, now, tolerance: tolerance) && differ(before, between, tolerance: tolerance)
                && differ(between, now, tolerance: tolerance)
        }
    }

    private static func differ(_ first: UInt8, _ second: UInt8, tolerance: UInt8) -> Bool {
        (first > second ? first - second : second - first) > tolerance
    }
}

/// One look at the region: its pixels, its text when the rule reads text, and when.
public struct RegionWatchSample: Sendable {
    public let frame: LuminanceFrame
    public let text: String?
    public let time: Date

    public init(frame: LuminanceFrame, text: String?, time: Date) {
        self.frame = frame
        self.text = text
        self.time = time
    }
}

public enum RegionWatchOutcome: Equatable, Sendable {
    case watching
    case fired
}

/// Decides when a rule fires from a run of samples. Changed and text rules need two matching
/// samples in a row, so a tooltip or a misread for one frame doesn't fire them. Pixels seen
/// to flip back (a blinking cursor) are left out of every comparison from then on, so they
/// neither fire "changed" nor keep "stopped changing" from ever firing.
public struct RegionWatchMonitor: Sendable {
    public static let confirmations = 2

    public let rule: RegionWatchRule
    private var baseline: LuminanceFrame?
    private var older: LuminanceFrame?
    private var previous: LuminanceFrame?
    private var flicker: [Bool] = []
    private var streak = 0
    /// The last time the region moved; nil until it has moved once.
    private var lastChange: Date?
    private var fired = false

    public init(rule: RegionWatchRule) {
        self.rule = rule
    }

    public mutating func observe(_ sample: RegionWatchSample) -> RegionWatchOutcome {
        guard !fired else { return .fired }
        updateFlicker(with: sample.frame)
        defer {
            older = previous
            previous = sample.frame
        }
        switch rule {
        case .changed:
            guard let baseline else {
                baseline = sample.frame
                return .watching
            }
            confirm(sample.frame.isChanged(from: baseline, ignoring: flicker))
        case .containsText:
            confirm(sample.text.map(rule.matches(text:)) ?? false)
        case .stoppedChanging(let seconds):
            if let previous, sample.frame.isChanged(from: previous, ignoring: flicker) {
                lastChange = sample.time
            } else if let lastChange, sample.time.timeIntervalSince(lastChange) >= seconds {
                fired = true
            }
        }
        return fired ? .fired : .watching
    }

    /// Picks up after a pause. Time spent paused wasn't watched, so it can't count as still,
    /// and a change half confirmed before the pause has to be seen again.
    public mutating func resume(at time: Date) {
        older = nil
        previous = nil
        streak = 0
        if lastChange != nil { lastChange = time }
    }

    /// Adds pixels that just flipped back. A frame of a new size (the window shrank) starts
    /// the mask over.
    private mutating func updateFlicker(with frame: LuminanceFrame) {
        if flicker.count != frame.pixels.count { flicker = [Bool](repeating: false, count: frame.pixels.count) }
        guard let older, let previous,
            let flipped = LuminanceFrame.flickering(older: older, previous: previous, current: frame)
        else { return }
        for index in flipped.indices where flipped[index] { flicker[index] = true }
    }

    private mutating func confirm(_ matched: Bool) {
        streak = matched ? streak + 1 : 0
        if streak >= Self.confirmations { fired = true }
    }
}

/// How often to look, and when to stop looking to save the battery.
public enum RegionWatchSchedule {
    public enum Step: Equatable, Sendable {
        case capture(after: TimeInterval)
        case paused(checkAfter: TimeInterval)
    }

    public static let minimumInterval: TimeInterval = 2
    public static let maximumInterval: TimeInterval = 5
    public static let pausedCheck: TimeInterval = 30
    public static let lowBattery = 20

    /// OCR costs more, so text is read less often. A short "stopped changing" wait needs
    /// tighter sampling to be on time.
    public static func interval(for rule: RegionWatchRule) -> TimeInterval {
        switch rule {
        case .changed: 3
        case .containsText: 4
        case .stoppedChanging(let seconds): min(max((seconds / 3).rounded(), minimumInterval), maximumInterval)
        }
    }

    /// Below 20% on battery power, watching waits until the Mac is plugged in or charged.
    public static func isPaused(battery: BatteryState?) -> Bool {
        guard let battery else { return false }
        return battery.percent < lowBattery && !battery.isCharging && !battery.isPluggedIn
    }

    public static func next(for rule: RegionWatchRule, battery: BatteryState?) -> Step {
        isPaused(battery: battery) ? .paused(checkAfter: pausedCheck) : .capture(after: interval(for: rule))
    }
}

/// A window on screen, front to back as the window server lists them.
public struct WindowCandidate: Equatable, Sendable {
    public let id: UInt32
    public let layer: Int
    /// Global, top-left origin.
    public let frame: CGRect
    public let ownerPID: Int32

    public init(id: UInt32, layer: Int, frame: CGRect, ownerPID: Int32) {
        self.id = id
        self.layer = layer
        self.frame = frame
        self.ownerPID = ownerPID
    }
}

/// Maps a dragged rectangle onto the window under it, and the region onto a capture.
public enum RegionGeometry {
    public static let minimumSide: CGFloat = 8
    public static let maximumCaptureSide: CGFloat = 4000

    /// AppKit's bottom-left global rect in the window server's top-left space.
    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The selection as an offset and size in points from the window's top-left corner,
    /// clipped to the window, so resizing the window keeps it on the same content.
    /// Nil when too little of it falls on the window.
    public static func region(_ selection: CGRect, in window: CGRect) -> CGRect? {
        let clipped = selection.intersection(window)
        guard !clipped.isNull, clipped.width >= minimumSide, clipped.height >= minimumSide else { return nil }
        return clipped.offsetBy(dx: -window.minX, dy: -window.minY)
    }

    /// The part of the region still inside a window of this size; nil once it has shrunk away.
    public static func sourceRect(_ region: CGRect, windowSize: CGSize) -> CGRect? {
        let clipped = region.intersection(CGRect(origin: .zero, size: windowSize))
        guard !clipped.isNull, clipped.width >= minimumSide, clipped.height >= minimumSide else { return nil }
        return clipped
    }

    /// Full display resolution for OCR, capped on the long side.
    public static func textCaptureSize(for points: CGSize, scale: CGFloat) -> CGSize {
        let longest = max(points.width, points.height) * scale
        let fitted = longest > maximumCaptureSide ? scale * maximumCaptureSide / longest : scale
        return CGSize(width: (points.width * fitted).rounded(), height: (points.height * fitted).rounded())
    }

    /// The frontmost ordinary window under a point, skipping Wisp's own windows.
    public static func topWindow(at point: CGPoint, in windows: [WindowCandidate], excluding pid: Int32)
        -> WindowCandidate?
    {
        windows.first { $0.layer == 0 && $0.ownerPID != pid && $0.frame.contains(point) }
    }
}
