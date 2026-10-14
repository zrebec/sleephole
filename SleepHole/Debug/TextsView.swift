#if DEBUG   // developer aid: Debug builds only, like PlansView
import SwiftUI

/// Every text of the app in its own card, read from the COMPILED string tables of the bundle at run time
/// (`<lang>.lproj/Localizable.strings` + `.stringsdict`), so the screen always matches the build.
struct AppTextEntry: Identifiable, Equatable {
    let key: String
    let sk: [String]          // one element for a plain text, one per plural form otherwise ("category: text")
    let en: [String]
    var id: String { key }
    var skMain: String { sk.first ?? key }
    var haystack: String { (key + "\n" + sk.joined(separator: "\n") + "\n" + en.joined(separator: "\n")).lowercased() }
}

enum AppTexts {
    private static func table(_ lang: String, _ type: String) -> [String: Any] {
        guard let path = Bundle.main.path(forResource: "Localizable", ofType: type, inDirectory: nil, forLocalization: lang),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else { return [:] }
        return dict
    }

    private static let order = ["zero", "one", "two", "few", "many", "other"]

    /// The forms of one stringsdict entry: `NSStringLocalizedFormatKey` → variable → its plural categories.
    private static func forms(_ entry: Any?) -> [String] {
        guard let e = entry as? [String: Any] else { return [] }
        var out: [String] = []
        // a sentence around the plural variable(s) ("%1$@ už má %#@residents@.") is shown first
        if let f = e["NSStringLocalizedFormatKey"] as? String,
           !f.replacingOccurrences(of: "%#@[A-Za-z0-9_]+@", with: "", options: .regularExpression).isEmpty {
            out.append(f)
        }
        for (name, value) in e.sorted(by: { $0.key < $1.key }) where name != "NSStringLocalizedFormatKey" {
            guard let v = value as? [String: Any] else { continue }
            for cat in order { if let t = v[cat] as? String { out.append("\(cat): \(t)") } }
        }
        return out
    }

    static func load() -> [AppTextEntry] {
        let skS = table("sk", "strings"), enS = table("en", "strings")
        let skD = table("sk", "stringsdict"), enD = table("en", "stringsdict")
        let keys = Set(skS.keys).union(enS.keys).union(skD.keys).union(enD.keys)
        let entries = keys.map { key -> AppTextEntry in
            let sk = forms(skD[key]).isEmpty ? [(skS[key] as? String) ?? key] : forms(skD[key])
            let en = forms(enD[key]).isEmpty ? [(enS[key] as? String) ?? key] : forms(enD[key])
            return AppTextEntry(key: key, sk: sk, en: en)
        }
        return entries.sorted { $0.skMain.localizedCaseInsensitiveCompare($1.skMain) == .orderedAscending }
    }
}

struct TextsView: View {
    @State private var entries: [AppTextEntry] = AppTexts.load()
    @State private var query = ""
    /// Only the sleep buddy's sentences (phase TALK), in the order of `BuddyTalkText.keys`.
    @State private var buddyOnly = DevArgs.list.contains("-textsBuddy")

    private var shown: [AppTextEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var base = entries
        if buddyOnly {
            let byKey = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            base = BuddyTalkText.keys.compactMap { byKey[$0] }
        }
        return q.isEmpty ? base : base.filter { $0.haystack.contains(q) }
    }

    var body: some View {
        let list = shown
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Picker(L("Texts"), selection: $buddyOnly) {
                    Text(L("All texts")).tag(false)
                    Text(L("Buddy")).tag(true)
                }
                .pickerStyle(.segmented)
                Text(verbatim: "\(list.count) texts")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(list) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(e.sk.enumerated()), id: \.offset) { _, t in
                            Text(verbatim: t).font(.body.weight(.medium)).foregroundStyle(.primary)
                        }
                        Divider()
                        ForEach(Array(e.en.enumerated()), id: \.offset) { _, t in
                            Text(verbatim: t).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                if entries.isEmpty {
                    Text(verbatim: "No string tables found in this build.").foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("Texts"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text(verbatim: "Search"))
    }
}
#endif
