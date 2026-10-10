import Foundation
import Testing
@testable import SleepCore

/// The rule that turns sleep samples (Apple Health or anything else) into one summary of a night (phase HEALTH, H1).
/// Invented times: the window is 22:00 → 07:00.
@Suite struct SleepSummaryTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)         // 22:00 of the invented night
    func t(_ min: Double) -> Date { base + min * 60 }
    let from = Date(timeIntervalSince1970: 1_800_000_000)
    var to: Date { from + 9 * 3600 }

    func s(_ a: Double, _ b: Double, _ stage: SleepStage = .core, _ src: String = "Watch",
           first: Bool = false) -> SleepSample {
        SleepSample(start: t(a), end: t(b), stage: stage, source: src, isFirstParty: first)
    }
    func summary(_ samples: [SleepSample]) -> SleepSummary? { SleepAnalysis.summary(samples: samples, from: from, to: to) }

    @Test func aStagedNight() throws {
        let r = try #require(summary([s(0, 20, .inBed), s(30, 120, .core), s(120, 180, .deep), s(180, 240, .rem),
                                      s(240, 420, .core)]))
        #expect(r.fellAsleepAt == t(30) && r.wokeAt == t(420))
        #expect(r.asleepSeconds == 390 * 60 && r.awakeSeconds == 0)
        #expect(r.source == "Watch" && r.hasStages)
    }

    // Changed for rule version 2: the staged Watch (140 min) is under ⅔ of the Phone's 270 min, so the Phone still wins.
    @Test func theSourceWithMoreSleepWinsWhenStagesAreFarBehind() throws {
        let r = try #require(summary([s(30, 300, .asleep, "Phone"), s(60, 200, .core, "Watch")]))
        #expect(r.source == "Phone" && !r.hasStages && r.asleepSeconds == 270 * 60)
    }

    @Test func aStagedSourceWithTwoThirdsOfTheLargestWins() throws {
        let r = try #require(summary([s(0, 420, .asleep, "Phone"), s(0, 360, .core, "Watch")]))   // 6 h vs 7 h
        #expect(r.source == "Watch" && r.hasStages && r.asleepSeconds == 360 * 60)
    }

    @Test func aStagedSourceUnderTwoThirdsLoses() throws {
        let r = try #require(summary([s(0, 420, .asleep, "Phone"), s(0, 180, .core, "Watch")]))   // 3 h vs 7 h
        #expect(r.source == "Phone" && !r.hasStages)
    }

    @Test func ofTwoStagedSourcesTheBiggerWins() throws {
        let r = try #require(summary([s(0, 300, .core, "Ring"), s(0, 360, .deep, "Watch"), s(0, 420, .asleep, "Phone")]))
        #expect(r.source == "Watch")
    }

    @Test func withOnlyUnstagedSourcesTheBiggestWins() throws {
        let r = try #require(summary([s(0, 300, .asleep, "A"), s(0, 420, .asleep, "B")]))
        #expect(r.source == "B")
    }

    @Test func aStagedSourceUnderMinAsleepNeverWins() throws {
        let r = try #require(summary([s(0, 20, .core, "Watch"), s(0, 25, .asleep, "Phone"), s(0, 40, .asleep, "Other")]))
        #expect(r.source == "Other")
        #expect(summary([s(0, 20, .core, "Watch"), s(0, 25, .asleep, "Phone")]) == nil)
    }

    @Test func sourcesListsEverySourceSortedWithItsOwnNumbers() {
        let list = SleepAnalysis.sources(samples: [s(30, 150, .core, "Watch"), s(150, 160, .awake, "Watch"),
                                                   s(160, 200, .core, "Watch"), s(10, 20, .asleep, "Phone"),
                                                   s(0, 100, .asleep, "Another")], from: from, to: to)
        #expect(list.map(\.name) == ["Another", "Phone", "Watch"])
        #expect(list[0] == SleepAnalysis.SourceSummary(name: "Another", asleepSeconds: 6000, fellAsleepAt: t(0),
                                                       wokeAt: t(100), awakeSeconds: 0, hasStages: false))
        #expect(list[1].asleepSeconds == 600 && list[1].asleepSeconds < SleepAnalysis.minAsleep)   // listed, never chosen
        #expect(list[2].asleepSeconds == 160 * 60 && list[2].awakeSeconds == 10 * 60 && list[2].hasStages)
        #expect(list[2].fellAsleepAt == t(30) && list[2].wokeAt == t(200))
        #expect(SleepAnalysis.sources(samples: [], from: from, to: to).isEmpty)
    }

    // Changed for rule version 3 (was theRuleVersionIsTwo).
    @Test func theRuleVersionIsThree() {
        #expect(SleepAnalysis.ruleVersion == 3)
    }

    @Test func aFirstPartySourceWithTwoThirdsBeatsAThirdPartyWithStages() throws {
        let r = try #require(summary([s(0, 300, .core, "System", first: true), s(0, 420, .core, "App")]))   // 5 h vs 7 h
        #expect(r.source == "System")
    }

    @Test func aFirstPartySourceUnderTwoThirdsLoses() throws {
        let r = try #require(summary([s(0, 180, .core, "System", first: true), s(0, 420, .core, "App")]))   // 3 h vs 7 h
        #expect(r.source == "App")
    }

    @Test func aFirstPartySourceWithoutStagesBeatsAThirdPartyWithStages() throws {
        let r = try #require(summary([s(0, 360, .asleep, "System", first: true), s(0, 400, .core, "App")]))
        #expect(r.source == "System" && !r.hasStages)
    }

    @Test func ofSeveralFirstPartySourcesTheBiggerWinsThenTheSmallerName() throws {
        let big = try #require(summary([s(0, 360, .core, "B", first: true), s(0, 400, .core, "A", first: true)]))
        #expect(big.source == "A")
        let tie = try #require(summary([s(0, 300, .core, "B", first: true), s(0, 300, .core, "A", first: true)]))
        #expect(tie.source == "A")
    }

    @Test func aFirstPartySourceUnderMinAsleepNeverWins() throws {
        let r = try #require(summary([s(0, 20, .core, "System", first: true), s(0, 120, .core, "App")]))
        #expect(r.source == "App")
    }

    @Test func withNoFirstPartySourceTheVersionTwoRuleHolds() throws {
        let staged = try #require(summary([s(0, 420, .asleep, "Phone"), s(0, 300, .core, "Watch")]))
        #expect(staged.source == "Watch")
        let largest = try #require(summary([s(0, 420, .asleep, "Phone"), s(0, 180, .core, "Watch")]))
        #expect(largest.source == "Phone")
    }

    @Test func theFirstPartyFlagIsCarriedIntoTheSourceList() {
        let list = SleepAnalysis.sources(samples: [s(0, 100, .core, "System", first: true), s(0, 100, .core, "App")],
                                         from: from, to: to)
        #expect(list.map(\.isFirstParty) == [false, true])
    }

    @Test func aSourceSummaryWithoutTheFirstPartyKeyDecodesAsFalse() throws {
        let json = """
        {"name":"Old","asleepSeconds":3600,"fellAsleepAt":0,"wokeAt":3600,"awakeSeconds":0,"hasStages":true}
        """
        let back = try JSONDecoder().decode(SleepAnalysis.SourceSummary.self, from: Data(json.utf8))
        #expect(back.name == "Old" && back.hasStages && !back.isFirstParty)
        let withKey = SleepAnalysis.SourceSummary(name: "N", asleepSeconds: 1, fellAsleepAt: t(0), wokeAt: t(1),
                                                  awakeSeconds: 0, hasStages: false, isFirstParty: true)
        let round = try JSONDecoder().decode(SleepAnalysis.SourceSummary.self, from: JSONEncoder().encode(withKey))
        #expect(round == withKey)
    }

    // Changed for rule version 3: with the 300 s onset run the 6-minute doze would have been "fell asleep".
    @Test func aSixMinuteDozeBeforeTheRealSleepIsNotFallingAsleep() throws {
        let r = try #require(summary([s(20, 26), s(110, 300)]))
        #expect(r.fellAsleepAt == t(110))
    }

    @Test func exactlyTenMinutesCountsAsFallingAsleep() throws {
        let r = try #require(summary([s(20, 30), s(110, 300)]))
        #expect(r.fellAsleepAt == t(20))
    }

    @Test func aTieIsDecidedByStagesThenByName() throws {
        let staged = try #require(summary([s(30, 150, .asleep, "A"), s(30, 150, .core, "Z")]))
        #expect(staged.source == "Z" && staged.hasStages)
        let named = try #require(summary([s(30, 150, .core, "B"), s(30, 150, .core, "A")]))
        #expect(named.source == "A")
    }

    @Test func aOneMinuteBlipIsNotFallingAsleep() throws {
        let r = try #require(summary([s(10, 11), s(30, 200)]))
        #expect(r.fellAsleepAt == t(30))
        // the blip is outside the span: its minute is not "awake time" and the sleep still counts it
        #expect(r.awakeSeconds == 0 && r.asleepSeconds == 171 * 60)
    }

    @Test func withNoLongRunTheFirstRunCounts() throws {
        // ten 4-minute runs far apart (40 min in total): none reaches the 10-minute onset run
        let samples = (0..<10).map { i in s(Double(i) * 30, Double(i) * 30 + 4) }
        let r = try #require(summary(samples))
        #expect(r.fellAsleepAt == t(0) && r.wokeAt == t(274))
    }

    @Test func anAwakeStretchInTheMiddleIsCounted() throws {
        let r = try #require(summary([s(30, 150), s(150, 165, .awake), s(165, 300)]))
        #expect(r.awakeSeconds == 15 * 60 && r.asleepSeconds == 255 * 60)
        #expect(r.fellAsleepAt == t(30) && r.wokeAt == t(300))
    }

    @Test func samplesAreClippedToTheWindow() throws {
        let r = try #require(summary([s(-60, 60), s(480, 700)]))
        #expect(r.fellAsleepAt == from && r.wokeAt == to)
        #expect(r.asleepSeconds == 60 * 60 + 60 * 60)
    }

    @Test func gapsOfSixtySecondsBridgeAndFiveMinutesDoNot() throws {
        let joined = try #require(summary([s(30, 100), SleepSample(start: t(101), end: t(200), stage: .core, source: "Watch")]))
        #expect(joined.awakeSeconds == 60)                       // one run, the minute between is awake
        // two runs: the first is only a 3-minute blip, so falling asleep is the second run
        let split = try #require(summary([s(10, 13), s(18, 200)]))
        #expect(split.fellAsleepAt == t(18))
        // two long runs 5 minutes apart: still the first one, the gap is awake time
        let two = try #require(summary([s(10, 100), s(105, 200)]))
        #expect(two.fellAsleepAt == t(10) && two.awakeSeconds == 5 * 60)
    }

    @Test func onlyInBedOrAwakeIsNothing() {
        #expect(summary([s(0, 400, .inBed), s(100, 200, .awake)]) == nil)
        #expect(summary([]) == nil)
    }

    @Test func lessThanThirtyMinutesOfSleepIsNothing() {
        #expect(summary([s(30, 50)]) == nil)
        #expect(summary([s(30, 60)]) != nil)
    }

    @Test func overlapsInsideOneSourceAreMerged() throws {
        let r = try #require(summary([s(30, 100, .core), s(60, 130, .asleep)]))
        #expect(r.asleepSeconds == 100 * 60)
    }

    @Test func theOrderOfTheSamplesDoesNotMatter() {
        let samples = [s(30, 90, .core), s(90, 100, .awake), s(100, 200, .deep), s(30, 150, .asleep, "Phone"),
                       s(10, 11), s(220, 300, .rem)]
        let expected = summary(samples)
        #expect(expected != nil)
        for seed in 0..<10 {
            var rng = SeededGenerator(seed: UInt64(seed))
            #expect(summary(samples.shuffled(using: &rng)) == expected)
        }
    }

    @Test func theWindowEndsWithTheConfirmationOrThreeHoursAfterWake() {
        let wake = t(8 * 60)
        let confirmed = SleepAnalysis.window(nightStart: from, wake: wake, confirmedAt: t(450))
        #expect(confirmed.from == from && confirmed.to == t(450))
        let open = SleepAnalysis.window(nightStart: from, wake: wake, confirmedAt: nil)
        #expect(open.to == wake + 3 * 3600)
    }
}
