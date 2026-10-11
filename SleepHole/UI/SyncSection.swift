import SwiftUI

/// Settings → iCloud (phase SYNC, step S3): the per-device switch for keeping one town on all of the user's devices, the
/// state of the last sync in plain words and an explanation of what is stored. The switch works at any time – during a
/// night or nap the engine only remembers that a sync is owed (`SyncEngine`). The state is read from the engine, never
/// from the transport; a transport's raw error text is for the developer screen only.
struct SyncSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let status = SyncStatus.of(enabled: model.settings.usesSync, place: model.sync.place,
                                   error: model.sync.lastSyncError, lastSyncAt: model.sync.lastSyncAt)
        Section {
            Toggle(L("Sync through iCloud"), isOn: $model.settings.usesSync)
            if let status {
                Text(status.text(now: model.clock.now)).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(L("iCloud")).id("icloud")
        } footer: {
            Text(L("Your nights, coins and settings are kept in your own iCloud. The town is then the same on all your devices and comes back after you reinstall SleepHole. Nothing from Apple Health is stored there. Start and finish a night on the same device."))
        }
    }
}

extension SyncStatus {
    /// The status line in the current language. `now` decides between "14:05" and "30. 9. 14:05".
    func text(now: Date) -> String {
        switch self {
        case .unavailable: L("iCloud isn't available. Sign in to iCloud and switch on iCloud Drive in the iPhone's Settings.")
        case .failed: L("Couldn't sync just now. SleepHole will try again by itself.")
        case .synced(let at): L("Last synced: \(Fmt.moment(at, now: now))")
        case .notYet: L("Not synced yet")
        }
    }
}
