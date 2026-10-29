import CoreGraphics
import Foundation

/// Built-in display brightness. macOS has no public API for this on Apple silicon,
/// so it uses the private DisplayServices framework, loaded at runtime. If the
/// symbols are missing, brightness keys are left to the system.
@MainActor
enum DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    // dlsym returns an untyped pointer; reinterpreting it as the C function type is
    // the only way to call a symbol resolved at runtime.
    private static let getter: GetBrightness? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetBrightness.self) }
    private static let setter: SetBrightness? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetBrightness.self) }

    /// The built-in panel, if one is active.
    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var isAvailable: Bool { getter != nil && setter != nil && builtInDisplay != nil }

    static var brightness: Double? {
        guard let getter, let display = builtInDisplay else { return nil }
        var value: Float = 0
        return getter(display, &value) == 0 ? Double(value) : nil
    }

    @discardableResult
    static func setBrightness(_ value: Double) -> Bool {
        guard let setter, let display = builtInDisplay else { return false }
        return setter(display, Float(min(max(value, 0), 1))) == 0
    }
}
