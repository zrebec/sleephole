#if DEBUG   // reads `FolderSyncTransport`, which exists in Debug builds only
import SleepCore
import SwiftUI

/// Settings → Developer → Sync test (phase SYNC, step S3): what the sync engine knows right now, with the RAW error text
/// the users never see, and a button that runs one sync at once. For checking two devices (or the simulator and a
/// plain folder) against each other without waiting for the engine's own triggers.
struct SyncTestView: View {
    @Environment(AppModel.self) private var model
    @State private var running = false

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled)
        }
    }

    private func time(_ d: Date?) -> String { d.map { Fmt.timeSec($0) } ?? "–" }

    private func stamp(_ d: Date?) -> String { d.map { "\(Fmt.dayMonth(NightKey(date: $0, calendar: .current))) \(Fmt.timeSec($0))" } ?? "–" }

    private func placeName(_ p: SyncPlace) -> String {
        switch p {
        case .unknown: L("Not tried yet")
        case .available: L("Available")
        case .unavailable: L("Not available")
        }
    }

    var body: some View {
        let sync = model.sync
        let (transportName, fileName) = Self.describe(sync.transport)
        List {
            Section {
                row(L("Transport"), transportName)
                row(L("This device's file"), fileName ?? "–")
                row(L("Sync switch"), model.settings.usesSync ? L("On") : L("Off"))
                row(L("Sync place"), placeName(sync.place))
            }
            Section {
                row(L("Last sync"), time(sync.lastSyncAt))
                row(L("Last error"), sync.lastSyncError ?? "–")
                row(L("Other devices' files read"), "\(sync.othersRead)")
                row(L("Settings stamp"), stamp(model.settings.changedAt))
                row(L("First read done"), sync.firstReadDone ? L("Yes") : L("No"))
                row(L("Sync owed"), sync.isOwed ? L("Yes") : L("No"))
            }
            Section {
                Button(L("Sync now")) {
                    running = true
                    Task {
                        await sync.syncNow()
                        running = false
                    }
                }
                .disabled(running)
            } footer: {
                Text(L("Runs one sync at once. During a night or nap it only remembers that one is owed."))
            }
        }
        .navigationTitle(L("Sync test"))
    }

    /// The transport in use and the name of this device's file in it.
    static func describe(_ transport: any SyncTransport) -> (String, String?) {
        switch transport {
        case let t as FolderSyncTransport: (L("Plain folder"), t.deviceId + ".json")
        case let t as ICloudSyncTransport: (L("iCloud"), ICloudSyncTransport.fileName(forDevice: t.deviceId))
        case is NoSyncTransport: (L("None"), nil)
        default: (String(describing: type(of: transport)), nil)
        }
    }
}
#endif
