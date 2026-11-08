import AppKit
import EventKit
import SwiftUI
import WispCore

// MARK: Calendar

/// The calendar in the window: today and the next six days, each with its events (calendar
/// colour, time, title and Join for a call). Clicking an event opens it in Calendar.
struct CalendarPage: View {
    let store: CalendarStore

    var body: some View {
        Group {
            if store.access != .fullAccess {
                ContentUnavailableView {
                    Label("Calendar access needed", systemImage: "calendar")
                } description: {
                    Text("Allow Calendar to see the coming week here.")
                } actions: {
                    // macOS asks only once; after a denial the switch is in System Settings.
                    if store.access == .notDetermined {
                        Button("Allow Calendar") { store.requestAccess() }
                    } else {
                        Button("Open System Settings") { Permission.calendars.openSettings() }
                    }
                }
            } else if store.weekEvents.isEmpty {
                ContentUnavailableView(
                    "Nothing in the next week", systemImage: "calendar",
                    description: Text("Events from your calendars show up here."))
            } else {
                WindowWidgetPage(width: .readable) { _ in
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(CalendarDays.week(store.weekEvents, date: \.start, now: context.date), id: \.label)
                            {
                                day in
                                VStack(alignment: .leading, spacing: 8) {
                                    WindowSectionTitle(day.label)
                                    if day.items.isEmpty {
                                        Text("Nothing planned")
                                            .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                                    } else {
                                        ForEach(day.items) { event in
                                            DayEventRow(event: event) { store.open(event) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open Calendar", systemImage: "calendar") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
                .help("Open Calendar")
            }
        }
        .onAppear { store.refreshIfStale() }
    }
}

// MARK: Battery

/// Batteries in the window: the Mac's as a large card, then each accessory as a card with
/// every part it reports, emptiest first. The accessory source reads mice, keyboards and trackpads.
struct BatteryPage: View {
    let monitor: BatteryMonitor
    /// Accessories with a level, empty while the setting is off.
    let accessories: [BluetoothDevice]
    let showsAccessories: Bool
    let openSettings: () -> Void

    var body: some View {
        Group {
            if monitor.state == nil, accessories.isEmpty {
                ContentUnavailableView {
                    Label("No batteries", systemImage: "battery.0percent")
                } description: {
                    Text(
                        showsAccessories
                            ? "This Mac has no battery, and no accessory reports one."
                            : "This Mac has no battery. Mice, keyboards and trackpads can show here too.")
                } actions: {
                    if !showsAccessories { Button("Show accessories", action: openSettings) }
                }
            } else {
                WindowWidgetPage { width in
                    VStack(alignment: .leading, spacing: 12) {
                        if let state = monitor.state {
                            WindowSectionTitle("This Mac")
                            MacBatteryCard(state: state, minutes: monitor.minutesRemaining)
                        }
                        if !accessories.isEmpty {
                            WindowSectionTitle("Accessories").padding(.top, 12)
                            LazyVGrid(columns: windowGridColumns(width: width), spacing: WindowLayout.spacing) {
                                ForEach(sortedAccessories, id: \.address) { AccessoryBatteryCard(device: $0) }
                            }
                        } else if !showsAccessories {
                            HStack(spacing: 10) {
                                Text("Mice, keyboards and trackpads can show here too.")
                                    .font(.system(size: 13)).foregroundStyle(Color.secondaryText)
                                Button("Show accessories", action: openSettings)
                            }
                            .padding(.top, 12)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedAccessories: [BluetoothDevice] {
        accessories.sorted { (BatteryText.lowestLevel(of: $0) ?? 101) < (BatteryText.lowestLevel(of: $1) ?? 101) }
    }
}

private struct MacBatteryCard: View {
    let state: BatteryState
    let minutes: Int?

    var body: some View {
        let low = state.percent <= 20 && !state.isPluggedIn
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: Double(state.percent) / 100, tint: low ? .red : .wispGreen, lineWidth: 9)
                ValueText(text: "\(state.percent)%", size: 22)
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Label(BatteryText.status(state), systemImage: state.isPluggedIn ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 17, weight: .semibold))
                Text(BatteryText.remaining(minutes: minutes, state: state) ?? "Working out the time left")
                    .font(.system(size: 13)).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

private struct AccessoryBatteryCard: View {
    let device: BluetoothDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: device.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ink.opacity(0.1)))
                Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            ForEach(BatteryText.parts(of: device), id: \.label) { part in
                HStack(spacing: 8) {
                    Text(part.label)
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                        .frame(width: 52, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.ink.opacity(0.1))
                            Capsule()
                                .fill(part.isLow ? Color.red : Color.wispGreen)
                                .frame(width: proxy.size.width * CGFloat(min(max(part.level, 0), 100)) / 100)
                        }
                    }
                    .frame(height: 6)
                    Text("\(part.level)%")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(part.isLow ? Color.red : .ink)
                        .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(part.label), \(part.level)%")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ink.opacity(0.05)))
    }
}

// MARK: System Stats

/// CPU and memory in the window: a card each with the current value, the average and peak of
/// the samples kept (about the last 40 seconds) and a larger chart. Samples only while shown.
struct SystemStatsPage: View {
    let store: SystemStatsStore

    var body: some View {
        WindowWidgetPage { width in
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: windowGridColumns(width: width, minimum: 300), spacing: WindowLayout.spacing) {
                    StatCard(
                        title: "CPU", symbol: "cpu", value: store.cpu, history: store.cpuHistory,
                        detail: nil, tint: SystemStatsWidget.cpuTint, filled: false)
                    StatCard(
                        title: "Memory", symbol: "memorychip", value: store.memory.fraction,
                        history: store.memoryHistory, detail: memoryText, tint: SystemStatsWidget.ramTint, filled: true)
                }
                Text("The charts show about the last 40 seconds.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
            }
        }
        .onAppear { store.attach() }
        .onDisappear { store.detach() }
    }

    private var memoryText: String {
        let used = ByteCountFormatter.string(fromByteCount: Int64(store.memory.usedBytes), countStyle: .memory)
        let total = ByteCountFormatter.string(fromByteCount: Int64(store.memory.totalBytes), countStyle: .memory)
        return "\(used) of \(total)"
    }
}

private struct StatCard: View {
    let title: String
    let symbol: String
    let value: Double
    let history: SampleHistory
    let detail: String?
    let tint: Color
    let filled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                // Tint on the icon and chart only; text in it would be faint in Light mode.
                Label {
                    Text(title).foregroundStyle(.ink)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(tint)
                }
                .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    ValueText(text: "\(LevelStep.percent(value))", size: 30)
                    Text("%").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.secondaryText)
                }
            }
            Sparkline(values: history.values, tint: tint, filled: filled)
                .frame(height: 120)
            HStack {
                if let average = history.average, let peak = history.peak {
                    Text("Average \(LevelStep.percent(average))%  ·  Peak \(LevelStep.percent(peak))%")
                }
                Spacer()
                if let detail { Text(detail) }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.secondaryText)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Weather

/// Weather in the window: the current conditions large, then the next hours the store already
/// has. Nothing new is fetched; the store reads at most every 30 minutes.
struct WeatherPage: View {
    let store: WeatherStore

    var body: some View {
        Group {
            if let reading = store.reading {
                WindowWidgetPage(width: .readable) { width in
                    VStack(alignment: .leading, spacing: 24) {
                        current(reading)
                        if !reading.hours.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                WindowSectionTitle("Next hours")
                                LazyVGrid(
                                    columns: windowGridColumns(width: width, minimum: 100),
                                    spacing: WindowLayout.spacing
                                ) {
                                    ForEach(reading.hours) { hour in hourCard(hour) }
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No weather yet", systemImage: "cloud.sun")
                } description: {
                    Text(store.status)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.refreshIfStale() }
    }

    private func current(_ reading: WeatherStore.Reading) -> some View {
        let now = WeatherCode.describe(reading.code, isDay: reading.isDay)
        return HStack(alignment: .center, spacing: 22) {
            Image(systemName: now.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 64))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label(reading.place.isEmpty ? "Here" : reading.place, systemImage: "location.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                Text("\(Int(reading.temperature.rounded()))°")
                    .font(.system(size: 60, weight: .regular, design: .rounded))
                Text("\(now.title) · H:\(Int(reading.high.rounded()))° L:\(Int(reading.low.rounded()))°")
                    .font(.system(size: 14, weight: .medium))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    private func hourCard(_ hour: WeatherStore.Hour) -> some View {
        let date = Calendar.current.date(bySettingHour: hour.hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return VStack(spacing: 8) {
            Text(date, format: .dateTime.hour())
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.secondaryText)
            Image(systemName: WeatherCode.describe(hour.code, isDay: hour.isDay).symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 24))
            Text("\(Int(hour.temperature.rounded()))°").font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}
