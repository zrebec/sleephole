import SleepCore
import SwiftUI

/// Weekly town journal (idea M, owner 2026-09-30): one week in numbers plus a warm sentence.
struct WeekJournalView: View {
    let week: WeekSummary
    /// The week before, for a gentle comparison.
    var previous: WeekSummary?
    var showTitle = true

    static func range(_ w: WeekSummary) -> String { "\(Fmt.dayMonth(w.monday)) – \(Fmt.dayMonth(w.sunday))" }

    /// Never shaming: a quiet week gets a fresh start, fewer good nights than last week are not mentioned.
    static func sentence(_ w: WeekSummary, previous: WeekSummary?) -> String {
        if w.nights == 0 { return L("A quiet week. Tonight is a new start 🌱") }
        if w.complete == 7 { return L("A perfect week – every night complete! 🌟") }
        if let p = previous, p.nights > 0, w.complete > p.complete { return L("Better than last week – your town noticed 💪") }
        if w.complete >= 5 { return L("A great week for your town 🏙️") }
        return L("Every night counts – your town keeps growing 🌱")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showTitle {
                Text(L("Week of \(Self.range(week))")).font(.headline)
            }
            if week.nights > 0 {
                HStack(spacing: 14) {
                    count("🏢", week.complete, L("complete"))
                    count("🚧", week.unfinished, L("unfinished"))
                    count("🧱", week.ruins, L("ruins"))
                    Spacer()
                    Text(verbatim: "+\(week.coins) 🪙").font(.headline).foregroundStyle(.yellow)
                }
                if !week.buildingIds.isEmpty {
                    Text(L("New buildings: \(week.buildingIds.count)")).font(.subheadline)
                    HStack(spacing: 4) {
                        ForEach(Array(week.buildingIds.prefix(7).enumerated()), id: \.offset) { _, id in
                            BuildingImage(id: id, maxHeight: 40).frame(maxWidth: 44)
                        }
                    }
                }
                if let start = week.averageStart, let wake = week.averageWake {
                    Text(L("Average start \(Fmt.time(start)) · wake-up \(Fmt.time(wake))")).font(.subheadline)
                }
                Text(L("Best streak: \(week.bestStreak) 🔥")).font(.subheadline)
                if week.completeNaps > 0 { Text(L("Complete naps: \(week.completeNaps) 😴")).font(.subheadline) }
                if let p = previous, p.nights > 0 {
                    Text(L("Complete nights last week: \(p.complete)")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Text(Self.sentence(week, previous: previous)).font(.subheadline.italic())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func count(_ icon: String, _ n: Int, _ label: String) -> some View {
        Text(verbatim: "\(icon) \(n)").font(.headline.monospacedDigit()).accessibilityLabel(Text(verbatim: "\(n) \(label)"))
    }
}

/// Štatistiky → "Town journal": this week so far + the earlier weeks (collapsed).
struct JournalCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let weeks = model.journalWeeks
        let current = model.journalWeek(monday: model.currentMonday)
        let lastMonday = model.currentMonday.adding(days: -7, calendar: .current)
        let earlier = weeks.filter { $0.monday < model.currentMonday }
        VStack(alignment: .leading, spacing: 10) {
            Text(L("This week · \(WeekJournalView.range(current))")).font(.subheadline.bold())
            if current.nights == 0 && current.completeNaps == 0 {
                Text(L("No nights yet this week – tonight can be the first 🌙")).font(.subheadline).foregroundStyle(.secondary)
            } else {
                WeekJournalView(week: current, previous: weeks.first { $0.monday == lastMonday }, showTitle: false)
            }
            if !earlier.isEmpty {
                DisclosureGroup(L("Earlier weeks")) {
                    ForEach(Array(earlier.enumerated()), id: \.element.monday) { i, w in
                        DisclosureGroup {
                            WeekJournalView(week: w, previous: earlier[safe: i + 1], showTitle: false)
                                .padding(.vertical, 4)
                        } label: {
                            Text(verbatim: "\(WeekJournalView.range(w)) · 🏢 \(w.complete) · +\(w.coins) 🪙")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }
}
