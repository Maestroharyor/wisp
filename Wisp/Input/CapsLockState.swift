import IOKit
import IOKit.hidsystem

/// Reads and flips the Caps Lock state directly, so a quick press of the remapped
/// key can still toggle Caps Lock.
enum CapsLockState {
    static func toggle() {
        withConnection { connect in
            var current = false
            guard IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &current) == KERN_SUCCESS else {
                return
            }
            IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !current)
        }
    }

    private static func withConnection(_ body: (io_connect_t) -> Void) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS
        else { return }
        defer { IOServiceClose(connect) }
        body(connect)
    }
}
