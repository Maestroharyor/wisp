import AppKit
import SwiftUI
import WispCore

struct PermissionSettings: View {
    /// Holds the statuses; the Settings window re-reads them every second.
    let model: SettingsModel
    /// Screen Recording may reach Wisp only after a relaunch, so once asked, offer one.
    @State private var askedScreenRecording = false

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    let status = model.statuses[permission.rawValue] ?? nil
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title)
                            Text(permission.purpose).font(.caption).foregroundStyle(.secondary)
                            if offersReopen(permission, status: status) {
                                Text(reopenHint).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if let status { StatusDot(granted: status) }
                        if offersReopen(permission, status: status), Relaunch.isAvailable {
                            Button("Reopen Wisp") { Relaunch.now() }
                        }
                        // With no status (Automation while nothing can answer), asking still lists Wisp.
                        if status != true {
                            Button("Allow") {
                                permission.request()
                                if permission == .screenRecording { askedScreenRecording = true }
                            }
                        }
                    }
                }
            } footer: {
                Button("Refresh") {
                    Task {
                        await AutomationPermission.refresh()
                        model.refreshHealth()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var reopenHint: String {
        Relaunch.isAvailable
            ? "If you switched it on, reopen Wisp to apply it"
            : "If you switched it on, move Wisp to Applications and open it again"
    }

    private func offersReopen(_ permission: Permission, status: Bool?) -> Bool {
        permission == .screenRecording && askedScreenRecording && status == false
    }
}

struct StatusDot: View {
    let granted: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(granted ? .green : .orange).frame(width: 8, height: 8)
            Text(granted ? "Granted" : "Not granted").foregroundStyle(.secondary)
        }
    }
}
