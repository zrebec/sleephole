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
                            Text(L("Tap a day to see how that night went.")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    card(L("Average (last 14 nights)")) {
                        HStack {
                            metric(L("Build start"), s.averageStart.map(Fmt.time) ?? "–")
                            Divider()
                            metric(L("Wake-up"), s.averageWake.map(Fmt.time) ?? "–")
                        }
                        regularity(s.regularityMinutes)
                    }
                    card(L("When you start and get up")) { NightChart(points: s.series, bedtime: model.settings.schedule) }
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
                            Text(L("Level \(next.level) in \(Plural.nights(next.nights))")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .skyBackground()
            .onAppear {                                   // `-scrollTo journal|achievements` (screenshots)
                let args = ProcessInfo.processInfo.arguments
                for id in ["journal", "achievements"] where args.contains(id) { proxy.scrollTo(id, anchor: .top) }
            }
            .onChange(of: selectedDay) { _, day in
                if day != nil { withAnimation { proxy.scrollTo("detail", anchor: .top) } }
            }
            }
            .navigationTitle(L("Stats"))
            .onAppear { if preselect, selectedDay == nil { selectedDay = model.realResults().last.map { NightKey($0.keyString)! } } }
        }
    }

    private func tile(_ icon: String, _ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(icon).font(.title)
            Text(verbatim: "\(value)").font(.title.bold().monospacedDigit())
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label).font(.caption).foregroundStyle(.secondary)
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
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func regularity(_ minutes: Double?) -> some View {
        if let m = minutes {
            let (text, color): (String, Color) = m <= 15 ? (L("excellent 🌟"), .green) : m <= 30 ? (L("good 👍"), .yellow)
                : (L("varies – try to start at the same time 🌙"), .orange)
            Label(L("Regularity: ±\(Int(m.rounded())) min – \(text)"), systemImage: "metronome.fill")
                .font(.subheadline).foregroundStyle(color)
        } else {
            Text(L("You'll see your regularity after 2 nights.")).font(.subheadline).foregroundStyle(.secondary)
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
                            .overlay(Text(verbatim: "\(d.key.day)").font(.caption2).foregroundStyle(.primary.opacity(0.7)))
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

/// Start and wake times of the last 30 nights (dashed lines = the schedule).
struct NightChart: View {
    let points: [NightPoint]
    let bedtime: Schedule

    var body: some View {
        if points.isEmpty {
            Text(L("The chart fills up after your first nights.")).font(.subheadline).foregroundStyle(.secondary)
        } else {
            let bed = Double((bedtime.bedtime.hour * 60 + bedtime.bedtime.minute + 720) % 1440)
            Chart {
                RuleMark(y: .value(L("Bedtime"), bed))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.indigo.opacity(0.6))
                ForEach(points, id: \.key) { p in
                    if let s = p.startMinutes {
                        PointMark(x: .value(L("Night"), Fmt.dayMonth(p.key)), y: .value(L("Start"), s))
                            .foregroundStyle(CalendarGrid.color(p.outcome))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let m = v.as(Double.self) { Text(Self.clock(m + 720)) }
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            Text(L("Dots = build start, line = bedtime.")).font(.caption).foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                if b?.repairedLater == true { Text(L("Repaired later 🛠️")).foregroundStyle(.green) }
                if b?.completedLater == true { Text(L("Finished later 💪")).foregroundStyle(.green) }
            }
        }
    }

    private func row(_ icon: String, _ label: String, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(verbatim: icon)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "–").monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func trips(_ title: String, _ list: [NightReport.Trip], ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(title): \(list.count)×").foregroundStyle(.secondary)
            ForEach(Array(list.enumerated()), id: \.offset) { _, t in
                HStack {
                    Text(Fmt.timeSec(t.start)).monospacedDigit()
                    Text(verbatim: "→ \(Self.duration(t.duration))")
                        .foregroundStyle(ok || t.duringPause ? Color.secondary
                                         : (t.duration ?? .infinity) > 13 ? .orange : .secondary)
                    if t.duringPause { Text(verbatim: "🌙") }
                }
                .font(.caption)
            }
        }
    }

    private func chips(_ title: String, _ dates: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            if !dates.isEmpty {
                Text(dates.map(Fmt.time).joined(separator: " · "))
                    .font(.caption.monospacedDigit())
            }
        }
    }
}
