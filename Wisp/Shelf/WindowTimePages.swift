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
        WindowWidgetPage {
            WindowPageHeader(
                symbol: "sun.horizon.fill", tint: .orange, title: "Day Progress",
                subtitle: "How far through your working day you are, and what's still to come"
            ) {
                Button("Working hours", systemImage: "clock") { editingHours = true }
                    .help("Set your working hours")
                    .popover(isPresented: $editingHours, arrowEdge: .bottom) { hoursEditor }
            }
        } content: { width in
            TimelineView(.everyMinute) { context in
                let day = DayProgress(startHour: preferences.workdayStart, endHour: preferences.workdayEnd)
                VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                    hero(day, now: context.date)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .windowCardBackground()
                    WindowCard(title: "Today", symbol: "chart.bar.xaxis", tint: .wispViolet) {
                        DayTimeline(
                            day: day, now: context.date, events: calendar.todayEvents.filter { !$0.isAllDay },
                            width: width - 32, open: calendar.open)
                    }
                    WindowCard(title: "Still to come", symbol: "calendar", tint: .red) {
                        events(now: context.date)
                    }
                }
                // A page left open past midnight reads the new day's events.
                .onChange(of: Calendar.current.startOfDay(for: context.date)) { calendar.refreshIfStale() }
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
                    Text("of the working day").font(.title3).foregroundStyle(Color.secondaryText)
                }
                Text("\(DurationText.text(for: TimeInterval(left * 60))) left · \(range)")
                    .font(.body.weight(.medium)).foregroundStyle(.ink.opacity(0.85))
            } else {
                let next = day.nextStart(after: now)
                let ended = day.fraction(at: now) >= 1
                Text(ended ? "Done for today" : "Your day hasn't started")
                    .font(.title.weight(.semibold))
                Text(
                    "Starts \(Calendar.current.isDateInToday(next) ? "today" : "tomorrow") at \(next.formatted(date: .omitted, time: .shortened)) · \(range)"
                )
                .font(.body.weight(.medium)).foregroundStyle(Color.secondaryText)
            }
        }
    }

    @ViewBuilder private func events(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if calendar.access != .fullAccess {
                HStack(spacing: 10) {
                    Text("Your calendar's events can show on the timeline.")
                        .font(.body).foregroundStyle(Color.secondaryText)
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
                    Text("Nothing else today").font(.body).foregroundStyle(Color.secondaryText)
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
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
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
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .frame(
                                    width: max(6, (mark.upperBound - mark.lowerBound) * width - 2),
                                    height: Self.laneHeight - 4, alignment: .leading
                                )
                                .foregroundStyle(event.color)
                                .wispHover()
                                .background(
                                    RoundedRectangle(cornerRadius: SurfaceRadius.control, style: .continuous).fill(
                                        event.color.opacity(0.18))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.control, style: .continuous))
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
                            .font(.caption.weight(.medium))
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(event.color).frame(
                        width: 4, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.body.weight(.semibold)).lineLimit(1)
                        Text(timeText).font(.subheadline).foregroundStyle(Color.secondaryText)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(event.title), \(timeText)")
            .accessibilityHint("Opens it in Calendar")
            // Beside the row's button rather than inside it, so it's its own target.
            if let link = event.link {
                Button("Join") { NSWorkspace.shared.open(link) }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                .fill(event.color.opacity(hovering ? 0.16 : 0.1))
        )
        .onHover { hovering = $0 }
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
        WindowWidgetPage {
            WindowPageHeader(
                symbol: "globe", tint: .cyan, title: "World Clocks",
                subtitle: "The time where your people are, and a slider to plan across zones",
                count: "\(cities.count) of \(WorldClock.maximumCities)"
            ) {
                Button("Reset to now", systemImage: "arrow.uturn.backward") { resetShift() }
                    .labelStyle(.iconOnly)
                    .disabled(base == nil)
                    .help("Reset to now")
                WindowPrimaryButton(title: "Add city", symbol: "plus") { addingCity = true }
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
            }
        } content: { width in
            TimelineView(.everyMinute) { context in
                let shown = base.map { WorldClock.shiftedTime(base: $0, minutes: shift) } ?? context.date
                VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                    here(shown)
                    if cities.isEmpty {
                        WindowCard(title: "Cities", symbol: "globe", tint: .cyan) {
                            WindowEmptyState(
                                symbol: "globe", title: "No cities yet",
                                message: "Add up to \(WorldClock.maximumCities) cities to see their time at a glance."
                            ) {
                                WindowPrimaryButton(title: "Add city", symbol: "plus") { addingCity = true }
                            }
                        }
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
    }

    /// Your own time and zone, large, as the clocks are read against it.
    private func here(_ shown: Date) -> some View {
        HStack(alignment: .center, spacing: 18) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: shown)
            AnalogFace(
                hour: parts.hour ?? 0, minute: parts.minute ?? 0,
                daytime: WorldClock.isDaytime(hour: parts.hour ?? 0)
            )
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text("Here").font(.subheadline).foregroundStyle(Color.secondaryText)
                Text(shown, format: .dateTime.hour().minute())
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                Text(TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)
                    .font(.subheadline).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .windowCardBackground()
        .accessibilityElement(children: .combine)
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
            .font(.body.weight(.medium))
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
                Text("−12h").font(.caption).foregroundStyle(Color.secondaryText)
            } maximumValueLabel: {
                Text("+12h").font(.caption).foregroundStyle(Color.secondaryText)
            }
            .labelsHidden()
        }
        .padding(14)
        .windowCardBackground()
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
                Text(WorldClock.cityName(zone.identifier)).font(.body.weight(.semibold)).lineLimit(1)
                ValueText(text: time.formatted(style), size: 20)
                HStack(spacing: 4) {
                    Image(systemName: day ? "sun.max.fill" : "moon.fill")
                        .foregroundStyle(day ? Color.wispAmber : Color.indigo)
                    Text("\(time.formatted(weekday)) · \(WorldClock.offsetLabel(seconds: offset))")
                        .foregroundStyle(Color.secondaryText)
                }
                .font(.subheadline)
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
                        Text(identifier).foregroundStyle(.secondary).font(.subheadline)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .wispHover(cornerRadius: SurfaceRadius.row)
                .padding(.vertical, -2)
                .padding(.horizontal, -6)
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
        WindowWidgetPage {
            WindowPageHeader(
                symbol: "brain.head.profile", tint: .red, title: "Pomodoro",
                subtitle: store.phase == .focus ? "Focus, then a short break" : "Take a break, then back to focus"
            ) { actions }
        } content: { width in
            let wide = WindowLayout.showsInspector(width: width + 2 * WindowLayout.margin)
            if wide {
                HStack(alignment: .top, spacing: WindowLayout.spacing) {
                    timerColumn
                        .padding(24)
                        .frame(maxWidth: .infinity, minHeight: 460)
                        .windowCardBackground()
                    today.frame(width: WindowLayout.inspectorWidth)
                }
            } else {
                VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                    timerColumn.padding(24).frame(maxWidth: .infinity).windowCardBackground()
                    today
                }
            }
        }
        // A reminder dragged here from the Reminders widget says what the session is for.
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                Task { @MainActor in
                    // Home cards dragged from the shelf carry their widget id; that isn't a label.
                    if let text, WidgetDrag.id(from: text) == nil { store.setFocusLabel(from: text) }
                }
            }
            return true
        }
    }

    private var timerColumn: some View {
        let countdown = store.pomodoro
        return VStack(spacing: 20) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CountdownRing(
                    countdown: countdown,
                    title: store.phase == .focus ? store.focusLabel ?? store.phase.title : store.phase.title,
                    now: context.date, animated: !reduceMotion)
            }
            .frame(width: 260, height: 260)
            if let label = store.focusLabel {
                Button("Clear “\(label)”", systemImage: "xmark.circle.fill", action: store.clearFocusLabel)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Stop saying what this session is for")
            }
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
        WindowCard(title: "Today", symbol: "checkmark.circle", tint: .wispViolet, minHeight: 460) {
            TimelineView(.everyMinute) { context in
                let sessions = store.log.today(now: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    if sessions.isEmpty {
                        WindowEmptyState(
                            symbol: "brain.head.profile", title: "No sessions yet",
                            message: "Finished focus sessions show up here, with what each was for.")
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            ValueText(text: "\(store.log.focusMinutes(now: context.date))", tint: .wispViolet, size: 28)
                            Text(
                                "minutes of focus in \(sessions.count) \(sessions.count == 1 ? "session" : "sessions")"
                            )
                            .font(.callout).foregroundStyle(Color.secondaryText)
                        }
                        ForEach(sessions.reversed()) { session in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wispViolet)
                                VStack(alignment: .leading, spacing: 1) {
                                    if let label = session.label { Text(label).lineLimit(1) }
                                    Text(
                                        "\(session.start.formatted(date: .omitted, time: .shortened)) to \(session.end.formatted(date: .omitted, time: .shortened))"
                                    )
                                    .foregroundStyle(session.label == nil ? .primary : Color.secondaryText)
                                }
                                Spacer()
                                Text("\(session.minutes) min").foregroundStyle(Color.secondaryText)
                            }
                            .font(.body)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: SurfaceRadius.control, style: .continuous).fill(
                                    .ink.opacity(0.05)))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button(
            "Ruler sounds",
            systemImage: preferences.scrubberSounds ? "speaker.wave.2.fill" : "speaker.slash.fill"
        ) {
            preferences.scrubberSounds.toggle()
        }
        .labelStyle(.iconOnly)
        .help("Tick sounds when scrubbing")
        .accessibilityValue(preferences.scrubberSounds ? "On" : "Off")
        Button("Reset", systemImage: "arrow.counterclockwise", action: store.resetPomodoro)
            .labelStyle(.iconOnly)
            .disabled(!store.pomodoro.hasStarted)
            .help("Reset")
        Button("Skip phase", systemImage: "forward.end.fill", action: store.skipPhase)
            .labelStyle(.iconOnly)
            .help(store.phase == .focus ? "Skip to the break" : "Skip to focus")
        WindowPrimaryButton(
            title: store.pomodoro.isRunning ? "Pause" : "Start",
            symbol: store.pomodoro.isRunning ? "pause.fill" : "play.fill", action: store.togglePomodoro)
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
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.wispViolet)
                ValueText(text: Countdown.format(countdown.remaining(now: now)), size: 52)
                Text(status)
                    .font(.callout)
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
        .wispHover(shape: Capsule())
    }
}

struct ChipLabel: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? AnyShapeStyle(Color.wispViolet) : AnyShapeStyle(.ink.opacity(0.08))))
            .contentShape(Capsule())
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
        WindowWidgetPage {
            WindowPageHeader(
                symbol: "timer", tint: .orange, title: "Timer", subtitle: "A countdown for the tea, the oven or a break"
            ) {
                Button("Reset", systemImage: "arrow.counterclockwise", action: store.resetTimer)
                    .labelStyle(.iconOnly)
                    .disabled(!store.timer.hasStarted)
                    .help("Reset")
                WindowPrimaryButton(
                    title: store.timer.isRunning ? "Pause" : "Start",
                    symbol: store.timer.isRunning ? "pause.fill" : "play.fill", action: store.toggleTimer)
            }
        } content: { width in
            let wide = WindowLayout.showsInspector(width: width + 2 * WindowLayout.margin)
            let layout =
                wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: WindowLayout.spacing))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: WindowLayout.spacing))
            layout {
                dial
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 420)
                    .windowCardBackground()
                running.frame(width: wide ? WindowLayout.inspectorWidth : nil)
            }
        }
    }

    private var dial: some View {
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
        }
        .frame(maxWidth: .infinity)
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
        WindowCard(
            title: "Running", symbol: "timer", tint: .wispViolet, count: rows.isEmpty ? nil : rows.count, minHeight: 420
        ) {
            if rows.isEmpty {
                WindowEmptyState(
                    symbol: "timer", title: "Nothing counting down",
                    message: "Pick a length and press Start. Running timers and Pomodoros show here.")
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 8) {
                        ForEach(rows, id: \.title) { row in
                            HStack(spacing: 10) {
                                Image(systemName: row.countdown.isRunning ? "timer" : "pause.circle")
                                    .foregroundStyle(Color.wispViolet)
                                Text(row.title).font(.body.weight(.medium))
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
                            .background(
                                RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous).fill(
                                    .ink.opacity(0.05)))
                        }
                    }
                }
            }
        }
    }

    private struct RunningRow {
        let title: String
        let countdown: Countdown
        let toggle: () -> Void
    }
}
