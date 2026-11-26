import AppKit
import EventKit
import SwiftUI
import WispCore

/// The calendar in the window: a week as an hour grid (Week), one day's grid (Day) or a list
/// (Agenda), starting from today and the next six days. ⌘← and ⌘→ browse other weeks (days in
/// Day). Clicking an event opens it in Calendar.
struct CalendarPage: View {
    let store: CalendarStore
    let preferences: Preferences
    /// The day the page is on; nil is today. Week and Agenda show this day's week.
    @State private var anchor: Date?

    private var calendar: Calendar { .current }
    private var layout: CalendarLayout { preferences.calendarLayout }
    private var anchorDay: Date { calendar.startOfDay(for: anchor ?? .now) }
    private var weekStart: Date { WeekStrip.weekStart(of: anchorDay, calendar: calendar) }

    /// Whether today's cached week covers what's shown, so the page reads it as it always has.
    private var showsComingWeek: Bool {
        switch layout {
        case .day: WeekStrip.isInComingWeek(anchorDay, now: .now, calendar: calendar)
        case .week, .agenda: weekStart == WeekStrip.weekStart(of: .now, calendar: calendar)
        }
    }

    /// The week read into the store's browsed cache when the coming week doesn't cover it.
    private var browseStart: Date? { showsComingWeek ? nil : weekStart }

    private var browseLoaded: Bool { browseStart == nil || store.browsedStart == browseStart }

    /// The events of the shown week, finished ones included.
    private var shownEvents: [CalendarStore.Event] {
        guard browseStart != nil else { return store.wholeWeek }
        return browseLoaded ? store.browsed : []
    }

    /// The seven days shown: today onwards for the coming week, otherwise the anchor's week.
    private var shownDays: [Date] {
        WeekStrip.days(from: showsComingWeek ? .now : weekStart, calendar: calendar)
    }

    private var atToday: Bool { layout == .day ? anchor == nil : showsComingWeek }

    private var subtitle: String {
        showsComingWeek
            ? "Today and the next six days" : WeekStrip.title(weekStart: weekStart, now: .now, calendar: calendar)
    }

    var body: some View {
        WindowPageFrame {
            WindowPageHeader(
                symbol: "calendar", tint: .red, title: "Calendar", subtitle: subtitle,
                count: store.access == .fullAccess && store.loaded && browseLoaded ? countText : nil
            ) {
                if store.access == .fullAccess {
                    stepButtons
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
            content.wispAnimation(.wispSmooth, value: preferences.calendarLayout)
        }
        .onAppear { store.refreshIfStale() }
        .onChange(of: browseStart, initial: true) { _, start in
            if let start { store.browse(weekStarting: start) } else { store.stopBrowsing() }
        }
        .onDisappear { store.stopBrowsing() }
    }

    /// Previous, Today and next: a day at a time in Day, a week in Week and Agenda, with ⌘←,
    /// ⌘T and ⌘→.
    @ViewBuilder private var stepButtons: some View {
        let unit = layout == .day ? "day" : "week"
        ControlGroup {
            Button("Previous \(unit)", systemImage: "chevron.left") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help("Previous \(unit)")
            Button("Next \(unit)", systemImage: "chevron.right") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("Next \(unit)")
        }
        .labelStyle(.iconOnly)
        .fixedSize()
        Button("Today") { anchor = nil }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(atToday)
    }

    private func step(_ offset: Int) {
        if layout == .day {
            let day = calendar.date(byAdding: .day, value: offset, to: anchorDay) ?? anchorDay
            anchor = calendar.isDateInToday(day) ? nil : day
        } else {
            let start = WeekStrip.steppedWeek(weekStart, by: offset, calendar: calendar)
            anchor = start == WeekStrip.weekStart(of: .now, calendar: calendar) ? nil : start
        }
    }

    private var countText: String {
        let count = shownEvents.count
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
        } else if !store.loaded || !browseLoaded {
            LoadingLabel("Loading…").windowCardBackground()
        } else {
            layoutView
                .id(preferences.calendarLayout)
                .wispTransition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder private var layoutView: some View {
        Group {
            switch layout {
            case .week:
                if shownEvents.isEmpty {
                    WindowEmptyState(
                        symbol: "calendar.badge.checkmark", title: "A clear week",
                        message: showsComingWeek
                            ? "Nothing on your calendars for the next seven days."
                            : "Nothing on your calendars that week."
                    )
                    .frame(maxHeight: .infinity)
                    .windowCardBackground()
                } else {
                    HourGrid(store: store, events: shownEvents, days: shownDays, preferences: preferences)
                }
            case .day:
                VStack(spacing: 12) {
                    DayPicker(days: shownDays, selection: $anchor)
                    HourGrid(store: store, events: shownEvents, days: [anchorDay], preferences: preferences)
                }
            case .agenda:
                Agenda(store: store, events: showsComingWeek ? nil : shownEvents, start: weekStart)
            }
        }
    }
}

// MARK: Day picker

/// The shown week's day buttons for the Day layout.
private struct DayPicker: View {
    let days: [Date]
    /// The chosen day; nil is today.
    @Binding var selection: Date?

    var body: some View {
        let calendar = Calendar.current
        let chosen = selection ?? calendar.startOfDay(for: .now)
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let selected = calendar.isDate(chosen, inSameDayAs: day)
                Button {
                    selection = calendar.isDateInToday(day) ? nil : day
                } label: {
                    HStack(spacing: 4) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                        Text(day, format: .dateTime.day()).fontWeight(.semibold)
                    }
                    .wispFont(.callout)
                    .foregroundStyle(selected ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .wispHover(shape: Capsule())
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
    /// The shown week's events, finished ones included.
    let events: [CalendarStore.Event]
    let days: [Date]
    let preferences: Preferences

    private static let hourHeight: CGFloat = 52
    private static let gutter: CGFloat = 56
    @State private var width: CGFloat = 0

    private var calendar: Calendar { .current }

    private func events(on day: Date) -> [CalendarStore.Event] {
        events.filter { calendar.isDate($0.start, inSameDayAs: day) }
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
                .wispFont(.callout)
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
                Text("All day").wispFont(.caption).foregroundStyle(Color.secondaryText)
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
                        .wispFont(.caption).monospacedDigit()
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
                    Text(event.title).wispFont(.caption, weight: .semibold).lineLimit(compact ? 1 : 2)
                    if !compact, !event.isAllDay {
                        Text(event.start, format: .dateTime.hour().minute())
                            .wispFont(.caption2).foregroundStyle(Color.secondaryText)
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
    /// Another week's events; nil lists what's still to come from today, as before.
    let events: [CalendarStore.Event]?
    /// The first day of the browsed week.
    let start: Date

    var body: some View {
        ScrollView(.vertical) {
            TimelineView(.everyMinute) { context in
                LazyVStack(alignment: .leading, spacing: WindowLayout.spacing) {
                    ForEach(days(now: context.date), id: \.label) { day in
                        WindowCard(
                            title: day.label, symbol: "calendar", tint: .red,
                            count: day.items.isEmpty ? nil : day.items.count
                        ) {
                            if day.items.isEmpty {
                                Text("Nothing planned").wispFont(.callout).foregroundStyle(Color.secondaryText)
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

    private func days(now: Date) -> [CalendarDays.Day<CalendarStore.Event>] {
        guard let events else { return CalendarDays.week(store.weekEvents, date: \.start, now: now) }
        return CalendarDays.week(events, date: \.start, start: start, now: now)
    }
}
