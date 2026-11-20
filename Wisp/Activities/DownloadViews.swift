import AppKit
import SwiftUI
import WispCore

/// A ring while the total is known; otherwise an arrow (AirDrop's waves for an AirDrop), since a
/// guessed ring would lie.
struct DownloadGlyph: View {
    let progress: DownloadProgress
    var origin: DownloadOrigin = .browser
    var size: CGFloat = 16

    var body: some View {
        let tint = progress.isStalled ? Color.secondaryText : Color.wispViolet
        if let fraction = progress.fraction {
            ProgressRing(progress: fraction, tint: tint, lineWidth: 2.5)
                .frame(width: size, height: size)
        } else {
            Image(systemName: progress.isStalled ? "pause.circle" : symbol)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

    private var symbol: String {
        switch origin {
        case .browser: "arrow.down.circle"
        case .airDrop: AirDropGlyph.symbol
        }
    }
}

/// AirDrop's mark where a one-colour glyph fits (buttons, tiles, the ring). SF Symbols has no
/// AirDrop symbol, and this one has its dot and waves.
enum AirDropGlyph {
    static let symbol = "dot.radiowaves.up.forward"
}

/// The pill's value: percent, speed or size, and how many more are running.
struct DownloadValue: View {
    let summary: DownloadSummary

    var body: some View {
        HStack(spacing: 4) {
            if summary.count > 1 {
                Text("+\(summary.count - 1)").foregroundStyle(Color.secondaryText)
            }
            ValueText(
                text: DownloadText.detail(summary.primary),
                tint: summary.primary.isStalled ? Color.secondaryText : .ink)
        }
        .lineLimit(1)
    }
}

/// "Downloaded" under the notch, with Show in Finder and Open.
struct DownloadDoneCard: View {
    let download: FinishedDownload
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    Text(download.name).font(.system(size: 13, weight: .bold)).lineLimit(1).truncationMode(.middle)
                    Text("\(caption), \(DownloadText.bytes(download.size))")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                }
                Spacer(minLength: 8)
                if download.itemCount > 1 {
                    // Several files: their folder is the one thing to open.
                    CapsuleButton("Show in Finder", prominent: true) {
                        NSWorkspace.shared.open(url)
                        model.services.activities.remove(.downloadDone)
                    }
                } else {
                    CapsuleButton("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        model.services.activities.remove(.downloadDone)
                    }
                    CapsuleButton("Open", prominent: true) {
                        NSWorkspace.shared.open(url)
                        model.services.activities.remove(.downloadDone)
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
        .overlay(alignment: .topTrailing) { CardCloseGlyph(model: model) }
    }

    private var url: URL { URL(fileURLWithPath: download.path) }

    private var caption: String {
        switch download.origin {
        case .browser: "Downloaded"
        case .airDrop: "Received with AirDrop"
        }
    }

    @ViewBuilder private var icon: some View {
        if download.origin == .airDrop, let airDrop = AppIcon.airDrop {
            Image(nsImage: airDrop).resizable().frame(width: 38, height: 38)
        } else {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.wispViolet)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.wispViolet.opacity(0.18)))
        }
    }
}
