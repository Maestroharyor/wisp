import AppKit
import SwiftUI
import WispCore

/// Notification card under the notch (design §12): avatar with an app badge, sender,
/// age and message. Clicking it opens a reply bar when Wisp can answer the app.
struct NotificationCardView: View {
    let item: NotificationItem
    let model: NotchModel

    @State private var sending = false
    @State private var failed = false
    @FocusState private var fieldFocused: Bool

    init(item: NotificationItem, model: NotchModel) {
        self.item = item
        self.model = model
    }

    private var replying: Bool { model.replyingTo?.id == item.id }

    private var draft: Binding<String> {
        Binding(get: { model.replyDraft }, set: { model.replyDraft = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .top, spacing: 12) {
                NotificationAvatar(item: item, avatars: model.services.notifications.avatars)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.sender).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 8)
                        TimelineView(.everyMinute) { context in
                            Text(RelativeAge.short(from: item.date, to: context.date))
                                .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                        }
                    }
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    Text(item.body)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(item.subtitle.isEmpty ? 2 : 1)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)

            if replying {
                replyBar
                    .padding(.horizontal, 14)
                    .frame(height: SurfaceSizing.replyBarHeight)
                    .transition(model.motion.expands ? .opacity.combined(with: .move(edge: .top)) : .opacity)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .onChange(of: replying) { _, now in fieldFocused = now }
        // Rebuilt after another alert took its place: focus the field again.
        .onAppear { if replying { fieldFocused = true } }
    }

    private var replyBar: some View {
        HStack(spacing: 8) {
            TextField(failed ? "Couldn't send. Try again" : placeholder, text: draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($fieldFocused)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(failed ? Color.red.opacity(0.6) : .clear))
            Button(action: send) {
                Image(systemName: sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sending ? "Sending" : "Send reply")
            .disabled(model.replyDraft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
    }

    private var placeholder: String {
        switch item.channel {
        case .iMessage: "iMessage"
        case .whatsApp: "Reply on WhatsApp"
        case .telegram: "Reply on Telegram"
        case nil: "Reply"
        }
    }

    private func send() {
        let text = model.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        failed = false
        Task {
            let ok = await model.services.notifications.reply(to: item, text: text)
            sending = false
            guard ok else {
                failed = true
                return
            }
            model.services.endReply(sentText: text)
            model.onReplyEnded()
        }
    }
}

/// Contact photo (or initials) with the sending app's icon as a badge.
struct NotificationAvatar: View {
    let item: NotificationItem
    let avatars: ContactAvatars
    var size: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let photo = avatars.image(for: item.title) {
                    Image(nsImage: photo).resizable().aspectRatio(contentMode: .fill)
                } else if item.channel != nil, !item.title.isEmpty {
                    ZStack {
                        Circle().fill(
                            LinearGradient(colors: [.gray, .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        Text(ContactAvatars.initials(for: item.title))
                            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    }
                } else if let icon = appIcon {
                    Image(nsImage: icon).resizable()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if item.channel != nil || avatars.image(for: item.title) != nil, let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: size * 0.42, height: size * 0.42)
                    .offset(x: 3, y: 3)
            }
        }
    }

    private var appIcon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.appID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
