import AppKit
import Observation
import WispCore

/// Opens the ring from the mouse button chosen in Settings: hold, move and let go to pick,
/// or press quickly to leave it open for clicking.
@MainActor
final class RingTrigger {
    private let services: AppServices
    private let tap = MouseButtonTap()

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
        tap.stop()
        guard let number = services.preferences.ringButton.number else { return }
        tap.start(button: number)
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
