import AppKit
import Observation
import WispCore

/// Opens the ring from the mouse button chosen in Settings: hold, move and let go to pick,
/// or press quickly to leave it open for clicking.
@MainActor
@Observable
final class RingTrigger {
    enum Status: Equatable {
        case off
        case active
        case needsAccessibility

        var message: String {
            switch self {
            case .off: "Off"
            case .active: "Active"
            case .needsAccessibility: "Waiting for Accessibility access"
            }
        }
    }

    private(set) var status: Status = .off
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let tap = MouseButtonTap()
    @ObservationIgnored private var accessWaiter: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
        tap.onPress = { [weak self] point in
            guard let ring = self?.services.ring else { return }
            if ring.isVisible { ring.hide() } else { ring.show(at: point, holding: true) }
        }
        tap.onMove = { [weak self] point in self?.services.ring.pointerMoved(to: point) }
        tap.onRelease = { [weak self] point in self?.services.ring.released(at: point) }
    }

    func start() {
        configure()
        observe()
    }

    private func configure() {
        accessWaiter?.cancel()
        tap.stop()
        guard let number = services.preferences.ringButton.number else {
            status = .off
            return
        }
        if tap.start(button: number) {
            status = .active
            return
        }
        // The tap needs Accessibility; start once it's granted rather than failing silently.
        status = .needsAccessibility
        accessWaiter = Task { [weak self] in
            await AccessibilityPermission.waitUntilTrusted()
            guard !Task.isCancelled else { return }
            self?.configure()
        }
    }

    private func observe() {
        withObservationTracking {
            _ = services.preferences.ringButton
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.configure()
                self?.observe()
            }
        }
    }
}
