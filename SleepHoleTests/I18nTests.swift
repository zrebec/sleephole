import Foundation
import SleepCore
import SwiftData
import Testing
import UIKit
@testable import SleepHole

/// Multi-language (docs/IMPLEMENTATION_I18N.md §7): English by default, Slovak switchable, stored in SwiftData.
@MainActor
struct I18nTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current
    /// Repo root (the simulator can read the Mac's file system).
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    init() { AudioKeeper.muted = true }

    func store() -> ModelContainer {
        try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func model(_ c: ModelContainer, at now: Date = Date(timeIntervalSinceReferenceDate: 0)) -> AppModel {
        AppModel(context: c.mainContext, catalog: sprites.catalog, clock: FakeClock(now), settings: AppSettings(),
                 servicesEnabled: false)
    }

    // MARK: catalog

    @Test func everyKeyHasASlovakTranslationAndPluralForms() throws {
        let url = Self.root.appendingPathComponent("SleepHole/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        #expect(json["sourceLanguage"] as? String == "en")
        let strings = json["strings"] as! [String: [String: Any]]
        #expect(strings.count > 250)
        for (key, entry) in strings {
            let locs = entry["localizations"] as? [String: [String: Any]] ?? [:]
            let sk = try #require(locs["sk"], "no sk for \(key)")
            if let plural = (sk["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                #expect(Set(plural.keys).isSuperset(of: ["one", "few", "many", "other"]), "sk plural \(key)")
                let en = (locs["en"]?["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
                #expect(Set(en.keys).isSuperset(of: ["one", "other"]), "en plural \(key)")
            } else {
                let value = (sk["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                #expect(!value.isEmpty, "empty sk for \(key)")
            }
        }
    }

    /// No Slovak text may be hard-coded in the app any more – everything goes through `L("English key")`.
    @Test func noSlovakLiteralsLeftInTheApp() throws {
        let diacritics = CharacterSet(charactersIn: "áäčďéíĺľňóôŕšťúýžÁÄČĎÉÍĹĽŇÓÔŔŠŤÚÝŽ")
        let literal = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
        let dir = Self.root.appendingPathComponent("SleepHole")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 20)
        var offenders: [String] = []
        for file in files {
            for (i, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || line.contains("i18n-ignore") { continue }
                let ns = line as NSString
                let literals = literal.matches(in: line, range: NSRange(location: 0, length: ns.length)).map(\.range)
                // a trailing comment starts at the first "//" that is not inside a string literal
                var comment = ns.length
                var search = NSRange(location: 0, length: ns.length)
                while case let r = ns.range(of: "//", range: search), r.location != NSNotFound {
                    if !literals.contains(where: { NSLocationInRange(r.location, $0) }) { comment = r.location; break }
                    search = NSRange(location: r.location + 2, length: ns.length - r.location - 2)
                }
                for range in literals where range.location < comment
                    && ns.substring(with: range).rangeOfCharacter(from: diacritics) != nil {
                    offenders.append("\(file.lastPathComponent):\(i + 1): \(ns.substring(with: range))")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: "\n"))")
    }

    // MARK: switching + storage

    @Test func defaultIsEnglishEvenWithExistingSlovakNights() {
        let c = store()
        let m1 = model(c)
        let rec = NightRecord(window: m1.window, buildingId: "l1-house-a-a", isDebug: false, setupGrace: 300)
        c.mainContext.insert(rec)
        try? c.mainContext.save()
        let m2 = model(c)
        #expect(m2.language == .en && Lang.current == .en)
        #expect(L("🌙 Go to sleep") == "🌙 Go to sleep")
        _ = m1
    }

    @Test func switchingIsImmediateAndStoredInTheDatabase() {
        let c = store()
        let m = model(c)
        m.language = .sk
        #expect(Lang.current == .sk)
        #expect(L("🌙 Go to sleep") == "🌙 Ísť spať" && L("Today") == "Dnes")
        #expect(AppSettings.AlarmSound.gentle.title == "Jemný" && AudioKeeper.Ambience.brownNoise.title == "Hnedý šum")
        let again = model(c)                                    // a new model on the same database reads it
        #expect(again.language == .sk && Lang.current == .sk)
        again.language = .en
        #expect(L("🌙 Go to sleep") == "🌙 Go to sleep")
        #expect(model(c).language == .en)
    }

    @Test func pluralsInBothLanguages() {
        Lang.current = .sk
        #expect(Plural.nights(1) == "1 noc" && Plural.nights(2) == "2 noci" && Plural.nights(5) == "5 nocí")
        #expect(L("\(3) nights in a row") == "3 noci v rade" && L("\(1) complete naps") == "1 hotový odpočinok")
        Lang.current = .en
        #expect(Plural.nights(1) == "1 night" && Plural.nights(2) == "2 nights")
        #expect(L("\(1) nights in a row") == "1 night in a row" && L("Restored: \(1) nights ✓") == "Restored: 1 night ✓")
    }

    @Test func interpolationKeepsTheArgumentOrder() {
        Lang.current = .sk
        #expect(L("Bedtime \("21:00") · wake-up \("4:30")") == "Večierka 21:00 · budíček 4:30")
        #expect(L("Level \(3) in \(Plural.nights(5))") == "Level 3 o 5 nocí")
        Lang.current = .en
        #expect(L("Level \(3) in \(Plural.nights(5))") == "Level 3 in 5 nights")
    }

    @Test func soundsHaveDifferentTitlesInBothLanguages() {
        for lang in AppLanguage.allCases where lang != .en {
            for s in AppSettings.AlarmSound.allCases where s != .retro && s != .kalimba {   // the same word in SK
                Lang.current = .en; let en = (s.title, s.detail)
                Lang.current = lang; let other = (s.title, s.detail)
                #expect(!en.0.isEmpty && !other.0.isEmpty && en.0 != other.0 && en.1 != other.1)
            }
            for a in AudioKeeper.Ambience.allCases {
                Lang.current = .en; let en = (a.title, a.detail)
                Lang.current = lang; let other = (a.title, a.detail)
                #expect(!en.0.isEmpty && en.0 != other.0 && en.1 != other.1)
            }
        }
        Lang.current = .en
        #expect(AppSettings.timerTitle(nil) == "All night" && AppSettings.timerTitle(1) == "1 min (test)")
        #expect(AppLanguage.sk.nativeName == "Slovenčina" && AppLanguage.en.nativeName == "English")   // i18n-ignore
    }

    @Test func launchArgumentPicksTheLanguage() {
        #expect(AppModel.launchLanguage(args: ["x", "-lang", "sk"]) == .sk)
        #expect(AppModel.launchLanguage(args: ["x", "-lang", "xx"]) == nil && AppModel.launchLanguage(args: ["-lang"]) == nil)
    }

    // MARK: buildings

    @Test func buildingNamesAndSignSpritesPerLanguage() throws {
        let catalog = try #require(sprites.catalog)
        #expect(catalog.entries.allSatisfy { $0.nameEN?.isEmpty == false })
        #expect(catalog["l3-police"]?.name("en") == "Police station" && catalog["l3-police"]?.name("sk") == "Polícia")
        let signs = ["l2-museum-a", "l2-museum-b", "l2-library-a", "l2-library-b", "l3-townhall", "l3-school",
                     "l3-firestation", "l3-police", "l3-hospital"]
        #expect(Set(catalog.entries.filter { $0.fileEN != nil }.map(\.id)) == Set(signs))
        for id in signs {
            let en = try #require(sprites.image(for: id, language: .en))
            let sk = try #require(sprites.image(for: id, language: .sk))
            #expect(en.size == sk.size)                                  // same size + anchor as the Slovak sprite
            #expect(en.pngData() != sk.pngData())
        }
        // a sprite without text is the same file in both languages
        #expect(sprites.image(for: "l1-house-a-a", language: .en) === sprites.image(for: "l1-house-a-a", language: .sk))
        Lang.current = .sk
        #expect(catalog["l1-house-a-a"]?.displayName == "Rodinný dom")
        Lang.current = .en
        #expect(catalog["l1-house-a-a"]?.displayName == "Family house")
    }

    // MARK: formatting

    @Test func datesAndTimes() {
        let was12h = Fmt.systemUses12h
        defer { Fmt.systemUses12h = was12h }
        let key = NightKey("2026-10-02")!
        Lang.current = .sk
        #expect(Fmt.fullDate(key) == "2. 10. 2026" && Fmt.dayMonth(key) == "2. 10.")
        Fmt.systemUses12h = true                                          // SK ignores the 12 h setting
        #expect(Fmt.time(TimeOfDay(21, 5)) == "21:05")
        Lang.current = .en
        #expect(Fmt.fullDate(key) == "Oct 2, 2026" && Fmt.dayMonth(key) == "10/2")
        #expect(!Fmt.fullDate(key).contains("2 026") && !Fmt.fullDate(key).contains("2,026"))
        #expect(Fmt.time(TimeOfDay(21, 5)).replacingOccurrences(of: "\u{202F}", with: " ") == "9:05 PM")
        Fmt.systemUses12h = false
        #expect(Fmt.time(TimeOfDay(21, 5)) == "21:05" && Fmt.time(minutesOfDay: -30) == "23:30")
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 4, minute: 30, second: 7))!
        #expect(Fmt.timeSec(d) == "4:30:07")
    }

    // MARK: backup

    @Test func languageRoundTripsThroughTheBackup() throws {
        let m = model(store())
        m.language = .sk
        let data = try m.makeBackup().encoded()
        #expect(try BackupFile.decode(data).language == "sk")
        let other = model(store())
        #expect(other.language == .en)
        try other.restore(BackupFile.decode(data))
        #expect(other.language == .sk)
        // an old backup without a language keeps the current choice
        var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        old["language"] = nil
        let oldFile = try BackupFile.decode(JSONSerialization.data(withJSONObject: old))
        #expect(oldFile.language == nil)
        other.language = .en
        try other.restore(oldFile)
        #expect(other.language == .en)
    }
}
