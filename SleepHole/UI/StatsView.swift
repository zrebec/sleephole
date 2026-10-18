import Charts
import SleepCore
import SwiftUI

/// "Štatistiky" tab (plan §9, F4).
struct StatsView: View {
    @Environment(AppModel.self) private var model
    /// `-selectLastNight` preselects the newest night (screenshots).
    @State private var selectedDay: NightKey?
    private let preselect = DevArgs.list.contains("-selectLastNight")

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
                            // the scroll target includes some air above the header, so after the auto-scroll the
                            // navigation bar does not cover the header's first line (B15)
                            NightDetail(key: key).padding(.top, Self.detailTopInset).id("detail")
                        } else {
                            Text(L("Tap a day to see how that night went.")).font(.footnote).cardCaption()
                        }
                    }
                    card(L("Average (last 14 nights)")) {
                        HStack {
                            metric(L("Build start"), s.averageStart.map(Fmt.time) ?? "–")
                            Divider()
                            metric(L("Getting up"), s.averageWake.map(Fmt.time) ?? "–")
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
                    card(showsSleep(s) ? L("When you go to bed, fall asleep and get up") : L("When you start and get up")) {
                        NightChart(points: Self.chartSeries(s.series), bedtime: model.settings.schedule, showsSleep: showsSleep(s),
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
                let target = DevArgs.value(after: "-scrollTo")
                for id in ["journal", "achievements", "chart", "average"] where target == id { proxy.scrollTo(id, anchor: .top) }
                if target == "detail" {                // after `-selectLastNight` has opened the detail card
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo("detail", anchor: .top) }
                }
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
    /// Air above the night detail's header, inside its scroll target.
    static let detailTopInset: CGFloat = 28

    static func launchChartNight(_ series: [NightPoint], args: [String] = DevArgs.list) -> NightKey? {
        guard let i = args.firstIndex(of: "-selectChartNight"), i + 1 < args.count, let back = Int(args[i + 1]),
              series.indices.contains(series.count - 1 - back) else { return nil }
        return series[series.count - 1 - back].key
    }

    /// `-hideSleepFor N` (Debug) → the N newest nights lose their Health values on the chart.
    static func chartSeries(_ series: [NightPoint], args: [String] = DevArgs.list) -> [NightPoint] {
        NightChart.hidingSleep(series, count: DevArgs.value(after: "-hideSleepFor", in: args).flatMap(Int.init) ?? 0)
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

    enum RegularityLevel: Equatable { case excellent, good, varies }

    /// The word follows the number the user sees: the level comes from the rounded minutes (≤15 excellent, ≤30 good).
    static func regularityLevel(_ minutes: Double) -> RegularityLevel {
        let r = Int(minutes.rounded())
        return r <= 15 ? .excellent : r <= 30 ? .good : .varies
    }

    @ViewBuilder
    private func regularity(_ minutes: Double?) -> some View {
        if let m = minutes {
            let (text, color): (String, Color) = switch Self.regularityLevel(m) {
            case .excellent: (L("excellent 🌟"), Color.readableGreen)
            case .good: (L("good 👍"), Color.readableYellow)
            case .varies: (L("varies – try to start at the same time 🌙"), Color.readableOrange)
            }
            Label(L("Regularity: ±\(Int(m.rounded())) min – \(text)"), systemImage: "clock.fill")
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

    @Environment(\.colorScheme) private var scheme

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
        let up = p.upMinutes.map(clock(afterNoon:))
        if showsSleep, let asleep = p.asleepMinutes {
            let after = NightDetail.minutesToSleep(startMinutes: p.startMinutes, asleepMinutes: asleep)
            if let up {
                return L("\(date) · start \(start) · asleep \(clock(afterNoon: asleep)) · after \(after) min · up \(up)")
            }
            return L("\(date) · start \(start) · asleep \(clock(afterNoon: asleep)) · after \(after) min")
        }
        if let up { return L("\(date) · start \(start) · up \(up)") }
        return L("\(date) · start \(start)")
    }

    /// The y axis (minutes after 12:00) in whole 2 h steps: from the earliest to the latest mark (bedtime and wake
    /// time included), at least `minSpan` long, so the evening and the morning both fit.
    static func yDomain(points: [NightPoint], bed: Double, wake: Double, minSpan: Double = 480) -> ClosedRange<Double> {
        let values = points.flatMap { [$0.startMinutes, $0.asleepMinutes, $0.upMinutes] }.compactMap { $0 } + [bed, wake]
        var lo = ((values.min() ?? bed) / 120).rounded(.down) * 120
        var hi = ((values.max() ?? wake) / 120).rounded(.up) * 120
        if hi - lo < minSpan { hi = lo + minSpan }
        lo = max(lo, 0)
        return lo...hi
    }

    /// Whole-hour labels: every 2 h (every 4 h when the domain is longer than 14 h, so the labels stay readable).
    static func yTicks(_ domain: ClosedRange<Double>) -> [Double] {
        let step: Double = domain.upperBound - domain.lowerBound > 840 ? 240 : 120
        let first = (domain.lowerBound / step).rounded(.up) * step
        return Array(stride(from: first, through: domain.upperBound, by: step))
    }

    /// The blue of sleep (falling asleep → getting up) and of the dashed wake line; theme-aware, ≥ 3 : 1 on the card.
    static func sleepBlue(dark: Bool) -> Color {
        dark ? Color(red: 0x8D / 255, green: 0xB4 / 255, blue: 0xF2 / 255) : Color(red: 0x3E / 255, green: 0x6F / 255, blue: 0xC9 / 255)
    }
    static let sleepLineOpacity = (dark: 0.8, light: 0.75)
    /// The gradient of a night without Apple Health fades to this opacity at getting up.
    static let gradientTopOpacity = 0.25

    /// The ring around the start dot: the card's own colour, so a joker's pale indigo dot stays visible on the indigo bar.
    static func ringColor(dark: Bool) -> Color { CardBacking.color(dark: dark) }

    /// A night without Apple Health (or with the switch off) that has a start and a getting up is drawn as one
    /// gradient line in the night's outcome colour – never as "sleep".
    static func drawsGradient(_ p: NightPoint, showsSleep: Bool) -> Bool {
        p.startMinutes != nil && p.upMinutes != nil && (!showsSleep || p.asleepMinutes == nil)
    }

    /// The blue sleep line (falling asleep → getting up) exists only with Health data and a getting up.
    static func drawsSleepLine(_ p: NightPoint, showsSleep: Bool) -> Bool {
        showsSleep && p.asleepMinutes != nil && p.upMinutes != nil
    }

    /// Bottom (start) full colour, top (getting up) the same colour faded.
    static func gradientColors(_ outcome: Outcome) -> [Color] {
        let c = CalendarGrid.color(outcome)
        return [c, c.opacity(gradientTopOpacity)]
    }

    enum LegendItem: Equatable { case fallingAsleep, sleep, withoutHealth, outcome(Outcome) }

    /// The chips under the chart: only marks that really appear in it.
    static func legendItems(points: [NightPoint], showsSleep: Bool) -> [LegendItem] {
        var items: [LegendItem] = []
        if showsSleep, points.contains(where: { $0.startMinutes != nil && $0.asleepMinutes != nil }) { items.append(.fallingAsleep) }
        if points.contains(where: { drawsSleepLine($0, showsSleep: showsSleep) }) { items.append(.sleep) }
        if showsSleep, points.contains(where: { drawsGradient($0, showsSleep: true) }) { items.append(.withoutHealth) }
        for o in [Outcome.complete, .unfinished, .ruins, .excused]
        where points.contains(where: { $0.startMinutes != nil && $0.outcome == o }) { items.append(.outcome(o)) }
        return items
    }

    /// Debug: `-hideSleepFor N` drops the Health values of the N newest nights (screenshots of the no-Health look).
    static func hidingSleep(_ series: [NightPoint], count: Int) -> [NightPoint] {
        guard count > 0 else { return series }
        return series.enumerated().map { i, p in
            i < series.count - count ? p
                : NightPoint(key: p.key, startMinutes: p.startMinutes, wakeMinutes: p.wakeMinutes, asleepMinutes: nil,
                             outcome: p.outcome, upMinutes: p.upMinutes)
        }
    }

    /// Clock time of a minute count after 12:00.
    static func clock(afterNoon minutes: Double) -> String { Fmt.time(minutesOfDay: Int((minutes + 720).rounded())) }

    // MARK: view

    var body: some View {
        if points.isEmpty {
            Text(L("The chart fills up after your first nights.")).font(.subheadline).cardCaption()
        } else {
            let bed = Double((bedtime.bedtime.hour * 60 + bedtime.bedtime.minute + 720) % 1440)
            let wakeAt = Double((bedtime.wake.hour * 60 + bedtime.wake.minute + 720) % 1440)
            let domain = Self.yDomain(points: points, bed: bed, wake: wakeAt)
            let step = Self.labelStep(count: points.count)
            let chosen = points.first { $0.key == selected }
            let dark = scheme == .dark
            let blue = Self.sleepBlue(dark: dark)
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
                    RuleMark(y: .value(L("Getting up"), wakeAt))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(blue.opacity(0.6))
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
                        if Self.drawsSleepLine(p, showsSleep: showsSleep), let a = p.asleepMinutes, let up = p.upMinutes {
                            RuleMark(x: .value(L("Night"), i), yStart: .value(L("Fell asleep"), a), yEnd: .value(L("Getting up"), up))
                                .lineStyle(StrokeStyle(lineWidth: on ? 5 : 3, lineCap: .round))
                                .foregroundStyle(blue.opacity(dark ? Self.sleepLineOpacity.dark : Self.sleepLineOpacity.light))
                                .accessibilityLabel(label)
                        } else if Self.drawsGradient(p, showsSleep: showsSleep), let s = p.startMinutes, let up = p.upMinutes {
                            RuleMark(x: .value(L("Night"), i), yStart: .value(L("Start"), s), yEnd: .value(L("Getting up"), up))
                                .lineStyle(StrokeStyle(lineWidth: on ? 5 : 3, lineCap: .round))
                                .foregroundStyle(LinearGradient(colors: Self.gradientColors(p.outcome), startPoint: .bottom, endPoint: .top))
                                .accessibilityLabel(label)
                        }
                        if let s = p.startMinutes {
                            let size: Double = on ? 150 : 55
                            PointMark(x: .value(L("Night"), i), y: .value(L("Start"), s))      // the ring in the card's colour
                                .foregroundStyle(Self.ringColor(dark: dark))
                                .symbolSize(pow(size.squareRoot() + 4, 2))
                            PointMark(x: .value(L("Night"), i), y: .value(L("Start"), s))
                                .foregroundStyle(CalendarGrid.color(p.outcome))
                                .symbolSize(size)
                                .accessibilityLabel(label)
                        }
                        if on, showsSleep, let a = p.asleepMinutes {
                            PointMark(x: .value(L("Night"), i), y: .value(L("Fell asleep"), a))
                                .foregroundStyle(Color.blue)
                                .symbol(.diamond)
                                .symbolSize(150)
                                .accessibilityLabel(label)
                        }
                        if on, let up = p.upMinutes {
                            PointMark(x: .value(L("Night"), i), y: .value(L("Getting up"), up))
                                .foregroundStyle(Self.drawsGradient(p, showsSleep: showsSleep) ? CalendarGrid.color(p.outcome) : blue)
                                .symbolSize(150)
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
                    AxisMarks(values: Self.yTicks(domain)) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let m = v.as(Double.self) { Text(Self.clock(afterNoon: m)) }
                        }
                    }
                }
                .chartYScale(domain: domain)
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
                legend
                Text(showsSleep ? L("The start dot has the night's colour from the calendar. The indigo part runs to falling asleep – the shorter, the sooner you slept. Blue is your sleep until you got up (your confirmation, else Apple Health). The dashed lines are your bedtime and wake-up.")
                                : L("The start dot has the night's colour from the calendar. The line runs from the start to getting up and fades towards the morning. The dashed lines are your bedtime and wake-up.")).font(.caption).cardCaption()
            }
        }
    }

    static func clock(_ minutes: Double) -> String { Fmt.time(minutesOfDay: Int(minutes.rounded())) }

    /// Chips of the marks FIRST, then the words.
    private var legend: some View {
        let dark = scheme == .dark
        let blue = Self.sleepBlue(dark: dark)
        return ChipFlow(spacing: 12, lineSpacing: 6) {
            ForEach(Self.legendItems(points: points, showsSleep: showsSleep), id: \.self) { item in
                HStack(spacing: 5) {
                    switch item {
                    case .fallingAsleep:
                        Capsule().fill(Self.barColor).frame(width: 5, height: 14)
                        Text(L("Falling asleep"))
                    case .sleep:
                        Capsule().fill(blue.opacity(dark ? Self.sleepLineOpacity.dark : Self.sleepLineOpacity.light)).frame(width: 3, height: 14)
                        Text(L("Sleep"))
                    case .withoutHealth:
                        Capsule().fill(LinearGradient(colors: Self.gradientColors(.complete), startPoint: .bottom, endPoint: .top))
                            .frame(width: 3, height: 14)
                        Text(L("Without Apple Health"))
                    case .outcome(let o):
                        Circle().fill(CalendarGrid.color(o)).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Self.ringColor(dark: dark), lineWidth: 1))
                        Text(Self.outcomeName(o))
                    }
                }
            }
        }
        .font(.caption2)
        .accessibilityElement(children: .combine)
    }

    static func outcomeName(_ o: Outcome) -> String {
        switch o {
        case .complete: L("complete")
        case .unfinished: L("unfinished")
        case .ruins: L("ruins")
        case .excused: L("joker 🛡️")
        case .missed: ""
        }
    }
}

extension NightChart.LegendItem: Hashable {}

/// Wraps its children into lines, left to right (the chart legend).
private struct ChipFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + lineSpacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), frames)
    }
}

/// The story of one night (plus that afternoon's nap).
struct NightDetail: View {
    @Environment(AppModel.self) private var model
    let key: NightKey

    static func duration(_ t: TimeInterval?) -> String {
        guard let t else { return L("you didn't come back") }
        let s = Int(t.rounded())
        return s >= 60 ? L("\(s / 60) min \(s % 60)s") : L("\(s)s")
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
                if !r.screenChecks.isEmpty { chips(L("👀 Screen checks: \(r.screenChecks.count)×"), r.screenChecks) }   // nights stored before 2026-10-14 only
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
                    if t.onLockScreen { Text(verbatim: "· \(L("used the phone outside the app"))").foregroundStyle(Color.cardCaption) }
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
