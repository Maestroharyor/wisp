import AppKit
import WispCore

/// Sends ⌘V to the app in front. Needs Accessibility.
enum PasteShortcut {
    /// Everything on the pasteboard, item by item, so it can be put back after a paste.
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    static func send() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Puts `text` on the pasteboard marked transient, so clipboard managers (Wisp's own
    /// history included) don't keep it. Returns the pasteboard's change count afterwards.
    @discardableResult
    static func stage(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: transientType)
        return pasteboard.changeCount
    }

    /// The kinds of clipboard content worth putting back. App-private types (and promised
    /// data that would make the source app render it now) are skipped.
    private static let restorableTypes: [NSPasteboard.PasteboardType] = [
        .string, .rtf, .png, .tiff, .fileURL, .URL,
    ]

    /// The clipboard's common content, or nil when it's too big to hold and put back.
    static func snapshot() -> Snapshot? {
        var total = 0
        var snapshot: Snapshot = []
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in restorableTypes where item.types.contains(type) {
                guard let data = item.data(forType: type) else { continue }
                total += data.count
                guard DictationPaste.canRestore(byteCount: total) else { return nil }
                types[type] = data
            }
            if !types.isEmpty { snapshot.append(types) }
        }
        return snapshot
    }

    /// Puts a snapshot back, marked transient so clipboard history doesn't add it a second time.
    static func restore(_ snapshot: Snapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.enumerated().map { index, types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            if index == 0 { item.setString("", forType: transientType) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}
