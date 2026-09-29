import SleepCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showGuide = false
    @State private var notificationStatus = "…"

    var body: some View {
        @Bindable var model = model
        let nightRunning = model.active != nil
        NavigationStack {
            Form {
                Section("Rozvrh") {
                    ScheduleFields()
                    Button("Ako to funguje") { showGuide = true }
                }
                .disabled(nightRunning)

                Section {
                    HStack {
                        Text("Kód")
                        Spacer()
                        Text(model.settings.wakeCode).font(.title2.monospacedDigit().bold())
                    }
                    Button("Vygenerovať nový kód") { model.settings.wakeCode = AppSettings.randomCode() }
                } header: {
                    Text("Ranné potvrdenie")
                } footer: {
                    Text("Ráno zatras telefónom alebo zadaj tento kód.")
                }

                Section {
                    HStack {
                        Text("Upozornenia")
                        Spacer()
                        Text(notificationStatus).foregroundStyle(.secondary)
                    }
                    Button("Otvoriť nastavenia upozornení") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text("Bez upozornení nepríde varovanie „Vráť sa“ ani záložný budík. Ak máš zapnuté Sústredenie (Spánok, Nerušiť), povoľ v ňom SleepHole.")
                }

                Section("Zvuky") {
                    Picker("Zvuk v noci", selection: $model.settings.ambience) {
                        ForEach(AudioKeeper.Ambience.allCases) { Text($0.rawValue).tag($0) }
                    }
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $model.settings.volume, in: 0...0.6)
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    Picker("Budík", selection: $model.settings.alarmSound) {
                        ForEach(AppSettings.AlarmSound.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: model.settings.alarmSound) { _, sound in
                        if model.active == nil { SoundFX.previewAlarm(sound.rawValue) }
                    }
                    HStack {
                        Button("Prehrať ukážku") { SoundFX.previewAlarm(model.settings.alarmSound.rawValue) }
                        Spacer()
                        Button("Stop") { SoundFX.stopPreview() }
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.active != nil)
                }

                Section("Vývoj") {
                    Button("Rýchla noc (4 min, príprava \(Int(AppModel.debugGrace)) s)") { model.startTestNight() }
                        .disabled(nightRunning)
                    Button("Testovacia noc (15 min, príprava 5 min)") { model.startTestNight(minutes: 15, grace: 300) }
                        .disabled(nightRunning)
                    Toggle("Ďalšia testovacia noc sa počíta do mesta (1×)", isOn: $model.nextTestNightCounts)
                        .disabled(nightRunning)
                    NavigationLink("Nočný denník") { NightLogView() }
                    NavigationLink("Test detekcie (F2)") { DetectionTestView() }
                    Button("Znova ukázať sprievodcu a prvú noc") { model.resetGuide() }
                        .disabled(nightRunning)
                }
            }
            .navigationTitle("Nastavenia")
            .sheet(isPresented: $showGuide) { GuideView(replay: true) }
            .task { notificationStatus = await Notifications.statusText() }
        }
    }
}

/// Debug: all nights with their events and outcome.
struct NightLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.records().reversed()) { rec in
            DisclosureGroup {
                ForEach(Array(rec.log.sortedEvents.enumerated()), id: \.offset) { _, e in
                    HStack {
                        Text(ProbeLog.timeFormat.string(from: e.at)).font(.caption2.monospacedDigit())
                        Text(e.kind.rawValue).font(.caption.monospaced())
                    }
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("\(rec.keyString)\(rec.isDebug ? " · test" : "") · \(rec.outcome?.rawValue ?? "prebieha")")
                    Text("\(rec.buildingId) · mimo \(Int(rec.awaySeconds)) s").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Nočný denník")
        .toolbar {
            Button("Vymazať", role: .destructive) { model.clearNights() }
                .disabled(model.active != nil)
        }
    }
}
