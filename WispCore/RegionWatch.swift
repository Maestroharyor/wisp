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

    /// The rule in a sentence, for the watch view.
    public var plainDescription: String {
        switch self {
        case .changed: "Tells you when anything in it changes"
        case .containsText(let text): "Tells you when it shows “\(text)”"
        case .stoppedChanging(let seconds): "Tells you when it changes, then stays still for \(Self.duration(seconds))"
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

/// The watch view's times, to the minute: the view only refreshes every 15 seconds, so
/// seconds would be stale.
public enum RegionWatchText {
    /// How long the watch has been running.
    public static func watching(since start: Date, now: Date) -> String {
        minutes(now.timeIntervalSince(start)) ?? "Under a minute"
    }

    /// When the region last moved, if it has since the watch began.
    public static func lastChange(_ date: Date?, now: Date) -> String {
        guard let date else { return "No change seen yet" }
        return minutes(now.timeIntervalSince(date)).map { "\($0) ago" } ?? "Just now"
    }

    /// "5 min", "1 h 20 min", "2 h"; nil under a minute.
    private static func minutes(_ seconds: TimeInterval) -> String? {
        let total = Int(max(0, seconds)) / 60
        guard total > 0 else { return nil }
        let hours = total / 60
        let rest = total % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
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

    /// Judged on the region's own size (less any masked pixels), so one digit in a status line
    /// counts while a speck in a large panel doesn't. A different size (the window shrank)
    /// always counts.
    public func isChanged(from other: LuminanceFrame, ignoring mask: [Bool] = []) -> Bool {
        guard width == other.width, height == other.height else { return true }
        let masked = mask.count == pixels.count ? mask.filter { $0 }.count : 0
        let watched = pixels.count - masked
        let needed = max(Self.minimumChangedPixels, Int((Double(watched) * Self.changedShare).rounded(.up)))
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

/// Pixels that keep flipping back, such as a blinking cursor, to leave out of comparisons.
/// Kept small and short-lived so content that is really moving (a scrolling log) can't hide
/// in it: a pixel is masked only after two flips, forgotten after `memory` samples without
/// one, and if more than 2% of the region (or one cursor, in a small region) would be masked
/// the mask is cleared and the flicker counts as a real change.
public struct FlickerMask: Equatable, Sendable {
    public static let flipsNeeded = 2
    public static let memory = 10
    public static let maximumShare = 0.02
    /// A text cursor with room to spare, in points.
    public static let cursorArea = CGSize(width: 10, height: 20)

    public private(set) var mask: [Bool] = []
    private var flips: [Int] = []
    private var lastFlip: [Int] = []
    private var sample = 0

    public init() {}

    /// The pixels one cursor covers at a grid scale of `pointsPerPixel`, so a cursor in a
    /// small region (a 200 x 20 pt prompt line) is still masked rather than counted as change.
    public static func cursorFloor(pointsPerPixel: CGFloat) -> Int {
        guard pointsPerPixel > 0 else { return 0 }
        return Int((cursorArea.width * cursorArea.height / (pointsPerPixel * pointsPerPixel)).rounded(.up))
    }

    /// Records one sample's flipped pixels (nil when there's nothing to compare yet).
    /// Returns true when more flickers than `max(2% of the region, floor)` pixels.
    public mutating func record(_ flipped: [Bool]?, pixelCount: Int, floor: Int = 0) -> Bool {
        if mask.count != pixelCount { clear(pixelCount) }
        sample += 1
        if let flipped, flipped.count == pixelCount {
            for index in flipped.indices where flipped[index] {
                flips[index] += 1
                lastFlip[index] = sample
            }
        }
        var masked = 0
        for index in 0..<pixelCount {
            if sample - lastFlip[index] > Self.memory { flips[index] = 0 }
            mask[index] = flips[index] >= Self.flipsNeeded
            if mask[index] { masked += 1 }
        }
        guard Double(masked) > max(Double(pixelCount) * Self.maximumShare, Double(floor)) else { return false }
        clear(pixelCount)
        return true
    }

    private mutating func clear(_ pixelCount: Int) {
        mask = [Bool](repeating: false, count: pixelCount)
        flips = [Int](repeating: 0, count: pixelCount)
        lastFlip = [Int](repeating: sample, count: pixelCount)
    }
}

/// One look at the region: its pixels, its text when the rule reads text, and when.
public struct RegionWatchSample: Sendable {
    public let frame: LuminanceFrame
    public let text: String?
    public let time: Date
    /// Region points per frame pixel, for sizing things in points (a cursor) on the frame.
    public let pointsPerPixel: CGFloat

    public init(frame: LuminanceFrame, text: String?, time: Date, pointsPerPixel: CGFloat = 1) {
        self.frame = frame
        self.text = text
        self.time = time
        self.pointsPerPixel = pointsPerPixel
    }
}

public enum RegionWatchOutcome: Equatable, Sendable {
    case watching
    case fired
}

/// Decides when a rule fires from a run of samples. Changed and text rules need two matching
/// samples in a row, so a tooltip or a misread for one frame doesn't fire them. A blinking
/// cursor is kept out through `FlickerMask`, so it neither fires "changed" nor keeps "stopped
/// changing" from firing.
public struct RegionWatchMonitor: Sendable {
    public static let confirmations = 2

    public let rule: RegionWatchRule
    private var baseline: LuminanceFrame?
    private var older: LuminanceFrame?
    private var previous: LuminanceFrame?
    private var flicker = FlickerMask()
    private var streak = 0
    /// The last time the region moved; nil until it has moved once.
    private var lastChange: Date?
    /// When a sample last differed from the one before, for every rule. Unlike `lastChange`,
    /// resuming never moves it, so it is only ever a change that was seen.
    public private(set) var lastMovement: Date?
    private var fired = false

    public init(rule: RegionWatchRule) {
        self.rule = rule
    }

    public mutating func observe(_ sample: RegionWatchSample) -> RegionWatchOutcome {
        guard !fired else { return .fired }
        let flipped = older.flatMap { older in
            previous.flatMap { LuminanceFrame.flickering(older: older, previous: $0, current: sample.frame) }
        }
        let flickersTooMuch = flicker.record(
            flipped, pixelCount: sample.frame.pixels.count,
            floor: FlickerMask.cursorFloor(pointsPerPixel: sample.pointsPerPixel))
        defer {
            older = previous
            previous = sample.frame
        }
        // A pixel going back to what it was two samples ago isn't movement on its own, so
        // a cursor doesn't count before it has flipped enough to be masked.
        let ignored = zip(flicker.mask, flipped ?? flicker.mask).map { $0 || $1 }
        let moved =
            flickersTooMuch || (previous.map { sample.frame.isChanged(from: $0, ignoring: ignored) } ?? false)
        if moved { lastMovement = sample.time }
        switch rule {
        case .changed:
            guard let baseline else {
                baseline = sample.frame
                return .watching
            }
            confirm(flickersTooMuch || sample.frame.isChanged(from: baseline, ignoring: flicker.mask))
        case .containsText:
            confirm(sample.text.map(rule.matches(text:)) ?? false)
        case .stoppedChanging(let seconds):
            if moved {
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
