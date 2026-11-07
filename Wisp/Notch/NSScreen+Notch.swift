import AppKit
import WispCore

extension NSScreen {
    var metrics: ScreenMetrics {
        ScreenMetrics(
            frame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeft: auxiliaryTopLeftArea,
            auxiliaryTopRight: auxiliaryTopRightArea
        )
    }

    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Stable across reconnects and rearrangement, unlike the display ID.
    var displayUUID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    /// The Mac's model identifier, such as "Mac15,6".
    static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }()

    func hasSystemIsland(_ setting: IslandSetting) -> Bool {
        SystemIsland.present(setting: setting, modelIdentifier: Self.modelIdentifier, builtIn: isBuiltIn)
    }

    var islandReport: String {
        SystemIsland.report(modelIdentifier: Self.modelIdentifier, builtIn: isBuiltIn, metrics: metrics)
    }
}
