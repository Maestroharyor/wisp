import AppKit
import SwiftUI
import WispCore

/// A ring while the total is known; otherwise an arrow, since a guessed ring would lie.
struct DownloadGlyph: View {
    let progress: DownloadProgress
    var size: CGFloat = 16

    var body: some View {
        let tint = progress.isStalled ? Color.secondaryText : Color.wispViolet
        if let fraction = progress.fraction {
            ProgressRing(progress: fraction, tint: tint, lineWidth: 2.5)
                .frame(width: size, height: size)
        } else {
            Image(systemName: progress.isStalled ? "pause.circle" : "arrow.down.circle")
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }
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
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.wispViolet)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.wispViolet.opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(download.name).font(.system(size: 13, weight: .bold)).lineLimit(1).truncationMode(.middle)
                    Text("Downloaded, \(DownloadText.bytes(download.size))")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                }
                Spacer(minLength: 8)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    model.services.activities.remove(.downloadDone)
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(.ink.opacity(0.14)))
                Button("Open") {
                    NSWorkspace.shared.open(url)
                    model.services.activities.remove(.downloadDone)
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 28)
                .background(Capsule().fill(Color.wispViolet))
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
        .overlay(alignment: .topTrailing) { CardCloseGlyph(model: model) }
    }

    private var url: URL { URL(fileURLWithPath: download.path) }
}
