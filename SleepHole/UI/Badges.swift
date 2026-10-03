import SleepCore
import SwiftUI

/// 🔥 streak badge with a flickering flame.
struct StreakBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let n = model.streak
        TimelineView(.animation(minimumInterval: 0.08)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                Text(verbatim: "🔥")
                    .font(.system(size: 30))
                    .scaleEffect(n > 0 ? 1 + 0.06 * sin(t * 9) + 0.03 * sin(t * 23) : 0.9)
                    .saturation(n > 0 ? 1 : 0)
                    .opacity(n > 0 ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(n > 0 ? L("\(n) nights in a row") : L("Your streak starts today")).font(.headline)
                    Text(n > 0 ? L("keep it going 💪") : L("your first good night lights it")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassCapsule(tint: n > 0 ? .orange : nil)
        }
    }
}

/// 🪙 coin balance.
struct CoinBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "🪙").font(.system(size: 26))
            Text(verbatim: "\(model.coins)").font(.headline.monospacedDigit())
                .contentTransition(.numericText(value: Double(model.coins)))
                .animation(.snappy, value: model.coins)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassCapsule(tint: .yellow)
        .accessibilityLabel(L("Coins: \(model.coins)"))
    }
}

/// Streak + coins side by side.
struct StatusBadges: View {
    var body: some View {
        HStack(spacing: 10) {
            StreakBadge()
            CoinBadge()
        }
    }
}

struct LevelInfo: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let built = model.builtNights
        let level = Progression.unlockedMaxLevel(builtBefore: built)
        VStack(spacing: 4) {
            Text(L("Nights built: \(built) · level \(level) unlocked")).font(.footnote)
            if let next = Progression.nightsToNextLevel(built: built) {
                Text(L("Level \(next.level) in \(Plural.nights(next.nights))")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}
