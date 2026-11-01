import AppKit
import SwiftUI
import WispCore

struct PermissionSettings: View {
    /// Re-reads the sidebar badge after a grant.
    let onChange: () -> Void
    @State private var refresh = 0
    /// Screen Recording reaches Wisp only after a relaunch, so once asked, offer one.
    @State private var askedScreenRecording = false

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title)
                            Text(permission.purpose).font(.caption).foregroundStyle(.secondary)
                            if needsReopen(permission) {
                                Text("Takes effect after Wisp reopens").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if let granted = permission.isGranted {
                            StatusDot(granted: granted)
                            if needsReopen(permission) {
                                Button("Reopen Wisp") { Relaunch.now() }
                            } else if !granted {
                                Button("Allow") {
                                    permission.request()
                                    if permission == .screenRecording { askedScreenRecording = true }
                                    onChange()
                                }
                            }
                        } else {
                            // No status to read (it's per app), but asking still lists Wisp.
                            Button("Allow") { permission.request() }
                        }
                    }
                    .id("\(permission.rawValue)-\(refresh)")
                }
            } footer: {
                Button("Refresh") {
                    refresh += 1
                    onChange()
                }
            }
        }
        .formStyle(.grouped)
        // Grants happen in System Settings, so follow them while this pane is open.
        .task {
            var last = Permission.statuses
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let now = Permission.statuses
                guard now != last else { continue }
                last = now
                refresh += 1
                onChange()
            }
        }
    }

    private func needsReopen(_ permission: Permission) -> Bool {
        permission == .screenRecording && askedScreenRecording && permission.isGranted == false
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
