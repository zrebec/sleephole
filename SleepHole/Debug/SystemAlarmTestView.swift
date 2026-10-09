import SwiftUI

/// Settings → Developer → System alarm test: rings the system alarm (AlarmKit) 20 seconds from now, so the owner can
/// check in a minute – without a night – that it sounds in silent mode and during a Focus, with the chosen alarm sound.
/// The alarm is scheduled like a safety alarm (see `AppModel.testSystemAlarm`).
struct SystemAlarmTestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// The consent as the phone reports it; read when the screen opens, after the question and after iOS Settings.
    @State private var consent: SystemAlarmConsent = .unavailable

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L("System alarm"))
                    Spacer()
                    Text(consent.title).foregroundStyle(.secondary)
                }
                if consent == .notAsked {
                    Button(L("Allow")) {
                        Task { consent = await model.systemAlarm.requestConsent() }
                    }
                }
                if consent == .denied {
                    Text(L("To allow it, open iOS Settings → SleepHole."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button(L("Ring in 20 seconds")) { model.testSystemAlarm() }
                    .disabled(consent != .allowed || !model.canTestSystemAlarm)
                Button(L("Cancel the test alarm")) { model.cancelTestSystemAlarm() }
                    .disabled(model.testAlarmAt == nil)
                Button(L("Stop the ringing alarm")) { model.stopRingingSystemAlarms() }
                if let at = model.testAlarmAt {
                    Label(L("Test alarm set for \(Fmt.timeSec(at))"), systemImage: "alarm.fill")
                }
            } footer: {
                Text(L("While it waits, Today shows it as a safety alarm – switching that off cancels the test too."))
            }
            Section {
                Text(L("1. Tap “Ring in 20 seconds”."))
                Text(L("2. Lock the phone, or swipe SleepHole away."))
                Text(L("3. The system alarm must ring – in silent mode and during a Focus too – with your alarm sound."))
                Text(L("4. “Stop” silences it; “Open SleepHole” opens the app."))
            }
        }
        .navigationTitle(L("System alarm test"))
        .task { consent = model.systemAlarm.consent }
        // back from iOS Settings: the answer there may have changed
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consent = model.systemAlarm.consent }
        }
    }
}
