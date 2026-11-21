import SwiftUI
import WispCore

/// Home in the window: a greeting with the time and quick actions, the coming week, and cards
/// for what's on today. The notch's Home keeps its widget row; this is the roomier version.
struct WindowHome: View {
    let model: NotchModel

    @Environment(\.openWindowRow) private var openRow
    /// The day the Events card lists; nil is today.
    @State private var day: Date?

    private var services: AppServices { model.services }
    private var cards: [HomeCard] { model.preferences.windowHomeCards }

    /// The content's width, for the number of card columns.
    @State private var width: CGFloat = 0

    var body: some View {
        // The scroll view is the page's root, so the toolbar's scroll edge sees it and keeps
        // scrolled cards from showing under its buttons.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                WindowHero(model: model)
                WeekStripView(store: services.calendar, selection: $day)
                if cards.isEmpty {
                    WindowEmptyState(
                        symbol: "square.grid.2x2", title: "No cards on Home",
                        message: "Choose Customise Home in the toolbar to add some."
                    )
                    .windowCardBackground()
                } else {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: WindowLayout.spacing, alignment: .top),
                            count: WindowLayout.dashboardColumns(width: width)),
                        alignment: .leading, spacing: WindowLayout.spacing
                    ) {
                        ForEach(cards) { card in
                            cardView(card)
                        }
                    }
                }
            }
            .padding(WindowLayout.margin)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width - 2 * WindowLayout.margin
            } action: {
                width = $0
            }
        }
        .windowScrollEdge()
        .onAppear {
            services.calendar.refreshIfStale()
            services.reminders.refreshIfStale()
        }
    }

    @ViewBuilder private func cardView(_ card: HomeCard) -> some View {
        switch card {
        case .events: EventsCard(store: services.calendar, day: day ?? .now) { openRow(.widget("calendar")) }
        case .reminders: RemindersCard(store: services.reminders) { openRow(.widget("reminders")) }
        case .agents: AgentsCard(hub: services.agents) { openRow(.widget("agents")) }
        case .notes: NotesCard(store: services.notes) { openRow(.widget("notes")) }
        }
    }
}

// MARK: Hero

/// The greeting, the date and a live clock over a wash that follows the time of day, with the
/// things people start most from Home.
private struct WindowHero: View {
    let model: NotchModel

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openWindowRow) private var openRow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let hour = Calendar.current.component(.hour, from: context.date)
            let palette = WindowGreeting.palette(hour: hour, isDark: scheme == .dark)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WindowGreeting.greeting(hour: hour, fullName: NSFullUserName()))
                            .font(.largeTitle.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityAddTraits(.isHeader)
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                // Labels while they fit; icons with tooltips in a narrow window.
                ViewThatFits(in: .horizontal) {
                    actions(labelled: true)
                    actions(labelled: false)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
            .background(background(palette))
            .clipShape(RoundedRectangle(cornerRadius: SurfaceRadius.largePanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SurfaceRadius.largePanel, style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.5), lineWidth: 0.5))
        }
    }

    @ViewBuilder private func background(_ palette: WindowGreeting.Palette) -> some View {
        let leading = Color(rgb: palette.leading)
        let trailing = Color(rgb: palette.trailing)
        if reduceTransparency {
            leading
        } else {
            ZStack {
                LinearGradient(colors: [leading, trailing], startPoint: .topLeading, endPoint: .bottomTrailing)
                // A soft glow toward the clock, as light falls on the corner.
                RadialGradient(
                    colors: [.white.opacity(scheme == .dark ? 0.12 : 0.35), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: 360)
            }
        }
    }

    private func actions(labelled: Bool) -> some View {
        HStack(spacing: 8) {
            HeroAction(title: "New timer", symbol: "timer", labelled: labelled) { openRow(.widget("timer")) }
            HeroAction(title: "New reminder", symbol: "checklist", labelled: labelled) { quickAdd("remind me ") }
            HeroAction(title: "New event", symbol: "calendar.badge.plus", labelled: labelled) { quickAdd("event ") }
            HeroAction(title: "Capture text", symbol: "text.viewfinder", labelled: labelled) {
                model.services.textCapture.begin()
            }
        }
        .fixedSize()
    }

    /// Quick add with the start of the sentence typed, so the rest is a few words.
    private func quickAdd(_ start: String) {
        let input = model.services.quickInput
        input.text = start
        input.requestFocus()
        openRow(.widget("quickInput"))
    }
}

private struct HeroAction: View {
    let title: String
    let symbol: String
    let labelled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if labelled {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.medium))
            } else {
                Label(title, systemImage: symbol)
                    .labelStyle(.iconOnly)
                    .font(.callout.weight(.medium))
            }
        }
        .help(title)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

// MARK: Week strip

/// Today and the six days after it; picking one lists its events on the Events card.
private struct WeekStripView: View {
    let store: CalendarStore
    @Binding var selection: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let days = WeekStrip.days(from: context.date, calendar: .current)
            HStack(spacing: 6) {
                Text(context.date, format: .dateTime.month(.wide).year())
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 150, alignment: .leading)
                ForEach(days, id: \.self) { day in
                    dayButton(day, today: days.first)
                }
                if selection != nil {
                    Button("Today") { selection = nil }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
        }
    }

    private func dayButton(_ day: Date, today: Date?) -> some View {
        let calendar = Calendar.current
        let selected = calendar.isDate(day, inSameDayAs: selection ?? today ?? .now)
        let busy = store.weekEvents.contains { calendar.isDate($0.start, inSameDayAs: day) }
        return Button {
            selection = day == today ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text(day, format: .dateTime.weekday(.abbreviated))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selected ? .white.opacity(0.85) : Color.secondaryText)
                Text(day, format: .dateTime.day())
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selected ? .white : .primary)
                Circle().fill(selected ? .white : Color.wispViolet).frame(width: 4, height: 4)
                    .opacity(busy ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: SurfaceRadius.row + 2, style: .continuous)
                    .fill(selected ? Color.wispViolet : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(busy ? "Has events" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Cards

private struct EventsCard: View {
    let store: CalendarStore
    let day: Date
    let open: () -> Void

    private var events: [CalendarStore.Event] {
        let calendar = Calendar.current
        // Today keeps the meetings already over, so the card reads as the whole day.
        if calendar.isDateInToday(day) { return store.todayEvents }
        return store.weekEvents.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    var body: some View {
        WindowCard(
            title: Calendar.current.isDateInToday(day) ? "Today's events" : day.formatted(.dateTime.weekday(.wide)),
            symbol: "calendar", tint: .red, count: store.access == .fullAccess ? events.count : nil, open: open,
            minHeight: 240
        ) {
            if store.access != .fullAccess {
                CardMessage(text: "Allow Calendar to see your events here.") {
                    Button("Allow Calendar") { store.requestAccess() }
                }
            } else if !store.loaded {
                LoadingLabel("Loading…")
            } else if events.isEmpty {
                CardMessage(text: "Nothing planned.")
            } else {
                VStack(spacing: 8) {
                    ForEach(events) { event in
                        DayEventRow(event: event) { store.open(event) }
                    }
                }
            }
        }
    }
}

private struct RemindersCard: View {
    let store: RemindersStore
    let open: () -> Void

    var body: some View {
        WindowCard(
            title: "Reminders", symbol: "checklist", tint: .orange,
            count: store.access == .fullAccess ? store.items.count : nil, open: open, minHeight: 240
        ) {
            if store.access != .fullAccess {
                CardMessage(text: "Allow Reminders to tick them off here.") {
                    Button("Allow Reminders") { store.requestAccess() }
                }
            } else if store.items.isEmpty {
                if store.loaded || store.failed {
                    CardMessage(text: store.failed ? "Couldn't read Reminders." : "All done.")
                } else {
                    LoadingLabel("Loading…")
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.items.prefix(8).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 28) }
                        ReminderRow(item: item, done: store.justDone.contains(item.id), store: store)
                            .padding(.vertical, 7)
                    }
                }
            }
        }
    }
}

private struct AgentsCard: View {
    let hub: AgentHub
    let open: () -> Void

    var body: some View {
        let sessions = hub.sessions.list
        WindowCard(
            title: "Agents", symbol: "sparkles", tint: .purple, count: sessions.count, open: open, minHeight: 240
        ) {
            if sessions.isEmpty {
                CardMessage(text: "Claude Code and Codex sessions show up here while they run.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                        if index > 0 { Divider() }
                        Button {
                            hub.focus(session: session.id)
                        } label: {
                            row(session)
                        }
                        .buttonStyle(.plain)
                        .help("Show its terminal")
                    }
                }
            }
        }
    }

    private func row(_ session: AgentSession) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot(session.state)).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.project.isEmpty ? session.source.displayName : session.project)
                    .font(.body.weight(.semibold)).lineLimit(1)
                Text("\(session.source.displayName) · \(session.stateLabel)")
                    .font(.subheadline).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let percent = session.contextPercent {
                ContextBar(percent: percent)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func dot(_ state: AgentSession.State) -> Color {
        switch state {
        case .needsApproval, .waiting: .orange
        case .idle, .finished: .green
        case .running: Color.wispViolet
        }
    }
}

private struct NotesCard: View {
    let store: NotesStore
    let open: () -> Void

    var body: some View {
        let notes = Array(store.book.sorted.filter { !$0.isEmpty }.prefix(4))
        WindowCard(
            title: "Recent notes", symbol: "note.text", tint: .yellow,
            count: notes.isEmpty ? nil : store.book.notes.count,
            open: open, minHeight: 240
        ) {
            if notes.isEmpty {
                CardMessage(text: "Notes you write in Wisp show up here.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        if index > 0 { Divider() }
                        Button {
                            store.selectedID = note.id
                            open()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).font(.body.weight(.semibold)).lineLimit(1)
                                if !note.preview.isEmpty {
                                    Text(note.preview).font(.subheadline).foregroundStyle(Color.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// A short line in an empty card, with an optional action under it.
private struct CardMessage<Action: View>: View {
    let text: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
            action
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
    }
}

extension CardMessage where Action == EmptyView {
    init(text: String) {
        self.init(text: text) { EmptyView() }
    }
}

// MARK: Customise

/// Which cards Home shows and in what order.
struct HomeCardsSheet: View {
    let preferences: Preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customise Home").font(.title2.bold())
            Text("Choose the cards on Home and drag to reorder them.")
                .font(.subheadline).foregroundStyle(Color.secondaryText)
            List {
                ForEach(preferences.windowHomeCards) { card in
                    toggle(card)
                }
                .onMove { source, destination in
                    preferences.windowHomeCards = HomeCard.moved(
                        preferences.windowHomeCards, from: source, to: destination)
                }
                ForEach(HomeCard.allCases.filter { !preferences.windowHomeCards.contains($0) }) { card in
                    toggle(card)
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 200)
            HStack {
                Button("Reset") { preferences.windowHomeCards = HomeCard.standard }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func toggle(_ card: HomeCard) -> some View {
        Toggle(
            card.title,
            isOn: Binding(
                get: { preferences.windowHomeCards.contains(card) },
                set: { _ in preferences.windowHomeCards = HomeCard.toggled(card, in: preferences.windowHomeCards) }))
    }
}
