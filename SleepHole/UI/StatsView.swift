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
                        tile("🔥", "\(s.currentStreak)", "séria teraz")
                        tile("🏆", "\(s.bestStreak)", "najdlhšia séria")
                        tile("🏗️", "\(s.builtNights)", "postavené noci")
                        tile("🪙", "\(s.coins)", "mince")
                    }
                    card("Kalendár nocí") {
                        CalendarGrid(days: s.calendar, selected: $selectedDay)
                        if let key = selectedDay {
                            Divider()
                            NightDetail(key: key).id("detail")
                        } else {
                            Text("Ťukni na deň a uvidíš, ako tá noc prebehla.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    card("Priemer (posledných 14 nocí)") {
                        HStack {
                            metric("Štart stavby", s.averageStart.map(\.description) ?? "–")
                            Divider()
                            metric("Vstávanie", s.averageWake.map(\.description) ?? "–")
                        }
                        regularity(s.regularityMinutes)
                    }
                    card("Kedy začínaš a vstávaš") { NightChart(points: s.series, bedtime: model.settings.schedule) }
                    card("Odpočinky") {
                        let n = model.napSummary
                        Label("\(n.count) hotových odpočinkov · +\(n.coins) 🪙", systemImage: "bed.double.fill")
                    }
                    card("Levely") {
                        ProgressView(value: Double(s.maxLevel), total: 4) { Text("Odomknutý level \(s.maxLevel) zo 4") }
                        if let next = Progression.nightsToNextLevel(built: s.builtNights) {
                            Text("Level \(next.level) o \(SK.nights(next.nights))").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: selectedDay) { _, day in
                if day != nil { withAnimation { proxy.scrollTo("detail", anchor: .top) } }
            }
            }
            .navigationTitle("Štatistiky")
            .onAppear { if preselect, selectedDay == nil { selectedDay = model.realResults().last.map { NightKey($0.keyString)! } } }
        }
    }

    private func tile(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(icon).font(.title)
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
            let (text, color): (String, Color) = m <= 15 ? ("výborná 🌟", .green) : m <= 30 ? ("dobrá 👍", .yellow)
                : ("kolíše – skús začínať v rovnaký čas 🌙", .orange)
            Label("Pravidelnosť: ±\(Int(m.rounded())) min – \(text)", systemImage: "metronome.fill")
                .font(.subheadline).foregroundStyle(color)
        } else {
            Text("Pravidelnosť uvidíš po 2 nociach.").font(.subheadline).foregroundStyle(.secondary)
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
                            .overlay(Text("\(d.key.day)").font(.caption2).foregroundStyle(.primary.opacity(0.7)))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: selected.wrappedValue == d.key ? 3 : 0))
                    }
                    .buttonStyle(.plain)                 // no accent tint on the day numbers
                    .accessibilityLabel("\(d.key.day). \(d.key.month).")
                }
            }
            HStack(spacing: 12) {
                legend(.green, "hotová"); legend(.orange, "rozostavaná"); legend(.gray, "ruina")
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
            Text("Graf sa naplní po prvých nociach.").font(.subheadline).foregroundStyle(.secondary)
        } else {
            let bed = Double((bedtime.bedtime.hour * 60 + bedtime.bedtime.minute + 720) % 1440)
            Chart {
                RuleMark(y: .value("Večierka", bed))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.indigo.opacity(0.6))
                ForEach(points, id: \.key) { p in
                    if let s = p.startMinutes {
                        PointMark(x: .value("Noc", "\(p.key.day).\(p.key.month)."), y: .value("Štart", s))
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
            Text("Body = začiatok stavby, čiara = večierka.").font(.caption).foregroundStyle(.secondary)
        }
    }

    static func clock(_ minutes: Double) -> String {
        let m = (Int(minutes.rounded()) % 1440 + 1440) % 1440
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

/// The story of one night (plus that afternoon's nap).
struct NightDetail: View {
    @Environment(AppModel.self) private var model
    let key: NightKey

    static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "H:mm"; return f }()
    static let timeSec: DateFormatter = { let f = DateFormatter(); f.dateFormat = "H:mm:ss"; return f }()

    static func duration(_ t: TimeInterval?) -> String {
        guard let t else { return "nevrátil si sa" }
        let s = Int(t.rounded())
        return s >= 60 ? "\(s / 60) min \(s % 60) s" : "\(s) s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Noc na \(key.day). \(key.month). \(key.year)").font(.headline)   // verbatim: no "2 026"
            if let rec = model.nightRecord(for: key), let outcome = rec.outcome {
                let r = NightReport(log: rec.log, rules: rec.rules)
                building(outcome: outcome)
                row("🌙", "Začiatok stavby", r.startedAt.map { Self.timeSec.string(from: $0) })
                row("🔒", "Zamkol si telefón", r.firstLockAt.map { Self.timeSec.string(from: $0) })
                row("⏰", "Budík", r.alarmFiredAt.map { "zazvonil \(Self.timeSec.string(from: $0))" + (r.alarmStoppedAt.map { ", stíchol \(Self.time.string(from: $0))" } ?? "") }
                    ?? ((r.confirmedAt ?? .distantFuture) < rec.wake ? "nezazvonil – vstal si skôr" : nil))
                row("☀️", "Vstal si", r.confirmedAt.map { Self.timeSec.string(from: $0) + (r.confirmMethod.map { $0 == .code ? " (kód)" : " (zatrasenie)" } ?? "") })
                trips("Odchody počas prípravy (do \(r.setupEnds.map { Self.time.string(from: $0) } ?? "–"))", r.setupTrips, ok: true)
                trips("Odchody po príprave", r.nightTrips, ok: false)
                chips("👀 Pohľady na displej: \(r.screenChecks.count)×", r.screenChecks)
                if !r.calls.isEmpty { trips("📞 Telefonáty", r.calls, ok: true) }
                if !r.relaunches.isEmpty { chips("🔄 Appka sa reštartovala", r.relaunches) }
                if let c = r.collapsedAt { row("🧱", "Stavba sa zrútila", Self.timeSec.string(from: c)) }
                if let a = r.abandonedAt { row("✋", "Noc si zrušil", Self.time.string(from: a)) }
                if let coins = model.coinsEarned(for: key) { row("🪙", "Mince", "+\(coins)") }
            } else {
                Label("Appka v túto noc nebežala – nestavalo sa.", systemImage: "moon.zzz")
                    .foregroundStyle(.secondary)
            }
            if let nap = model.napRecord(before: key), let o = nap.outcome {
                Divider()
                row("😴", "Odpočinok \(Self.time.string(from: nap.bedtime))–\(Self.time.string(from: nap.wake))",
                    (o == .complete ? "hotový" : o == .unfinished ? "skrátený" : "nepodaril sa") + " · +\(NapPlan.reward(o)) 🪙")
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
                Text(model.catalog?[model.nightRecord(for: key)?.buildingId ?? ""]?.nameSK ?? "").font(.headline)
                Text(outcome == .complete ? "Hotová 🏢" : outcome == .unfinished ? "Rozostavaná 🚧" : "Ruina 🧱")
                if b?.repairedLater == true { Text("Neskôr opravená 🛠️").foregroundStyle(.green) }
                if b?.completedLater == true { Text("Neskôr dostavaná 💪").foregroundStyle(.green) }
            }
        }
    }

    private func row(_ icon: String, _ label: String, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(icon)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "–").monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func trips(_ title: String, _ list: [NightReport.Trip], ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(list.count)×").foregroundStyle(.secondary)
            ForEach(Array(list.enumerated()), id: \.offset) { _, t in
                HStack {
                    Text(Self.timeSec.string(from: t.start)).monospacedDigit()
                    Text("→ \(Self.duration(t.duration))")
                        .foregroundStyle(ok ? Color.secondary : (t.duration ?? .infinity) > 13 ? .orange : .secondary)
                }
                .font(.caption)
            }
        }
    }

    private func chips(_ title: String, _ dates: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            if !dates.isEmpty {
                Text(dates.map { Self.time.string(from: $0) }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
            }
        }
    }
}
