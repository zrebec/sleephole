import Foundation
import Testing
@testable import SleepCore

@Suite struct SyncMergeTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func copy(_ outcome: Outcome?, started: TimeInterval? = nil, finalized: TimeInterval? = nil, events: Int = 0,
              _ fingerprint: String = "a") -> SyncMerge.NightCopy {
        SyncMerge.NightCopy(outcome: outcome, startedAt: started.map { t0 + $0 }, finalizedAt: finalized.map { t0 + $0 },
                            eventCount: events, fingerprint: fingerprint)
    }

    // MARK: rank

    @Test func rankOrdersTheOutcomes() {
        #expect(SyncMerge.rank(.complete) == 4 && SyncMerge.rank(.unfinished) == 3 && SyncMerge.rank(.ruins) == 2)
        #expect(SyncMerge.rank(.missed) == 1 && SyncMerge.rank(.excused) == 1 && SyncMerge.rank(nil) == 0)
    }

    @Test func theBetterOutcomeIsKeptForEveryPairOfRanks() {
        let all: [Outcome?] = [.complete, .unfinished, .ruins, .missed, .excused, nil]
        for a in all {
            for b in all where SyncMerge.rank(a) != SyncMerge.rank(b) {
                let better = SyncMerge.rank(a) > SyncMerge.rank(b)
                #expect(SyncMerge.keepsFirst(copy(a), copy(b)) == better)
                #expect(SyncMerge.keepsFirst(copy(b), copy(a)) == !better)
            }
        }
        // the rank wins over everything else: a complete copy that started LATER still beats an earlier ruin
        #expect(SyncMerge.keepsFirst(copy(.complete, started: 500, finalized: 900, "z"),
                                     copy(.ruins, started: 1, finalized: 2, "a")))
    }

    // MARK: the tie-breaks

    @Test func sameRankTheEarlierStartWins() {
        #expect(SyncMerge.keepsFirst(copy(.complete, started: 10), copy(.complete, started: 20)))
        #expect(!SyncMerge.keepsFirst(copy(.complete, started: 20), copy(.complete, started: 10)))
        // a copy with a start beats one without
        #expect(SyncMerge.keepsFirst(copy(.ruins, started: 99), copy(.ruins, started: nil)))
        #expect(!SyncMerge.keepsFirst(copy(.ruins, started: nil), copy(.ruins, started: 99)))
        // the start decides before the finalization does
        #expect(SyncMerge.keepsFirst(copy(.complete, started: 10, finalized: 900), copy(.complete, started: 20, finalized: 100)))
    }

    @Test func sameStartTheEarlierFinalizationWins() {
        #expect(SyncMerge.keepsFirst(copy(.complete, started: 10, finalized: 30), copy(.complete, started: 10, finalized: 40)))
        #expect(!SyncMerge.keepsFirst(copy(.complete, started: 10, finalized: 40), copy(.complete, started: 10, finalized: 30)))
        #expect(SyncMerge.keepsFirst(copy(.complete, finalized: 30), copy(.complete, finalized: nil)))
        #expect(!SyncMerge.keepsFirst(copy(.complete, finalized: nil), copy(.complete, finalized: 30)))
    }

    @Test func sameDatesTheSmallerFingerprintWins() {
        #expect(SyncMerge.keepsFirst(copy(.complete, started: 10, finalized: 30, "b1"),
                                     copy(.complete, started: 10, finalized: 30, "b2")))
        #expect(!SyncMerge.keepsFirst(copy(.complete, started: 10, finalized: 30, "b2"),
                                      copy(.complete, started: 10, finalized: 30, "b1")))
    }

    @Test func missedAndExcusedShareARankSoTheNameDecidesLast() {
        let missed = copy(.missed), excused = copy(.excused)
        #expect(SyncMerge.keepsFirst(excused, missed) != SyncMerge.keepsFirst(missed, excused))
    }

    @Test func equalCopiesKeepTheFirst() {
        let c = copy(.unfinished, started: 5, finalized: 6, "x")
        #expect(SyncMerge.keepsFirst(c, c) && SyncMerge.keepsFirst(c, copy(.unfinished, started: 5, finalized: 6, "x")))
    }

    // MARK: the same run – the copy with more events wins (A2)

    @Test func ofTwoCopiesOfTheSameRunTheOneWithMoreEventsWinsEvenWithALowerOutcome() {
        // the developer tool `-revokeForgiveness` appends an event and turns `complete` into `ruins`
        let old = copy(.complete, started: 10, finalized: 30, events: 5), corrected = copy(.ruins, started: 10, finalized: 30, events: 6)
        #expect(SyncMerge.keepsFirst(corrected, old) && !SyncMerge.keepsFirst(old, corrected))
        // … and it does not matter in which order a device looks at the pair
        let best = [old, corrected].reduce(old) { SyncMerge.keepsFirst($0, $1) ? $0 : $1 }
        let bestReversed = [corrected, old].reduce(corrected) { SyncMerge.keepsFirst($0, $1) ? $0 : $1 }
        #expect(best == corrected && bestReversed == corrected)
        // more events also beats the earlier finalization, the smaller fingerprint and a better rank of any kind
        #expect(SyncMerge.keepsFirst(copy(.missed, started: 10, finalized: 900, events: 3, "z"),
                                     copy(.complete, started: 10, finalized: 1, events: 2, "a")))
    }

    @Test func twoDifferentRunsOfANightStillKeepTheBetterOutcomeWhateverTheirEvents() {
        let better = copy(.complete, started: 10, events: 4), worse = copy(.ruins, started: 20, events: 9)
        #expect(SyncMerge.keepsFirst(better, worse) && !SyncMerge.keepsFirst(worse, better))
        // with the same rank the earlier start wins, not the longer log
        let early = copy(.complete, started: 10, events: 2), late = copy(.complete, started: 20, events: 8)
        #expect(SyncMerge.keepsFirst(early, late) && !SyncMerge.keepsFirst(late, early))
        // a copy without a start is never "the same run" as another one without a start
        #expect(SyncMerge.keepsFirst(copy(.complete, events: 1), copy(.ruins, events: 7)))
        #expect(!SyncMerge.keepsFirst(copy(.ruins, events: 7), copy(.complete, events: 1)))
        // the same run and the same number of events: the old criteria
        #expect(SyncMerge.keepsFirst(copy(.complete, started: 10, events: 3), copy(.ruins, started: 10, events: 3)))
        #expect(SyncMerge.keepsFirst(copy(.complete, started: 10, finalized: 5, events: 3), copy(.complete, started: 10, finalized: 6, events: 3)))
    }

    // MARK: a strict total order

    /// Every outcome value (and "not finalized") × three starts × three finalizations × two fingerprints; the number of
    /// events is the same everywhere, so the criteria before A2 are what is being ordered.
    var universe: [SyncMerge.NightCopy] { build(starts: [nil, 10, 20], events: { _ in [0] }) }

    /// ONE run (the same start) in every outcome with 1, 2 or 3 events: a later correction may lower the outcome.
    var oneRun: [SyncMerge.NightCopy] { build(starts: [10], events: { _ in [1, 2, 3] }) }

    /// Several runs where a log that is longer is never a worse outcome (events = rank + 1): the new criterion and the
    /// old ones agree, so the whole set is ordered.
    var growingRuns: [SyncMerge.NightCopy] {
        build(starts: [nil, 10, 20], events: { [rank = SyncMerge.rank] in [rank($0) + 1] })
    }

    /// All the combinations of the given starts, outcomes (and nil), three finalizations and two fingerprints; `events`
    /// gives the numbers of events to try for an outcome.
    func build(starts: [TimeInterval?], events: (Outcome?) -> [Int]) -> [SyncMerge.NightCopy] {
        let outcomes: [Outcome?] = Outcome.allCases.map { Optional($0) } + [nil]
        let finals: [TimeInterval?] = [nil, 100, 200]
        var all: [SyncMerge.NightCopy] = []
        for o in outcomes {
            for s in starts {
                for f in finals {
                    for e in events(o) {
                        for fp in ["a", "b"] { all.append(copy(o, started: s, finalized: f, events: e, fp)) }
                    }
                }
            }
        }
        return all
    }

    /// Antisymmetric and total, with every number of events mixed freely (this holds for ANY set of copies).
    @Test func keepsFirstIsAntisymmetricAndTotal() {
        let everything = build(starts: [nil, 10, 20], events: { _ in [0, 1, 2] })
        #expect(everything.count == 6 * 3 * 3 * 3 * 2)
        for all in [universe, oneRun, growingRuns, everything] {
            for a in all {
                #expect(SyncMerge.keepsFirst(a, a))
                for b in all where a != b {
                    #expect(SyncMerge.keepsFirst(a, b) != SyncMerge.keepsFirst(b, a))     // exactly one of the two
                }
            }
        }
    }

    @Test func keepsFirstIsTransitive() {
        #expect(universe.count == 6 * 3 * 3 * 2 && oneRun.count == 6 * 3 * 3 * 2 && growingRuns.count == 6 * 3 * 3 * 2)
        for all in [universe, oneRun, growingRuns] {
            for a in all {
                for b in all where a != b && SyncMerge.keepsFirst(a, b) {
                    for c in all where c != b && c != a && SyncMerge.keepsFirst(b, c) {
                        #expect(SyncMerge.keepsFirst(a, c))
                    }
                }
            }
        }
    }

    @Test func theOneKnownCycleNeedsTwoRunsAndACorrectionThatLowersTheOutcome() {
        // pinned so that nobody mistakes it for a general order: a = the old state of a run, b = the same run corrected
        // to a lower outcome, c = another run that ranks between them
        let a = copy(.complete, started: 10, events: 5), b = copy(.ruins, started: 10, events: 6), c = copy(.unfinished, started: 20, events: 1)
        #expect(SyncMerge.keepsFirst(b, a) && SyncMerge.keepsFirst(a, c) && SyncMerge.keepsFirst(c, b))
        // still antisymmetric for each pair, so two devices that look at the same pair agree
        #expect(!SyncMerge.keepsFirst(a, b) && !SyncMerge.keepsFirst(c, a) && !SyncMerge.keepsFirst(b, c))
    }

    @Test func mergingInAnyOrderLeavesTheSameCopy() {
        // the best of a set does not depend on the order it is looked at
        func best(_ list: [SyncMerge.NightCopy]) -> SyncMerge.NightCopy {
            list.dropFirst().reduce(list[0]) { SyncMerge.keepsFirst($0, $1) ? $0 : $1 }
        }
        var rng = SeededGenerator(seed: 7)
        for all in [universe, oneRun, growingRuns] {
            #expect(best(all) == best(all.reversed()))
            #expect(best(all) == best(all.shuffled(using: &rng)))
        }
    }

    // MARK: the stamp of a device at first contact (A1)

    @Test func theFirstContactStampIsTheReferenceDatePlusOneSecondPerNight() {
        #expect(SyncMerge.firstContactStamp(established: 0) == Date(timeIntervalSinceReferenceDate: 0))
        #expect(SyncMerge.firstContactStamp(established: 46) == Date(timeIntervalSinceReferenceDate: 46))
        #expect(SyncMerge.firstContactStamp(established: -3) == Date(timeIntervalSinceReferenceDate: 0))   // never below the base
    }

    @Test func theMoreEstablishedDeviceWinsAndAnyRealChangeBeatsEveryFirstContactStamp() {
        let fresh = SyncMerge.firstContactStamp(established: 0), established = SyncMerge.firstContactStamp(established: 46)
        // last-writer-wins, from either side
        #expect(SyncMerge.newer(("fresh", fresh), ("established", established)).value == "established")
        #expect(SyncMerge.newer(("established", established), ("fresh", fresh)).value == "established")
        // a real change (a stamp of "now") beats even a very established device
        let change = t0, huge = SyncMerge.firstContactStamp(established: 1_000_000)
        #expect(change > huge)
        #expect(SyncMerge.newer(("established", huge), ("real", change)).value == "real")
        #expect(SyncMerge.newer(("real", change), ("established", huge)).value == "real")
    }

    // MARK: dates and last-writer-wins

    @Test func earliestAndLatestPreferADateToNil() {
        let a = t0, b = t0 + 5
        #expect(SyncMerge.earliest(a, b) == a && SyncMerge.earliest(b, a) == a)
        #expect(SyncMerge.latest(a, b) == b && SyncMerge.latest(b, a) == b)
        #expect(SyncMerge.earliest(a, nil) == a && SyncMerge.earliest(nil, b) == b)
        #expect(SyncMerge.latest(a, nil) == a && SyncMerge.latest(nil, b) == b)
        #expect(SyncMerge.earliest(nil, nil) == nil && SyncMerge.latest(nil, nil) == nil)
        #expect(SyncMerge.earliest(a, a) == a && SyncMerge.latest(b, b) == b)
    }

    @Test func newerIsLastWriterWins() {
        let early = t0, late = t0 + 60
        // both stamped: the later stamp
        #expect(SyncMerge.newer(("L", late), ("R", early)).value == "L")
        #expect(SyncMerge.newer(("L", early), ("R", late)).value == "R")
        #expect(SyncMerge.newer(("L", early), ("R", late)).at == late)
        // a stamp beats no stamp, on either side
        #expect(SyncMerge.newer(("L", nil), ("R", early)).value == "R")
        #expect(SyncMerge.newer(("L", early), ("R", nil)).value == "L")
        // equal stamps and two missing stamps keep the local value
        #expect(SyncMerge.newer(("L", early), ("R", early)).value == "L")
        #expect(SyncMerge.newer(("L", nil), ("R", nil)).value == "L")
    }

    @Test func sameMomentIsLessThanOneSecond() {
        #expect(SyncMerge.sameMoment(t0, t0))
        #expect(SyncMerge.sameMoment(t0, t0 + 0.4) && SyncMerge.sameMoment(t0 + 0.4, t0))
        #expect(SyncMerge.sameMoment(t0, t0 + 0.999) && SyncMerge.sameMoment(t0 + 0.999, t0))
        #expect(!SyncMerge.sameMoment(t0, t0 + 1.0) && !SyncMerge.sameMoment(t0 + 1.0, t0))
        #expect(!SyncMerge.sameMoment(t0, t0 + 5) && !SyncMerge.sameMoment(t0 + 5, t0))
    }
}
