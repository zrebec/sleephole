import SleepCore
import SwiftUI

/// Falling confetti (Canvas + TimelineView, no assets).
struct ConfettiView: View {
    private struct Piece { let x, speed, drift, size, phase: Double; let color: Color }
    private static let pieces: [Piece] = {
        var rng = SeededGenerator(seed: 11)
        let colors: [Color] = [.yellow, .orange, .pink, .green, .blue, .purple, .red]
        return (0..<90).map { _ in
            Piece(x: .random(in: 0...1, using: &rng), speed: .random(in: 0.12...0.3, using: &rng),
                  drift: .random(in: -0.05...0.05, using: &rng), size: .random(in: 5...10, using: &rng),
                  phase: .random(in: 0...1, using: &rng), color: colors.randomElement(using: &rng)!)
        }
    }()
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start) / Motion.pace
            Canvas { gc, size in
                for p in Self.pieces {
                    let y = ((p.phase + t * p.speed).truncatingRemainder(dividingBy: 1.1) - 0.05) * size.height
                    let x = (p.x + sin(t * 2 + p.phase * 6) * p.drift) * size.width
                    var g = gc
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .radians(t * 3 + p.phase * 10))
                    g.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)),
                           with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// "Level N odomknutý!" – shown over the result screen when a night unlocks a level.
struct LevelUpCard: View {
    @Environment(AppModel.self) private var model
    let level: Int
    let onClose: () -> Void

    var body: some View {
        let samples = Array((model.catalog?.buildable(level: level) ?? []).filter { $0.kind != .roadLit }.prefix(3))
        VStack(spacing: 14) {
            Text(verbatim: "🎉").font(.system(size: 54))
            Text(L("Level \(level) unlocked!")).font(.largeTitle.bold())
            Text(GuideText.levels[safe: level - 1]?.what ?? "")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(samples) { BuildingImage(id: $0.id, maxHeight: 90) }
            }
            Text(L("From tonight these buildings can be built too.")).font(.footnote).foregroundStyle(.secondary)
            Button(L("Great!"), action: onClose).buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(24)
    }
}
