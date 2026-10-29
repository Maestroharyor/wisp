import Foundation

/// Synthesises a watch-crown ratchet click: a very short burst of bright noise (the
/// pawl striking) plus a small metallic ring that dies within a few milliseconds.
/// Deterministic, so it sounds identical every time and can be tested.
public enum ClickSynth {
    public static let duration: Double = 0.03
    public static let minorPeak: Float = 0.35
    public static let majorPeak: Float = 0.6

    public static func samples(sampleRate: Double, major: Bool) -> [Float] {
        let count = Int(sampleRate * duration)
        var generator = LinearCongruential(seed: major ? 7 : 3)
        // Major ticks ring a little lower and longer, like the detent at each notch.
        let ringFrequency = major ? 3_900.0 : 4_800.0
        let ringDecay = major ? 1_100.0 : 1_500.0
        let noiseDecay = 2_600.0

        var previous: Float = 0
        var raw = (0..<count).map { index -> Float in
            let time = Double(index) / sampleRate
            // High-passed noise burst: the dry "tk".
            let noise = Float(generator.nextUnit() * 2 - 1)
            let bright = noise - previous * 0.85
            previous = noise
            let burst = bright * Float(exp(-time * noiseDecay))
            // Tiny metallic ring.
            let ring = Float(sin(2 * Double.pi * ringFrequency * time) * exp(-time * ringDecay)) * 0.6
            return burst + ring
        }

        let peak = raw.map(abs).max() ?? 1
        let target = major ? majorPeak : minorPeak
        if peak > 0 { raw = raw.map { $0 / peak * target } }
        return raw
    }
}

/// Small deterministic PRNG so the click is reproducible.
private struct LinearCongruential {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
