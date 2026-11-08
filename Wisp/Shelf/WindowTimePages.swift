import EventKit
import SwiftUI
import WispCore

// MARK: Day Progress

/// Day Progress in the window: the percentage and time left, a timeline of the working day
/// with today's events on it, and the events still to come.
struct DayProgressPage: View {
    let calendar: CalendarStore
    @Bindable var preferences: Preferences

    @State private var editingHours = false

    var body: some View {
        WindowWidgetPage { width in
            TimelineView(.everyMinute) { context in
                let day = DayProgress(startHour: preferences.workdayStart, endHour: preferences.workdayEnd)
                VStack(alignment: .leading, spacing: 28) {
                    hero(day, now: context.date)
                    DayTimeline(
                        day: day, now: context.date, events: calendar.todayEvents.filter { !$0.isAllDay },
                        width: width, open: calendar.open)
                    events(now: context.date)
                }
                // A page left open past midnight reads the new day's events.
                .onChange(of: Calendar.current.startOfDay(for: context.date)) { calendar.refreshIfStale() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Working hours", systemImage: "clock") { editingHours = true }
                    .help("Working hours")
                    .popover(isPresented: $editingHours, arrowEdge: .bottom) { hoursEditor }
            }
        }
        .onAppear { calendar.refreshIfStale() }
    }

    @ViewBuilder private func hero(_ day: DayProgress, now: Date) -> some View {
        let range = "\(hourLabel(day.startHour)) to \(hourLabel(day.endHour))"
        VStack(alignment: .leading, spacing: 6) {
            if day.isWorking(at: now) {
                let left = day.minutesLeft(at: now)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ValueText(text: "\(Int((day.fraction(at: now) * 100).rounded()))%", tint: .wispViolet, size: 48)
                    Text("of the working day").font(.system(size: 15)).foregroundStyle(Color.secondaryText)
                }
                Text("\(DurationText.text(for: TimeInterval(left * 60))) left · \(range)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.ink.opacity(0.85))
            } else {
                let next = day.nextStart(after: now)
                let ended = day.fraction(at: now) >= 1
                Text(ended ? "Done for today" : "Your day hasn't started")
                    .font(.system(size: 28, weight: .semibold))
                Text(
                    "Starts \(Calendar.current.isDateInToday(next) ? "today" : "tomorrow") at \(next.formatted(date: .omitted, time: .shortened)) · \(range)"
                )
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.secondaryText)
            }
        }
    }

    @ViewBuilder private func events(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowSectionTitle("Still to come")
            if calendar.access != .fullAccess {
                HStack(spacing: 10) {
                    Text("Your calendar's events can show on the timeline.")
                        .font(.system(size: 13)).foregroundStyle(Color.secondaryText)
                    // macOS asks only once; after a denial the switch is in System Settings.
                    if calendar.access == .notDetermined {
                        Button("Show events") { calendar.requestAccess() }
                    } else {
                        Button("Allow Calendar in System Settings") { Permission.calendars.openSettings() }
                    }
                }
            } else {
                let rest = calendar.todayEvents.filter { $0.end > now }
                if rest.isEmpty {
                    Text("Nothing else today").font(.system(size: 13)).foregroundStyle(Color.secondaryText)
                } else {
                    ForEach(rest) { event in
                        DayEventRow(event: event) { calendar.open(event) }
                    }
                }
            }
        }
    }

    private var hoursEditor: some View {
        Form {
            Stepper(
                "Day starts at \(hourLabel(preferences.workdayStart))", value: $preferences.workdayStart,
                in: 0...(preferences.workdayEnd - 1))
            Stepper(
                "Day ends at \(hourLabel(preferences.workdayEnd))", value: $preferences.workdayEnd,
                in: (preferences.workdayStart + 1)...24)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

/// The working day as a wide track: the elapsed part in violet, a "now" marker, today's events
/// as titled blocks below it (overlapping ones on separate rows) and the hours underneath.
private struct DayTimeline: View {
    let day: DayProgress
    let now: Date
    let events: [CalendarStore.Event]
    let width: CGFloat
    let open: (CalendarStore.Event) -> Void

    private static let laneHeight: CGFloat = 30

    var body: some View {
        let placed = events.compactMap { event in
            day.mark(for: event.start...max(event.start, event.end), on: now).map { (event, $0) }
        }
        let lanes = DayProgress.lanes(for: placed.map(\.1))
        let laneCount = (lanes.max() ?? -1) + 1
        let fraction = day.fraction(at: now)
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(.ink.opacity(0.08)).frame(height: 10)
                if fraction > 0 {
                    Capsule().fill(Color.wispViolet).frame(width: max(10, fraction * width), height: 10)
                }
                if day.isWorking(at: now) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.ink)
                        .frame(width: 3, height: 22)
                        .offset(x: min(max(fraction * width - 1.5, 0), width - 3))
                        .accessibilityLabel("Now")
                }
            }
            .frame(width: width, height: 22)
            if laneCount > 0 {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(placed.enumerated()), id: \.offset) { index, item in
                        let (event, mark) = item
                        Button {
                            open(event)
                        } label: {
                            Text(event.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .frame(
                                    width: max(6, (mark.upperBound - mark.lowerBound) * width - 2),
                                    height: Self.laneHeight - 4, alignment: .leading
                                )
                                .foregroundStyle(event.color)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(
                                        event.color.opacity(0.18))
                                )
                                .opacity(event.end < now ? 0.55 : 1)
                        }
                        .buttonStyle(.plain)
                        .help(event.title)
                        .offset(x: mark.lowerBound * width, y: CGFloat(lanes[index]) * Self.laneHeight)
                    }
                }
                .frame(width: width, height: CGFloat(laneCount) * Self.laneHeight, alignment: .topLeading)
            }
            ZStack(alignment: .topLeading) {
                let hours = day.hourMarks(on: now)
                // Every other hour once the hours get crowded.
                let step = width / CGFloat(max(hours.count - 1, 1)) < 44 ? 2 : 1
                ForEach(Array(hours.enumerated()), id: \.offset) { index, mark in
                    if index % step == 0 || index == hours.count - 1 {
                        Text(hourText(mark.hour))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondaryText)
                            .fixedSize()
                            .frame(
                                width: 44,
                                alignment: index == 0 ? .leading : index == hours.count - 1 ? .trailing : .center
                            )
                            .offset(x: min(max(mark.fraction * width - 22, 0), width - 44))
                    }
                }
            }
            .frame(width: width, height: 14, alignment: .topLeading)
        }
    }

    private func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: now) ?? now
        return date.formatted(.dateTime.hour())
    }
}

/// One event: calendar colour, time and title, with Join for a call. The Calendar page uses it too.
struct DayEventRow: View {
    let event: CalendarStore.Event
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(timeText).font(.system(size: 11)).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 8)
            if let link = event.link {
                Button("Join") { NSWorkspace.shared.open(link) }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ink.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open in Calendar", open)
    }

    private var timeText: String {
        guard !event.isAllDay else { return "All day" }
        let format = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(event.start.formatted(format)) to \(event.end.formatted(format))"
    }
}

// MARK: World Clocks

/// World Clocks in the window: a card per city with an analog face, and a slider to see the
/// times a few hours away.
struct WorldClocksPage: View {
    let preferences: Preferences

    @State private var shift = 0
    /// The moment the shift counts from, fixed when the slider first moves.
    @State private var base: Date?
    @State private var addingCity = false

    private var cities: [String] { WorldClock.cities(preferences.worldClockZones) }

    var body: some View {
        WindowWidgetPage { width in
            TimelineView(.everyMinute) { context in
                let shown = base.map { WorldClock.shiftedTime(base: $0, minutes: shift) } ?? context.date
                VStack(alignment: .leading, spacing: 20) {
                    if cities.isEmpty {
                        ContentUnavailableView {
                            Label("No cities", systemImage: "globe")
                        } description: {
                            Text("Add up to \(WorldClock.maximumCities) cities to see their time.")
                        } actions: {
                            Button("Add city") { addingCity = true }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: windowGridColumns(width: width, minimum: 200), spacing: WindowLayout.spacing)
                        {
                            ForEach(Array(cities.enumerated()), id: \.element) { index, identifier in
                                if let zone = TimeZone(identifier: identifier) {
                                    ClockCard(zone: zone, time: shown)
                                        .contextMenu { cardMenu(identifier, index: index) }
                                }
                            }
                        }
                        shiftBar(shown)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add city", systemImage: "plus") { addingCity = true }
                    .disabled(cities.count >= WorldClock.maximumCities)
                    .help(
                        cities.count >= WorldClock.maximumCities
                            ? "Up to \(WorldClock.maximumCities) cities" : "Add city"
                    )
                    .popover(isPresented: $addingCity, arrowEdge: .bottom) {
                        CityPicker(existing: cities) { identifier in
                            preferences.worldClockZones = WorldClock.adding(identifier, to: preferences.worldClockZones)
                            addingCity = false
                        }
                    }
                Button("Reset to now", systemImage: "arrow.uturn.backward") { resetShift() }
                    .disabled(base == nil)
                    .help("Reset to now")
            }
        }
    }

    @ViewBuilder private func cardMenu(_ identifier: String, index: Int) -> some View {
        Button("Move left") {
            preferences.worldClockZones = WorldClock.moving(identifier, by: -1, in: preferences.worldClockZones)
        }
        .disabled(index == 0)
        Button("Move right") {
            preferences.worldClockZones = WorldClock.moving(identifier, by: 1, in: preferences.worldClockZones)
        }
        .disabled(index == cities.count - 1)
        Divider()
        Button("Remove", role: .destructive) {
            preferences.worldClockZones = WorldClock.removing(identifier, from: preferences.worldClockZones)
        }
    }

    private func shiftBar(_ shown: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if base == nil {
                    Text("Drag to compare another time").foregroundStyle(Color.secondaryText)
                } else {
                    Text("Showing \(shown.formatted(date: .omitted, time: .shortened)) here")
                        .foregroundStyle(Color.wispViolet)
                    Text(WorldClock.offsetLabel(seconds: shift * 60).replacingOccurrences(of: "Same time", with: ""))
                        .foregroundStyle(Color.secondaryText)
                    Spacer()
                    Button("Now") { resetShift() }.controlSize(.small)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .frame(height: 22)
            Slider(
                value: Binding(
                    get: { Double(shift) },
                    set: { value in
                        let next = WorldClock.snappedShift(minutes: value)
                        if next != 0, base == nil { base = .now }
                        shift = next
                        if next == 0 { base = nil }
                    }),
                in: Double(WorldClock.shiftRange.lowerBound)...Double(WorldClock.shiftRange.upperBound),
                step: Double(WorldClock.shiftStep)
            ) {
                Text("Time shift")
            } minimumValueLabel: {
                Text("−12h").font(.system(size: 10)).foregroundStyle(Color.secondaryText)
            } maximumValueLabel: {
                Text("+12h").font(.system(size: 10)).foregroundStyle(Color.secondaryText)
            }
            .labelsHidden()
        }
        .padding(14)
        .card()
    }

    private func resetShift() {
        shift = 0
        base = nil
    }
}

/// One city: an analog face, the name, the time and its difference from here, shaded for day
/// or night there.
private struct ClockCard: View {
    let zone: TimeZone
    let time: Date

    var body: some View {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 0
        let day = WorldClock.isDaytime(hour: hour)
        let offset = zone.secondsFromGMT(for: time) - TimeZone.current.secondsFromGMT(for: time)
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        var weekday = Date.FormatStyle().weekday(.abbreviated)
        weekday.timeZone = zone
        return HStack(spacing: 14) {
            AnalogFace(hour: hour, minute: parts.minute ?? 0, daytime: day)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(WorldClock.cityName(zone.identifier)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                ValueText(text: time.formatted(style), size: 20)
                HStack(spacing: 4) {
                    Image(systemName: day ? "sun.max.fill" : "moon.fill")
                        .foregroundStyle(day ? Color.wispAmber : Color.indigo)
                    Text("\(time.formatted(weekday)) · \(WorldClock.offsetLabel(seconds: offset))")
                        .foregroundStyle(Color.secondaryText)
                }
                .font(.system(size: 11))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: ShellMetrics.widgetCornerRadius, style: .continuous)
                .fill(day ? AnyShapeStyle(.ink.opacity(0.06)) : AnyShapeStyle(Color.indigo.opacity(0.16)))
        )
        .accessibilityElement(children: .combine)
    }
}

/// A clock face drawn with shapes: twelve ticks and two hands.
private struct AnalogFace: View {
    let hour: Int
    let minute: Int
    let daytime: Bool

    var body: some View {
        let angles = WorldClock.handAngles(hour: hour, minute: minute)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(daytime ? AnyShapeStyle(.background) : AnyShapeStyle(Color.indigo.opacity(0.35)))
                Circle().strokeBorder(.ink.opacity(0.2), lineWidth: 1)
                ForEach(0..<12, id: \.self) { tick in
                    Capsule()
                        .fill(.ink.opacity(tick % 3 == 0 ? 0.6 : 0.25))
                        .frame(width: 1.5, height: tick % 3 == 0 ? side * 0.1 : side * 0.06)
                        .offset(y: -side * 0.4)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                hand(length: side * 0.26, width: 3, angle: angles.hour)
                hand(length: side * 0.38, width: 2, angle: angles.minute)
                Circle().fill(Color.wispViolet).frame(width: 5, height: 5)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }

    private func hand(length: CGFloat, width: CGFloat, angle: Double) -> some View {
        Capsule()
            .fill(.ink)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}

/// A searchable list of time zones to add.
private struct CityPicker: View {
    let existing: [String]
    let pick: (String) -> Void

    @State private var query = ""

    private static let zones = TimeZone.knownTimeZoneIdentifiers.sorted {
        WorldClock.cityName($0) < WorldClock.cityName($1)
    }

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = Self.zones.filter {
            !existing.contains($0)
                && (needle.isEmpty || $0.lowercased().contains(needle)
                    || WorldClock.cityName($0).lowercased().contains(needle))
        }
        VStack(spacing: 0) {
            TextField("Search cities", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            List(matches, id: \.self) { identifier in
                Button {
                    pick(identifier)
                } label: {
                    HStack {
                        Text(WorldClock.cityName(identifier))
                        Spacer()
                        Text(identifier).foregroundStyle(.secondary).font(.system(size: 11))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay { if matches.isEmpty { ContentUnavailableView.search(text: query) } }
        }
        .frame(width: 320, height: 380)
    }
}

// MARK: Pomodoro

/// Pomodoro in the window: a large ring with the time left, preset lengths, and today's
/// finished sessions beside it (below it in a narrow window).
struct PomodoroPage: View {
    let store: TimerStore
    let preferences: Preferences

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let presets = [(25, 5), (50, 10)]

    var body: some View {
        WindowWidgetPage { width in
            let wide = WindowLayout.showsInspector(width: width + 2 * WindowLayout.margin)
            if wide {
                HStack(alignment: .top, spacing: 24) {
                    timerColumn.frame(maxWidth: .infinity)
                    today.frame(width: WindowLayout.inspectorWidth)
                }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    timerColumn.frame(maxWidth: .infinity)
                    today
                }
            }
        }
        .toolbar { toolbar }
    }

    private var timerColumn: some View {
        let countdown = store.pomodoro
        return VStack(spacing: 20) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CountdownRing(
                    countdown: countdown, title: store.phase.title, now: context.date, animated: !reduceMotion)
            }
            .frame(width: 260, height: 260)
            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.0) { focus, rest in
                    LengthChip(
                        title: "\(focus)/\(rest)",
                        selected: store.focusMinutes == focus && store.breakMinutes == rest
                    ) {
                        store.applyPreset(focus: focus, rest: rest)
                    }
                }
                // The scrubber below sets a custom length; this only shows that one is in use.
                ChipLabel(title: "Custom", selected: !isPreset)
            }
            .disabled(countdown.hasStarted)
            RulerScrubber(
                value: Binding(
                    get: { store.phase == .focus ? store.focusMinutes : store.breakMinutes },
                    set: { store.phase == .focus ? (store.focusMinutes = $0) : (store.breakMinutes = $0) }
                ),
                range: store.phase == .focus ? 15...60 : 3...20,
                enabled: !countdown.hasStarted,
                feedback: preferences.scrubberSounds
            )
            .frame(maxWidth: 320)
            .accessibilityLabel(store.phase == .focus ? "Focus length" : "Break length")
        }
    }

    private var isPreset: Bool {
        Self.presets.contains { $0.0 == store.focusMinutes && $0.1 == store.breakMinutes }
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 10) {
            WindowSectionTitle("Today")
            TimelineView(.everyMinute) { context in
                let sessions = store.log.today(now: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    if sessions.isEmpty {
                        ContentUnavailableView {
                            Label("No sessions yet", systemImage: "brain.head.profile")
                        } description: {
                            Text("Finished focus sessions show up here.")
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            ValueText(text: "\(store.log.focusMinutes(now: context.date))", tint: .wispViolet, size: 28)
                            Text(
                                "minutes of focus in \(sessions.count) \(sessions.count == 1 ? "session" : "sessions")"
                            )
                            .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                        }
                        ForEach(sessions.reversed()) { session in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wispViolet)
                                Text(
                                    "\(session.start.formatted(date: .omitted, time: .shortened)) to \(session.end.formatted(date: .omitted, time: .shortened))"
                                )
                                Spacer()
                                Text("\(session.minutes) min").foregroundStyle(Color.secondaryText)
                            }
                            .font(.system(size: 13))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ink.opacity(0.05)))
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(
                store.pomodoro.isRunning ? "Pause" : "Start",
                systemImage: store.pomodoro.isRunning ? "pause.fill" : "play.fill", action: store.togglePomodoro
            )
            .buttonStyle(.borderedProminent)
            .help(store.pomodoro.isRunning ? "Pause" : "Start")
            Button("Skip phase", systemImage: "forward.end.fill", action: store.skipPhase)
                .help(store.phase == .focus ? "Skip to the break" : "Skip to focus")
            Button("Reset", systemImage: "arrow.counterclockwise", action: store.resetPomodoro)
                .disabled(!store.pomodoro.hasStarted)
                .help("Reset")
            Button(
                "Ruler sounds",
                systemImage: preferences.scrubberSounds ? "speaker.wave.2.fill" : "speaker.slash.fill"
            ) {
                preferences.scrubberSounds.toggle()
            }
            .help("Tick sounds when scrubbing")
            .accessibilityValue(preferences.scrubberSounds ? "On" : "Off")
        }
    }
}

/// A large countdown ring (Pomodoro and Timer): progress in Wisp violet around the time left,
/// a title and when it ends. Sweeps between seconds, or steps with Reduce Motion.
struct CountdownRing: View {
    let countdown: Countdown
    let title: String
    let now: Date
    let animated: Bool

    var body: some View {
        let progress = countdown.progress(now: now)
        ZStack {
            Circle().stroke(.ink.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.wispViolet, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animated && countdown.isRunning ? .linear(duration: 1) : nil, value: progress)
            VStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.wispViolet)
                ValueText(text: Countdown.format(countdown.remaining(now: now)), size: 52)
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding(7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Countdown.format(countdown.remaining(now: now))) left, \(status)")
    }

    private var status: String {
        if let end = countdown.endDate(now: now) {
            return "Ends at \(end.formatted(date: .omitted, time: .shortened))"
        }
        return countdown.hasStarted ? "Paused" : "\(Int(countdown.duration / 60)) min"
    }
}

/// A rounded chip for a preset length.
struct LengthChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, selected: selected)
        }
        .buttonStyle(.plain)
    }
}

struct ChipLabel: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? AnyShapeStyle(Color.wispViolet) : AnyShapeStyle(.ink.opacity(0.08))))
            .foregroundStyle(selected ? Color.white : .ink.opacity(0.85))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Timer

/// The timer in the window: a large ring with the time left and when it ends, preset lengths,
/// and what's counting down right now (the timer and the Pomodoro).
struct TimerPage: View {
    let store: TimerStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let presets = [5, 10, 15, 30, 60]

    var body: some View {
        WindowWidgetPage { _ in
            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    CountdownRing(
                        countdown: store.timer, title: TimerStore.timerLabel, now: context.date,
                        animated: !reduceMotion)
                }
                .frame(width: 260, height: 260)
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        LengthChip(title: "\(minutes) min", selected: Int(store.timer.duration) == minutes * 60) {
                            store.setTimer(minutes: minutes)
                        }
                    }
                }
                .disabled(store.timer.hasStarted)
                HStack(spacing: 10) {
                    Button("One less minute", systemImage: "minus") { store.adjustTimer(byMinutes: -1) }
                        .help("One less minute")
                    Button("One more minute", systemImage: "plus") { store.adjustTimer(byMinutes: 1) }
                        .help("One more minute")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.timer.hasStarted)
                running.padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(
                    store.timer.isRunning ? "Pause" : "Start",
                    systemImage: store.timer.isRunning ? "pause.fill" : "play.fill", action: store.toggleTimer
                )
                .buttonStyle(.borderedProminent)
                .help(store.timer.isRunning ? "Pause" : "Start")
                Button("Reset", systemImage: "arrow.counterclockwise", action: store.resetTimer)
                    .disabled(!store.timer.hasStarted)
                    .help("Reset")
            }
        }
    }

    /// The countdowns that have started, each with its own pause and resume.
    @ViewBuilder private var running: some View {
        let rows = [
            store.timer.hasStarted
                ? RunningRow(title: TimerStore.timerLabel, countdown: store.timer, toggle: store.toggleTimer) : nil,
            store.pomodoro.hasStarted
                ? RunningRow(
                    title: "Pomodoro, \(store.phase.title.lowercased())", countdown: store.pomodoro,
                    toggle: store.togglePomodoro) : nil,
        ]
        .compactMap { $0 }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                WindowSectionTitle("Running")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 8) {
                        ForEach(rows, id: \.title) { row in
                            HStack(spacing: 10) {
                                Image(systemName: row.countdown.isRunning ? "timer" : "pause.circle")
                                    .foregroundStyle(Color.wispViolet)
                                Text(row.title).font(.system(size: 13, weight: .medium))
                                Spacer()
                                ValueText(text: Countdown.format(row.countdown.remaining(now: context.date)), size: 15)
                                Button(
                                    row.countdown.isRunning ? "Pause" : "Resume",
                                    systemImage: row.countdown.isRunning ? "pause.fill" : "play.fill",
                                    action: row.toggle
                                )
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help(row.countdown.isRunning ? "Pause" : "Resume")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ink.opacity(0.05)))
                        }
                    }
                }
            }
            .frame(maxWidth: 420)
        }
    }

    private struct RunningRow {
        let title: String
        let countdown: Countdown
        let toggle: () -> Void
    }
}
