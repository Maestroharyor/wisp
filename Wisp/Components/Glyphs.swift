import AppKit
import SwiftUI

/// Short rounded level bar used by volume and brightness.
struct LevelBar: View {
    let value: Double
    let tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(tint).frame(width: max(proxy.size.width * min(max(value, 0), 1), height))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: value)
    }
}

/// Circular progress ring, 0...1.
struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Animated equaliser bars tinted with the artwork colour. Still when paused.
struct Waveform: View {
    let tint: Color
    let playing: Bool
    var barCount = 4
    var barWidth: CGFloat = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth < 3 ? 1.5 : 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: playing ? Self.level(index, time) : 0.25, anchor: .center)
                }
            }
        }
    }

    private static func level(_ index: Int, _ time: TimeInterval) -> CGFloat {
        let speeds = [5.1, 7.3, 6.2, 8.4]
        let phase = Double(index) * 1.7
        let value = (sin(time * speeds[index % speeds.count] + phase) + 1) / 2
        return CGFloat(0.3 + value * 0.7)
    }
}

/// Album art or a placeholder.
struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(
                        .white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Monospaced value text coloured by meaning.
struct ValueText: View {
    let text: String
    var tint: Color = .white
    var size: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

/// Round icon button used across the shelf.
struct ShelfButton: View {
    let symbol: String
    var size: CGFloat = 13
    var tint: Color = .white
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size + 15, height: size + 15)
                .background(Circle().fill(.white.opacity(hovering ? 0.16 : 0.0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension ShapeStyle where Self == Color {
    static var wispAmber: Color { Color(red: 1, green: 0.72, blue: 0.2) }
    static var wispGreen: Color { Color(red: 0.3, green: 0.85, blue: 0.4) }
    static var secondaryText: Color { Color.white.opacity(0.55) }
}
