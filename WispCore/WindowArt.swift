import Foundation

/// The scene drawn at the foot of the window's sidebar: a sky that follows the time of day,
/// stars after dark, and ridges stepping down toward the viewer. Everything comes from a
/// seed, so the picture is the same each time it's drawn.
public enum NightRidge {
    public static let layerCount = 4
    /// Heights across the width of each ridge, evenly spaced, left to right: a power of two
    /// plus one, for halving.
    public static let samples = 33

    public struct Layer: Equatable, Sendable {
        /// 0 is the bottom of the scene, 1 the top.
        public let heights: [Double]
        public let colour: RGB
    }

    public struct Star: Equatable, Sendable {
        /// 0 to 1 across the scene.
        public let x: Double
        /// 0 is the top of the scene.
        public let y: Double
        public let size: Double
        public let brightness: Double
    }

    public struct Sky: Equatable, Sendable {
        public let top: RGB
        public let bottom: RGB
        /// The glow rising behind the far ridge, Wisp's flame.
        public let glow: RGB
    }

    public static func sky(hour: Int, isDark: Bool) -> Sky {
        let palette = WindowGreeting.palette(hour: hour, isDark: isDark)
        let night = showsStars(hour: hour, isDark: isDark)
        let violet = RGB(red: 0.48, green: 0.42, blue: 1)
        // After dark the sky leans to Wisp's violet whatever the hour, so a dark morning isn't brown.
        let top = night ? TimeOfDayTint.mix(palette.trailing, base(isDark: true), 0.5) : palette.trailing
        let bottom = isDark ? TimeOfDayTint.mix(palette.leading, scaled(violet, 0.45), 0.5) : palette.leading
        return Sky(top: top, bottom: bottom, glow: RGB(red: 0.62, green: 0.5, blue: 1))
    }

    /// Far ridges are tall, sharp and pale; near ones low, gentle and dark.
    public static func layers(seed: UInt64, hour: Int, isDark: Bool) -> [Layer] {
        var random = SplitMix(seed: seed)
        let sky = sky(hour: hour, isDark: isDark)
        let ground = base(isDark: isDark)
        return (0..<layerCount).map { index in
            let depth = Double(index)
            let middle = 0.6 - depth * 0.14
            let amplitude = 0.15 - depth * 0.03
            let profile = ridgeProfile(&random, roughness: 0.5 + depth * 0.04)
            let heights = profile.map { min(max(middle + amplitude * $0, 0.05), 0.95) }
            let colour = TimeOfDayTint.mix(sky.bottom, ground, 0.3 + depth * 0.22)
            return Layer(heights: heights, colour: colour)
        }
    }

    /// A ridge line from -1 to 1 around a zero mean, by halving and nudging each midpoint
    /// less each time, which gives peaks rather than waves.
    private static func ridgeProfile(_ random: inout SplitMix, roughness: Double) -> [Double] {
        var heights = [Double](repeating: 0, count: samples)
        heights[0] = random.unit() * 2 - 1
        heights[samples - 1] = random.unit() * 2 - 1
        var step = samples - 1
        var scale = 1.0
        while step > 1 {
            let half = step / 2
            for index in stride(from: half, to: samples, by: step) {
                heights[index] = (heights[index - half] + heights[index + half]) / 2 + (random.unit() * 2 - 1) * scale
            }
            scale *= roughness
            step = half
        }
        let mean = heights.reduce(0, +) / Double(samples)
        let centred = heights.map { $0 - mean }
        let peak = centred.map(abs).max() ?? 1
        return centred.map { $0 / max(peak, 0.0001) }
    }

    public static func stars(seed: UInt64, count: Int) -> [Star] {
        var random = SplitMix(seed: seed ^ 0x5157_4152)
        return (0..<max(count, 0)).map { _ in
            Star(
                x: random.unit(), y: random.unit() * 0.6, size: 0.6 + random.unit() * 1.2,
                brightness: 0.35 + random.unit() * 0.65)
        }
    }

    /// Stars come out in Dark mode, and at night in Light mode too.
    public static func showsStars(hour: Int, isDark: Bool) -> Bool {
        isDark || WindowGreeting.greeting(hour: hour) == "Good night"
    }

    private static func scaled(_ colour: RGB, _ amount: Double) -> RGB {
        RGB(red: colour.red * amount, green: colour.green * amount, blue: colour.blue * amount)
    }

    private static func base(isDark: Bool) -> RGB {
        isDark ? RGB(red: 0.04, green: 0.035, blue: 0.08) : RGB(red: 0.3, green: 0.28, blue: 0.46)
    }
}

/// A small seeded generator, so the scene's ridges and stars never move between draws.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 up to but not including 1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }
}

/// The window's own short lines: one in the top bar that changes each day, and one per page
/// over the sidebar's scene.
public enum WindowTaglines {
    public static let lines = [
        "One thing at a time.",
        "Small steps, kept close.",
        "Leave a little room in the day.",
        "Finish one, then the next.",
        "Quiet work is still work.",
        "Make it simple, then make it good.",
        "The list can wait a minute.",
        "Rest is part of the plan.",
        "Notice what's working.",
        "Begin where you are.",
        "Good enough, shipped, beats perfect.",
        "A clear desk, a clear head.",
        "Keep the promise you made today.",
        "Less, but on purpose.",
        "Slow down to see it.",
        "Done is a kind of calm.",
        "Hold it lightly.",
        "Make room for the good part.",
        "Today counts, even the small bits.",
        "Steady beats busy.",
        "Ask once, then listen.",
        "Light the next step only.",
    ]

    /// When a page has no line of its own.
    public static let fallback = "Everything here stays on this Mac."

    /// By the sidebar row's saved name ("page:home", "widget:notes").
    public static let phrases: [String: String] = [
        "page:home": "Your day, at a glance.",
        "page:tray": "Set it down, pick it up later.",
        "page:media": "Something good is playing.",
        "widget:nowPlaying": "Turn it up a little.",
        "widget:calendar": "Room to breathe between things.",
        "widget:reminders": "Off your mind, onto the list.",
        "widget:timer": "Time, made visible.",
        "widget:pomodoro": "Focus now, rest soon.",
        "widget:battery": "Charged and ready.",
        "widget:systemStats": "Everything running smoothly.",
        "widget:weather": "Look up, then out.",
        "widget:notes": "Write it down, let it go.",
        "widget:quickToggles": "One click, done.",
        "widget:shortcuts": "Teach it once, run it often.",
        "widget:clipboard": "Everything you copied, kept close.",
        "widget:mirror": "Check your hair, then the call.",
        "widget:dayProgress": "Most of the day is still ahead.",
        "widget:worldClocks": "Somewhere, it's a good time.",
        "widget:agents": "Let the agents do the typing.",
        "widget:script": "Your own little machine.",
        "widget:quickInput": "Say it plainly, Wisp sorts it.",
    ]

    public static func line(for date: Date, calendar: Calendar) -> String {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return lines[day % lines.count]
    }

    public static func phrase(for destination: WindowDestination) -> String {
        phrases[destination.rawValue] ?? fallback
    }
}
