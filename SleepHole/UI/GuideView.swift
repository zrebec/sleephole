import SleepCore
import SwiftUI
import UserNotifications

/// Number phrases with correct plurals in the current language ("5 minutes" / "5 minút", "1 minútu").
enum Plural {
    static func minutes(_ t: TimeInterval) -> String { L("\(Int((t / 60).rounded())) minutes") }
    static func seconds(_ t: TimeInterval) -> String { L("\(Int(t.rounded())) seconds") }
    static func nights(_ n: Int) -> String { L("\(n) nights") }
}

/// The rules as sentences, generated from the real constants so the guide never lies.
enum GuideText {
    static let rules = SleepRules()
    static var startWindow: String {
        L("You can start building at the earliest \(Plural.minutes(NightWindow.startLead)) before bedtime and at the latest \(Plural.minutes(rules.startDeadline)) after it. Otherwise the night counts as missed.")
    }
    static var setup: String {
        L("For setup (podcast, bedtime story, selfies…) you have from the start until bedtime plus \(Plural.minutes(rules.setupGrace)) – start earlier, get more time. We'll warn you 15 s before it ends; then come back to SleepHole.")
    }
    static var night: String {
        L("You can turn the screen off, but SleepHole must stay open. If you switch to another app for more than \(Plural.seconds(rules.accidentalTolerance)), the building collapses.")
    }
    static var calls: String { L("Phone calls don't count – just come back to the app after the call.") }
    static var nap: String {
        let p = NapPlan.default
        return L("In the afternoon you can take a nap (30 or 60 min) – only between \(Fmt.time(p.windowStart))–\(Fmt.time(p.windowEnd)) (changeable), once a day. Same rules as at night, \(Plural.minutes(NapPlan.rules.setupGrace)) to set up, an alarm at the end. A complete nap = +\(NapPlan.reward(.complete)) 🪙, it doesn't build.")
    }
    static var alarm: String {
        L("The alarm rings for at most \(Plural.minutes(rules.alarmDuration)). Confirm you're up by shaking the phone or entering the code – at the earliest \(Plural.minutes(NightWindow.earlyConfirm)) before wake-up.")
    }
    static var outcomes: [(String, String)] {
        [(L("🏢 Complete"), L("confirmed within \(Plural.minutes(NightWindow.onTimeConfirm)) after wake-up")),
         (L("🚧 Unfinished"), L("confirmed within \(Plural.minutes(NightWindow.lateConfirm)) after wake-up – your next good night finishes it")),
         (L("🧱 Ruins"), L("the building collapsed, you cancelled the night, or you didn't confirm getting up. Your next complete night repairs it 🛠️ (unless an unfinished building is waiting), otherwise flowers grow over it 🌸"))]
    }
    /// title, what the level unlocks, when.
    static var levels: [(title: String, what: String, when: String)] {
        let t = Progression.thresholds
        return [(L("Level 1"), L("houses and apartment blocks"), L("from the start")),
                (L("Level 2"), L("parks, lit streets, museums, libraries"), L("after \(Plural.nights(t[1].minBuilt))")),
                (L("Level 3"), L("town hall, school, fire station, police, hospital"), L("after \(Plural.nights(t[2].minBuilt))")),
                (L("Level 4"), L("skyscrapers"), L("after \(Plural.nights(t[3].minBuilt))"))]
    }
}

/// First-run guide ("sprievodca"). `replay` = opened again from Settings (no permission step result needed).
struct GuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var replay = false
    @State private var page = 0
    @State private var notificationsAllowed: Bool?
    static let pageCount = 6

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                schedule.tag(1)
                nightRules.tag(2)
                morning.tag(3)
                levels.tag(4)
                tips.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            HStack {
                if page > 0 { Button(L("Back")) { withAnimation { page -= 1 } } }
                Spacer()
                if page < Self.pageCount - 1 {
                    Button(L("Next")) { withAnimation { page += 1 } }.buttonStyle(.borderedProminent)
                } else {
                    Button(replay ? L("Close") : L("Let's start 🌙")) { finish() }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .background { NightSky().opacity(0.9) }
        .preferredColorScheme(.dark)
    }

    func finish() {
        Self.complete(replay: replay, model: model)
        dismiss()
    }

    /// Marks the guide as done in the database (not when it was only replayed from Settings).
    static func complete(replay: Bool, model: AppModel) {
        guard !replay else { return }
        model.completeOnboarding()
        guard model.servicesEnabled else { return }
        Task {
            // ask for notifications even if the button on the last page was skipped
            if await Notifications.requestAuthorization() { Notifications.scheduleReminders(model.settings.schedule) }
        }
    }

    // MARK: pages

    private func pageLayout<C: View>(_ icon: String, _ title: String, @ViewBuilder content: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity)
                Text(title).font(.largeTitle.bold()).frame(maxWidth: .infinity)
                content()
            }
            .padding(24)
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(.yellow)
            Text(text).font(.body.leading(.loose)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        pageLayout("moon.stars.fill", L("Welcome to SleepHole")) {
            LanguagePicker()
            BuildingImage(id: "l1-house-a-a", maxHeight: 170).frame(maxWidth: .infinity)
            Text(L("Every evening you start a building. Leave your phone alone at night and get up on time, and the building gets finished – your nights grow into a town."))
                .font(.title3)
            Text(L("The goal is simple: go to bed and get up at the same time every day. 💙"))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var schedule: some View {
        @Bindable var model = model
        return pageLayout("clock.fill", L("Your schedule")) {
            Text(L("The same time every day is the base of good sleep. You can change it later in Settings."))
            // first run: saved at once (the guide is always free); replayed from Settings: change it there
            ScheduleFields(schedule: Binding(get: { model.settings.schedule }, set: { model.applySchedule($0) }))
                .disabled(replay)
                .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            if replay {
                Text(L("You change your schedule in Settings.")).font(.footnote).foregroundStyle(.secondary)
            }
            Text(L("Nap: \(model.settings.nap.minutes) min, between \(Fmt.time(model.settings.nap.windowStart)) and \(Fmt.time(model.settings.nap.windowEnd)) (change it in Settings)."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var nightRules: some View {
        pageLayout("hammer.fill", L("How a night works")) {
            row("clock.badge.checkmark", GuideText.startWindow)
            row("headphones", GuideText.setup)
            row("lock.iphone", GuideText.night)
            row("phone.fill", GuideText.calls)
            row("bed.double.fill", GuideText.nap)
            row("bell.badge", L("If you leave the app, you'll get a “Come back to SleepHole” alert."))
        }
    }

    private var morning: some View {
        pageLayout("sun.max.fill", L("Morning")) {
            row("alarm.fill", GuideText.alarm)
            HStack {
                Text(L("Your code:"))
                Text(model.settings.wakeCode).font(.title.monospacedDigit().bold())
            }
            ForEach(GuideText.outcomes, id: \.0) { title, text in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(text).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var levels: some View {
        pageLayout("star.fill", L("Town and levels")) {
            Text(L("Every night that builds something (complete or unfinished) moves you forward:"))
            ForEach(GuideText.levels, id: \.title) { level in
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title).font(.headline)
                    Text(verbatim: "\(level.what) – \(level.when)").foregroundStyle(.secondary)
                }
            }
            Text(L("Coins 🪙")).font(.headline)
            Text(L("A complete night = \(Economy.reward(.complete)) 🪙, unfinished = \(Economy.reward(.unfinished)) 🪙, and every \(Economy.streakBonusEvery)th complete night in a row adds a +\(Economy.streakBonus) 🪙 bonus. Soon you'll buy buildings with them: house \(Economy.price(level: 1)), L2 \(Economy.price(level: 2)), L3 \(Economy.price(level: 3)), L4 \(Economy.price(level: 4)) 🪙."))
                .foregroundStyle(.secondary)
        }
    }

    private var tips: some View {
        pageLayout("checklist", L("Notifications and tips")) {
            Button {
                Task { notificationsAllowed = await Notifications.requestAuthorization() }
            } label: {
                Label(notificationsAllowed == true ? L("Notifications allowed ✓") : L("Allow notifications"),
                      systemImage: "bell.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(notificationsAllowed == true)
            Text(L("They remind you of bedtime, warn you before the building collapses and act as a backup alarm."))
                .font(.footnote).foregroundStyle(.secondary)
            row("key.fill", L("Keep a passcode / Face ID on your iPhone – without it the app can't tell when the phone is locked."))
            row("battery.100.bolt", L("Keep your phone on the charger overnight."))
            row("moon.zzz.fill", L("The SleepHole alarm also rings in Do Not Disturb or Sleep focus. To get the “Come back” warning too, allow SleepHole: Settings → Focus → Sleep (and Do Not Disturb) → Apps → Add."))
            row("speaker.wave.2.fill", L("The alarm rings even in silent mode. Pick the sound in Settings."))
            row("arrow.down.circle", L("iOS may install an update at night and restart your phone. The building is safe (it counts in your favour), but the in-app alarm can't ring then – only the backup notification. For calmer nights: Settings → General → Software Update → Automatic Updates → turn off installing."))
            row("arrow.clockwise", L("The free version of the app expires after 7 days – run it again from Xcode then. Your data stays."))
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = settings.authorizationStatus == .authorized ? true : nil
        }
    }
}

/// Bedtime / wake / reminder pickers (shared by the guide and Settings) – they edit `schedule`, the caller decides
/// when it is saved (Settings: a draft with "Save", owner 2026-09-30 limits).
struct ScheduleFields: View {
    @Binding var schedule: Schedule

    var body: some View {
        VStack(spacing: 10) {
            DatePicker(L("Bedtime"), selection: time(\.bedtime), displayedComponents: .hourAndMinute)
            DatePicker(L("Wake-up"), selection: time(\.wake), displayedComponents: .hourAndMinute)
            Stepper(value: reminder, in: 0...120, step: 5) {
                Text(reminder.wrappedValue == 0 ? L("Reminder: off")
                     : L("Reminder \(reminder.wrappedValue) min before bedtime"))
            }
        }
    }

    private func time(_ path: WritableKeyPath<Schedule, TimeOfDay>) -> Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: schedule[keyPath: path].hour,
                                                       minute: schedule[keyPath: path].minute)) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            schedule[keyPath: path] = TimeOfDay(c.hour ?? 0, c.minute ?? 0)
        }
    }

    private var reminder: Binding<Int> {
        Binding {
            schedule.reminderOffsets.first ?? 0
        } set: {
            schedule.reminderOffsets = [$0]
        }
    }
}

/// "Tvoja prvá noc" – shown once before the first real night is started.
struct FirstNightBriefing: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(L("You have until bedtime + \(Plural.minutes(GuideText.rules.setupGrace)) for a podcast or story."), systemImage: "headphones")
                    Label(L("Then come back to SleepHole and lock your phone."), systemImage: "lock.iphone")
                    Label(L("Keep your phone on the charger."), systemImage: "battery.100.bolt")
                    Label(L("Alarm at \(Fmt.time(model.window.wake)) – shake your phone or enter code \(model.settings.wakeCode)."), systemImage: "alarm.fill")
                    Label(L("Leaving to another app for more than \(Plural.seconds(GuideText.rules.accidentalTolerance)) collapses the building."), systemImage: "exclamationmark.triangle.fill")
                } footer: {
                    Text(L("You'll only see this before your first night. The rules are in Settings → How it works."))
                }
                Section {
                    Button {
                        model.acknowledgeFirstNightBriefing()
                        model.startNight()
                        dismiss()
                    } label: {
                        Text(L("Got it, start building")).frame(maxWidth: .infinity).bold()
                    }
                    Button(L("Not yet"), role: .cancel) { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(L("Your first night 🌙"))
        }
    }
}

/// English | Slovenčina (native names) – Settings and the first guide page (I18N Q4).
struct LanguagePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker(selection: $model.language) {
            ForEach(AppLanguage.allCases) { Text(verbatim: $0.nativeName).tag($0) }
        } label: {
            Label(L("Language"), systemImage: "globe")
        }
        .pickerStyle(.segmented)
    }
}
