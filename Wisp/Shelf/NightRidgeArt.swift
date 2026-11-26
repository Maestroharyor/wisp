import SwiftUI
import WispCore

/// The scene at the foot of the window's sidebar: a sky for the time of day, stars after dark,
/// Wisp's violet glow behind the far ridge and ridges stepping down toward the viewer.
/// Drawn, never loaded from an image, so it follows Light and Dark at any size.
struct NightRidgeArt: View {
    /// Which ridges and stars; the same seed always draws the same scene.
    var seed: UInt64 = 11

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.everyMinute) { context in
            let hour = Calendar.current.component(.hour, from: context.date)
            let isDark = scheme == .dark
            Canvas { canvas, size in
                draw(in: &canvas, size: size, hour: hour, isDark: isDark)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, hour: Int, isDark: Bool) {
        let rect = CGRect(origin: .zero, size: size)
        let sky = NightRidge.sky(hour: hour, isDark: isDark)
        canvas.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [Color(rgb: sky.top), Color(rgb: sky.bottom)]), startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)))
        if NightRidge.showsStars(hour: hour, isDark: isDark) {
            for star in NightRidge.stars(seed: seed, count: 26) {
                let dot = CGRect(
                    x: star.x * size.width, y: star.y * size.height, width: star.size, height: star.size)
                canvas.fill(Path(ellipseIn: dot), with: .color(.white.opacity(star.brightness * 0.8)))
            }
        }
        let layers = NightRidge.layers(seed: seed, hour: hour, isDark: isDark)
        // The flame's glow sits between the far ridge and the rest, low and wide.
        let glowCentre = CGPoint(x: size.width * 0.62, y: size.height * 0.5)
        for (index, layer) in layers.enumerated() {
            canvas.fill(ridge(layer.heights, in: size), with: .color(Color(rgb: layer.colour)))
            if index == 0 {
                canvas.fill(
                    Path(rect),
                    with: .radialGradient(
                        Gradient(colors: [Color(rgb: sky.glow).opacity(isDark ? 0.55 : 0.4), .clear]),
                        center: glowCentre, startRadius: 0, endRadius: size.width * 0.55))
            }
            // A little fog between ridges, so they read as distance rather than paper cut-outs.
            if index < layers.count - 1 {
                canvas.fill(
                    ridge(layer.heights.map { $0 - 0.04 }, in: size),
                    with: .linearGradient(
                        Gradient(colors: [Color(rgb: sky.bottom).opacity(0.25), .clear]),
                        startPoint: CGPoint(x: 0, y: size.height * 0.3), endPoint: CGPoint(x: 0, y: size.height)))
            }
        }
    }

    /// A filled ridge through `heights`, straight between points so the peaks stay sharp.
    private func ridge(_ heights: [Double], in size: CGSize) -> Path {
        Path { path in
            guard heights.count > 1 else { return }
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, height) in heights.enumerated() {
                path.addLine(
                    to: CGPoint(
                        x: size.width * Double(index) / Double(heights.count - 1), y: size.height * (1 - height)))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }
}
