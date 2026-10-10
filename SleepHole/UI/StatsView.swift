import Charts
import SleepCore
import SwiftUI

/// "Štatistiky" tab (plan §9, F4).
struct StatsView: View {
    @Environment(AppModel.self) private var model
    /// `-selectLastNight` preselects the newest night (screenshots).
    @State private var selectedDay: NightKey?
    private let preselect = ProcessInfo.processInfo.arguments.contains("-selectLastNight")

    var body: some View {
        let s = model.stats
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        tile("🔥", s.currentStreak, L("current streak")).appearIn(delay: 0)
                        tile("🏆", s.bestStreak, L("best streak")).appearIn(delay: 0.05)
                        tile("🏗️", s.builtNights, L("nights built")).appearIn(delay: 0.1)
                        tile("🪙", model.coins, L("coins")).appearIn(delay: 0.15)          // incl. naps + achievements
                    }
                    card(L("Night calendar")) {
                        CalendarGrid(days: s.calendar, selected: $selectedDay)
                        if let key = selectedDay {
                            Divider()
                            NightDetail(key: key).id("detail")
                        } else {
                            Text(L("Tap a day to see how that night went.")).font(.footnote).cardCaption()
                        }
                    }
                    card(L("Average (last 14 nights)")) {
                        HStack {
                            metric(L("Build start"), s.averageStart.map(Fmt.time) ?? "–")
                            Divider()
                            metric(L("Wake-up"), s.averageWake.map(Fmt.time) ?? "–")
                        }
                        if showsSleep(s) {
                            Divider()
                            HStack {
                                metric(L("Fell asleep"), s.averageFellAsleep.map(Fmt.time) ?? "–")
                                Divider()
                                metric(L("Time to fall asleep"), s.averageMinutesToSleep.map { L("\(Int($0.rounded())) min") } ?? "–")
                            }
                        }
                        regularity(s.regularityMinutes)
                    }
                    .id("average")
                    card(showsSleep(s) ? L("When you go to bed and fall asleep") : L("When you start and get up")) {
                        NightChart(points: s.series, bedtime: model.settings.schedule, showsSleep: showsSleep(s),
                                   initialSelection: Self.launchChartNight(s.series)) { key in
                            if selectedDay == key { withAnimation { proxy.scrollTo("detail", anchor: .top) } }
                            else { selectedDay = key }
                        }
                    }
                    .id("chart")
                    card(L("Naps")) {
                        let n = model.napSummary
                        Label(L("\(n.count) complete naps") + " · +\(n.coins) 🪙", systemImage: "bed.double.fill")
                    }
                    card(L("Town journal")) { JournalCard() }
                        .id("journal")
                    card(L("Achievements") + " \(model.achievements.count)/\(Achievement.allCases.count)") {
                        AchievementsCard()
                    }
                    .id("achievements")
                    card(L("Levels")) {
                        ProgressView(value: Double(s.maxLevel), total: 4) { Text(L("Level \(s.maxLevel) of 4 unlocked")) }
                        if let next = Progression.nightsToNextLevel(built: s.builtNights) {
                            Text(L("Level \(next.level) in \(Plural.nights(next.nights))")).font(.footnote).cardCaption()
                        }
                    }
                }
                .padding()
            }
            .skyBackground()
            .onAppear {                                   // `-scrollTo journal|achievements` (screenshots)
                let args = ProcessInfo.processInfo.arguments
                for id in ["journal", "achievements", "chart", "average"] where args.contains(id) { proxy.scrollTo(id, anchor: .top) }
            }
            .onChange(of: selectedDay) { _, day in
                if day != nil { withAnimation { proxy.scrollTo("detail", anchor: .top) } }
            }
            }
            .navigationTitle(L("Stats"))
            .task { await model.refreshSleepIfIdle() }
            .onAppear { if preselect, selectedDay == nil { selectedDay = model.realResults().last.map { NightKey($0.keyString)! } } }
        }
    }

    /// Sleep data (phase HEALTH) shows only with the switch on and at least one shown night with a value.
    private func showsSleep(_ s: StatsSummary) -> Bool {
        Self.showsSleep(s, on: model.settings.usesHealth)
    }

    /// `-selectChartNight K` → the night K places before the newest one is selected on the chart (screenshots).
    static func launchChartNight(_ series: [NightPoint], args: [String] = ProcessInfo.processInfo.arguments) -> NightKey? {
        guard let i = args.firstIndex(of: "-selectChartNight"), i + 1 < args.count, let back = Int(args[i + 1]),
              series.indices.contains(series.count - 1 - back) else { return nil }
        return series[series.count - 1 - back].key
    }

    static func showsSleep(_ s: StatsSummary, on: Bool) -> Bool {
        on && s.series.contains { $0.asleepMinutes != nil }
    }

    private func tile(_ icon: String, _ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(icon).font(.title)
            Text(verbatim: "\(value)").font(.title.bold().monospacedDigit())
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label).font(.caption).cardCaption()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard()
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCard()
        .appearIn(delay: 0.2)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).cardCaption()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func regularity(_ minutes: Double?) -> some View {
        if let m = minutes {
            let (text, color): (String, Color) = m <= 15 ? (L("excellent 🌟"), Color.readableGreen) : m <= 30 ? (L("good 👍"), Color.readableYellow)
                : (L("varies – try to start at the same time 🌙"), Color.readableOrange)
            Label(L("Regularity: ±\(Int(m.rounded())) min – \(text)"), systemImage: "metronome.fill")
                .font(.subheadline).foregroundStyle(color)
        } else {
            Text(L("You'll see your regularity after 2 nights.")).font(.subheadline).cardCaption()
        }
    }
}

/// Last 5 weeks, one square per night, coloured by outcome. Tap = select.
struct CalendarGrid: View {
    let days: [CalendarDay]
    var selected: Binding<NightKey?> = .constant(nil)

    static func color(_ o: Outcome?) -> Color {
        switch o {
        case .complete: .green
        case .unfinished: .orange
        case .ruins: .gray
        case .excused: .indigo.opacity(0.55)                     // protected by a joker 🛡️
        case .missed, .none: .gray.opacity(0.15)
        }
    }

    /// The day number on its square (B7): dark text on the bright squares of dark mode (white on bright green is
    /// unreadable there), the primary colour everywhere else.
    static func numberColor(_ o: Outcome?, dark: Bool) -> Color {
        guard dark else { return .primary.opacity(0.7) }
        switch o {
        case .complete, .unfinished, .ruins: return .black.opacity(0.78)
        case .excused, .missed, .none: return .primary.opacity(0.72)
        }
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(days, id: \.key) { d in
                    Button {
                        selected.wrappedValue = selected.wrappedValue == d.key ? nil : d.key
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Self.color(d.outcome))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(Text(verbatim: "\(d.key.day)").font(.caption2)
                                .foregroundStyle(Self.numberColor(d.outcome, dark: scheme == .dark)))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: selected.wrappedValue == d.key ? 3 : 0))
                    }
                    .buttonStyle(.plain)                 // no accent tint on the day numbers
                    .accessibilityLabel(Fmt.fullDate(d.key))
                }
            }
            HStack(spacing: 12) {
                legend(.green, L("complete")); legend(.orange, L("unfinished")); legend(.gray, L("ruins"))
                legend(.indigo.opacity(0.55), L("joker 🛡️"))
            }
            .font(.caption2)
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10); Text(t) }
    }
}

/// The last 30 nights: per night the build start (a dot in the outcome's colour) and, with Apple Health data, a bar up
/// to the blue "fell asleep" diamond. Tap a night to select it; the dashed line is the bedtime.
struct NightChart: View {
    let points: [NightPoint]
    let bedtime: Schedule
    /// Also draw the bars and the blue "fell asleep" points (Apple Health).
    var showsSleep = false
    /// The night shown selected when the card first appears (screenshots only).
    var initialSelection: NightKey?
    /// "Night details" in the callout: StatsView selects that night in the calendar.
    var onDetails: (NightKey) -> Void = { _ in }

    @State private var selected: NightKey?

    init(points: [NightPoint], bedtime: Schedule, showsSleep: Bool = false, initialSelection: NightKey? = nil,
         onDetails: @escaping (NightKey) -> Void = { _ in }) {
        self.points = points
        self.bedtime = bedtime
        self.showsSleep = showsSleep
        self.initialSelection = initialSelection
        self.onDetails = onDetails
        _selected = State(initialValue: initialSelection)
    }

    private static let barColor = Color(red: 0.40, green: 0.47, blue: 0.82)         // solid, reads on light and dark skies

    // MARK: pure rules (unit-tested)

    /// The index of the night nearest to a tapped x position (the chart's x axis is the night's index); nil without nights.
    static func nearestIndex(x: Double, count: Int) -> Int? {
        guard count > 0, x.isFinite else { return nil }
        return min(max(Int(x.rounded()), 0), count - 1)
    }

    /// A tap on the already selected night clears the selection.
    static func toggled(_ current: NightKey?, tapped: NightKey) -> NightKey? { current == tapped ? nil : tapped }

    /// Every n-th night gets a label on the x axis, so the day numbers never collide.
    static func labelStep(count: Int) -> Int { count <= 12 ? 1 : count <= 24 ? 2 : 5 }

    /// The line under the card's title: the hint, or the selected night in words (also the marks' spoken label).
    static func callout(_ p: NightPoint?, showsSleep: Bool) -> String {
        guard let p else { return L("Tap a night to see it.") }
        let date = Fmt.dayMonth(p.key)
        let start = p.startMinutes.map(clock(afterNoon:)) ?? "–"
        if showsSleep, let asleep = p.asleepMinutes {
            return L("\(date) · start \(start) · asleep \(clock(afterNoon: asleep)) · after \(NightDetail.minutesToSleep(startMinutes: p.startMinutes, asleepMinutes: asleep)) min")
        }
        return L("\(date) · start \(start)")
    }

    /// Clock time of a minute count after 12:00.
    static func clock(afterNoon minutes: Double) -> String { Fmt.time(minutesOfDay: Int((minutes + 720).rounded())) }

    // MARK: view

    var body: some View {
        if points.isEmpty {
            Text(L("The chart fills up after your first nights.")).font(.subheadline).cardCaption()
        } else {
            let bed = Double((bedtime.bedtime.hour * 60 + bedtime.bedtime.minute + 720) % 1440)
            let step = Self.labelStep(count: points.count)
            let chosen = points.first { $0.key == selected }
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.callout(chosen, showsSleep: showsSleep)).font(.footnote).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if let chosen {
                    Button(L("Night details")) { onDetails(chosen.key) }
                        .font(.footnote.weight(.semibold)).buttonStyle(.borderedProminent).tint(.indigo).controlSize(.small)
                }
                Chart {
                    RuleMark(y: .value(L("Bedtime"), bed))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.indigo.opacity(0.6))
                    if let i = points.firstIndex(where: { $0.key == selected }) {
                        RuleMark(x: .value(L("Night"), i))                               // behind the selected night
                            .lineStyle(StrokeStyle(lineWidth: 2)).foregroundStyle(Color.gray)
                    }
                    ForEach(Array(points.enumerated()), id: \.element.key) { i, p in
                        let on = p.key == selected
                        let label = Self.callout(p, showsSleep: showsSleep)
                        if showsSleep, let s = p.startMinutes, let a = p.asleepMinutes {
                            RuleMark(x: .value(L("Night"), i), yStart: .value(L("Start"), s), yEnd: .value(L("Fell asleep"), a))
                                .lineStyle(StrokeStyle(lineWidth: on ? 8 : 5, lineCap: .round))
                                .foregroundStyle(Self.barColor)
                                .accessibilityLabel(label)
                        }
                        if let s = p.startMinutes {
                            PointMark(x: .value(L("Night"), i), y: .value(L("Start"), s))
                                .foregroundStyle(CalendarGrid.color(p.outcome))
                                .symbolSize(on ? 150 : 55)
                                .accessibilityLabel(label)
                        }
                        if showsSleep, let a = p.asleepMinutes {
                            PointMark(x: .value(L("Night"), i), y: .value(L("Fell asleep"), a))
                                .foregroundStyle(Color.blue)
                                .symbol(.diamond)
                                .symbolSize(on ? 150 : 55)
                                .accessibilityLabel(label)
                        }
                    }
                }
                .chartXScale(domain: -0.5...(Double(points.count) - 0.5))
                .chartXAxis {
                    AxisMarks(values: Array(stride(from: 0, to: points.count, by: step))) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let i = v.as(Int.self), points.indices.contains(i) { Text(verbatim: "\(points[i].key.day)") }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let m = v.as(Double.self) { Text(Self.clock(afterNoon: m)) }
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                guard let frame = proxy.plotFrame,
                                      let x = proxy.value(atX: location.x - geo[frame].origin.x, as: Double.self),
                                      let i = Self.nearestIndex(x: x, count: points.count) else { return }
                                selected = Self.toggled(selected, tapped: points[i].key)
                            }
                    }
                }
                .frame(height: 180)
                Text(showsSleep ? L("Each bar runs from the build start to falling asleep – the shorter, the sooner you slept. The dashed line is your bedtime.")
                                : L("Dots = build start, line = bedtime.")).font(.caption).cardCaption()
            }
        }
    }

    static func clock(_ minutes: Double) -> String { Fmt.time(minutesOfDay: Int(minutes.rounded())) }
}

/// The story of one night (plus that afternoon's nap).
struct NightDetail: View {
    @Environment(AppModel.self) private var model
    let key: NightKey

    static func duration(_ t: TimeInterval?) -> String {
        guard let t else { return L("you didn't come back") }
        let s = Int(t.rounded())
        return s >= 60 ? L("\(s / 60) min \(s % 60) s") : L("\(s) s")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Night of \(Fmt.fullDate(key))")).font(.headline)
            if model.coreResults().contains(where: { $0.key == key && $0.outcome == .excused }) {
                Label(L("Protected by a joker 🛡️ – your streak waited for you."), systemImage: "shield.fill")
                    .font(.subheadline).foregroundStyle(.indigo)
            }
            if let rec = model.nightRecord(for: key), let outcome = rec.outcome {
                let r = NightReport(log: rec.log, rules: rec.rules)
                building(outcome: outcome)
                row("🌙", L("Build started"), r.startedAt.map(Fmt.timeSec))
                row("🔒", L("Phone locked"), r.firstLockAt.map(Fmt.timeSec))
                sleepRows(rec)
                row("⏰", L("Alarm"), r.alarmFiredAt.map { fired in
                        r.alarmStoppedAt.map { L("rang at \(Fmt.timeSec(fired)), stopped \(Fmt.time($0))") }
                            ?? L("rang at \(Fmt.timeSec(fired))") }
                    ?? ((r.confirmedAt ?? .distantFuture) < rec.wake ? L("didn't ring – you got up earlier") : nil))
                row("☀️", L("Got up"), r.confirmedAt.map { Fmt.timeSec($0) + (r.confirmMethod.map { $0 == .code ? L(" (code)") : L(" (shake)") } ?? "") })
                trips(L("Trips during setup (until \(r.setupEnds.map(Fmt.time) ?? "–"))"), r.setupTrips, ok: true)
                trips(L("Trips after setup"), r.nightTrips, ok: false)
                if !r.pauses.isEmpty { chips(L("🌙 Pauses: \(r.pauses.count)×"), r.pauses) }
                chips(L("👀 Screen checks: \(r.screenChecks.count)×"), r.screenChecks)
                if !r.calls.isEmpty { trips(L("📞 Calls"), r.calls, ok: true) }
                if !r.relaunches.isEmpty { chips(L("🔄 The app restarted"), r.relaunches) }
                if let c = r.collapsedAt { row("🧱", L("The building collapsed"), Fmt.timeSec(c)) }
                if let a = r.abandonedAt { row("✋", L("You cancelled the night"), Fmt.time(a)) }
                if let coins = model.coinsEarned(for: key) { row("🪙", L("Coins"), "+\(coins)") }
            } else {
                Label(L("The app didn't run that night – nothing was built."), systemImage: "moon.zzz")
                    .cardCaption()
            }
            if let nap = model.napRecord(before: key), let o = nap.outcome {
                Divider()
                row("😴", L("Nap \(Fmt.time(nap.bedtime))–\(Fmt.time(nap.wake))"),
                    (o == .complete ? L("complete") : o == .unfinished ? L("cut short") : L("didn't work out")) + " · +\(NapPlan.reward(o)) 🪙")
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func building(outcome: Outcome) -> some View {
        let b = model.townBuilding(for: key)
        let id = b.map { $0.state == .ruins ? "o-ruin-\($0.placement.size)" : $0.buildingId }
            ?? model.nightRecord(for: key)?.buildingId ?? ""
        HStack(spacing: 12) {
            BuildingImage(id: id, progress: b?.state == .unfinished ? 0.6 : 1, maxHeight: 90)
                .frame(width: 110)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.catalog?[model.nightRecord(for: key)?.buildingId ?? ""]?.displayName ?? "").font(.headline)
                Text(outcome == .complete ? L("Complete 🏢") : outcome == .unfinished ? L("Unfinished 🚧") : L("Ruins 🧱"))
                if b?.repairedLater == true { Text(L("Repaired later 🛠️")).foregroundStyle(Color.readableGreen) }
                if b?.completedLater == true { Text(L("Finished later 💪")).foregroundStyle(Color.readableGreen) }
            }
        }
    }

    /// Minutes from the build start to falling asleep: rounded, never negative.
    static func minutesToSleep(started: Date?, fellAsleep: Date) -> Int {
        max(0, Int((fellAsleep.timeIntervalSince(started ?? fellAsleep) / 60).rounded()))
    }

    /// The same on the chart's axis (minutes after 12:00): no build start counts as no waiting.
    static func minutesToSleep(startMinutes: Double?, asleepMinutes: Double) -> Int {
        max(0, Int((asleepMinutes - (startMinutes ?? asleepMinutes)).rounded()))
    }

    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let m = max(0, Int((seconds / 60).rounded()))
        return L("\(m / 60) h \(m % 60) min")
    }

    /// What the night's detail says about sleep (phase HEALTH): nothing with the switch off or before the first read.
    enum SleepLines: Equatable {
        case hidden
        case none
        case values(fellAsleep: String, slept: String, source: String?)
    }

    static func sleepLines(_ rec: NightRecord, on: Bool) -> SleepLines {
        guard on else { return .hidden }
        if let fell = rec.fellAsleepAt {
            let minutes = minutesToSleep(started: rec.startedAt, fellAsleep: fell)
            return .values(fellAsleep: Fmt.time(fell) + L(" (after \(minutes) min)"),
                           slept: rec.asleepSeconds.map(hoursMinutes) ?? "–",
                           source: rec.sleepSourceName)
        }
        return rec.sleepReadAt != nil ? .none : .hidden
    }

    @ViewBuilder
    private func sleepRows(_ rec: NightRecord) -> some View {
        switch Self.sleepLines(rec, on: model.settings.usesHealth) {
        case .hidden: EmptyView()
        case .none: Text(L("No sleep data for this night")).cardCaption()
        case let .values(fell, slept, source):
            row("😴", L("Fell asleep"), fell)
            row("🛌", L("Slept"), slept)
            if let source { Text(L("Source: \(source)")).cardCaption() }
            #if DEBUG
            debugSources(rec)
            #endif
        }
    }

    #if DEBUG
    /// Developer aid: what every source said about the night (which one the rule chose is marked).
    @ViewBuilder
    private func debugSources(_ rec: NightRecord) -> some View {
        ForEach(rec.sleepSources, id: \.name) { src in
            let m = Int((src.asleepSeconds / 60).rounded())
            let mark = src.name == rec.sleepSourceName ? "> " : "· "
            Text(verbatim: "\(mark)\(src.name): \(m / 60) h \(m % 60) min asleep, from \(Fmt.time(src.fellAsleepAt)), "
                 + (src.hasStages ? "stages" : "no stages") + (src.isFirstParty ? ", first-party" : ""))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    #endif

    private func row(_ icon: String, _ label: String, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(verbatim: icon)
            Text(label).cardCaption()
            Spacer()
            Text(value ?? "–").monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func trips(_ title: String, _ list: [NightReport.Trip], ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(title): \(list.count)×").cardCaption()
            ForEach(Array(list.enumerated()), id: \.offset) { _, t in
                HStack {
                    Text(Fmt.timeSec(t.start)).monospacedDigit()
                    Text(verbatim: "→ \(Self.duration(t.duration))")
                        .foregroundStyle(ok || t.duringPause || t.notCounted ? Color.cardCaption
                                         : (t.duration ?? .infinity) > 13 ? Color.readableOrange : Color.cardCaption)
                    if t.closedApp { Text(verbatim: "· \(L("closed the app"))").foregroundStyle(Color.cardCaption) }
                    if t.onLockScreen { Text(verbatim: "· \(L("used the phone on the lock screen"))").foregroundStyle(Color.cardCaption) }
                    if t.duringPause { Text(verbatim: "🌙") }
                }
                .font(.caption)
            }
        }
    }

    private func chips(_ title: String, _ dates: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).cardCaption()
            if !dates.isEmpty {
                Text(dates.map(Fmt.time).joined(separator: " · "))
                    .font(.caption.monospacedDigit())
            }
        }
    }
}
