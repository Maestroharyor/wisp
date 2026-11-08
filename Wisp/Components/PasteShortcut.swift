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

    /// Pastes `text` through the clipboard, then puts the user's clipboard back after `delay`
    /// unless something new was copied meanwhile.
    @MainActor
    static func pasteRestoring(_ text: String, after delay: Duration) {
        let saved = snapshot()
        let staged = stage(text)
        send()
        guard let saved else { return }
        Task {
            try? await Task.sleep(for: delay)
            guard
                DictationPaste.shouldRestore(
                    stagedChangeCount: staged, currentChangeCount: NSPasteboard.general.changeCount)
            else { return }
            restore(saved)
        }
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

    /// The clipboard's content, or nil when it can't be put back exactly: a type Wisp doesn't
    /// keep (see `DictationPaste.canCapture`), data that can't be read, or too much of it.
    static func snapshot() -> Snapshot? {
        let items = NSPasteboard.general.pasteboardItems ?? []
        guard DictationPaste.canCapture(itemTypes: items.map { $0.types.map(\.rawValue) }) else { return nil }
        var total = 0
        var snapshot: Snapshot = []
        for item in items {
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                total += data.count
                guard DictationPaste.canRestore(byteCount: total) else { return nil }
                types[type] = data
            }
            snapshot.append(types)
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
