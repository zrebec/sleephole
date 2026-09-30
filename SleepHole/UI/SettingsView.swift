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
    @State private var townNameDraft = ""

    var body: some View {
        @Bindable var model = model
        let nightRunning = model.active != nil
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    LanguagePicker()
                } header: {
                    Text(verbatim: "Language · Jazyk")
                }

                Section {
                    TextField(L("My Town"), text: $townNameDraft)
                        .submitLabel(.done)
                        .onSubmit { model.renameTown(townNameDraft) }
                        .onAppear { townNameDraft = model.customTownName ?? "" }
                        .onDisappear { model.renameTown(townNameDraft) }
                } header: {
                    Text(L("Town name"))
                } footer: {
                    Text(L("Shown above your town. Leave it empty for the default name."))
                }

                Section(L("Schedule")) {
                    ScheduleFields()
                    Button(L("How it works")) { showGuide = true }
                }
                .disabled(nightRunning)

                Section {
                    Picker(L("Length"), selection: $model.settings.nap.minutes) {
                        ForEach(NapPlan.allowedMinutes, id: \.self) { Text(L("\($0) min")).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker(L("From"), selection: napTime(\.windowStart), displayedComponents: .hourAndMinute)
                    DatePicker(L("To"), selection: napTime(\.windowEnd), displayedComponents: .hourAndMinute)
                } header: {
                    Text(L("Nap"))
                } footer: {
                    Text(L("A nap can only start in this window, once a day. A complete nap earns \(NapPlan.reward(.complete)) 🪙."))
                }
                .disabled(nightRunning)

                Section {
                    HStack {
                        Text(L("Code"))
                        Spacer()
                        Text(model.settings.wakeCode).font(.title2.monospacedDigit().bold())
                    }
                    Button(L("Generate a new code")) { model.settings.wakeCode = AppSettings.randomCode() }
                } header: {
                    Text(L("Morning confirmation"))
                } footer: {
                    Text(L("In the morning shake your phone or enter this code."))
                }

                Section {
                    HStack {
                        Text(L("Notifications"))
                        Spacer()
                        Text(notificationStatus).foregroundStyle(.secondary)
                    }
                    Button(L("Open notification settings")) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text(L("Without notifications you won't get the “Come back” warning or the backup alarm. If you use a Focus (Sleep, Do Not Disturb), allow SleepHole in it."))
                }

                Section {
                    Picker(L("Sound"), selection: $model.settings.ambience) {
                        ForEach(AudioKeeper.Ambience.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model.settings.ambience) { _, a in preview.switchTo(a, volume: model.settings.volume) }
                    Picker(L("Play for"), selection: $model.settings.ambienceMinutes) {
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
                    Text(L("Sleep sound")).id("sounds")
                } footer: {
                    if let end = preview.endsAt {
                        Text(L("\(model.settings.ambience.detail) Playing until \(Fmt.time(end))."))
                    } else if preview.playing != nil {
                        Text(L("\(model.settings.ambience.detail) Playing until you press ■."))
                    } else {
                        Text(model.settings.ambience.detail)
                    }
                }

                Section {
                    Picker(L("Alarm"), selection: $model.settings.alarmSound) {
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
                    Text(L("Alarm"))
                } footer: {
                    Text(model.settings.alarmSound.detail)
                }

                Section {
                    ShareLink(item: BackupDocument(data: (try? model.makeBackup().encoded()) ?? Data()),
                              preview: SharePreview(L("SleepHole – backup"))) {
                        Label(L("Export backup"), systemImage: "square.and.arrow.up")
                    }
                    Button { importing = true } label: {
                        Label(L("Restore from backup…"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(nightRunning)
                } header: {
                    Text(L("Backup"))
                } footer: {
                    Text(L("After every night a backup is also saved automatically: Files → On My iPhone → SleepHole → \(BackupFile.fileName)."))
                }

                Section(L("About")) {
                    NavigationLink(L("Credits")) { CreditsView() }
                }

                Section(L("Developer")) {
                    Button(L("Quick night (4 min, \(Int(AppModel.debugGrace)) s setup)")) { model.startTestNight() }
                        .disabled(nightRunning)
                    Button(L("Test night (15 min, 5 min setup)")) { model.startTestNight(minutes: 15, grace: 300) }
                        .disabled(nightRunning)
                    Toggle(L("Next test night counts for the town"), isOn: $model.nextTestNightCounts)
                        .disabled(nightRunning)
                    NavigationLink(L("Night journal")) { NightLogView() }
                    NavigationLink(L("Detection test (F2)")) { DetectionTestView() }
                    Button(L("Show the guide and first night again")) { model.resetGuide() }
                        .disabled(nightRunning)
                }
            }
            .onAppear {                                   // `-scrollTo sounds` (screenshots)
                if ProcessInfo.processInfo.arguments.contains("sounds") { proxy.scrollTo("sounds", anchor: .top) }
            }
            }
            .navigationTitle(L("Settings"))
            .sheet(isPresented: $showGuide) { GuideView(replay: true) }
            .task { notificationStatus = await Notifications.statusText() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    pendingRestore = try BackupFile.decode(Data(contentsOf: url))
                } catch {
                    backupMessage = L("The file can't be read: \(error.localizedDescription)")
                }
            }
            .confirmationDialog(L("Restore the backup? Your current nights, town and settings will be replaced."),
                                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible) {
                Button(L("Restore"), role: .destructive) {
                    if let b = pendingRestore {
                        do {
                            try model.restore(b)
                            backupMessage = L("Restored: \(b.nights.count) nights ✓")
                        } catch { backupMessage = error.localizedDescription }
                    }
                    pendingRestore = nil
                }
            }
            .alert(backupMessage ?? "", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
                Button(L("OK"), role: .cancel) {}
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
                    Text(verbatim: rec.keyString + (rec.isNap ? " · " + L("nap") : "") + (rec.isDebug ? " · test" : "")
                         + " · " + (rec.outcome?.rawValue ?? L("in progress")))
                    Text(L("\(rec.buildingId) · away \(Int(rec.awaySeconds)) s")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L("Night journal"))
        .toolbar {
            Button(L("Delete all"), role: .destructive) { model.clearNights() }
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
            GlassCircleButton(systemImage: "play.fill", label: L("Play preview"), highlighted: playing, action: play)
            GlassCircleButton(systemImage: "stop.fill", label: L("Stop"), action: stop)
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
