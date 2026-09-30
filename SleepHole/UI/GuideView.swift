import SleepCore
import SwiftUI
import UserNotifications

/// Slovak number phrases ("5 minút", "2 minúty", "1 minútu", "10 sekúnd").
enum SK {
    static func minutes(_ t: TimeInterval) -> String { plural(Int((t / 60).rounded()), "minútu", "minúty", "minút") }
    static func seconds(_ t: TimeInterval) -> String { plural(Int(t.rounded()), "sekundu", "sekundy", "sekúnd") }
    static func nights(_ n: Int) -> String { plural(n, "noc", "noci", "nocí") }
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(n) " + (n == 1 ? one : (2...4).contains(n) ? few : many)
    }
}

/// The rules as sentences, generated from the real constants so the guide never lies.
enum GuideText {
    static let rules = SleepRules()
    static var startWindow: String {
        "Stavbu môžeš začať najskôr \(SK.minutes(NightWindow.startLead)) pred večierkou a najneskôr \(SK.minutes(rules.startDeadline)) po nej. Inak sa noc počíta ako vynechaná."
    }
    static var setup: String {
        "Na prípravu (podcast, rozprávka, selfie…) máš čas od štartu až do večierky a ešte \(SK.minutes(rules.setupGrace)) po nej – kto začne skôr, má viac času. 15 s pred koncom ťa upozorníme, potom sa vráť do SleepHole."
    }
    static var night: String {
        "Displej môžeš vypnúť, ale SleepHole musí zostať v popredí. Keď odídeš do inej appky dlhšie ako na \(SK.seconds(rules.accidentalTolerance)), stavba sa zrúti."
    }
    static let calls = "Telefonát sa nepočíta – po hovore sa len vráť do appky."
    static var nap: String {
        let p = NapPlan.default
        return "Popoludní si môžeš dať odpočinok (30 alebo 60 min) – iba v okne \(p.windowStart)–\(p.windowEnd) (dá sa zmeniť), raz denne. Platí to isté ako v noci, na prípravu máš \(SK.minutes(NapPlan.rules.setupGrace)), na konci zazvoní budík. Hotový odpočinok = +\(NapPlan.reward(.complete)) 🪙, budovu nestavia."
    }
    static var alarm: String {
        "Budík zvoní najviac \(SK.minutes(rules.alarmDuration)). Vstávanie potvrdíš zatrasením telefónu alebo kódom – najskôr \(SK.minutes(NightWindow.earlyConfirm)) pred budíčkom."
    }
    static var outcomes: [(String, String)] {
        [("🏢 Hotová", "potvrdíš do \(SK.minutes(NightWindow.onTimeConfirm)) po budíčku"),
         ("🚧 Rozostavaná", "potvrdíš do \(SK.minutes(NightWindow.lateConfirm)) po budíčku – ďalšia dobrá noc ju dostavia"),
         ("🧱 Ruina", "stavba sa zrútila, zrušil si noc, alebo si nepotvrdil vstávanie. Ďalšia hotová noc ju opraví 🛠️ (ak nečaká rozostavaná budova), inak časom zarastie kvetmi 🌸")]
    }
    static var levels: [(String, String)] {
        let t = Progression.thresholds
        return [("Level 1", "obyčajné domy a bytovky – od začiatku"),
                ("Level 2", "parky, osvetlené ulice, múzeá, knižnice – po \(SK.nights(t[1].minBuilt))"),
                ("Level 3", "radnica, škola, hasiči, polícia, nemocnica – po \(SK.nights(t[2].minBuilt))"),
                ("Level 4", "mrakodrapy – po \(SK.nights(t[3].minBuilt))")]
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
                if page > 0 { Button("Späť") { withAnimation { page -= 1 } } }
                Spacer()
                if page < Self.pageCount - 1 {
                    Button("Ďalej") { withAnimation { page += 1 } }.buttonStyle(.borderedProminent)
                } else {
                    Button(replay ? "Zavrieť" : "Začnime 🌙") { finish() }.buttonStyle(.borderedProminent)
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
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(.yellow)
            Text(text).font(.body.leading(.loose)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        pageLayout("moon.stars.fill", "Vitaj v SleepHole") {
            BuildingImage(id: "l1-house-a-a", maxHeight: 170).frame(maxWidth: .infinity)
            Text("Každý večer začneš stavať budovu. Keď v noci necháš telefón na pokoji a ráno vstaneš načas, budova sa dokončí – a z tvojich nocí rastie mesto.")
                .font(.title3)
            Text("Cieľ je jednoduchý: chodiť spať a vstávať každý deň v rovnakom čase. 💙")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var schedule: some View {
        @Bindable var model = model
        return pageLayout("clock.fill", "Tvoj rozvrh") {
            Text("Rovnaký čas každý deň je základ dobrého spánku. Neskôr ho zmeníš v Nastaveniach.")
            ScheduleFields().padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            Text("Odpočinok: \(model.settings.nap.minutes) min, medzi \(model.settings.nap.windowStart) a \(model.settings.nap.windowEnd) (zmeníš v Nastaveniach).")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var nightRules: some View {
        pageLayout("hammer.fill", "Ako prebieha noc") {
            row("clock.badge.checkmark", GuideText.startWindow)
            row("headphones", GuideText.setup)
            row("lock.iphone", GuideText.night)
            row("phone.fill", GuideText.calls)
            row("bed.double.fill", GuideText.nap)
            row("bell.badge", "Ak odídeš z appky, príde upozornenie „Vráť sa do SleepHole“.")
        }
    }

    private var morning: some View {
        pageLayout("sun.max.fill", "Ráno") {
            row("alarm.fill", GuideText.alarm)
            HStack {
                Text("Tvoj kód:")
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
        pageLayout("star.fill", "Mesto a levely") {
            Text("Každá noc, ktorá postaví budovu (hotovú či rozostavanú), ťa posunie ďalej:")
            ForEach(GuideText.levels, id: \.0) { title, text in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(text).foregroundStyle(.secondary)
                }
            }
            Text("Mince 🪙").font(.headline)
            Text("Hotová noc = \(Economy.reward(.complete)) 🪙, rozostavaná = \(Economy.reward(.unfinished)) 🪙 a každá \(Economy.streakBonusEvery). hotová noc v rade pridá bonus +\(Economy.streakBonus) 🪙. Čoskoro si za ne budeš kupovať budovy: dom \(Economy.price(level: 1)), L2 \(Economy.price(level: 2)), L3 \(Economy.price(level: 3)), L4 \(Economy.price(level: 4)) 🪙.")
                .foregroundStyle(.secondary)
        }
    }

    private var tips: some View {
        pageLayout("checklist", "Upozornenia a tipy") {
            Button {
                Task { notificationsAllowed = await Notifications.requestAuthorization() }
            } label: {
                Label(notificationsAllowed == true ? "Upozornenia povolené ✓" : "Povoliť upozornenia",
                      systemImage: "bell.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(notificationsAllowed == true)
            Text("Pripomenú večierku, varujú pred zrútením stavby a sú záložným budíkom.")
                .font(.footnote).foregroundStyle(.secondary)
            row("key.fill", "Maj na iPhone nastavený kód / Face ID – bez neho appka nerozozná zamknutie telefónu.")
            row("battery.100.bolt", "Nechaj telefón cez noc na nabíjačke.")
            row("moon.zzz.fill", "Budík SleepHole zvoní aj v režime Nerušiť či Spánok. Aby prišlo aj varovanie „Vráť sa“, pridaj SleepHole do povolených appiek: Nastavenia → Sústredenie → Spánok (a Nerušiť) → Appky → Pridať.")
            row("speaker.wave.2.fill", "Budík zvoní aj v tichom režime. Zvuk si vyberieš v Nastaveniach.")
            row("arrow.down.circle", "iOS si v noci môže sám nainštalovať aktualizáciu a reštartovať telefón. Stavbe to neublíži (počíta sa v tvoj prospech), ale budík z appky vtedy nezazvoní – ozve sa len záložné upozornenie. Pokojnejšie spanie: Nastavenia → Všeobecné → Aktualizácia softvéru → Automatické aktualizácie → vypni inštaláciu.")
            row("arrow.clockwise", "Bezplatná verzia appky vyprší po 7 dňoch – vtedy ju treba znova spustiť z Xcode. Dáta zostanú.")
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = settings.authorizationStatus == .authorized ? true : nil
        }
    }
}

/// Bedtime / wake / reminder pickers (shared by the guide and Settings).
struct ScheduleFields: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            DatePicker("Večierka", selection: time(\.bedtime), displayedComponents: .hourAndMinute)
            DatePicker("Budíček", selection: time(\.wake), displayedComponents: .hourAndMinute)
            Stepper(value: reminder, in: 0...120, step: 5) {
                Text(reminder.wrappedValue == 0 ? "Pripomienka: vypnutá"
                     : "Pripomienka \(reminder.wrappedValue) min pred večierkou")
            }
        }
    }

    private func time(_ path: WritableKeyPath<Schedule, TimeOfDay>) -> Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: model.settings.schedule[keyPath: path].hour,
                                                       minute: model.settings.schedule[keyPath: path].minute)) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.settings.schedule[keyPath: path] = TimeOfDay(c.hour ?? 0, c.minute ?? 0)
        }
    }

    private var reminder: Binding<Int> {
        Binding {
            model.settings.schedule.reminderOffsets.first ?? 0
        } set: {
            model.settings.schedule.reminderOffsets = [$0]
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
                    Label("Na podcast či rozprávku máš čas do večierky + \(SK.minutes(GuideText.rules.setupGrace)).", systemImage: "headphones")
                    Label("Potom sa vráť do SleepHole a zamkni telefón.", systemImage: "lock.iphone")
                    Label("Telefón nechaj na nabíjačke.", systemImage: "battery.100.bolt")
                    Label("Budík o \(clockFormat.string(from: model.window.wake)) – zatras telefónom alebo zadaj kód \(model.settings.wakeCode).", systemImage: "alarm.fill")
                    Label("Odchod do inej appky na viac ako \(SK.seconds(GuideText.rules.accidentalTolerance)) stavbu zrúti.", systemImage: "exclamationmark.triangle.fill")
                } footer: {
                    Text("Toto uvidíš len pred prvou nocou. Pravidlá nájdeš v Nastaveniach → Ako to funguje.")
                }
                Section {
                    Button {
                        model.acknowledgeFirstNightBriefing()
                        model.startNight()
                        dismiss()
                    } label: {
                        Text("Rozumiem, začať stavbu").frame(maxWidth: .infinity).bold()
                    }
                    Button("Ešte nie", role: .cancel) { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Tvoja prvá noc 🌙")
        }
    }
}
