#if DEBUG   // developer screen: not part of Release builds
import SleepCore
import SwiftUI

/// Settings → Developer → Pre-alarm lab (W7, build 14b1): measures, without a night, whether an Apple Watch buzzes for a
/// SILENT AlarmKit alarm 30 seconds before the alarm, whether the iPhone lights up, and whether the pre-alarm leaves the
/// real (test) alarm alone. Nothing here touches a real night. The pre-alarm in Developer test nights has its own toggles.
struct PreAlarmLabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var consent: SystemAlarmConsent = .unavailable
    /// What AlarmKit holds for the app, refreshed every second while the screen is open.
    @State private var alarms: [SystemAlarmInfo] = []
    @AppStorage(AppModel.preAlarmTestNightsKey) private var testNights = true
    @AppStorage(AppModel.preAlarmKeepAliveKey) private var keepAlive = true

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L("System alarm"))
                    Spacer()
                    Text(consent.title).foregroundStyle(.secondary)
                }
                if consent == .notAsked {
                    Button(L("Allow")) { Task { consent = await model.systemAlarm.requestConsent() } }
                }
                if consent == .denied {
                    Text(L("To allow it, open iOS Settings → SleepHole.")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button(L("Silent pre-alarm in 20s")) { model.labPreAlarm(after: 20) }
                    .disabled(!canRun)
                Button(L("Silent pre-alarm in 20s – the app stops it \(Int(PreAlarmPlan.lead))s later")) {
                    model.labPreAlarm(after: 20, appStopsAfter: PreAlarmPlan.lead)
                }
                .disabled(!canRun)
                Button(L("Stop the pre-alarm")) { model.labStopPreAlarm() }
                Button(L("Real alarm + pre-alarm")) { model.labRealAndPreAlarm() }
                    .disabled(!canRun || !model.canTestSystemAlarm)
                Button(L("Stop the real alarm only")) { model.labStopTestAlarmOnly() }
                    .disabled(model.testAlarmAt == nil)
                Button(L("Stop the ringing alarm")) { model.stopRingingSystemAlarms() }
            } footer: {
                Text(L("“Real alarm + pre-alarm” sets the test system alarm at +45s and the pre-alarm at +20s. The two stop separately: “Stop the pre-alarm” leaves the real alarm, “Stop the real alarm only” leaves the pre-alarm. Keep SleepHole open until the pre-alarm has fired when the app stops it."))
            }
            Section(L("Alarms of the app")) {
                if alarms.isEmpty {
                    Text(L("None")).foregroundStyle(.secondary)
                }
                ForEach(alarms.indices, id: \.self) { i in
                    HStack {
                        Text(roleTitle(alarms[i].role))
                        Spacer()
                        Text(verbatim: "…\(alarms[i].idSuffix) · \(stateTitle(alarms[i].state))").foregroundStyle(.secondary)
                    }
                }
                Button(L("Refresh the list")) { alarms = model.systemAlarm.alarmSnapshot() }
            }
            Section {
                Toggle(L("Pre-alarm in test nights"), isOn: $testNights)
                Toggle(L("Keep-alive for the pre-alarm"), isOn: $keepAlive)
            } footer: {
                Text(L("A quick night (Developer) then sets the silent pre-alarm \(Int(PreAlarmPlan.lead))s before its wake time. Real nights, naps and counted test nights never get one. Without the keep-alive the app may be suspended while the pre-alarm rings."))
            }
            Section(L("Checklist")) {
                Text(L("A1. Silent pre-alarm in 20s, lock the iPhone, Apple Watch on the wrist. Does the Watch buzz, and for how long (stopwatch)? Haptic only, or also a tone? Does the iPhone light up, show a full-screen alarm, make a sound or vibrate?"))
                Text(L("A2. The same with Sleep Focus on (the Watch in sleep mode)."))
                Text(L("A3. Stop it on the Watch: does the iPhone's alert go too? Then stop it on the iPhone: does the Watch go too? With “Real alarm + pre-alarm”: is the real alarm still in the list after the pre-alarm was stopped?"))
                Text(L("A4. Leave it alone: when does it end by itself?"))
                Text(L("A5. The same with the ring / silent switch on silent."))
                Text(L("A6. The Watch off the wrist: what does the iPhone show?"))
                Text(L("A7. SleepHole open and unlocked when it fires: what is shown, does the app leave the foreground?"))
                Text(L("B1. Developer → Quick night, gentle mode, a sleep sound playing, iPhone locked: the Watch buzzes \(Int(PreAlarmPlan.lead))s before the wake time, our alarm rings on time, the pre-alarm disappears."))
            }
        }
        .navigationTitle(L("Pre-alarm lab"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            consent = model.systemAlarm.consent
            while !Task.isCancelled {
                alarms = model.systemAlarm.alarmSnapshot()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // back from iOS Settings: the answer there may have changed
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consent = model.systemAlarm.consent }
        }
    }

    private var canRun: Bool { consent == .allowed && model.active == nil }

    private func roleTitle(_ role: String) -> String {
        switch role {
        case "backup": L("Real alarm")
        case "warning": L("Warning alarm")
        case "pre-alarm": L("Pre-alarm")
        default: L("Other alarm")
        }
    }

    private func stateTitle(_ state: String) -> String {
        switch state {
        case "scheduled": L("waiting")
        case "ringing": L("ringing")
        case "countdown": L("countdown")
        case "paused": L("paused")
        default: state
        }
    }
}
#endif
