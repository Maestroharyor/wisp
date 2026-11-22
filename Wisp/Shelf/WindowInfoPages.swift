import AppKit
import EventKit
import SwiftUI
import WispCore

// MARK: Battery

/// Batteries in the window: the Mac's as a large card, then each accessory as a card with
/// every part it reports, emptiest first. The accessory source reads mice, keyboards and trackpads.
struct BatteryPage: View {
    let monitor: BatteryMonitor
    /// Accessories with a level, empty while the setting is off.
    let accessories: [BluetoothDevice]
    let showsAccessories: Bool
    /// The battery warning level from Settings; parts at or below it show red.
    let lowLevel: Int
    let openSettings: () -> Void

    var body: some View {
        WindowWidgetPage {
            WindowPageHeader(
                symbol: "battery.75percent", tint: .green, title: "Battery",
                subtitle: "This Mac and the accessories paired with it",
                count: monitor.state.map { "\($0.percent)%" }
            ) {
                Button("Battery settings", systemImage: "gearshape", action: openSettings)
                    .labelStyle(.iconOnly)
                    .help("Battery settings")
            }
        } content: { width in
            VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                if let state = monitor.state {
                    HStack(alignment: .top, spacing: WindowLayout.spacing) {
                        MacBatteryCard(state: state, minutes: monitor.minutesRemaining)
                        if width > 640 { details(state).frame(width: 300) }
                    }
                    if width <= 640 { details(state) }
                } else {
                    WindowCard(title: "This Mac", symbol: "desktopcomputer", tint: .gray) {
                        WindowEmptyState(
                            symbol: "powerplug", title: "No battery",
                            message: "This Mac runs on power. Accessories with batteries show below.")
                    }
                }
                accessoriesCard(width: width)
            }
        }
    }

    private func details(_ state: BatteryState) -> some View {
        WindowCard(title: "Details", symbol: "info.circle", tint: .blue, minHeight: 150) {
            VStack(alignment: .leading, spacing: 8) {
                detail("Power", state.isPluggedIn ? "Power adapter" : "Battery")
                detail("Status", BatteryText.status(state))
                detail("Warns at", "\(lowLevel)%")
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.secondaryText)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .wispFont(.callout)
        .accessibilityElement(children: .combine)
    }

    private func accessoriesCard(width: CGFloat) -> some View {
        WindowCard(
            title: "Accessories", symbol: "keyboard", tint: .indigo,
            count: accessories.isEmpty ? nil : accessories.count
        ) {
            if !accessories.isEmpty {
                LazyVGrid(columns: windowGridColumns(width: width - 32), spacing: 12) {
                    ForEach(sortedAccessories, id: \.address) {
                        AccessoryBatteryCard(device: $0, lowLevel: lowLevel)
                    }
                }
            } else if !showsAccessories {
                WindowEmptyState(
                    symbol: "computermouse", title: "Accessories are hidden",
                    message: "Mice, keyboards and trackpads can show their batteries here."
                ) {
                    WindowPrimaryButton(title: "Show accessories", symbol: "eye", action: openSettings)
                }
            } else {
                WindowEmptyState(
                    symbol: "computermouse", title: "No accessories",
                    message: "Bluetooth mice, keyboards and trackpads that report a battery show here.")
            }
        }
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
                    .wispFont(.title2, weight: .semibold)
                Text(BatteryText.remaining(minutes: minutes, state: state) ?? "Working out the time left")
                    .wispFont(.body).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .windowCardBackground()
        .accessibilityElement(children: .combine)
    }
}

private struct AccessoryBatteryCard: View {
    let device: BluetoothDevice
    let lowLevel: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: device.symbol)
                    .wispFont(.title3, weight: .semibold)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ink.opacity(0.1)))
                Text(device.name).wispFont(.body, weight: .semibold).lineLimit(1)
            }
            ForEach(BatteryText.parts(of: device, lowLevel: lowLevel), id: \.label) { part in
                HStack(spacing: 8) {
                    Text(part.label)
                        .wispFont(.callout).foregroundStyle(Color.secondaryText)
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
                        .wispFont(.callout, weight: .semibold).monospacedDigit()
                        .foregroundStyle(part.isLow ? Color.red : .ink)
                        .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(part.label), \(part.level)%")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SurfaceRadius.row + 2, style: .continuous).fill(.primary.opacity(0.05)))
    }
}

// MARK: System Stats

/// CPU and memory in the window: a card each with the current value, the average and peak of
/// the samples kept (about the last 40 seconds) and a larger chart. Samples only while shown.
struct SystemStatsPage: View {
    let store: SystemStatsStore

    var body: some View {
        WindowWidgetPage {
            WindowPageHeader(
                symbol: "cpu", tint: .teal, title: "System Stats",
                subtitle: "How busy this Mac is, sampled every second while you watch")
        } content: { width in
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: windowGridColumns(width: width, minimum: 300), spacing: WindowLayout.spacing) {
                    StatCard(
                        title: "CPU", symbol: "cpu", value: store.sampled ? store.cpu : nil, history: store.cpuHistory,
                        detail: nil, tint: SystemStatsWidget.cpuTint, filled: false)
                    StatCard(
                        title: "Memory", symbol: "memorychip", value: store.memory.fraction,
                        history: store.memoryHistory, detail: memoryText, tint: SystemStatsWidget.ramTint, filled: true)
                }
                MacInfoCard(memory: store.memory)
                Text("The charts show about the last 40 seconds.")
                    .wispFont(.subheadline).foregroundStyle(Color.secondaryText)
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

/// What the Mac is: its chip's cores, memory, macOS version, how long it's been up and how warm.
private struct MacInfoCard: View {
    let memory: MemoryUsage

    var body: some View {
        let info = ProcessInfo.processInfo
        WindowCard(title: "This Mac", symbol: "laptopcomputer", tint: .gray) {
            TimelineView(.everyMinute) { _ in
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .leading)], spacing: 12) {
                    fact("Cores", "\(info.activeProcessorCount)")
                    fact(
                        "Memory",
                        ByteCountFormatter.string(fromByteCount: Int64(memory.totalBytes), countStyle: .memory))
                    fact("macOS", info.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: ""))
                    fact("Up for", AccessibilityText.duration(info.systemUptime))
                    fact("Temperature", thermal(info.thermalState))
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).wispFont(.subheadline).foregroundStyle(Color.secondaryText)
            Text(value).wispFont(.body, weight: .semibold).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        @unknown default: "Unknown"
        }
    }
}

private struct StatCard: View {
    let title: String
    let symbol: String
    /// Nil until the first reading, shown as a dash.
    let value: Double?
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
                .wispFont(.body, weight: .semibold)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    ValueText(text: value.map { "\(LevelStep.percent($0))" } ?? "–", size: 30)
                    Text("%").wispFont(.body, weight: .semibold).foregroundStyle(Color.secondaryText)
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
            .wispFont(.subheadline)
            .foregroundStyle(Color.secondaryText)
        }
        .padding(16)
        .windowCardBackground()
        .accessibilityElement(children: .combine)
    }
}

// MARK: Weather

/// Weather in the window: the current conditions large, then the next hours the store already
/// has. Nothing new is fetched; the store reads at most every 30 minutes.
struct WeatherPage: View {
    let store: WeatherStore
    @Environment(\.wispTextScale) private var textScale

    var body: some View {
        WindowWidgetPage(width: .readable) {
            WindowPageHeader(
                symbol: "cloud.sun.fill", tint: .cyan, title: "Weather",
                subtitle: store.reading.map { $0.place.isEmpty ? "Where you are" : $0.place } ?? "Where you are"
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") { store.retry() }
                    .labelStyle(.iconOnly)
                    .help("Refresh")
                    .disabled(store.loading)
            }
        } content: { width in
            if let reading = store.reading {
                VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                    current(reading)
                    if !reading.hours.isEmpty {
                        WindowCard(title: "Next hours", symbol: "clock", tint: .blue) {
                            LazyVGrid(
                                columns: windowGridColumns(width: width - 32, minimum: 100), spacing: 12
                            ) {
                                ForEach(reading.hours) { hour in hourCard(hour) }
                            }
                        }
                    }
                }
            } else {
                WindowCard(title: "Today", symbol: "cloud.sun", tint: .cyan) {
                    if store.loading {
                        LoadingLabel(store.status).frame(minHeight: 200)
                    } else {
                        WindowEmptyState(symbol: "cloud.sun", title: "No weather yet", message: store.status) {
                            if store.failed {
                                WindowPrimaryButton(title: "Try again", symbol: "arrow.clockwise") { store.retry() }
                            }
                        }
                    }
                }
            }
        }
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
                    .wispFont(.body, weight: .semibold)
                    .foregroundStyle(Color.secondaryText)
                Text("\(Int(reading.temperature.rounded()))°")
                    .font(.system(size: TextStyleSize.scaled(60, by: textScale), weight: .regular, design: .rounded))
                Text("\(now.title) · H:\(Int(reading.high.rounded()))° L:\(Int(reading.low.rounded()))°")
                    .wispFont(.body, weight: .medium)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .windowCardBackground()
        .accessibilityElement(children: .combine)
    }

    private func hourCard(_ hour: WeatherStore.Hour) -> some View {
        let date = Calendar.current.date(bySettingHour: hour.hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return VStack(spacing: 8) {
            Text(date, format: .dateTime.hour())
                .wispFont(.callout, weight: .medium).foregroundStyle(Color.secondaryText)
            Image(systemName: WeatherCode.describe(hour.code, isDay: hour.isDay).symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 24))
            Text("\(Int(hour.temperature.rounded()))°").wispFont(.title3, weight: .semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous).fill(.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}
