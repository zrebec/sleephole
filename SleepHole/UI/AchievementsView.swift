import SleepCore
import SwiftUI

/// Texts and icons of the achievements (idea S, owner 2026-09-30).
extension Achievement {
    var icon: String {
        switch self {
        case .firstBuilding: "🏠"
        case .streak3: "🔥"
        case .streak7: "🌟"
        case .streak30: "🏆"
        case .built10: "🏘️"
        case .built50: "🏙️"
        case .built100: "💯"
        case .firstLevel2: "🌳"
        case .firstLevel3: "🏛️"
        case .firstSkyscraper: "🏢"
        case .firstNap: "😴"
        case .firstRepair: "🛠️"
        }
    }

    var title: String {
        switch self {
        case .firstBuilding: L("First building")
        case .streak3: L("3 nights in a row")
        case .streak7: L("7 nights in a row")
        case .streak30: L("30 nights in a row")
        case .built10: L("10 nights built")
        case .built50: L("50 nights built")
        case .built100: L("100 nights built")
        case .firstLevel2: L("First level 2 building")
        case .firstLevel3: L("First level 3 building")
        case .firstSkyscraper: L("First skyscraper")
        case .firstNap: L("First nap")
        case .firstRepair: L("Ruin repaired")
        }
    }

    var detail: String {
        switch self {
        case .firstBuilding: L("Your first night that built something.")
        case .streak3: L("Three complete nights in a row.")
        case .streak7: L("A whole week of complete nights in a row.")
        case .streak30: L("Thirty complete nights in a row – that's a real habit!")
        case .built10: L("Ten nights that built something (complete or unfinished).")
        case .built50: L("Fifty nights that built something.")
        case .built100: L("A hundred nights that built something.")
        case .firstLevel2: L("A park, museum or library in your town.")
        case .firstLevel3: L("A town hall, school, fire station, police or hospital.")
        case .firstSkyscraper: L("Your town reaches the sky.")
        case .firstNap: L("A complete afternoon nap.")
        case .firstRepair: L("A good night rebuilt a ruin.")
        }
    }
}

/// Štatistiky → all achievements; locked ones are grey. Tap one to read what it is for.
struct AchievementsCard: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Achievement?

    var body: some View {
        let unlocked = Dictionary(model.achievements.map { ($0.achievement, $0.key) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                ForEach(Achievement.allCases) { a in
                    let key = unlocked[a]
                    Button { selected = selected == a ? nil : a } label: {
                        VStack(spacing: 4) {
                            Text(verbatim: a.icon).font(.system(size: 34))
                                .grayscale(key == nil ? 1 : 0).opacity(key == nil ? 0.35 : 1)
                                .overlay(alignment: .bottomTrailing) {
                                    if key == nil { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                                }
                            Text(a.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
                                .lineLimit(2, reservesSpace: true)
                            Text(verbatim: key.map(Fmt.dayMonth) ?? "+\(a.reward) 🪙")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selected == a ? Color.accentColor.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.title + ", " + (key == nil ? L("locked") : L("unlocked")))
                }
            }
            if let a = selected {
                Text(verbatim: "\(a.icon) \(a.detail)").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Result screen: achievements earned by this night.
struct NewAchievements: View {
    let achievements: [Achievement]

    var body: some View {
        if !achievements.isEmpty {
            VStack(spacing: 6) {
                Text(achievements.count == 1 ? L("New achievement!") : L("New achievements!"))
                    .font(.headline).foregroundStyle(.yellow)
                ForEach(achievements) { a in
                    Text(verbatim: "\(a.icon) \(a.title) · +\(a.reward) 🪙").font(.subheadline)
                }
            }
            .padding(12)
            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
