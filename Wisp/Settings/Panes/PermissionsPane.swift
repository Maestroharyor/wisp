import AppKit
import SwiftUI
import WispCore

struct PermissionSettings: View {
    /// Re-reads the sidebar badge after a grant.
    let onChange: () -> Void
    @State private var refresh = 0

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title)
                            Text(permission.purpose).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let granted = permission.isGranted {
                            StatusDot(granted: granted)
                            if !granted {
                                Button("Allow") {
                                    permission.request()
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
