import Foundation
import Testing
@testable import SleepCore

// Economy simulation (build 11, step 11b1): always-on sanity tests + the dev-aid report
// `ECON_SIM=/path/dir swift test --filter EconomySimulation` writes report.md and report.json there.

// MARK: - Aggregation

private func percentile(_ v: [Double], _ p: Double) -> Double {
    let s = v.sorted()
    return s.isEmpty ? 0 : s[Int((p * Double(s.count - 1)).rounded())]
}
private func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }

/// All metrics of one combination at one checkpoint; `-1` = "none" for the completion months.
private func aggregate(_ runs: [SimRun], checkpoint c: Int) -> [String: Double] {
    let nights = Double(simCheckpoints[c])
    let snaps = runs.map { $0.snaps[c] }
    func col(_ f: (SimSnap) -> Int) -> [Double] { snaps.map { Double(f($0)) } }
    var m: [String: Double] = [:]
    let bal = col { $0.balance }
    let avg = snaps.map(\.avgBalance)
    m["avg_balance_p10"] = percentile(avg, 0.1); m["avg_balance_median"] = percentile(avg, 0.5); m["avg_balance_p90"] = percentile(avg, 0.9)
    m["lowest_after_30_median"] = percentile(col { $0.lowestAfter30 }, 0.5)
    m["balance_p10"] = percentile(bal, 0.1); m["balance_median"] = percentile(bal, 0.5); m["balance_p90"] = percentile(bal, 0.9)
    for (k, f) in [("buildings", { (s: SimSnap) in s.building }), ("withoutPause", { $0.undisturbed }),
                   ("calmHours", { $0.calm }), ("streak7", { $0.streak }), ("naps", { $0.nap }),
                   ("achievements", { $0.achievement }), ("boxReturns", { $0.boxCoins }),
                   ("pauses", { $0.pauses }), ("silverJokers", { $0.silver }), ("scheduleUnlocks", { $0.unlock }),
                   ("rerolls", { $0.reroll }), ("boxesPaid", { $0.boxPaid }),
                   ("rerollCount", { $0.rerolls }), ("silverBought", { $0.silversBought }), ("silverWanted", { $0.silverWanted }),
                   ("luckyWon", { $0.luckyWon }), ("luckyPaid", { $0.luckyPaid }),
                   ("boxJokersWon", { $0.jokersWon }), ("boxJokersUsed", { $0.jokersUsed })] as [(String, (SimSnap) -> Int)] {
        m["mean_" + k] = mean(col(f))
    }
    let earned = mean(snaps.map { Double($0.building + $0.undisturbed + $0.calm + $0.streak + $0.nap + $0.achievement + $0.boxCoins) })
    m["earned_per_night"] = earned / nights
    m["earned_per_30_days"] = earned / nights * 30
    let boxes = Double(snaps.map(\.boxes).reduce(0, +)), paid = Double(snaps.map(\.boxPaid).reduce(0, +))
    m["boxes_per_month"] = boxes / Double(snaps.count) / (nights / 30.4375)
    m["avg_box_price"] = boxes > 0 ? paid / boxes : 0
    m["real_return_pct"] = paid > 0 ? Double(snaps.map(\.boxCoins).reduce(0, +)) / paid * 100 : 0
    m["pct_runs_below_400"] = Double(snaps.filter(\.below400).count) / Double(snaps.count) * 100
    let big = col { $0.largestPrize }
    m["largest_prize_median"] = percentile(big, 0.5); m["largest_prize_max"] = big.max() ?? 0
    for col_ in SimCollection.allCases {
        let i = col_.rawValue
        m["owned_median_\(col_.label)"] = percentile(snaps.map { Double($0.owned[i]) }, 0.5)
        let months = snaps.map { $0.completeMonth[i].map(Double.init) ?? Double.infinity }
        let med = percentile(months, 0.5)
        m["complete_month_median_\(col_.label)"] = med.isInfinite ? -1 : med
    }
    return m
}

// MARK: - The report

private struct Combo {
    let profile: SimProfile
    let policy: Int
    let variant: SimOddsVariant?
    let rerolls: Bool
    var id: String { "\(profile.name)/P\(policy)/\(variant?.name ?? "-")/rerolls-\(rerolls ? "on" : "off")" }
    var config: SimConfig { SimConfig(profile: profile, boxesPerMonth: policy, variant: variant, rerolls: rerolls) }
}

private func f0(_ x: Double) -> String { String(Int(x.rounded())) }
private func f1(_ x: Double) -> String { String(format: "%.1f", x) }

@Suite struct EconomySimulation {
    /// Dev aid: writes the report when ECON_SIM is set; ECON_RUNS overrides the 500 runs (for a quick look).
    @Test func writeReport() throws {
        guard let dir = ProcessInfo.processInfo.environment["ECON_SIM"] else { return }
        let runs = Int(ProcessInfo.processInfo.environment["ECON_RUNS"] ?? "") ?? 500
        let started = Date()
        let catalog = try loadRealCatalog()
        let calendar = SimCalendar()
        var cache: [String: [String: [String: Double]]] = [:]       // combo id → checkpoint → metrics

        func run(_ combos: [Combo]) {
            for combo in combos where cache[combo.id] == nil {
                let rs = simulateBatch(combo.config, runs: runs, catalog: catalog, calendar: calendar)
                var per: [String: [String: Double]] = [:]
                for (c, n) in simCheckpoints.enumerated() { per["\(n)"] = aggregate(rs, checkpoint: c) }
                cache[combo.id] = per
            }
        }
        func boxCombos(_ variants: [SimOddsVariant]) -> [Combo] {
            SimProfile.all.flatMap { p in [3, 6, 9].flatMap { k in variants.map { Combo(profile: p, policy: k, variant: $0, rerolls: true) } } }
        }
        func g(_ c: Combo, _ n: Int, _ k: String) -> Double { cache[c.id]!["\(n)"]![k]! }

        let base = SimProfile.all.flatMap { p in [false, true].map { Combo(profile: p, policy: 0, variant: nil, rerolls: $0) } }
        run(base)
        let variants: [SimOddsVariant] = [.A, .B, .C, .CNew, .CNewReserve, .D]
        run(boxCombos(variants))

        // ---- markdown
        var md = "# SleepHole economy simulation (build 11, step 11b1)\n\n"
        md += """
        ## Assumptions
        - Start night key 2026-11-01 (Gregorian, Europe/Bratislava), 365 nights of a fresh user (0 coins, nothing built); checkpoints after night 30 / 100 / 365 (the night's morning box included; the box is bought on the night key = the wake date, and the month counter follows that date).
        - Schedule 22:30 -> 06:30, 5-minute setup: 7 possible calm hours (22:35 to 06:30). Real rules from SleepCore: Economy, PausePolicy, NapPlan, Jokers, Progression, BuildingPicker (real catalog), Reroll, SchedulePolicy, Achievements.
        - \(runs) runs per combination, seeded per profile / policy / variant / run index; the night events (nap, outcome, pauses, calm hours, reroll dice) are drawn from a stream seeded by profile + run index, so P0 / P3 / P6 / P9 and the variants live the same life (paired). Same seeds give the same report. Numbers are median / p10 / p90 unless "mean".
        - Profiles (per night): perfect 100 % complete, no pauses, 7 calm hours, naps always; typical 85 / 7 / 5 / 3 % complete / unfinished / ruins / missed, pauses >=1 / >=2 / >=3 = 10 / 2 / 0 %, calm 7:50 % 6:30 % 5:15 % 4:5 %, naps 45 / 5 %, silver in months 3, 6, 9, 12 (every 3rd month), schedule unlock in month 6, rerolls 30 % / 15 %; weak 65 / 12 / 13 / 10 %, pauses 25 / 8 / 2 %, calm uniform 3..7, naps 15 / 5 %, silver in months 2, 4, 6, 8, 10, 12, unlock in months 3 and 9, rerolls 10 % / 5 %.
        - A \"silver wanted, not affordable\" is counted each time a silver would have been bought (willing month, failed night, streak running, own bronze used, no held box silver, no held box bronze) but the balance was below 1 000. A silver joker is bought only on a failed night with a running streak after the month's own bronze is used, in a willing month, with 1 000 coins (or a held box silver); it excuses up to 3 consecutive failed nights. Gold never, rename never. Pauses and rerolls are paid only if the balance allows.
        - A started night (complete, unfinished, ruins) draws its building before the outcome is known, so a reroll or a pause is paid even if a joker later excuses the night; an excused night leaves no building in the history. The reroll draws use `BuildingPicker.pick` with `excluding`.
        - Boxes: one a day, only the morning after a complete real night; month's box n: 1-3 -> 20 %, 4-6 -> 40 %, 7-9 -> 60 % of the balance; price = max(400, tier % x balance) rounded down to 10, needs balance >= price; no 10th box in a month (counted by purchase date). P3 / P6 / P9 buy at every allowed morning (if affordable) until they hold 3 / 6 / 9 boxes that month. Duplicates pay 0.25 x price, a lucky night adds the next complete night's coins once more (stacking: one per complete night), an extra joker lasts to the end of the next month, one of each kind held at a time. A held box bronze is used after the month's own bronze; a held box silver replaces a silver purchase.
        - Real coin return = (prizes + duplicates + lucky-night extras) / coins paid, pooled over all runs.

        """
        func variantLine(_ v: SimOddsVariant) -> String {
            "- \(v.name): " + v.table.map { c, w in
                let label: String
                switch c {
                case .coins(let t): label = "\(Double(t) / 10)x"
                case .luckyNight: label = "lucky night"
                case .collectible(let k): label = k.label
                case .bronze: label = "bronze"
                case .silver: label = "silver"
                }
                return "\(label) \(Double(w) / 10)%"
            }.joined(separator: ", ")
        }
        md += "\n## Odds variants (sum 100 %)\n" + variants.map(variantLine).joined(separator: "\n") + "\n"
        md += "\nNo extra variant was needed: A, B and C each keep typical P3 and P6 at a median balance of 1 000 to 15 000 with p90 <= 3x median at night 365 (see the typical tables). C-new = C, but a collectible draw picks an item not owned yet while the collection is incomplete (a duplicate only after it is complete); C-new-reserve = C-new, and a box is offered only if the balance after paying stays >= 1 000. D = C-new-reserve with accessories 7 %, night sky 5 %, bronze 3 % (more collectibles; 3x cap kept). \"Avg balance\" is each run's mean end-of-day balance over the last 100 nights up to the checkpoint (all 30 at night 30), then p10 / median / p90 across runs; \"lowest after night 30\" is the median of each run's minimum end-of-day balance after night 30. The night-365 snapshot is a 31 Oct end-of-month value, so it is shown beside the averages.\n"

        for p in SimProfile.all {
            md += "\n## Profile: \(p.name)\n\n### Today's economy (P0, no boxes)\n\n"
            md += "| nights | rerolls | balance p10 / median / p90 | earned per night | per 30 days | buildings | +30 | calm | 7th night | naps | achiev. | spent: pauses | silver | unlocks | rerolls | rerolls made | silver wanted, not affordable | avg balance, last 100 nights p10 / median / p90 | lowest after night 30 (median) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
            for n in simCheckpoints {
                for r in [false, true] {
                    let c = Combo(profile: p, policy: 0, variant: nil, rerolls: r)
                    md += "| \(n) | \(r ? "on" : "off") | \(f0(g(c, n, "balance_p10"))) / \(f0(g(c, n, "balance_median"))) / \(f0(g(c, n, "balance_p90"))) | \(f1(g(c, n, "earned_per_night"))) | \(f0(g(c, n, "earned_per_30_days"))) | \(f0(g(c, n, "mean_buildings"))) | \(f0(g(c, n, "mean_withoutPause"))) | \(f0(g(c, n, "mean_calmHours"))) | \(f0(g(c, n, "mean_streak7"))) | \(f0(g(c, n, "mean_naps"))) | \(f0(g(c, n, "mean_achievements"))) | \(f0(g(c, n, "mean_pauses"))) | \(f0(g(c, n, "mean_silverJokers"))) | \(f0(g(c, n, "mean_scheduleUnlocks"))) | \(f0(g(c, n, "mean_rerolls"))) | \(f1(g(c, n, "mean_rerollCount"))) | \(f1(g(c, n, "mean_silverWanted"))) | \(f0(g(c, n, "avg_balance_p10"))) / \(f0(g(c, n, "avg_balance_median"))) / \(f0(g(c, n, "avg_balance_p90"))) | \(f0(g(c, n, "lowest_after_30_median"))) |\n"
                }
            }
            md += "\n(sources and sinks are means per run, in coins)\n"
            md += "\n### With boxes (rerolls on)\n"
            for n in simCheckpoints {
                md += "\n**After night \(n)**\n\n| policy | variant | balance p10 / median / p90 | boxes / month | avg price | real return % | runs ever < 400 (%) | largest prize median / max | lucky nights won | box jokers won / used | silver bought | silver wanted, not affordable | avg balance, last 100 nights p10 / median / p90 | lowest after night 30 (median) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
                for k in [3, 6, 9] {
                    for v in variants {
                        let c = Combo(profile: p, policy: k, variant: v, rerolls: true)
                        md += "| P\(k) | \(v.name) | \(f0(g(c, n, "balance_p10"))) / \(f0(g(c, n, "balance_median"))) / \(f0(g(c, n, "balance_p90"))) | \(f1(g(c, n, "boxes_per_month"))) | \(f0(g(c, n, "avg_box_price"))) | \(f1(g(c, n, "real_return_pct"))) | \(f1(g(c, n, "pct_runs_below_400"))) | \(f0(g(c, n, "largest_prize_median"))) / \(f0(g(c, n, "largest_prize_max"))) | \(f1(g(c, n, "mean_luckyWon"))) | \(f1(g(c, n, "mean_boxJokersWon"))) / \(f1(g(c, n, "mean_boxJokersUsed"))) | \(f1(g(c, n, "mean_silverBought"))) | \(f1(g(c, n, "mean_silverWanted"))) | \(f0(g(c, n, "avg_balance_p10"))) / \(f0(g(c, n, "avg_balance_median"))) / \(f0(g(c, n, "avg_balance_p90"))) | \(f0(g(c, n, "lowest_after_30_median"))) |\n"
                    }
                }
            }
            md += "\n### Collections (median owned at 30 / 100 / 365; month number in which complete, 1 = Nov 2026)\n\n| policy | variant | postcards /30 | decorations /12 | accessories /6 | sky /4 | complete month: postcards | decorations | accessories | sky |\n|---|---|---|---|---|---|---|---|---|---|\n"
            for k in [3, 6, 9] {
                for v in variants {
                    let c = Combo(profile: p, policy: k, variant: v, rerolls: true)
                    func owned(_ col: SimCollection) -> String { simCheckpoints.map { f0(g(c, $0, "owned_median_\(col.label)")) }.joined(separator: " / ") }
                    func done(_ col: SimCollection) -> String {
                        let x = g(c, 365, "complete_month_median_\(col.label)"); return x < 0 ? "not in a year" : f0(x)
                    }
                    md += "| P\(k) | \(v.name) | \(owned(.postcard)) | \(owned(.decoration)) | \(owned(.accessory)) | \(owned(.nightSky)) | \(done(.postcard)) | \(done(.decoration)) | \(done(.accessory)) | \(done(.nightSky)) |\n"
                }
            }
        }

        // ---- observations (computed, at most 8 lines)
        let t0 = Combo(profile: .typical, policy: 0, variant: nil, rerolls: false)
        let t0r = Combo(profile: .typical, policy: 0, variant: nil, rerolls: true)
        let p0 = Combo(profile: .perfect, policy: 0, variant: nil, rerolls: false)
        let w0 = Combo(profile: .weak, policy: 0, variant: nil, rerolls: false)
        func tc(_ v: SimOddsVariant, _ k: Int, _ p: SimProfile = .typical) -> Combo { Combo(profile: p, policy: k, variant: v, rerolls: true) }
        func mo(_ c: Combo, _ col: SimCollection) -> String {
            let x = g(c, 365, "complete_month_median_\(col.label)"); return x < 0 ? "not in a year" : "month " + f0(x)
        }
        var obs: [String] = []
        obs.append("Without boxes and rerolls the median balance at night 365 is \(f0(g(p0, 365, "balance_median"))) (perfect), \(f0(g(t0, 365, "balance_median"))) (typical), \(f0(g(w0, 365, "balance_median"))) (weak).")
        obs.append("Rerolls cost a typical user a mean of \(f0(g(t0r, 365, "mean_rerolls"))) coins in a year (\(f1(g(t0r, 365, "mean_rerollCount"))) draws); median balance \(f0(g(t0r, 365, "balance_median"))) with rerolls vs \(f0(g(t0, 365, "balance_median"))) without.")
        obs.append("Typical P6 real return at night 365: A \(f1(g(tc(.A, 6), 365, "real_return_pct"))) %, B \(f1(g(tc(.B, 6), 365, "real_return_pct"))) %, C \(f1(g(tc(.C, 6), 365, "real_return_pct"))) %, C-new \(f1(g(tc(.CNew, 6), 365, "real_return_pct"))) %, C-new-reserve \(f1(g(tc(.CNewReserve, 6), 365, "real_return_pct"))) %.")
        obs.append("Typical P9 balance, last-100-nights average vs night-365 snapshot (medians): C \(f0(g(tc(.C, 9), 365, "avg_balance_median"))) vs \(f0(g(tc(.C, 9), 365, "balance_median"))); C-new-reserve \(f0(g(tc(.CNewReserve, 9), 365, "avg_balance_median"))) vs \(f0(g(tc(.CNewReserve, 9), 365, "balance_median"))); D \(f0(g(tc(.D, 9), 365, "avg_balance_median"))) vs \(f0(g(tc(.D, 9), 365, "balance_median"))).")
        obs.append("Typical P6 lowest balance after night 30 (median of run minimums): C \(f0(g(tc(.C, 6), 365, "lowest_after_30_median"))), C-new-reserve \(f0(g(tc(.CNewReserve, 6), 365, "lowest_after_30_median"))), D \(f0(g(tc(.D, 6), 365, "lowest_after_30_median"))); P0 typical rerolls on \(f0(g(t0r, 365, "lowest_after_30_median"))); runs ever below 400: C \(f1(g(tc(.C, 6), 365, "pct_runs_below_400"))) %, C-new-reserve \(f1(g(tc(.CNewReserve, 6), 365, "pct_runs_below_400"))) %.")
        obs.append("Typical P6 accessories / sky owned at 365: C-new-reserve \(f0(g(tc(.CNewReserve, 6), 365, "owned_median_accessories"))) / \(f0(g(tc(.CNewReserve, 6), 365, "owned_median_sky effects"))), D \(f0(g(tc(.D, 6), 365, "owned_median_accessories"))) / \(f0(g(tc(.D, 6), 365, "owned_median_sky effects"))); D real return \(f1(g(tc(.D, 6), 365, "real_return_pct"))) %.")
        obs.append("Silver wanted but not affordable per run in a year (mean): weak P0 \(f1(g(w0, 365, "mean_silverWanted"))), weak P6 C \(f1(g(tc(.C, 6, .weak), 365, "mean_silverWanted"))), weak P6 C-new-reserve \(f1(g(tc(.CNewReserve, 6, .weak), 365, "mean_silverWanted"))); typical P6 C \(f1(g(tc(.C, 6), 365, "mean_silverWanted"))), C-new-reserve \(f1(g(tc(.CNewReserve, 6), 365, "mean_silverWanted"))).")
        obs.append("Largest single coin prize seen anywhere: A-B (10x) \(f0([SimOddsVariant.A, .B].flatMap { v in SimProfile.all.flatMap { p in [3, 6, 9].map { g(tc(v, $0, p), 365, "largest_prize_max") } } }.max() ?? 0)), C-family (3x) \(f0([SimOddsVariant.C, .CNew, .CNewReserve].flatMap { v in SimProfile.all.flatMap { p in [3, 6, 9].map { g(tc(v, $0, p), 365, "largest_prize_max") } } }.max() ?? 0)).")
        md += "\n## Observations\n\n" + obs.prefix(8).map { "- " + $0 }.joined(separator: "\n") + "\n"
        let secs = Int(Date().timeIntervalSince(started))
        md += "\n(Run time of this report: \(secs) s for \(runs) runs per combination, \(cache.count) combinations.)\n"

        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try md.write(toFile: dir + "/report.md", atomically: true, encoding: .utf8)
        let json = try JSONSerialization.data(withJSONObject: ["runsPerCombination": runs, "checkpoints": simCheckpoints,
                                                               "combinations": cache], options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: dir + "/report.json"))
    }

    // MARK: Always-on tests

    @Test func boxPriceTiersFloorAndRounding() {
        // tiers by the month's box number
        #expect(SimBoxRules.price(balance: 10_000, boxNumber: 1) == 2000)
        #expect(SimBoxRules.price(balance: 10_000, boxNumber: 3) == 2000)
        #expect(SimBoxRules.price(balance: 10_000, boxNumber: 4) == 4000)
        #expect(SimBoxRules.price(balance: 10_000, boxNumber: 6) == 4000)
        #expect(SimBoxRules.price(balance: 10_000, boxNumber: 7) == 6000)
        #expect(SimBoxRules.price(balance: 10_000, boxNumber: 9) == 6000)
        #expect(SimBoxRules.price(balance: 10_000, boxNumber: 10) == nil)
        #expect(SimBoxRules.price(balance: 10_000, boxNumber: 0) == nil)
        // the 400 floor, and a balance below it buys nothing
        #expect(SimBoxRules.price(balance: 1000, boxNumber: 1) == 400)
        #expect(SimBoxRules.price(balance: 400, boxNumber: 1) == 400)
        #expect(SimBoxRules.price(balance: 399, boxNumber: 1) == nil)
        #expect(SimBoxRules.price(balance: 500, boxNumber: 7) == 400)         // 60 % = 300 -> floor 400
        #expect(SimBoxRules.price(balance: 400, boxNumber: 4) == 400)
        // rounding down to a multiple of 10
        #expect(SimBoxRules.price(balance: 2999, boxNumber: 1) == 590)        // 20 % = 599.8 -> 599 -> 590
        #expect(SimBoxRules.price(balance: 4567, boxNumber: 4) == 1820)       // 40 % = 1826.8 -> 1820
        #expect(SimBoxRules.price(balance: 4567, boxNumber: 7) == 2740)       // 60 % = 2740.2 -> 2740
    }

    @Test func oneBoxADayOnlyAfterACompleteNight() {
        #expect(SimBoxRules.offer(balance: 5000, boxesThisMonth: 0, boughtToday: false, afterCompleteNight: true) == 1000)
        #expect(SimBoxRules.offer(balance: 5000, boxesThisMonth: 0, boughtToday: true, afterCompleteNight: true) == nil)
        #expect(SimBoxRules.offer(balance: 5000, boxesThisMonth: 0, boughtToday: false, afterCompleteNight: false) == nil)
        #expect(SimBoxRules.offer(balance: 5000, boxesThisMonth: 9, boughtToday: false, afterCompleteNight: true) == nil)
    }

    @Test func monthlyCounterResetsOnTheFirst() {
        let cal = SimCalendar(days: 367)
        // the box on the morning of the night key 31 Oct is box 3 of October, the one on the morning of the key 1 Nov is
        // box 1 of November (the key is the wake date, and the box is counted by it)
        let oct31 = cal.keys.firstIndex(of: NightKey(year: 2027, month: 10, day: 31))!
        let nov1 = cal.keys.firstIndex(of: NightKey(year: 2027, month: 11, day: 1))!
        #expect(cal.month[oct31] == 11 && cal.month[nov1] == 12)
        var boxes: [Int: Int] = [11: 2]
        let n31 = boxes[cal.month[oct31], default: 0] + 1
        #expect(n31 == 3 && SimBoxRules.percent(boxNumber: n31) == 20)
        boxes[cal.month[oct31]] = n31
        let n1 = boxes[cal.month[nov1], default: 0] + 1
        #expect(n1 == 1 && SimBoxRules.percent(boxNumber: n1) == 20)
    }

    @Test func simulatedMonthsNeverExceedNineBoxesOrBuyBelowTheFloor() throws {
        let catalog = try loadRealCatalog(), cal = SimCalendar()
        let cfg = SimConfig(profile: .perfect, boxesPerMonth: 9, variant: .B, rerolls: true)
        for r in 0..<5 {
            let s = simulate(cfg, run: r, catalog: catalog, calendar: cal).snaps.last!
            #expect(s.boxes <= 9 * 13 && s.boxes > 0)
            #expect(s.boxPaid >= s.boxes * SimBoxRules.floor)
            #expect(s.balance >= 0)
        }
    }

    @Test func oddsVariantsSumToOneHundredPercent() {
        for v in [SimOddsVariant.A, .B, .C, .CNew, .CNewReserve, .D] { #expect(v.sum == 1000, "variant \(v.name)") }
        for p in SimProfile.all {
            #expect(abs(p.calm.reduce(0) { $0 + $1.1 } - 1) < 1e-9)
            #expect(p.complete + p.unfinished + p.ruins <= 1)
        }
    }

    @Test func fastPickerReturnsTheSameBuildingsAsTheRealOne() throws {
        let catalog = try loadRealCatalog()
        for seed in 1...10 {
            var a = SeededGenerator(seed: UInt64(seed)), b = a
            var fast = SimFastPicker(catalog: catalog)
            var history: [String] = []
            var mix = SeededGenerator(seed: UInt64(seed) &* 77)
            for n in 0..<400 {
                let maxLevel = Progression.unlockedMaxLevel(builtBefore: n)
                var excluding = Set<String>()
                for _ in 0..<Int.random(in: 0...2, using: &mix) {
                    let x = BuildingPicker.pick(maxLevel: maxLevel, catalog: catalog, history: history, excluding: excluding, rng: &a)
                    let y = fast.pick(maxLevel: maxLevel, excluding: excluding, rng: &b)
                    #expect(x.id == y.id)
                    excluding.insert(x.id)
                }
                let x = BuildingPicker.pick(maxLevel: maxLevel, catalog: catalog, history: history, excluding: excluding, rng: &a)
                let y = fast.pick(maxLevel: maxLevel, excluding: excluding, rng: &b)
                #expect(x.id == y.id)
                history.append(x.id); fast.append(y.id)
            }
        }
    }

    @Test func sameSeedsGiveTheSameNumbers() throws {
        let catalog = try loadRealCatalog(), cal = SimCalendar()
        let cfg = SimConfig(profile: .typical, boxesPerMonth: 6, variant: .B, rerolls: true)
        let a = simulateBatch(cfg, runs: 12, catalog: catalog, calendar: cal)
        let b = simulateBatch(cfg, runs: 12, catalog: catalog, calendar: cal)
        #expect(a.map(\.snaps) == b.map(\.snaps))
        #expect(aggregate(a, checkpoint: 2) == aggregate(b, checkpoint: 2))
    }

    /// The incremental loop must equal `Economy.ledger` + `Jokers.apply` + `Achievements` + naps, night by night.
    @Test func incrementalLoopMatchesTheLedger() throws {
        let catalog = try loadRealCatalog(), cal = SimCalendar()
        var excusedNights = 0, silverBought = 0, bronzeStyleBreaks = 0
        for profile in SimProfile.all {
            for r in 0..<20 {
                let cfg = SimConfig(profile: profile, boxesPerMonth: 0, variant: nil, rerolls: false)
                let sim = simulate(cfg, run: r, catalog: catalog, calendar: cal, trace: true)
                let t = sim.trace!
                excusedNights += t.final.filter { $0 == .excused }.count
                silverBought += t.silverStarts.count
                bronzeStyleBreaks += zip(t.raw, t.final).filter { $0.0 == .ruins && $0.1 == .ruins }.count
                let keys = Array(cal.keys.prefix(365))
                let results = (0..<365).map { i in
                    NightResult(key: keys[i], outcome: t.raw[i], buildingId: t.building[i], pauses: t.raw[i] == .missed ? nil : t.pauses[i],
                                calmHours: t.raw[i].isBuildNight ? t.calm[i] : nil, calmHoursTotal: t.raw[i].isBuildNight ? 7 : nil)
                }
                let manual = t.silverStarts.map { JokerUse(tier: .silver, firstNight: keys[$0]) }
                let (applied, _) = Jokers.apply(results: results, manual: manual, lastNight: keys[364], calendar: bratislava)
                let ledger = Economy.ledger(applied, calendar: bratislava, catalog: catalog)
                let naps = (0..<365).compactMap { i in t.napOutcome[i] == .complete ? NightResult(key: keys[i], outcome: .complete, buildingId: nil) : nil }
                let unlocked = Achievements.unlocked(results: applied, naps: naps, catalog: catalog, calendar: bratislava)
                var achByKey: [NightKey: Int] = [:]
                for u in unlocked { achByKey[u.key, default: 0] += u.achievement.reward }

                var ok = ledger.count == 365
                for i in 0..<365 where ok {
                    let e = ledger[i]
                    if e.key != keys[i] || e.outcome != t.final[i] || e.coins != t.nightCoins[i] || achByKey[keys[i], default: 0] != t.achievementCoins[i] {
                        ok = false
                        Issue.record("\(profile.name) run \(r) night \(i): ledger \(e.outcome) \(e.coins)+\(achByKey[keys[i], default: 0]) vs sim \(t.final[i]) \(t.nightCoins[i])+\(t.achievementCoins[i])")
                    }
                }
                #expect(ok)
                // totals: ledger + achievements + naps == what the simulation earned
                let s = sim.snaps.last!
                let napCoins = t.napOutcome.compactMap { $0 }.reduce(0) { $0 + NapPlan.reward($1) }
                #expect(napCoins == s.nap)
                #expect(ledger.reduce(0) { $0 + $1.coins } == s.building + s.undisturbed + s.calm + s.streak)
                #expect(Achievements.coins(unlocked) == s.achievement)
                #expect(ledger.reduce(0) { $0 + $1.streakBonus } == s.streak)
                #expect(ledger.reduce(0) { $0 + $1.undisturbedBonus } == s.undisturbed)
                #expect(ledger.reduce(0) { $0 + $1.calmBonus } == s.calm)
            }
        }
        // the comparison is not vacuous: jokers, silver and real ruins all occurred
        #expect(excusedNights > 0 && silverBought > 0 && bronzeStyleBreaks > 0)
    }
}
