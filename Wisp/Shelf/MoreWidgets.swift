import AVFoundation
import AppKit
import SwiftUI
import WispCore

// MARK: Quick Toggles

struct QuickTogglesWidget: View {
    let actions: QuickActions

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ToggleTile(symbol: "cup.and.saucer.fill", title: "Awake", on: actions.keepAwake, tint: .wispAmber) {
                actions.toggleKeepAwake()
            }
            ToggleTile(symbol: "circle.lefthalf.filled", title: "Dark", on: actions.darkMode, tint: .indigo) {
                actions.toggleDarkMode()
            }
            ToggleTile(symbol: "eye.slash.fill", title: "Desktop", on: actions.desktopHidden, tint: .teal) {
                actions.toggleDesktopIcons()
            }
            ToggleTile(symbol: "moon.fill", title: "Focus", on: false, tint: .purple) {
                actions.toggleDoNotDisturb()
            }
            ToggleTile(symbol: "camera.viewfinder", title: "Capture", on: false, tint: .white) {
                actions.screenshot()
            }
            ToggleTile(symbol: "eyedropper.halffull", title: "Colour", on: false, tint: .white) {
                actions.pickColor()
            }
            ToggleTile(symbol: "lock.fill", title: "Lock", on: false, tint: .white) {
                actions.lockScreen()
            }
            ToggleTile(symbol: "trash.fill", title: "Trash", on: false, tint: .white) {
                actions.emptyTrash()
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { actions.refresh() }
    }
}

/// A small round control with a caption; filled with its tint while on.
private struct ToggleTile: View {
    let symbol: String
    let title: String
    let on: Bool
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .black : .white.opacity(0.9))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(on ? tint : .white.opacity(hovering ? 0.2 : 0.12)))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
    }
}

// MARK: Shortcuts

struct ShortcutsWidget: View {
    let runner: ShortcutsRunner
    let preferences: Preferences

    var body: some View {
        let names = ShortcutList.favourites(preferences.favouriteShortcuts, available: runner.available)
        Group {
            if names.isEmpty {
                VStack(spacing: 6) {
                    Text(runner.available.isEmpty ? "No Shortcuts found" : "Pick favourites in Settings › Widgets")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    Button("Open Shortcuts") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6
                    ) {
                        ForEach(names, id: \.self) { name in
                            ShortcutChip(name: name, running: runner.running == name) { runner.run(name) }
                        }
                    }
                }
            }
        }
        .onAppear { runner.refresh() }
    }
}

private struct ShortcutChip: View {
    let name: String
    let running: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if running {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(.pink)
                }
                Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.16 : 0.09)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: Clipboard

struct ClipboardWidget: View {
    let store: ClipboardStore

    var body: some View {
        let items = Array(store.history.items.sorted { $0.pinned && !$1.pinned }.prefix(6))
        Group {
            if items.isEmpty {
                Text("Copied items show up here")
                    .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(items) { item in
                            ClipRow(item: item, imageURL: store.imageURL(for: item)) { store.copy(item) }
                        }
                    }
                }
            }
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let imageURL: URL?
    let copy: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            copy()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            HStack(spacing: 7) {
                leading.frame(width: 18, height: 18)
                Text(label).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if copied {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(
                        Color.wispGreen)
                } else if item.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Color.secondaryText)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(hovering ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var leading: some View {
        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(Color.secondaryText)
        }
    }

    private var symbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .color: "paintpalette"
        }
    }

    private var label: String {
        let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Image" : text.replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: Mirror

struct MirrorWidget: View {
    let camera: CameraMirror

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .opacity(camera.state == .running ? 1 : 0)
            switch camera.state {
            case .denied:
                VStack(spacing: 6) {
                    Image(systemName: "video.slash.fill").font(.system(size: 16))
                    Button("Allow Camera") { Permission.camera.openSettings() }.controlSize(.small)
                }
            case .unavailable:
                Label("No camera", systemImage: "video.slash").font(.system(size: 12))
            case .idle:
                ProgressView().controlSize(.small)
            case .running:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { camera.attach() }
        .onDisappear { camera.detach() }
    }
}

/// A mirrored live preview layer for the capture session.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: Day Progress

struct DayProgressWidget: View {
    let calendar: CalendarStore
    let preferences: Preferences

    var body: some View {
        TimelineView(.everyMinute) { context in
            let day = DayProgress(startHour: preferences.workdayStart, endHour: preferences.workdayEnd)
            let fraction = day.fraction(at: context.date)
            let left = day.minutesLeft(at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    ValueText(text: "\(Int((fraction * 100).rounded()))%", tint: .accentColor, size: 24)
                    Text("of the day").font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    Spacer(minLength: 0)
                    Text(left > 0 ? "\(left / 60)h \(left % 60)m left" : "Done for today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(left > 0 ? .white.opacity(0.85) : Color.wispGreen)
                }
                DayBar(fraction: fraction, marks: day.marks(for: calendar.dayEvents, on: context.date))
                    .frame(height: 14)
                HStack {
                    Text(hourLabel(day.startHour))
                    Spacer()
                    Text(hourLabel(day.endHour))
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(Color.secondaryText)
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear { calendar.refresh() }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

/// The work day as a track: event blocks, the elapsed part, and a "now" marker.
private struct DayBar: View {
    let fraction: Double
    let marks: [ClosedRange<Double>]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.22))
                        .frame(width: max(3, (mark.upperBound - mark.lowerBound) * width), height: 8)
                        .offset(x: mark.lowerBound * width)
                }
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.6), .accentColor], startPoint: .leading,
                            endPoint: .trailing)
                    )
                    .frame(width: max(4, fraction * width), height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .accentColor, radius: 4)
                    .offset(x: fraction * width - 5)
            }
            .frame(height: proxy.size.height)
        }
    }
}

// MARK: World Clocks

struct WorldClocksWidget: View {
    let preferences: Preferences

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                let zones = preferences.worldClockZones.compactMap(TimeZone.init(identifier:)).prefix(3)
                if zones.isEmpty {
                    Text("Add cities in Settings › Widgets")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(Array(zones), id: \.identifier) { zone in
                    ClockRow(zone: zone, now: context.date)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct ClockRow: View {
    let zone: TimeZone
    let now: Date

    var body: some View {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: now)
        let offset = zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return HStack(spacing: 6) {
            Image(systemName: WorldClock.isDaytime(hour: hour) ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 9))
                .foregroundStyle(WorldClock.isDaytime(hour: hour) ? Color.wispAmber : Color.indigo)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(WorldClock.cityName(zone.identifier)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(WorldClock.offsetLabel(seconds: offset)).font(.system(size: 9)).foregroundStyle(
                    Color.secondaryText)
            }
            Spacer(minLength: 4)
            Text(now, format: style)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

// MARK: Script

/// The latest output of a user command, refreshed while the widget is visible.
struct ScriptWidget: View {
    let store: ScriptStore
    let preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if preferences.scriptCommand.isEmpty {
                Text("Set a command in Settings › Widgets")
                    .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(store.lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(
                            .system(
                                size: index == 0 ? 15 : 12, weight: index == 0 ? .semibold : .regular,
                                design: .monospaced)
                        )
                        .foregroundStyle(index == 0 ? Color.white : Color.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if let problem = store.problem {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text(problem)
                    } else if let ranAt = store.ranAt {
                        Text(ranAt, style: .relative)
                        Text("ago")
                    }
                    Spacer()
                    Button {
                        Task { await store.refresh(command: preferences.scriptCommand, interval: 0, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Run again")
                    .disabled(store.running)
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Restarts when the saved command or the interval changes.
        .task(id: "\(preferences.scriptCommand)|\(preferences.scriptInterval)") {
            let interval = ScriptOutput.clampedInterval(preferences.scriptInterval)
            while !Task.isCancelled {
                await store.refresh(command: preferences.scriptCommand, interval: interval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}
