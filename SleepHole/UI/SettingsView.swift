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
    @State private var renaming = false
    /// The schedule being edited (nil = not edited); saved only with "Save" (owner 2026-09-30 limits).
    @State private var scheduleDraft: Schedule?
    @State private var confirmSchedule = false
    /// Dev aid: `-openSoundTest` opens Developer → Sound effects test at once (screenshots; `-scrollTo cat` shows the cat).
    @State private var soundTest = ProcessInfo.processInfo.arguments.contains("-openSoundTest")

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
                    Picker(L("Theme"), selection: $model.settings.theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle(L("Sound effects"), isOn: $model.settings.soundEffects)
                    Toggle(L("Voice (good night, good morning)"), isOn: $model.settings.voice)
                } header: {
                    Text(L("Appearance & sounds"))
                } footer: {
                    Text(L("System follows the iPhone's light / dark setting. The night screen is always dark."))
                }

                Section {
                    HStack {
                        Text(verbatim: model.townName)
                        Spacer()
                        Button(L("Rename…")) { renaming = true }
                    }
                } header: {
                    Text(L("Town name"))
                } footer: {
                    Text(L("Your first name and one rename a year are free, otherwise renaming costs \(RenamePolicy.price) 🪙."))
                }

                Section {
                    ScheduleFields(schedule: Binding(get: { scheduleDraft ?? model.settings.schedule },
                                                     set: { scheduleDraft = $0 }))
                    if let draft = scheduleDraft, draft != model.settings.schedule {
                        HStack {
                            Button(L("Cancel")) { scheduleDraft = nil }
                                .buttonStyle(.borderless)
                            Spacer()
                            Button(L("Save")) { saveSchedule(draft) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    Button(L("How it works")) { showGuide = true }
                } header: {
                    Text(L("Schedule"))
                } footer: {
                    Text(Self.scheduleRules(model.scheduleChangeCost(), nextFree: model.nextFreeScheduleChange,
                                            calibrationEnds: model.scheduleCalibrationEnds))
                }
                .disabled(nightRunning)
                .confirmationDialog(L("Save the new schedule?"), isPresented: $confirmSchedule,
                                    titleVisibility: .visible) {
                    Button(L("Save and start the streak again"), role: .destructive) {
                        if let draft = scheduleDraft { model.applySchedule(draft) }
                        scheduleDraft = nil
                    }
                    Button(L("Cancel"), role: .cancel) {}
                } message: {
                    Text(L("Outside the free window a new bedtime or wake-up starts your 🔥 streak of \(Plural.nights(model.streak)) again. Your buildings, coins and levels stay. Free changes: from \(Fmt.fullDate(NightKey(date: model.nextFreeScheduleChange, calendar: .current))), days 1–3 of every month."))
                }

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
                    .onChange(of: model.settings.ambience) { _, a in
                        if !nightRunning { preview.switchTo(a, volume: model.settings.volume) }
                    }
                    Picker(L("Play for"), selection: $model.settings.ambienceMinutes) {
                        ForEach(AppSettings.ambienceTimerOptions, id: \.self) { m in
                            Text(AppSettings.timerTitle(m)).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle(L("Play when the night starts"), isOn: $model.settings.playsAtStart)
                        .disabled(model.settings.ambience == .silence)
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $model.settings.volume, in: 0...0.6)
                            .onChange(of: model.settings.volume) { _, v in preview.setVolume(v) }
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    // during a night ▶ / ■ control the night's own sound (a second player would fight over the
                    // shared audio session – owner bug 2026-09-30)
                    PreviewButtons(playing: nightRunning ? model.sleepSoundPlaying : preview.playing != nil,
                                   play: {
                                       if nightRunning {
                                           model.playSleepSound(model.settings.ambience, minutes: model.settings.ambienceMinutes)
                                       } else {
                                           preview.play(model.settings.ambience, volume: model.settings.volume,
                                                        seconds: model.settings.ambienceSeconds)
                                       }
                                   },
                                   stop: { if nightRunning { model.stopSleepSound() } else { preview.stop() } })
                        .disabled(model.settings.ambience == .silence)
                } header: {
                    Text(L("Sleep sound")).id("sounds")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let end = nightRunning ? model.sleepSound?.endsAt : preview.endsAt {
                            Text(L("\(model.settings.ambience.detail) Playing until \(Fmt.time(end))."))
                        } else if nightRunning ? model.sleepSoundPlaying : preview.playing != nil {
                            Text(L("\(model.settings.ambience.detail) Playing until you press ■."))
                        } else {
                            Text(model.settings.ambience.detail)
                        }
                        Text(L("Stopping the sound during a night switches this off; pressing ▶ during a night switches it on again."))
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

                Section {
                    NavigationLink(L("Credits")) { CreditsView() }
                    if let expiry = AppExpiry.date {
                        HStack {
                            Text(L("The app works until"))
                            Spacer()
                            Text(L("\(Fmt.dayMonth(NightKey(date: expiry, calendar: .current))) at \(Fmt.time(expiry))"))
                                .foregroundStyle(AppExpiry.isSoon(at: Date()) ? .orange : .secondary)
                        }
                    }
                } header: {
                    Text(L("About"))
                } footer: {
                    if AppExpiry.date != nil {
                        Text(L("Free signing lasts 7 days. Before it ends, connect your iPhone to the Mac and run SleepHole from Xcode – your data stays. You'll get a reminder a day and 3 hours ahead."))
                    }
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
                    NavigationLink(L("Vibration test")) { VibrationTestView() }
                    NavigationLink(L("Sound effects test")) { SoundEffectsTestView() }
                    Button(L("Show the guide and first night again")) { model.resetGuide() }
                        .disabled(nightRunning)
                }
            }
            .onAppear {                                   // `-scrollTo sounds` (screenshots)
                if ProcessInfo.processInfo.arguments.contains("sounds") { proxy.scrollTo("sounds", anchor: .top) }
            }
            }
            .skyBackground()
            .navigationTitle(L("Settings"))
            .navigationDestination(isPresented: $soundTest) { SoundEffectsTestView() }
            .renameTownAlert(isPresented: $renaming)
            .sheet(isPresented: $showGuide) { GuideView(replay: true) }
            .task { notificationStatus = await Notifications.statusText() }
            .onChange(of: nightRunning) { _, running in if running { preview.stop() } }   // one player at a time
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
    /// A new bedtime / wake that costs the streak asks first (only when there is a streak to lose).
    func saveSchedule(_ draft: Schedule) {
        let old = model.settings.schedule
        let timesChanged = draft.bedtime != old.bedtime || draft.wake != old.wake
        if timesChanged, model.scheduleChangeCost() == .resetsStreak, model.streak > 0 {
            confirmSchedule = true
        } else {
            model.applySchedule(draft)
            scheduleDraft = nil
        }
    }

    static func scheduleRules(_ cost: SchedulePolicy.Change, nextFree: Date, calibrationEnds: Date?) -> String {
        switch cost {
        case .free(.monthStart):
            return L("Days 1–3 of the month: you can change bedtime and wake-up for free now.")
        case .free(.calibration):
            let end = calibrationEnds.map { Fmt.fullDate(NightKey(date: $0, calendar: .current)) } ?? ""
            return L("Your first week: bedtime and wake-up can be changed for free until \(end).")
        case .resetsStreak:
            return L("Bedtime and wake-up can be changed for free on days 1–3 of every month (next: \(Fmt.fullDate(NightKey(date: nextFree, calendar: .current)))). Changing them now starts your 🔥 streak again. The reminder can change any time.")
        }
    }

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

/// Developer: play every effect and voice line (phase UI-2), so the owner can judge them without a night.
struct SoundEffectsTestView: View {
    @Environment(AppModel.self) private var model
    @State private var showSplash: Bool?
    @State private var showWow = false

    private var effects: [(file: String, title: String)] {
        [("fx_sleep", L("Go to sleep")), ("fx_wow", L("Building finished (WOW)")), ("fx_coins", L("Coins")),
         ("fx_sparkle", L("Sparkle")), ("fx_whoosh", L("Whoosh")), ("fx_pop", L("Pop")),
         ("fx_purr", L("Purr")), ("fx_meow", L("Meow")),
         ("level_up", L("Level up")), ("building_unfinished", L("Unfinished")), ("building_ruin", L("Ruins"))]
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section(L("Effects")) {
                ForEach(effects, id: \.file) { e in
                    Button { SoundFX.play(e.file) } label: {
                        Label(e.title, systemImage: "speaker.wave.2.fill")
                    }
                }
            }
            Section(L("Voice")) {
                ForEach(Array(Voice.Line.allCases.enumerated()), id: \.offset) { _, line in
                    Button { Voice.say(line.text) } label: { Label(line.text, systemImage: "person.wave.2.fill") }
                }
            }
            Section(L("Animations")) {
                Button(L("Good night splash")) { showSplash = false; SoundFX.play("fx_sleep", volume: 0.6) }
                Button(L("Nap splash")) { showSplash = true; SoundFX.play("fx_sleep", volume: 0.6) }
                Button(L("Building finished (WOW)")) {
                    showWow = true
                    SoundFX.play("fx_wow")
                }
                // the Today cat: tap it for purr → arched back → wink (sound + vibration + frames)
                VStack(spacing: 8) {
                    Text(L("Tap the cat")).font(.footnote).foregroundStyle(.secondary)
                    BuddyView.centred(BuddyView(state: .awake, onPet: { model.petBuddy() }).frame(width: 180))
                        .padding(.top, 34)           // room for the arched back's tail
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .id("cat")
            }
        }
        .onAppear {                                       // `-scrollTo cat` (screenshots)
            if ProcessInfo.processInfo.arguments.contains("cat") { proxy.scrollTo("cat", anchor: .center) }
        }
        }
        .navigationTitle(L("Sound effects test"))
        .overlay { if let nap = showSplash { GoodNightSplash(nap: nap) { showSplash = nil } } }
        .sheet(isPresented: $showWow) {
            ZStack {
                SunRays().frame(width: 340, height: 340)
                DustPuff(delay: Motion.landing).frame(width: 340, height: 260)
                BuildingImage(id: "l1-house-a-a").dropIn(delay: 0.15)
                SparkleBurst(delay: Motion.landing + 0.1).frame(width: 340, height: 300)
            }
            .presentationDetents([.medium])
        }
    }
}
