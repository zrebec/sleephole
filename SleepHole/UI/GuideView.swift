import os
import SleepCore
import SwiftUI
import UIKit
import UserNotifications

/// Number phrases with correct plurals in the current language ("5 minutes" / "5 minút", "1 minútu").
enum Plural {
    static func minutes(_ t: TimeInterval) -> String { L("\(Int((t / 60).rounded())) minutes") }
    static func seconds(_ t: TimeInterval) -> String { L("\(Int(t.rounded())) seconds") }
    static func hours(_ t: TimeInterval) -> String { L("\(Int((t / 3600).rounded())) hours") }
    static func nights(_ n: Int) -> String { L("\(n) nights") }
    static func days(_ n: Int) -> String { L("\(n) days") }
}

/// First-run guide: nine swipe pages the sleep buddy narrates (owner 2026-10-18, build 9c).
/// `replay` = opened again from Settings (the times are then edited under the change-week rules, the guide does not finish anything).
struct GuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var replay = false
    @State private var page: Int
    @State private var notificationsAllowed: Bool?
    @State private var showRules: Bool
    @State private var style: GuideStyle?
    static let pageCount = GuideText.pageCount

    init(replay: Bool = false) {
        self.replay = replay
        // Debug launch arguments for screenshots: `-guidePage N` (1-based), `-guideRules` (the rules sheet).
        let a = DevArgs.list
        let n = a.firstIndex(of: "-guidePage").flatMap { a.indices.contains($0 + 1) ? Int(a[$0 + 1]) : nil } ?? 1
        _page = State(initialValue: min(max(n, 1), GuideText.pageCount) - 1)
        _showRules = State(initialValue: a.contains("-guideRules"))
        #if DEBUG
        if a.contains("-guideReplay") { self.replay = true }      // screenshots: the guide as opened from Settings
        #endif
    }

    private struct PickKey: Hashable {
        var width: CGFloat, room: CGFloat, language: AppLanguage, replay: Bool, setup: TimeInterval, locked: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let room = proxy.size.height - GuideLayout.dotsHeight
                let key = PickKey(width: proxy.size.width, room: room, language: model.language, replay: replay,
                                  setup: model.settings.setupGrace, locked: !SchedulePolicy.allowsChange(model.scheduleState))
                TabView(selection: $page) {
                    ForEach(0..<Self.pageCount, id: \.self) { i in
                        ScrollView {
                            GuidePageView(index: i, replay: replay, style: style ?? .smallest,
                                          notificationsAllowed: $notificationsAllowed, showRules: $showRules)
                                // shorter pages sit in the vertical middle of the room above the dots (9k);
                                // room + dots = the scroll view's height, so a page that fits never scrolls
                                .frame(minHeight: max(room, 0))
                                .padding(.bottom, GuideLayout.dotsHeight)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .opacity(style == nil ? 0 : 1)              // hidden for the one frame before the style is known
                .task(id: key) { pickStyle(key) }
            }
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

    /// Picks the biggest style for which all nine pages fit the room (once per size / language / replay / setup time).
    private func pickStyle(_ key: PickKey) {
        guard key.width > 0, key.room > 0 else { return }
        let start = Date()
        let chosen = GuideStyle.choose(width: key.width, room: key.room, replay: replay, model: model)
        style = chosen
        #if DEBUG
        let ms = Date().timeIntervalSince(start) * 1000
        Logger(subsystem: "sk.zrebec.sleephole", category: "guide").info(
            "guide style: text \(chosen.textSize) pt, line \(chosen.lineHeight), gap \(chosen.gap), k \(chosen.k) – picked in \(ms) ms")
        print("guide style: text \(chosen.textSize) pt, line \(chosen.lineHeight), gap \(chosen.gap), k \(chosen.k) – picked in \(Int(ms)) ms")
        #endif
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

/// Fixed sizes around a guide page, shared with the test that proves no page scrolls on any supported iPhone.
enum GuideLayout {
    /// Room kept under a page's content for the page dots.
    static let dotsHeight: CGFloat = 34
    static let buttonBarPadding: CGFloat = 12
}

/// How big a guide page is drawn (owner 2026-10-18, step 9h): the text as large as the display allows, with a line height
/// of 1.5 × the text size while it fits (WCAG 1.4.12), and real gaps between the blocks. The same for every page.
struct GuideStyle: Equatable {
    var textSize: CGFloat
    /// Line height as a multiple of the text size.
    var lineHeight: CGFloat
    /// Gap between the title, the art, the cat and the text.
    var gap: CGFloat

    /// Scale of the title, the art and the cat relative to the 17-pt text of the smallest phone.
    var k: CGFloat { textSize / 17 }
    var titleSize: CGFloat { 1.6 * textSize }
    func artSize(_ index: Int) -> CGFloat { (index == 1 ? 2.0 : 2.3) * textSize }
    var catScale: CGFloat { min(k, 1.3) }

    /// Extra spacing between lines so that a line is `lineHeight × textSize` tall (never negative).
    var lineSpacing: CGFloat {
        let base = UIFont.systemFont(ofSize: textSize, weight: .medium)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: textSize) } ?? base
        return max(0, lineHeight * textSize - font.lineHeight)
    }

    /// Most preferred first: line height 1.5 with 25 … 17 pt (gaps 28 … 14), then 17 pt tighter, then 16 and 15 pt.
    static let candidates: [GuideStyle] = {
        var list: [GuideStyle] = []
        for size in stride(from: 25, through: 17, by: -1) {
            let t = CGFloat(25 - size) / 8
            list.append(GuideStyle(textSize: CGFloat(size), lineHeight: 1.5, gap: (28 - 14 * t).rounded()))
        }
        list.append(GuideStyle(textSize: 17, lineHeight: 1.35, gap: 12))
        list.append(GuideStyle(textSize: 17, lineHeight: 1.2, gap: 10))
        list.append(GuideStyle(textSize: 16, lineHeight: 1.2, gap: 8))
        list.append(GuideStyle(textSize: 15, lineHeight: 1.2, gap: 8))
        return list
    }()
    static let smallest = candidates[candidates.count - 1]

    /// The first candidate that fits; the candidates run from big to small, so "fits" is monotone and a binary search
    /// is enough. When nothing fits, the last (smallest) one.
    static func pick(from list: [GuideStyle] = candidates, fits: (GuideStyle) -> Bool) -> GuideStyle {
        var lo = 0, hi = list.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if fits(list[mid]) { hi = mid } else { lo = mid + 1 }
        }
        return lo < list.count ? list[lo] : list[list.count - 1]
    }

    /// Whether every one of the nine pages in this style fits `room` at this width (measured as the layout would;
    /// stops at the first page that does not fit).
    @MainActor static func fits(_ style: GuideStyle, width: CGFloat, room: CGFloat, replay: Bool, model: AppModel) -> Bool {
        (0..<GuideText.pageCount).allSatisfy { i in
            let view = GuidePageView(index: i, replay: replay, style: style, notificationsAllowed: .constant(nil),
                                     showRules: .constant(false)).environment(model)
            return UIHostingController(rootView: view)
                .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height <= room
        }
    }

    @MainActor static func choose(width: CGFloat, room: CGFloat, replay: Bool, model: AppModel) -> GuideStyle {
        pick { fits($0, width: width, room: room, replay: replay, model: model) }
    }
}

/// One guide page: title, art row, the sleep buddy and its sentence, and the page's own extras.
/// The sizes come from a `GuideStyle` the guide picks so that every page fits the display without scrolling.
struct GuidePageView: View {
    @Environment(AppModel.self) private var model
    let index: Int
    var replay = false
    var style: GuideStyle = .smallest
    @Binding var notificationsAllowed: Bool?
    @Binding var showRules: Bool

    private var content: GuideText.Page { GuideText.page(index, setup: model.settings.setupGrace) }
    /// Pages with extras show a smaller cat.
    private var catHeight: CGFloat {
        let base: CGFloat = switch index {
        case 0: 130
        case 1: 100
        case 6, 8: 170
        default: 200
        }
        return base * style.catScale
    }

    var body: some View {
        VStack(spacing: style.gap) {
            Text(content.title).font(.system(size: style.titleSize, weight: .bold)).multilineTextAlignment(.center)
                .minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            Text(content.art).font(.system(size: style.artSize(index)))
            Image(content.cat).resizable().scaledToFit().frame(height: catHeight)
                .accessibilityHidden(true)
            Text(content.text)
                .font(.system(size: style.textSize, weight: .medium, design: .rounded))
                .lineSpacing(style.lineSpacing)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            extras
        }
        .padding(.horizontal, 20).padding(.top, style.gap / 2)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var extras: some View {
        switch index {
        case 0:
            LanguagePicker().padding(.top, 4)
        case 1:
            @Bindable var model = model
            VStack(spacing: 6) {
                if replay {
                    // opened again from Settings: the same editor and rules as Settings → Schedule
                    ScheduleEditor(compact: true)
                } else {
                    // first run: saved at once (the guide is always free)
                    ScheduleFields(schedule: Binding(get: { model.settings.schedule }, set: { model.applySchedule($0) }))
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
