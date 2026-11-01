/// `CFBundleVersion` derived from the marketing version, so Sparkle always sees a
/// larger number for a newer release: major * 10000 + minor * 100 + patch.
/// `scripts/release.sh` applies the same formula.
public enum BuildNumber {
    public static func from(version: String) -> Int? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        let (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
        guard minor < 100, patch < 100 else { return nil }
        return major * 10000 + minor * 100 + patch
    }
}
