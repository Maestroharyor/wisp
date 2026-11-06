import Foundation
import IOKit.pwr_mgt

/// One named IOKit power assertion, held or released. macOS drops it if Wisp quits.
@MainActor
final class SleepAssertion {
    private(set) var isHeld = false
    private var id: IOPMAssertionID = 0
    private let type: String
    private let name: String

    /// `type` is an IOKit assertion type such as `kIOPMAssertionTypePreventUserIdleSystemSleep`.
    init(type: String, name: String) {
        self.type = type
        self.name = name
    }

    @discardableResult
    func hold() -> Bool {
        guard !isHeld else { return true }
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id)
        isHeld = result == kIOReturnSuccess
        return isHeld
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(id)
        id = 0
        isHeld = false
    }
}
