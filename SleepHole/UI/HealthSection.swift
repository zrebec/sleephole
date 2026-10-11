import SwiftUI

/// Settings → Apple Health (phase HEALTH): the switch for reading when the user really fell asleep, how many nights have
/// sleep data and, while the switch is on and Health can be read, the "Read sleep again" button – it reads every finalized
/// night once more, also those past their three-day window (a night received from another device, a Health source that
/// was fixed later). The values are only ever read on this device and never leave it.
struct HealthSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle(L("Show when you fell asleep"), isOn: Binding(
                get: { model.settings.usesHealth },
                set: { on in Task { await model.setHealth(on: on) } }))
                .disabled(!model.sleepSource.isAvailable)
            if model.showsReadSleepAgain {
                let status = model.sleepStatus
                Text(L("Nights with sleep data: \(status.withData) of \(status.total)"))
                Button(L("Read sleep again")) { Task { await model.readSleepAgain() } }
                    .disabled(!model.canReadSleepAgain)
                if status.withData == 0, status.anyRead {
                    Text(L("No data yet? In the Health app open your profile → Apps → SleepHole and allow Sleep."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L("Apple Health")).id("health")
        } footer: {
            Text(model.sleepSource.isAvailable
                 ? L("SleepHole reads your sleep from Apple Health (an Apple Watch or another sleep app writes it there) and shows when you really fell asleep next to when you went to bed. It only reads – nothing is written to Health and nothing leaves your iPhone.")
                 : L("Apple Health isn't available on this device."))
        }
    }
}
