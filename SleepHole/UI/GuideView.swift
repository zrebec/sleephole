import SleepCore
import SwiftUI
import UserNotifications

/// Number phrases with correct plurals in the current language ("5 minutes" / "5 minút", "1 minútu").
enum Plural {
    static func minutes(_ t: TimeInterval) -> String { L("\(Int((t / 60).rounded())) minutes") }
    static func seconds(_ t: TimeInterval) -> String { L("\(Int(t.rounded())) seconds") }
    static func hours(_ t: TimeInterval) -> String { L("\(Int((t / 3600).rounded())) hours") }
    static func nights(_ n: Int) -> String { L("\(n) nights") }
    static func days(_ n: Int) -> String { L("\(n) days") }
}

/// First-run guide: nine swipe pages the sleep buddy narrates in a comic speech bubble (owner 2026-10-18, build 9c).
/// `replay` = opened again from Settings (the times are then changed in Settings, the guide does not finish anything).
struct GuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var replay = false
    @State private var page: Int
    @State private var notificationsAllowed: Bool?
    @State private var showRules: Bool
    static let pageCount = GuideText.pageCount

    init(replay: Bool = false) {
        self.replay = replay
        // Debug launch arguments for screenshots: `-guidePage N` (1-based), `-guideRules` (the rules sheet).
        let a = DevArgs.list
        let n = a.firstIndex(of: "-guidePage").flatMap { a.indices.contains($0 + 1) ? Int(a[$0 + 1]) : nil } ?? 1
        _page = State(initialValue: min(max(n, 1), GuideText.pageCount) - 1)
        _showRules = State(initialValue: a.contains("-guideRules"))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(0..<Self.pageCount, id: \.self) { i in
                    ScrollView {
                        GuidePageView(index: i, replay: replay, notificationsAllowed: $notificationsAllowed,
                                      showRules: $showRules)
                            .padding(.bottom, GuideLayout.dotsHeight)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .tag(i)
                }
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
            .padding(.horizontal).padding(.vertical, GuideLayout.buttonBarPadding)
        }
        .background { NightSky().opacity(0.9) }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showRules) { RulesView() }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = settings.authorizationStatus == .authorized ? true : nil
        }
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
            if await Notifications.requestAuthorization() { model.rescheduleReminders() }
            await model.refreshTimeSensitive()
        }
    }
}

/// Fixed sizes around a guide page, shared with the test that proves no page scrolls on a 375 × 667 pt iPhone SE.
enum GuideLayout {
    /// Room kept under a page's content for the page dots.
    static let dotsHeight: CGFloat = 34
    static let buttonBarPadding: CGFloat = 12
}

/// One guide page: title, art row, the sleep buddy and its sentence in a comic bubble, and the page's own extras.
/// The content is sized to fit the smallest supported iPhone at the default text size without scrolling.
struct GuidePageView: View {
    @Environment(AppModel.self) private var model
    let index: Int
    var replay = false
    @Binding var notificationsAllowed: Bool?
    @Binding var showRules: Bool

    private var content: GuideText.Page { GuideText.page(index, setup: model.settings.setupGrace) }
    /// Pages with extras show a smaller cat.
    private var catHeight: CGFloat {
        switch index {
        case 0: 130
        case 1: 100
        case 6, 8: 170
        default: 200
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(content.title).font(.title.bold()).multilineTextAlignment(.center)
                .minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            Text(content.art).font(.system(size: index == 1 ? 34 : 40))
            Image(content.cat).resizable().scaledToFit().frame(height: catHeight)
                .accessibilityHidden(true)
            GuideBubble(text: content.text)
            extras
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var extras: some View {
        switch index {
        case 0:
            LanguagePicker().padding(.top, 4)
        case 1:
            @Bindable var model = model
            VStack(spacing: 6) {
                // first run: saved at once (the guide is always free); replayed from Settings: change it there
                ScheduleFields(schedule: Binding(get: { model.settings.schedule }, set: { model.applySchedule($0) }))
                    .disabled(replay)
                if replay {
                    Text(L("You change your schedule in Settings.")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(red: 0.12, green: 0.14, blue: 0.24), in: RoundedRectangle(cornerRadius: 14))
        case 6:
            HStack {
                Text(L("Your code:"))
                Text(model.settings.wakeCode).font(.title.monospacedDigit().bold())
            }
        case 8:
            VStack(spacing: 10) {
                Button { showRules = true } label: {
                    Label(L("All rules"), systemImage: "list.bullet").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    Task {
                        notificationsAllowed = await Notifications.requestAuthorization()
                        await model.refreshTimeSensitive()
                    }
                } label: {
                    Label(notificationsAllowed == true ? L("Notifications allowed ✓") : L("Allow notifications"),
                          systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(notificationsAllowed == true)
            }
            .controlSize(.large)
            .padding(.top, 4)
        default:
            EmptyView()
        }
    }
}

/// The sleep buddy's comic speech bubble on a guide page: the tail points up to the cat, solid colours (no transparency).
struct GuideBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(SpeechBubbleShape.ink(.dark))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 11 + SpeechBubbleShape.tailHeight).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SpeechBubbleShape().fill(SpeechBubbleShape.paper(.dark))
                SpeechBubbleShape().stroke(SpeechBubbleShape.ink(.dark).opacity(0.85),
                                           style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
    }
}

/// Bedtime / wake / reminder pickers (shared by the guide and Settings) – they edit `schedule`, the caller decides
/// when it is saved (Settings: a draft with "Save", owner 2026-09-30 limits).
struct ScheduleFields: View {
    @Binding var schedule: Schedule
    /// The schedule is locked (change week, owner 2026-10-15): bedtime and wake cannot be changed, the reminder can.
    var timesLocked = false

    var body: some View {
        VStack(spacing: 10) {
            DatePicker(L("Bedtime"), selection: time(\.bedtime), displayedComponents: .hourAndMinute)
                .disabled(timesLocked)
            DatePicker(L("Wake-up"), selection: time(\.wake), displayedComponents: .hourAndMinute)
                .disabled(timesLocked)
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
    /// Started from "Go to sleep early": the setup is counted from the start, not from the bedtime.
    var early = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(early ? L("You have \(Plural.minutes(GuideText.rules.earlySetup)) from now for a podcast or story.")
                                : L("You have until bedtime + \(Plural.minutes(model.settings.setupGrace)) for a podcast or story."),
                          systemImage: "headphones")
                    Label(L("Then come back to SleepHole and lock your phone."), systemImage: "lock.iphone")
                    Label(L("Keep your phone on the charger."), systemImage: "battery.100.bolt")
                    Label(L("Alarm at \(Fmt.time(model.window.wake)) – shake your phone or enter code \(model.settings.wakeCode)."), systemImage: "alarm.fill")
                    Label(L("Stay with SleepHole – after more than \(Plural.seconds(GuideText.rules.accidentalTolerance)) in another app tonight's building comes down."), systemImage: "exclamationmark.triangle.fill")
                } footer: {
                    Text(L("You'll only see this before your first night. The rules are in Settings → How it works."))
                }
                Section {
                    Button {
                        model.acknowledgeFirstNightBriefing()
                        model.startNight(early: early)
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
