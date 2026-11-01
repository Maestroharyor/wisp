import Foundation

/// How macOS volumes compare file names: APFS and HFS+ ignore case and Unicode
/// normalisation by default, so "IMG.JPG" and "img.jpg" are the same file.
public enum FileNameKey {
    public static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
    }

    public static func keys(_ names: Set<String>) -> Set<String> {
        Set(names.map(key))
    }
}
