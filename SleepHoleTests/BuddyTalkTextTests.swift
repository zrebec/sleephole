import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// The sleep buddy's texts (phase TALK): every sentence resolves in both languages, the plural forms are right and
/// the Debug list of keys agrees with the mapping.
@MainActor
struct BuddyTalkTextTests {
    private let at = Date(timeIntervalSinceReferenceDate: 0)
    private func name(_ id: String) -> String { id == "x" ? "The Cottage" : "Dom" }

    private var everyLine: [BuddyLine] {
        var l: [BuddyLine] = [
            .movedIn(buildingId: "x", people: 4), .newSight(buildingId: "x"), .waiting(buildingId: "x"), .ruined(buildingId: "x", repairsTonight: true),
            .ruined(buildingId: "x", repairsTonight: false),
            .streakSafe, .bedtimeSoon(at), .week, .streak(3), .newStreak, .size(.village, people: 150),
            .nextSize(missing: 5, .village), .firstNeighbours, .parks(2), .library, .museum, .tallest,
            .noFireStation, .noHospital, .noPolice, .noSchool, .noTownHall, .fireStation, .hospital, .tonight,
            .fullMoonTonight, .newMoonTonight, .longestNight, .shortestNight, .equinox, .fullMoonTomorrow,
            .fullMoonSoon(days: 2)]
        l += MoonQuarter.allCases.map { .moonPhase($0) }
        l += (0..<BuddyLine.chatterCount).map { .chatter($0) }
        return l
    }

    private func texts(_ lang: AppLanguage) -> [String] {
        let saved = Lang.current
        defer { Lang.current = saved }
        Lang.current = lang
        return everyLine.map { BuddyTalkText.text(for: $0, buildingName: name) }
    }

    @Test func everySentenceResolvesInBothLanguages() {
        for lang in AppLanguage.allCases {
            let t = texts(lang)
            #expect(t.allSatisfy { !$0.isEmpty && !$0.contains("%") && !$0.contains("#@") }, "\(lang): \(t)")
            #expect(Set(t).count == t.count)
        }
        // English and Slovak really differ
        #expect(zip(texts(.en), texts(.sk)).allSatisfy { $0 != $1 })
    }

    @Test func theSlovakSentenceForTheLargeCityNamesTheLargeCity() {
        let saved = Lang.current
        defer { Lang.current = saved }
        Lang.current = .sk
        let t = BuddyTalkText.text(for: .size(.city, people: 20_000), buildingName: name)
        #expect(t.contains("veľké mesto"), "\(t)")
        #expect(BuddyTalkText.sizeName(.city) == "veľké mesto")
        Lang.current = .en
        #expect(BuddyTalkText.sizeName(.city) == "city")
    }

    @Test func keysMatchTheMapping() {
        #expect(BuddyTalkText.keys.count == everyLine.count)
        #expect(Set(BuddyTalkText.keys).count == BuddyTalkText.keys.count)
    }

    @Test func pluralsWithAName() {
        let saved = Lang.current
        defer { Lang.current = saved }
        Lang.current = .en
        #expect(BuddyTalkText.text(for: .movedIn(buildingId: "x", people: 1), buildingName: name) == "The Cottage already has 1 resident.")
        #expect(BuddyTalkText.text(for: .movedIn(buildingId: "x", people: 4), buildingName: name) == "The Cottage already has 4 residents.")
        #expect(BuddyTalkText.text(for: .size(.village, people: 1), buildingName: name) == "We're a village now – 1 person lives here.")
        #expect(BuddyTalkText.text(for: .size(.city, people: 250), buildingName: name) == "We're a city now – 250 people live here.")
        #expect(BuddyTalkText.text(for: .nextSize(missing: 1, .smallTown), buildingName: name) == "1 more person and we'll be a small town!")
        #expect(BuddyTalkText.text(for: .streak(1), buildingName: name) == "1 night in a row! The builders are proud of you.")
        Lang.current = .sk
        #expect(BuddyTalkText.text(for: .movedIn(buildingId: "x", people: 1), buildingName: name) == "The Cottage už má 1 obyvateľa.")
        #expect(BuddyTalkText.text(for: .movedIn(buildingId: "x", people: 5), buildingName: name) == "The Cottage už má 5 obyvateľov.")
        #expect(BuddyTalkText.text(for: .nextSize(missing: 3, .village), buildingName: name) == "Ešte 3 ľudia a budeme dedina!")
        #expect(BuddyTalkText.text(for: .streak(2), buildingName: name) == "2 noci za sebou! Stavbári sú na teba hrdí.")
    }

    @Test func everyKeyIsInTheCatalogWithSlovak() throws {
        let url = I18nTests.root.appendingPathComponent("SleepHole/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let strings = json["strings"] as! [String: [String: Any]]
        for k in BuddyTalkText.keys {
            let locs = try #require((strings[k]?["localizations"]) as? [String: Any], "no catalog entry: \(k)")
            #expect(locs["sk"] != nil, "no sk: \(k)")
        }
    }
}

@Suite struct BuddyNewsLogTests {
    @Test func aNewsLineLeadsOncePerDay() throws {
        let d = try #require(UserDefaults(suiteName: "BuddyNewsLogTests"))
        d.removePersistentDomain(forName: "BuddyNewsLogTests")
        let log = BuddyNewsLog(calendar: Calendar.current, defaults: d)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(log.ledToday(now: now).isEmpty)
        log.markLed(.ruined(buildingId: "x", repairsTonight: true), now: now)
        log.markLed(.equinox, now: now)
        #expect(log.ledToday(now: now) == [BuddyLine.ruined(buildingId: "x", repairsTonight: true).newsKey, BuddyLine.equinox.newsKey])
        // the next calendar day starts afresh
        #expect(log.ledToday(now: now.addingTimeInterval(2 * 86_400)).isEmpty)
        d.removePersistentDomain(forName: "BuddyNewsLogTests")
    }
}
