import AppKit
import Contacts

/// Contact photos for notification senders, matched by name. Falls back to initials.
@MainActor
final class ContactAvatars {
    private let store = CNContactStore()
    private var cache: [String: NSImage] = [:]
    private var misses: Set<String> = []

    func image(for name: String) -> NSImage? {
        guard !name.isEmpty, CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        if let cached = cache[name] { return cached }
        guard !misses.contains(name) else { return nil }

        let keys: [CNKeyDescriptor] = [
            CNContactThumbnailImageDataKey as NSString, CNContactImageDataAvailableKey as NSString,
        ]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let contact = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys))?
            .first { $0.imageDataAvailable }
        guard let data = contact?.thumbnailImageData, let image = NSImage(data: data) else {
            misses.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }

    static func initials(for name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
