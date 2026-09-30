import SleepCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showGuide = false
    @State private var notificationStatus = "…"
    @State private var preview = SoundPreview()
    @State private var importing = false
    @State private var pendingRestore: BackupFile?
    @State private var backupMessage: String?

    var body: some View {
        @Bindable var model = model
        let nightRunning = model.active != nil
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section("Rozvrh") {
                    ScheduleFields()
                    Button("Ako to funguje") { showGuide = true }
                }
                .disabled(nightRunning)

                Section {
                    Picker("Dĺžka", selection: $model.settings.nap.minutes) {
                        ForEach(NapPlan.allowedMinutes, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Od", selection: napTime(\.windowStart), displayedComponents: .hourAndMinute)
                    DatePicker("Do", selection: napTime(\.windowEnd), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Odpočinok")
                } footer: {
                    Text("Odpočinok sa dá začať iba v tomto okne, raz za deň. Za hotový odpočinok dostaneš \(NapPlan.reward(.complete)) 🪙.")
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

                Section {
                    Picker("Zvuk", selection: $model.settings.ambience) {
                        ForEach(AudioKeeper.Ambience.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model.settings.ambience) { _, a in preview.switchTo(a, volume: model.settings.volume) }
                    Picker("Hrať", selection: $model.settings.ambienceMinutes) {
                        ForEach(AppSettings.ambienceTimerOptions, id: \.self) { m in
                            Text(AppSettings.timerTitle(m)).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $model.settings.volume, in: 0...0.6)
                            .onChange(of: model.settings.volume) { _, v in preview.setVolume(v) }
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    PreviewButtons(playing: preview.playing != nil,
                                   play: { preview.play(model.settings.ambience, volume: model.settings.volume,
                                                        seconds: model.settings.ambienceSeconds) },
                                   stop: { preview.stop() })
                        .disabled(model.active != nil || model.settings.ambience == .silence)
                } header: {
                    Text("Zvuk na zaspávanie").id("sounds")
                } footer: {
                    if let end = preview.endsAt {
                        Text("\(model.settings.ambience.detail) Hrá do \(clockFormat.string(from: end)).")
                    } else if preview.playing != nil {
                        Text("\(model.settings.ambience.detail) Hrá, kým nestlačíš ■.")
                    } else {
                        Text(model.settings.ambience.detail)
                    }
                }

                Section {
                    Picker("Budík", selection: $model.settings.alarmSound) {
                        ForEach(AppSettings.AlarmSound.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model.settings.alarmSound) { _, sound in
                        if model.active == nil { SoundFX.previewAlarm(sound.rawValue) }
                    }
                    PreviewButtons(playing: false,
                                   play: { SoundFX.previewAlarm(model.settings.alarmSound.rawValue) },
                                   stop: { SoundFX.stopPreview() })
                        .disabled(model.active != nil)
                } header: {
                    Text("Budík")
                } footer: {
                    Text(model.settings.alarmSound.detail)
                }

                Section {
                    ShareLink(item: BackupDocument(data: (try? model.makeBackup().encoded()) ?? Data()),
                              preview: SharePreview("SleepHole – záloha")) {
                        Label("Exportovať zálohu", systemImage: "square.and.arrow.up")
                    }
                    Button { importing = true } label: {
                        Label("Obnoviť zo zálohy…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(nightRunning)
                } header: {
                    Text("Záloha")
                } footer: {
                    Text("Po každej noci sa záloha uloží aj automaticky: Súbory → Na mojom iPhone → SleepHole → \(BackupFile.fileName).")
                }

                Section("O appke") {
                    NavigationLink("Poďakovanie") { CreditsView() }
                }

                Section("Vývoj") {
                    Button("Rýchla noc (4 min, príprava \(Int(AppModel.debugGrace)) s)") { model.startTestNight() }
                        .disabled(nightRunning)
                    Button("Testovacia noc (15 min, príprava 5 min)") { model.startTestNight(minutes: 15, grace: 300) }
                        .disabled(nightRunning)
                    Toggle("Ďalšia testovacia noc sa počíta do mesta", isOn: $model.nextTestNightCounts)
                        .disabled(nightRunning)
                    NavigationLink("Nočný denník") { NightLogView() }
                    NavigationLink("Test detekcie (F2)") { DetectionTestView() }
                    Button("Znova ukázať sprievodcu a prvú noc") { model.resetGuide() }
                        .disabled(nightRunning)
                }
            }
            .onAppear {                                   // `-scrollTo sounds` (screenshots)
                if ProcessInfo.processInfo.arguments.contains("sounds") { proxy.scrollTo("sounds", anchor: .top) }
            }
            }
            .navigationTitle("Nastavenia")
            .sheet(isPresented: $showGuide) { GuideView(replay: true) }
            .task { notificationStatus = await Notifications.statusText() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    pendingRestore = try BackupFile.decode(Data(contentsOf: url))
                } catch {
                    backupMessage = "Súbor sa nedá prečítať: \(error.localizedDescription)"
                }
            }
            .confirmationDialog("Obnoviť zálohu? Terajšie noci, mesto a nastavenia sa nahradia.",
                                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible) {
                Button("Obnoviť", role: .destructive) {
                    if let b = pendingRestore {
                        do {
                            try model.restore(b)
                            backupMessage = "Obnovené: \(b.nights.count) nocí ✓"
                        } catch { backupMessage = error.localizedDescription }
                    }
                    pendingRestore = nil
                }
            }
            .alert(backupMessage ?? "", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

extension SettingsView {
    func napTime(_ path: WritableKeyPath<NapPlan, TimeOfDay>) -> Binding<Date> {
        Binding {
            let t = model.settings.nap[keyPath: path]
            return Calendar.current.date(from: DateComponents(hour: t.hour, minute: t.minute)) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.settings.nap[keyPath: path] = TimeOfDay(c.hour ?? 0, c.minute ?? 0)
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
                    Text("\(rec.keyString)\(rec.isNap ? " · odpočinok" : "")\(rec.isDebug ? " · test" : "") · \(rec.outcome?.rawValue ?? "prebieha")")
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

/// Round ▶ / ■ preview buttons (Liquid Glass on iOS 26), left-aligned. `.borderless` gives each button its own
/// hit area – with default styles a List row fires ALL its buttons on a tap (owner bug 2026-09-30).
struct PreviewButtons: View {
    var playing = false
    let play: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            GlassCircleButton(systemImage: "play.fill", label: "Prehrať ukážku", highlighted: playing, action: play)
            GlassCircleButton(systemImage: "stop.fill", label: "Zastaviť", action: stop)
            Spacer()
        }
    }
}

struct GlassCircleButton: View {
    let systemImage: String
    let label: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(highlighted ? Color.accentColor : .primary)
                .frame(width: 46, height: 46)
                .modifier(GlassCircle())
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.thinMaterial, in: Circle())
        }
    }
}
