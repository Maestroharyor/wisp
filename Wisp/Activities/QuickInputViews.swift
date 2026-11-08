import SwiftUI
import WispCore

/// The confirm card under the notch: what a quick request will make, with Cancel and Add.
struct QuickIntentCard: View {
    let intent: QuickIntent
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                QuickIntentSummary(intent: intent, iconSize: 38)
                Spacer(minLength: 8)
                QuickIntentButtons(intent: intent, store: model.services.quickInput)
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
        .overlay(alignment: .topTrailing) { CardCloseGlyph(model: model) }
    }
}

/// The request's icon, what it is and when.
struct QuickIntentSummary: View {
    let intent: QuickIntent
    var iconSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: QuickIntentText.symbol(intent))
                .font(.system(size: iconSize * 0.42, weight: .semibold))
                .foregroundStyle(Color.wispViolet)
                .frame(width: iconSize, height: iconSize)
                .background(Circle().fill(Color.wispViolet.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(QuickIntentText.headline(intent)).font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(QuickIntentText.detail(intent, now: .now, calendar: .autoupdatingCurrent))
                    .font(.system(size: 12)).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
        }
    }
}

struct QuickIntentButtons: View {
    let intent: QuickIntent
    let store: QuickInputStore

    var body: some View {
        HStack(spacing: 8) {
            Button("Cancel") { store.cancel() }
                .buttonStyle(.plain).font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(.ink.opacity(0.14)))
            Button(QuickIntentText.action(intent)) { store.confirm() }
                .buttonStyle(.plain).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 28)
                .background(Capsule().fill(Color.wispViolet))
        }
    }
}

/// Quick add in the shelf: type or dictate a request, then confirm what Wisp read.
struct QuickInputWidget: View {
    @Bindable var store: QuickInputStore
    let dictation: DictationEngine
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick add", systemImage: "text.badge.plus")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.secondaryText)
            HStack(spacing: 6) {
                TextField("25 min, remind me to\u{2026}", text: $store.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { store.submit() }
                if listening {
                    Image(systemName: "waveform").foregroundStyle(Color.wispViolet).symbolEffect(.pulse)
                } else if store.state == .thinking {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ink.opacity(0.08)))
            footer
            Spacer(minLength: 0)
        }
        // The field may still be on its way in (the shelf opening), so focus waits a moment.
        .task(id: store.wantsFocus) {
            guard store.wantsFocus else { return }
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
            store.focusTaken()
        }
        .onChange(of: focused) { _, now in store.fieldFocused(now) }
        .onDisappear { if focused { store.fieldFocused(false) } }
    }

    private var listening: Bool { dictation.phase.isActive && dictation.target == .quickInput }

    @ViewBuilder private var footer: some View {
        if let intent = store.pending {
            VStack(alignment: .leading, spacing: 8) {
                QuickIntentSummary(intent: intent)
                QuickIntentButtons(intent: intent, store: store)
            }
        } else if case .message(let text) = store.state {
            Text(text).font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(2)
        } else if store.state == .thinking {
            Text("Reading\u{2026}").font(.system(size: 11)).foregroundStyle(Color.secondaryText)
        } else {
            Text("A timer, a reminder or an event. Press Return.")
                .font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(2)
        }
    }
}
