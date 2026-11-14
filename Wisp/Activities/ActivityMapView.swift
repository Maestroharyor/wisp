import SwiftUI
import WispCore

/// A year of agent use, one square per day in Wisp violet steps, with each day's count per agent
/// in its tooltip (`ActivityMap`). Sits in the history and on the Agents window page.
struct ActivityMapView: View, Equatable {
    let map: ActivityMap

    /// Its hosts redraw several times a second while agents work; the grid only needs to when the counts change.
    nonisolated static func == (lhs: ActivityMapView, rhs: ActivityMapView) -> Bool { lhs.map == rhs.map }

    @State private var metric: ActivityMetric = .turns

    private static let gap: CGFloat = 2
    private static let largestCell: CGFloat = 11

    var body: some View {
        TimelineView(.everyMinute) { context in
            let grid = map.grid(endingOn: context.date, metric: metric)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Activity").font(.system(size: 11, weight: .semibold))
                    Text("\(metric.phrase(grid.total)) in the last year")
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Picker("Count", selection: $metric) {
                        ForEach(ActivityMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .fixedSize()
                }
                ActivityGridView(grid: grid, metric: metric)
            }
        }
    }

    /// The grid at its largest cells.
    static func widest(weeks: Int) -> CGFloat {
        CGFloat(weeks) * largestCell + CGFloat(max(weeks - 1, 0)) * gap
    }

    fileprivate static func cellSize(width: CGFloat, weeks: Int) -> CGFloat {
        guard weeks > 0 else { return largestCell }
        return min(max((width - CGFloat(weeks - 1) * gap) / CGFloat(weeks), 2), largestCell)
    }
}

private struct ActivityGridView: View {
    let grid: ActivityGrid
    let metric: ActivityMetric

    var body: some View {
        GeometryReader { proxy in
            let cell = ActivityMapView.cellSize(width: proxy.size.width, weeks: grid.columns.count)
            HStack(alignment: .top, spacing: 2) {
                ForEach(Array(grid.columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 2) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            ActivityCell(day: day, level: grid.level(day), metric: metric, size: cell)
                        }
                    }
                }
            }
        }
        // A week column and a day row are about one cell and gap each, so the grid keeps its shape.
        .aspectRatio(CGFloat(max(grid.columns.count, 1)) / 7, contentMode: .fit)
        .frame(maxWidth: ActivityMapView.widest(weeks: grid.columns.count))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity map")
        .accessibilityValue(
            "\(metric.phrase(grid.total)) in the last year, the busiest day had \(metric.phrase(grid.busiest))")
    }
}

private struct ActivityCell: View {
    let day: ActivityDay
    let level: Int
    let metric: ActivityMetric
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: min(size * 0.25, 2.5), style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .help(day.future ? "" : "\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.summary(metric))")
    }

    private var fill: Color {
        if day.future { return .clear }
        guard level > 0 else { return .ink.opacity(0.08) }
        return Color.wispViolet.opacity(0.2 + 0.8 * Double(level) / Double(ActivityGrid.levels))
    }
}
