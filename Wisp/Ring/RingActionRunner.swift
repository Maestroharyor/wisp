import AppKit
import WispCore

/// Runs a ring action through the services that already do the work.
@MainActor
enum RingActionRunner {
    static func run(_ action: RingAction, files: [URL], services: AppServices) {
        if !files.isEmpty {
            runOnFiles(action, files: files, services: services)
            return
        }
        let quick = services.quickActions
        switch action.kind {
        case .home: services.openShelf(.home)
        case .tray: services.openShelf(.tray)
        case .mediaPage: services.openShelf(.media)
        case .widget:
            if let kind = action.value.flatMap(WidgetKind.init(rawValue:)) { services.openWidget(kind) }
        case .agents: services.openWidget(.agents)
        case .playPause: services.nowPlaying.togglePlayPause()
        case .nextTrack: services.nowPlaying.next()
        case .previousTrack: services.nowPlaying.previous()
        case .clipboard: services.openClipboard()
        case .miniPlayer: services.miniPlayer.toggle()
        case .timer:
            services.timers.setTimer(minutes: action.minutes)
            services.timers.toggleTimer()
        case .keepAwake: quick.toggleKeepAwake()
        case .darkMode: quick.toggleDarkMode()
        case .focus: quick.toggleDoNotDisturb()
        case .screenshot: quick.screenshot()
        case .pickColour: quick.pickColor()
        case .lockScreen: quick.lockScreen()
        case .shortcut: if let name = action.value { services.shortcuts.run(name) }
        case .transform: services.openTransform([])
        case .dropAction, .airDrop, .zip, .none: break
        }
    }

    private static func runOnFiles(_ action: RingAction, files: [URL], services: AppServices) {
        switch action.kind {
        case .tray: services.tray.add(files)
        case .airDrop: services.tray.airDrop(files)
        case .zip: services.tray.zip(files)
        case .transform: services.openTransform(files)
        case .dropAction:
            let id = action.value.flatMap(UUID.init(uuidString:))
            if let drop = services.preferences.dropActions.first(where: { $0.id == id }) {
                services.dropActions.run(drop, on: files)
            }
        default: break
        }
    }
}
