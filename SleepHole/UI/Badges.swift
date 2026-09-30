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
                Text("🔥")
                    .font(.system(size: 30))
                    .scaleEffect(n > 0 ? 1 + 0.06 * sin(t * 9) + 0.03 * sin(t * 23) : 0.9)
                    .saturation(n > 0 ? 1 : 0)
                    .opacity(n > 0 ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(n > 0 ? "\(SK.nights(n)) v rade" : "Séria začína dnes").font(.headline)
                    Text(n > 0 ? "nepreruš ju 💪" : "prvá dobrá noc ju zapáli").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.orange.opacity(n > 0 ? 0.18 : 0.08), in: Capsule())
        }
    }
}

/// 🪙 coin balance.
struct CoinBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Text("🪙").font(.system(size: 26))
            Text("\(model.coins)").font(.headline.monospacedDigit())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.yellow.opacity(0.16), in: Capsule())
        .accessibilityLabel("Mince: \(model.coins)")
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
            Text("Postavené noci: \(built) · odomknutý level \(level)").font(.footnote)
            if let next = Progression.nightsToNextLevel(built: built) {
                Text("Level \(next.level) o \(SK.nights(next.nights))").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}
