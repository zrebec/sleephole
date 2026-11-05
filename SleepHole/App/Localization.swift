import Foundation
import SleepCore

/// In-app language (owner 2026-09-30, docs/IMPLEMENTATION_I18N.md): English by default, stored in SwiftData
/// (`UserProgress.languageRaw`). New languages = one case + translations in `Localizable.xcstrings`.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case en, sk, cs

    static let fallback = AppLanguage.en
    var id: String { rawValue }

    /// Shown in the language pickers – never translated.
    var nativeName: String {
        switch self {
        case .en: "English"
        case .sk: "Slovenčina"   // i18n-ignore
        case .cs: "Čeština"   // i18n-ignore
        }
    }

    /// Formatting locale. EN keeps the iPhone's 12/24 h choice (Q3), SK and CS are always 24 h.
    var locale: Locale {
        switch self {
        case .sk: return Locale(identifier: "sk_SK")
        case .cs: return Locale(identifier: "cs_CZ")
        case .en:
            var c = Locale.Components(identifier: "en_US")
            c.hourCycle = Fmt.systemUses12h ? .oneToTwelve : .zeroToTwentyThree
            return Locale(components: c)
        }
    }

    /// Slovak and Czech share the continental formats: "30. 9.", 24 h clock, no 12-hour variant.
    var usesContinentalFormats: Bool { self != .en }

    /// The `<lang>.lproj` folder of the app bundle – `L(...)` looks strings up there, not in the system language.
    var bundle: Bundle { Self.bundles[self] ?? .main }

    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues: allCases.compactMap { lang in
        Bundle.main.path(forResource: lang.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)).map { (lang, $0) }
    })
}

/// The language all UI text is produced in. Written only by `AppModel` (main thread).
enum Lang {
    nonisolated(unsafe) static var current: AppLanguage = .fallback
}

/// The ONLY way UI text is produced: `L("Bedtime at \(time)")`. Keys are the English text; interpolations and
/// plural variations come from `Localizable.xcstrings`.
///
/// **Czech falls back to Slovak (build 13b):** a key without a Czech translation has no entry in `cs.lproj`, and the
/// bundle then answers with the English source text. There is no public API to ask whether a key exists, so the text is
/// looked up in the `cs` and in the `en` bundle; when both are equal the Czech text is missing and the Slovak one is
/// shown (formatted with the Czech locale). `I18nTests` guarantees that no catalog key has a Czech value equal to its
/// English value while its Slovak value differs, so a real translation is never mistaken for a missing one.
func L(_ key: String.LocalizationValue) -> String {
    let lang = Lang.current
    let text = String(localized: key, bundle: lang.bundle, locale: lang.locale)
    guard lang == .cs else { return text }
    let english = String(localized: key, bundle: AppLanguage.en.bundle, locale: lang.locale)
    guard text == english else { return Czech.prepositions(text) }
    return Czech.prepositions(String(localized: key, bundle: AppLanguage.sk.bundle, locale: lang.locale))
}

/// Czech grammar that depends on the formatted arguments (build 13b).
enum Czech {
    /// Hours before which Czech says "ve" instead of "v" ("ve 22:30", "ve 2:15", "ve 12:00").
    private static let veHours: Set<Int> = [2, 3, 4, 12, 13, 14, 20, 21, 22, 23]
    private static let beforeClock = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])([vV]) (\d{1,2}):\d{2}(?!\d)"#)

    /// "v" / "V" directly before a clock time "H:MM" / "HH:MM" becomes "ve" / "Ve" when the hour needs it (2–4, 12–14,
    /// 20–23); every other "v", an existing "ve", dates and other numbers are left alone. Applied to every Czech text,
    /// so the translations can simply say "v %@" – also when the text fell back to Slovak (its "o" never matches).
    static func prepositions(_ text: String) -> String {
        let ns = text as NSString
        var result = text
        for m in beforeClock.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let hour = Int(ns.substring(with: m.range(at: 2))), veHours.contains(hour) else { continue }
            let letter = m.range(at: 1)
            let insert = ns.substring(with: letter) == "V" ? "Ve" : "ve"
            result = (result as NSString).replacingCharacters(in: letter, with: insert)
        }
        return result
    }
}

/// Dates and times in the current language. SK / CS always 24 h; EN follows the iPhone's 12/24 h setting (Q3).
enum Fmt {
    /// true when the iPhone is set to a 12-hour clock.
    nonisolated(unsafe) static var systemUses12h: Bool =
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

    static func time(_ date: Date) -> String { formatter(seconds: false).string(from: date) }
    static func timeSec(_ date: Date) -> String { formatter(seconds: true).string(from: date) }

    static func time(_ t: TimeOfDay) -> String { time(minutesOfDay: t.hour * 60 + t.minute) }

    /// Minutes after midnight (wraps around).
    static func time(minutesOfDay m: Int) -> String {
        let m = (m % 1440 + 1440) % 1440
        let date = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: m / 60, minute: m % 60))!
        return time(date)
    }

    /// A chance in tenths of a percent as a percent with at most one decimal, in the app's language: 250 → "25%" / "25 %",
    /// 8 → "0.8%" / "0,8 %" (the box odds, 11b4a).
    static func permille(_ p: Int) -> String {
        let f = NumberFormatter()
        f.locale = Lang.current.locale
        f.numberStyle = .percent
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: Double(p) / 1000)) ?? "\(p / 10)%"
    }

    /// "30. 9." / "9/30"
    static func dayMonth(_ k: NightKey) -> String {
        Lang.current.usesContinentalFormats ? "\(k.day). \(k.month)." : "\(k.month)/\(k.day)"
    }

    /// "30. 9. 2026" / "Sep 30, 2026" – never with a grouping separator in the year.
    static func fullDate(_ k: NightKey) -> String {
        guard !Lang.current.usesContinentalFormats else { return "\(k.day). \(k.month). \(k.year)" }
        let date = Calendar.current.date(from: DateComponents(year: k.year, month: k.month, day: k.day, hour: 12))!
        return date.formatted(.dateTime.year().month(.abbreviated).day().locale(Lang.current.locale))
    }

    /// "3. 10. 2027 20:39" / "Oct 3, 2027 at 8:39 PM" – a moment that can be months away (the app's expiry): the year is
    /// always there, so it never reads as a date in the past.
    static func dateTimeWithYear(_ date: Date) -> String {
        let day = fullDate(NightKey(date: date, calendar: .current)), clock = time(date)
        return Lang.current.usesContinentalFormats ? "\(day) \(clock)" : L("\(day) at \(clock)")
    }

    /// A moment in the recent past for a status line: today → the clock time ("14:05"), another day → day, month and
    /// time ("30. 9. 14:05" / "9/30 2:05 PM").
    static func moment(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        return "\(dayMonth(NightKey(date: date, calendar: calendar))) \(time(date))"
    }

    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    private static func formatter(seconds: Bool) -> DateFormatter {
        let cacheKey = "\(Lang.current.rawValue)-\(systemUses12h)-\(seconds)"
        // a cached formatter keeps the zone of its creation: follow the default zone (what a new DateFormatter takes) on every use (L9)
        if let f = cache[cacheKey] { f.timeZone = NSTimeZone.default; return f }
        let f = DateFormatter()
        cache[cacheKey] = f
        f.locale = Lang.current.locale
        if Lang.current.usesContinentalFormats || !systemUses12h {
            f.dateFormat = seconds ? "H:mm:ss" : "H:mm"
        } else {
            f.setLocalizedDateFormatFromTemplate(seconds ? "hmmss" : "hmm")
        }
        return f
    }
}

extension CatalogEntry {
    /// Building name in the current UI language.
    var displayName: String { name(Lang.current.rawValue) }
}
