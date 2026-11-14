import SwiftUI
import WispCore

/// Settings › Agents › Quiet hours: a daily window (it may cross midnight) when the chosen
/// alert groups stay silent, then the "While you were away" card.
struct AgentQuietHoursSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Toggle("Quiet hours", isOn: $preferences.quietHours.on)
            if preferences.quietHours.on {
                DatePicker("From", selection: time(\.start), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: time(\.end), displayedComponents: .hourAndMinute)
                ForEach(AgentAlertGroup.allCases) { group in
                    Toggle(group.title, isOn: chosen(group))
                }
            }
            Toggle("Show what happened while I was away", isOn: $preferences.awaySummary)
        } header: {
            Text("Quiet hours")
        } footer: {
            Text(
                "In quiet hours the chosen alerts make no sound, send nothing to your phone, and Done cards don't show. Requests still show their card, silently. The bell in the Agents widget mutes everything for an hour. Sounds and Done cards are also skipped while the session's terminal is in front and you're using the Mac. The away card comes after the Mac sleeps, locks or sits idle for 15 minutes or more."
            )
        }
    }

    /// A minute of the day as today's date at that time, for the time pickers.
    private func time(_ path: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let parts = QuietHours.hourAndMinute(preferences.quietHours[keyPath: path])
                return Calendar.current.date(bySettingHour: parts.hour, minute: parts.minute, second: 0, of: .now)
                    ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences.quietHours[keyPath: path] = QuietHours.minuteOfDay(
                    hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            })
    }

    private func chosen(_ group: AgentAlertGroup) -> Binding<Bool> {
        Binding(
            get: { preferences.quietHours.groups.contains(group) },
            set: { on in
                if on {
                    preferences.quietHours.groups.insert(group)
                } else {
                    preferences.quietHours.groups.remove(group)
                }
            })
    }
}
