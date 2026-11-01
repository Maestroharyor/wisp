import AppKit
import OSLog
import WebKit
import WispCore

/// A persistent WhatsApp Web or Telegram Web session used to send replies from the
/// notch. The user logs in once in a visible window; afterwards the page runs in a
/// hidden window. Sending drives the page's own UI, so it can break when the site
/// changes; the selectors live in one table to keep fixes small.
@MainActor
final class WebChatSession: NSObject {
    let channel: ReplyChannel

    private var webView: WKWebView?
    /// Off-screen window that keeps the page running between replies.
    private var hiddenWindow: NSWindow?
    /// The visible window for scanning the login code; the page moves into it while shown.
    private var loginWindow: NSWindow?
    private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "webchat")

    init(channel: ReplyChannel) {
        self.channel = channel
    }

    private struct Site {
        let url: URL
        let title: String
        /// Async JS body for callAsyncJavaScript; receives `name` and `text`, returns a status string.
        let sendScript: String
    }

    private var site: Site? {
        switch channel {
        case .whatsApp:
            guard let url = URL(string: "https://web.whatsapp.com") else { return nil }
            return Site(url: url, title: "WhatsApp", sendScript: Self.whatsAppScript)
        case .telegram:
            guard let url = URL(string: "https://web.telegram.org/k/") else { return nil }
            return Site(url: url, title: "Telegram", sendScript: Self.telegramScript)
        case .iMessage:
            return nil
        }
    }

    /// Shows the page so the user can scan the login QR code.
    func showLogin() {
        guard let site else { return }
        let view = ensureWebView()
        let window =
            loginWindow
            ?? NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 960, height: 720),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
        window.title = "\(site.title) for Wisp"
        window.isReleasedWhenClosed = false
        window.delegate = self
        hiddenWindow?.contentView = nil
        hiddenWindow?.orderOut(nil)
        window.contentView = view
        window.center()
        loginWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens the chat named `name` and sends `text`. Returns false on any failure.
    func send(_ text: String, to name: String) async -> Bool {
        guard let site else { return false }
        let view = ensureWebView()
        if view.url == nil { view.load(URLRequest(url: site.url)) }
        // Give a freshly loaded page time to render its chat list.
        for _ in 0..<20 where view.isLoading {
            try? await Task.sleep(for: .milliseconds(250))
        }
        do {
            let result = try await view.callAsyncJavaScript(
                site.sendScript, arguments: ["name": name, "text": text], contentWorld: .page)
            let status = result.map { "\($0)" } ?? "nil"
            log.notice("\(site.title, privacy: .public) send result: \(status, privacy: .public)")
            return status == "ok"
        } catch {
            log.error("\(site.title, privacy: .public) send failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 960, height: 720), configuration: configuration)
        // The sites refuse unknown browsers; present as Safari.
        view.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        if let site { view.load(URLRequest(url: site.url)) }
        webView = view
        hide(view)
        return view
    }

    /// Pages only run while in a window; keep the page in one off-screen.
    private func hide(_ view: WKWebView) {
        let hidden =
            hiddenWindow
            ?? NSWindow(
                contentRect: CGRect(x: -10_000, y: -10_000, width: 960, height: 720), styleMask: [.borderless],
                backing: .buffered, defer: false)
        hidden.isReleasedWhenClosed = false
        hidden.contentView = view
        hidden.orderBack(nil)
        hiddenWindow = hidden
    }

    /// Each service keeps its own cookies so logins persist across launches.
    private var storeID: UUID {
        let key = "webChatStore.\(channel.rawValue)"
        if let saved = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) { return saved }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    private static let whatsAppScript = """
        const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
        const insert = (el, value) => { el.focus(); document.execCommand('selectAll', false); document.execCommand('insertText', false, value); };
        const search = document.querySelector('div[contenteditable="true"][data-tab="3"]')
            || document.querySelector('div[contenteditable="true"][role="textbox"]');
        if (!search) return 'login';
        insert(search, name);
        await sleep(900);
        const match = [...document.querySelectorAll('span[title]')].find((s) => s.getAttribute('title') === name);
        if (!match) return 'nochat';
        const row = match.closest('[role="listitem"], [role="row"]') || match;
        row.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
        row.click();
        await sleep(700);
        const box = document.querySelector('footer div[contenteditable="true"]');
        if (!box) return 'nobox';
        insert(box, text);
        await sleep(200);
        const send = document.querySelector('footer button[aria-label="Send"]')
            || document.querySelector('span[data-icon="send"], span[data-icon="wds-ic-send-filled"]');
        if (!send) return 'nosend';
        (send.closest('button') || send).click();
        return 'ok';
        """

    private static let telegramScript = """
        const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
        const search = document.querySelector('.input-search input, input.input-search-input');
        if (!search) return 'login';
        search.focus();
        search.value = name;
        search.dispatchEvent(new Event('input', { bubbles: true }));
        await sleep(900);
        const match = [...document.querySelectorAll('.search-group .chatlist-chat, .chatlist-chat')]
            .find((c) => (c.querySelector('.peer-title')?.textContent || '').trim() === name);
        if (!match) return 'nochat';
        match.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
        match.click();
        await sleep(800);
        const box = document.querySelector('.input-message-input[contenteditable="true"]');
        if (!box) return 'nobox';
        box.focus();
        document.execCommand('insertText', false, text);
        await sleep(200);
        const send = document.querySelector('.btn-send');
        if (!send) return 'nosend';
        send.click();
        return 'ok';
        """
}

extension WebChatSession: NSWindowDelegate {
    /// Closing the login window (the only one with this delegate) puts the page back
    /// off-screen so the session keeps running.
    func windowWillClose(_ notification: Notification) {
        guard let webView else { return }
        loginWindow?.contentView = nil
        hide(webView)
    }
}
