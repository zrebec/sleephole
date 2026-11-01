import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// Czech as the third UI language (build 13b): the Slovak fallback for texts without a Czech translation and the
/// safety checks over the String Catalog (a mismatch of format specifiers can crash the app).
@MainActor
struct CzechTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func catalog(_ name: String = "Localizable") throws -> [String: [String: [String: Any]]] {
        let url = root.appendingPathComponent("SleepHole/Resources/\(name).xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let strings = json["strings"] as! [String: [String: Any]]
        return strings.mapValues { ($0["localizations"] as? [String: [String: Any]]) ?? [:] }
    }

    // MARK: catalog walking

    typealias Loc = [String: Any]

    static func unitValue(_ x: Any?) -> String? { ((x as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }

    /// The plural variations of a localization (`variations.plural`): category → string.
    static func plural(_ loc: Loc) -> [String: String] {
        guard let p = (loc["variations"] as? [String: Any])?["plural"] as? [String: Any] else { return [:] }
        return p.compactMapValues(unitValue)
    }

    /// One representative text per localization – used to compare languages: the plain value, or the "other" form.
    static func representative(_ loc: Loc) -> String {
        var parts: [String] = []
        if let v = unitValue(loc) { parts.append(v) }
        if let o = plural(loc)["other"] { parts.append(o) }
        for (name, sub) in ((loc["substitutions"] as? [String: [String: Any]]) ?? [:]).sorted(by: { $0.key < $1.key }) {
            if let o = plural(sub)["other"] { parts.append("\(name)=\(o)") }
        }
        return parts.joined(separator: "|")
    }

    /// Every string a localization can produce, with the substitution it belongs to (nil = the top level).
    static func allTexts(_ loc: Loc) -> [String] {
        var out: [String] = []
        if let v = unitValue(loc) { out.append(v) }
        out += plural(loc).values
        for sub in (loc["substitutions"] as? [String: [String: Any]] ?? [:]).values { out += plural(sub).values }
        return out
    }

    // MARK: format specifiers

    static let specifier = try! NSRegularExpression(
        pattern: #"%(?:(\d+)\$)?[-+# 0]*(?:\d+|\*)?(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfeEgGcCsSpaAF])|%#@([A-Za-z0-9_]+)@"#)

    /// Position → type for one string. `substitutions` resolves `%#@name@` to the argument it stands for; `%arg` is the
    /// substitution's own argument (`argNum` and `formatSpecifier`).
    static func signature(_ text: String, subs: [String: [String: Any]], plainOffset: Int = 0) -> [Int: String] {
        let ns = text.replacingOccurrences(of: "%%", with: "") as NSString
        var result: [Int: String] = [:]
        var next = 1
        for m in specifier.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 4).location != NSNotFound {
                let name = ns.substring(with: m.range(at: 4))
                if let sub = subs[name], let n = sub["argNum"] as? Int, let f = sub["formatSpecifier"] as? String {
                    result[n] = f
                } else { result[-1000 - result.count] = "unresolved \(name)" }
                continue
            }
            let pos = m.range(at: 1).location != NSNotFound ? Int(ns.substring(with: m.range(at: 1)))! : next
            let type = (m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : "")
                + ns.substring(with: m.range(at: 3))
            if m.range(at: 1).location == NSNotFound { next += 1 }
            result[pos] = type
        }
        return result
    }

    /// All the signatures of one localization: the main string and every plural form (with its substitutions).
    static func signatures(_ loc: Loc) -> [String: [Int: String]] {
        let subs = (loc["substitutions"] as? [String: [String: Any]]) ?? [:]
        var out: [String: [Int: String]] = [:]
        if let v = unitValue(loc) { out["main"] = signature(v, subs: subs) }
        for (cat, t) in plural(loc) { out["plural.\(cat)"] = signature(t, subs: [:]) }
        for (name, sub) in subs {
            for (cat, t) in plural(sub) {
                // `%arg` stands for the substitution's own argument
                var sig = signature(t.replacingOccurrences(of: "%arg", with: "%\(sub["argNum"] as? Int ?? 1)$\(sub["formatSpecifier"] as? String ?? "lld")"), subs: [:])
                if sig.isEmpty { sig = [:] }
                out["sub.\(name).\(cat)"] = sig
            }
        }
        return out
    }

    /// What the English source needs: the main string (substitutions resolved) or the plural "other" form.
    static func reference(_ en: Loc) -> [Int: String] {
        if let main = signatures(en)["main"], unitValue(en) != nil {
            // plain key, or a key with substitutions: the main string plus the substitutions' arguments
            let subs = (en["substitutions"] as? [String: [String: Any]]) ?? [:]
            var sig = main
            for sub in subs.values { if let n = sub["argNum"] as? Int, let f = sub["formatSpecifier"] as? String { sig[n] = f } }
            return sig
        }
        return signatures(en)["plural.other"] ?? [:]
    }

    @Test func everyCzechTextKeepsTheEnglishFormatSpecifiers() throws {
        for name in ["Localizable"] {
            let strings = try Self.catalog(name)
            var checked = 0
            for (key, locs) in strings {
                guard let cs = locs["cs"], let en = locs["en"] else { continue }
                checked += 1
                let reference = Self.reference(en)
                let subs = (cs["substitutions"] as? [String: [String: Any]]) ?? [:]
                var all = Self.signatures(cs)
                #expect(!all.isEmpty, "empty cs for \(key)")
                // a main string with substitutions carries the substitution arguments too
                if all["main"] != nil {
                    for sub in subs.values { if let n = sub["argNum"] as? Int, let f = sub["formatSpecifier"] as? String { all["main"]?[n] = f } }
                }
                for (path, sig) in all {
                    // substitution forms only carry their own argument
                    if path.hasPrefix("sub.") {
                        let name = path.split(separator: ".")[1]
                        let s = subs[String(name)] ?? [:]
                        let own = [(s["argNum"] as? Int) ?? 1: (s["formatSpecifier"] as? String) ?? ""]
                        #expect(sig == own || sig.isEmpty, "cs substitution \(path) of '\(key)': \(sig) vs \(own)")
                        continue
                    }
                    #expect(sig == reference, "cs specifiers differ for '\(key)' [\(path)]: \(sig) vs en \(reference)")
                }
            }
            #expect(checked > 250, "only \(checked) Czech keys checked")
        }
    }

    @Test func czechPluralsHaveEveryCategory() throws {
        for (key, locs) in try Self.catalog() {
            guard let cs = locs["cs"] else { continue }
            let forms = [Self.plural(cs)] + ((cs["substitutions"] as? [String: [String: Any]]) ?? [:]).values.map(Self.plural)
            for p in forms where !p.isEmpty {
                #expect(Set(p.keys) == ["one", "few", "many", "other"], "cs plural categories of '\(key)': \(p.keys.sorted())")
                #expect(p.values.allSatisfy { !$0.isEmpty }, "empty cs plural form in '\(key)'")
            }
            #expect(Self.allTexts(cs).allSatisfy { !$0.isEmpty }, "empty cs text in '\(key)'")
        }
    }

    /// The runtime fallback compares the Czech and the English lookup: a Czech text equal to the English one would be
    /// shown in Slovak. This is the one case that comparison gets wrong, so it must not exist.
    @Test func noCzechTextEqualsTheEnglishOneWhileSlovakDiffers() throws {
        var offenders: [String] = []
        for (key, locs) in try Self.catalog() {
            guard let cs = locs["cs"], let en = locs["en"], let sk = locs["sk"] else { continue }
            if Self.representative(cs) == Self.representative(en) && Self.representative(sk) != Self.representative(en) {
                offenders.append(key)
            }
        }
        #expect(offenders.isEmpty, "\(offenders.sorted().joined(separator: "\n"))")
    }

    @Test func infoPlistTextsExistInCzech() throws {
        for (key, locs) in try Self.catalog("InfoPlist") where locs["sk"] != nil {
            #expect(locs["cs"] != nil, "no cs for \(key)")
        }
    }

    // MARK: runtime

    @Test func czechTextWinsAndMissingTextFallsBackToSlovak() throws {
        defer { Lang.current = .en }
        Lang.current = .cs
        #expect(L("🌙 Go to sleep") == "🌙 Jít spát" && L("Today") == "Dnes")
        #expect(L("Level \(3) in \(Plural.nights(5))") == "Úroveň 3 za 5 nocí")
        #expect(L("\(2) nights in a row") == "2 noci v řadě" && L("\(5) nights in a row") == "5 nocí v řadě")
        // a key without a Czech translation shows the Slovak text (never English, never the raw key)
        let strings = try Self.catalog()
        let missing = strings.filter { _, locs in locs["cs"] == nil && locs["sk"] != nil }
            .filter { key, locs in !key.contains("%") && Self.unitValue(locs["sk"]!) != nil && Self.unitValue(locs["sk"]!) != key }
            .keys.sorted()
        if let key = missing.first {
            let expected = Self.unitValue(strings[key]!["sk"]!)!
            Lang.current = .cs
            #expect(L(String.LocalizationValue(key)) == expected, "fallback for '\(key)'")
        }
        // the Slovak text keeps the Czech locale for numbers (a plain interpolation here)
        Lang.current = .sk
        #expect(L("Today") == "Dnes")
        Lang.current = .en
        #expect(L("Today") == "Today")
    }

    @Test func veBeforeSomeClockTimes() {
        #expect(Czech.prepositions("Večerka v 22:30") == "Večerka ve 22:30")
        #expect(Czech.prepositions("Budík v 6:00") == "Budík v 6:00")
        #expect(Czech.prepositions("v 2:15") == "ve 2:15" && Czech.prepositions("v 12:00") == "ve 12:00")
        #expect(Czech.prepositions("v 11:59") == "v 11:59" && Czech.prepositions("v 0:30") == "v 0:30")
        #expect(Czech.prepositions("V 21:00 začíná noc") == "Ve 21:00 začíná noc")
        #expect(Czech.prepositions("ve 21:30") == "ve 21:30")
        #expect(Czech.prepositions("v 3 minutách") == "v 3 minutách")
        #expect(Czech.prepositions("Večerka o 22:30") == "Večerka o 22:30")
        #expect(Czech.prepositions("v 22. 10. a v 14:05, v 4:30") == "v 22. 10. a ve 14:05, v 4:30".replacingOccurrences(of: "v 4:30", with: "ve 4:30"))
        #expect(Czech.prepositions("nav 22:30") == "nav 22:30")
        defer { Lang.current = .en }
        Lang.current = .cs
        #expect(L("Alarm at \("22:30")") == "Budík ve 22:30" && L("Alarm at \("6:30")") == "Budík v 6:30")
    }

    @Test func czechFormatsLikeSlovak() {
        let was12h = Fmt.systemUses12h
        defer { Fmt.systemUses12h = was12h; Lang.current = .en }
        Fmt.systemUses12h = true
        Lang.current = .cs
        let key = NightKey("2026-10-02")!
        #expect(Fmt.fullDate(key) == "2. 10. 2026" && Fmt.dayMonth(key) == "2. 10.")
        #expect(Fmt.time(TimeOfDay(21, 5)) == "21:05")
        #expect(Fmt.permille(8).replacingOccurrences(of: "\u{00A0}", with: " ") == "0,8 %")
        #expect(AppLanguage.cs.nativeName == "Čeština" && AppLanguage.cs.locale.identifier == "cs_CZ")   // i18n-ignore
        #expect(AppLanguage.allCases == [.en, .sk, .cs] && AppLanguage(rawValue: "cs") == .cs)
        #expect(AppModel.launchLanguage(args: ["-lang", "cs"]) == .cs)
        #expect(Voice.voiceLanguage(.cs) == "cs-CZ")
    }

    @Test func buildingNamesAreCzechAndSignsStaySlovak() throws {
        defer { Lang.current = .en }
        let sprites = SpriteLibrary.loadFromBundle()
        let catalog = try #require(sprites.catalog)
        Lang.current = .cs
        #expect(catalog["l1-house-a-a"]?.displayName == "Rodinný dům" && catalog["l3-police"]?.displayName == "Policie")
        #expect(sprites.image(for: "l3-police", language: .cs)?.pngData() == sprites.image(for: "l3-police", language: .sk)?.pngData())
    }
}
