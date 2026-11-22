import AppKit
import EventKit
import SwiftUI
import WispCore

/// The calendar in the window: today and the next six days as an hour grid (Week), one day's
/// grid (Day) or a list (Agenda). Clicking an event opens it in Calendar.
struct CalendarPage: View {
    let store: CalendarStore
    let preferences: Preferences
    /// The day the Day layout shows; nil is today.
    @State private var day: Date?

    var body: some View {
        WindowPageFrame {
            WindowPageHeader(
                symbol: "calendar", tint: .red, title: "Calendar", subtitle: "Today and the next six days",
                count: store.access == .fullAccess && store.loaded ? countText : nil
            ) {
                if preferences.calendarLayout == .day, store.access == .fullAccess {
                    dayButtons
                }
                Picker("Layout", selection: Bindable(preferences).calendarLayout) {
                    ForEach(CalendarLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("Open Calendar", systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
                .labelStyle(.iconOnly)
                .help("Open Calendar")
            }
        } content: {
            content
        }
        .onAppear { store.refreshIfStale() }
    }

    /// Previous day, Today and next day for the Day layout, with ⌘←, ⌘T and ⌘→.
    @ViewBuilder private var dayButtons: some View {
        let days = WeekStrip.days(from: .now, calendar: .current)
        let index = day.flatMap { day in days.firstIndex { Calendar.current.isDate($0, inSameDayAs: day) } } ?? 0
        ControlGroup {
            Button("Previous day", systemImage: "chevron.left") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(index == 0)
                .help("Previous day")
            Button("Next day", systemImage: "chevron.right") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(index >= days.count - 1)
                .help("Next day")
        }
        .labelStyle(.iconOnly)
        .fixedSize()
        Button("Today") { day = nil }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(day == nil)
    }

    private func step(_ offset: Int) {
        let calendar = Calendar.current
        day = WeekStrip.stepped(day, by: offset, in: WeekStrip.days(from: .now, calendar: calendar), calendar: calendar)
    }

    private var countText: String {
        let count = store.wholeWeek.count
        return count == 1 ? "1 event" : "\(count) events"
    }

    @ViewBuilder private var content: some View {
        if store.access != .fullAccess {
            WindowEmptyState(
                symbol: "calendar", title: "Calendar access needed",
                message: "Allow Calendar to see your week here. Wisp reads your events on this Mac only."
            ) {
                // macOS asks only once; after a denial the switch is in System Settings.
                if store.access == .notDetermined {
                    WindowPrimaryButton(title: "Allow Calendar", symbol: "lock.open") { store.requestAccess() }
                } else {
                    Button("Open System Settings") { Permission.calendars.openSettings() }
                }
            }
            .frame(maxHeight: .infinity)
            .windowCardBackground()
        } else if !store.loaded {
            LoadingLabel("Loading…").windowCardBackground()
        } else {
            switch preferences.calendarLayout {
            case .week:
                HourGrid(store: store, days: WeekStrip.days(from: .now, calendar: .current), preferences: preferences)
            case .day:
                VStack(spacing: 12) {
                    DayPicker(selection: $day)
                    HourGrid(
                        store: store, days: [day ?? Calendar.current.startOfDay(for: .now)],
                        preferences: preferences)
                }
            case .agenda:
                Agenda(store: store)
            }
        }
    }
}

// MARK: Day picker

/// Seven day buttons for the Day layout.
private struct DayPicker: View {
    @Binding var selection: Date?

    var body: some View {
        let days = WeekStrip.days(from: .now, calendar: .current)
        let chosen = selection ?? days.first
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let selected = chosen.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
                Button {
                    selection = day == days.first ? nil : day
                } label: {
                    HStack(spacing: 4) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                        Text(day, format: .dateTime.day()).fontWeight(.semibold)
                    }
                    .font(.callout)
                    .foregroundStyle(selected ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(selected ? Color.wispViolet : .primary.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month(.wide).day()))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Hour grid

/// Days side by side over the hours, events placed by their times and sharing a column where
/// they overlap. All-day events sit in a row above.
private struct HourGrid: View {
    let store: CalendarStore
    let days: [Date]
    let preferences: Preferences

    private static let hourHeight: CGFloat = 52
    private static let gutter: CGFloat = 56
    @State private var width: CGFloat = 0

    private var calendar: Calendar { .current }

    private func events(on day: Date) -> [CalendarStore.Event] {
        store.wholeWeek.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    private var hours: ClosedRange<Int> {
        var timed = days.flatMap(events(on:)).filter { !$0.isAllDay }.map { $0.start...max($0.start, $0.end) }
        // Today's grid reaches the current time, so the now line is on it.
        if days.contains(where: calendar.isDateInToday) { timed.append(Date.now...Date.now) }
        return WeekGrid.hours(
            events: timed, working: preferences.workdayStart...max(preferences.workdayEnd, preferences.workdayStart),
            calendar: calendar)
    }

    private var columnWidth: CGFloat {
        max((width - Self.gutter) / CGFloat(max(days.count, 1)), 40)
    }

    var body: some View {
        let hours = hours
        VStack(spacing: 0) {
            header
            allDayRow
            Divider()
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        lines(hours)
                        HStack(spacing: 0) {
                            Color.clear.frame(width: Self.gutter)
                            ForEach(days, id: \.self) { day in
                                column(day, hours: hours)
                                    .frame(width: columnWidth)
                            }
                        }
                    }
                    .frame(height: CGFloat(hours.count - 1) * Self.hourHeight + 12, alignment: .top)
                    .padding(.top, 6)
                }
                .onAppear {
                    let now = calendar.component(.hour, from: .now)
                    reader.scrollTo(min(max(now - 1, hours.lowerBound), hours.upperBound), anchor: .top)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .padding(.vertical, 8)
        .windowCardBackground()
    }

    private var header: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Self.gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let today = calendar.isDateInToday(day)
                HStack(spacing: 5) {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(Color.secondaryText)
                    Text(day, format: .dateTime.day())
                        .fontWeight(.semibold)
                        .foregroundStyle(today ? .white : .primary)
                        .padding(.horizontal, today ? 7 : 0)
                        .padding(.vertical, today ? 2 : 0)
                        .background(Capsule().fill(today ? Color.wispViolet : .clear))
                }
                .font(.callout)
                .frame(width: columnWidth)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private var allDayRow: some View {
        let allDay = days.map { day in events(on: day).filter(\.isAllDay) }
        if allDay.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("All day").font(.caption).foregroundStyle(Color.secondaryText)
                    .frame(width: Self.gutter - 8, alignment: .trailing)
                    .padding(.trailing, 8)
                ForEach(Array(days.enumerated()), id: \.element) { index, _ in
                    VStack(spacing: 3) {
                        ForEach(allDay[index]) { event in
                            EventBlock(event: event, compact: true) { store.open(event) }
                                .frame(height: 24)
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(width: columnWidth, alignment: .top)
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func lines(_ hours: ClosedRange<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(hours), id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(label(hour))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.secondaryText)
                        .frame(width: Self.gutter - 10, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5)
                }
                .frame(height: hour == hours.upperBound ? 1 : Self.hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func label(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return hour == 24 ? "" : date.formatted(.dateTime.hour())
    }

    private func column(_ day: Date, hours: ClosedRange<Int>) -> some View {
        let timed = events(on: day).filter { !$0.isAllDay }
        let placed = WeekGrid.lanes(timed.map { $0.start...max($0.start, $0.end) })
        let dayStart = calendar.startOfDay(for: day)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(.primary.opacity(0.06)).frame(width: 0.5).frame(maxHeight: .infinity)
            ForEach(Array(timed.enumerated()), id: \.element.id) { index, event in
                let frame = WeekGrid.frame(
                    for: event.start...max(event.start, event.end), dayStart: dayStart, hours: hours,
                    hourHeight: Self.hourHeight)
                let lane = placed[index]
                let laneWidth = (columnWidth - 6) / CGFloat(lane.lanes)
                EventBlock(event: event, compact: frame.height < 40) { store.open(event) }
                    .frame(width: max(laneWidth - 2, 10), height: frame.height - 2)
                    .offset(x: 3 + laneWidth * CGFloat(lane.lane), y: frame.top + 1)
            }
            if calendar.isDateInToday(day) {
                TimelineView(.everyMinute) { context in
                    let top = WeekGrid.frame(
                        for: context.date...context.date, dayStart: dayStart, hours: hours, hourHeight: Self.hourHeight
                    ).top
                    HStack(spacing: 0) {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Rectangle().fill(.red).frame(height: 1.5)
                    }
                    .offset(x: -3, y: top - 3.5)
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// An event in the grid: a tint of its calendar's colour with a bar down the side, its title
/// and time. The text stays the primary colour, so it reads on any calendar colour.
private struct EventBlock: View {
    let event: CalendarStore.Event
    let compact: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.caption.weight(.semibold)).lineLimit(compact ? 1 : 2)
                    if !compact, !event.isAllDay {
                        Text(event.start, format: .dateTime.hour().minute())
                            .font(.caption2).foregroundStyle(Color.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(event.color.opacity(hovering ? 0.34 : 0.22))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(event.title)
        .contextMenu {
            Button("Open in Calendar", action: open)
            if let link = event.link {
                Button("Join Call") { NSWorkspace.shared.open(link) }
            }
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens it in Calendar")
    }

    private var accessibilityText: String {
        guard !event.isAllDay else { return "\(event.title), all day" }
        let format = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(event.title), \(event.start.formatted(format)) to \(event.end.formatted(format))"
    }
}

// MARK: Agenda

/// The week as a list: a card per day with its events.
private struct Agenda: View {
    let store: CalendarStore

    var body: some View {
        ScrollView(.vertical) {
            TimelineView(.everyMinute) { context in
                LazyVStack(alignment: .leading, spacing: WindowLayout.spacing) {
                    ForEach(CalendarDays.week(store.weekEvents, date: \.start, now: context.date), id: \.label) {
                        day in
                        WindowCard(
                            title: day.label, symbol: "calendar", tint: .red,
                            count: day.items.isEmpty ? nil : day.items.count
                        ) {
                            if day.items.isEmpty {
                                Text("Nothing planned").font(.callout).foregroundStyle(Color.secondaryText)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(day.items) { event in
                                        DayEventRow(event: event) { store.open(event) }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: WindowLayout.readableCap)
                .frame(maxWidth: .infinity)
            }
        }
        .windowScrollEdge()
    }
}
