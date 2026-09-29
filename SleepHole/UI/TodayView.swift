import SleepCore
import SwiftUI

/// "Dnes" – driven by `AppModel.phase` (plan §9).
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle: IdleView()
                case .canStart: CanStartView()
                case .building: NightView()
                case .alarm: AlarmView()
                case .result: ResultView()
                }
            }
            .animation(.default, value: model.phase)
        }
    }
}

// MARK: - helpers

let clockFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "H:mm"
    return f
}()

struct BuildingImage: View {
    @Environment(SpriteLibrary.self) private var sprites
    let id: String
    var progress: Double = 1          // 0…1, reveals the building from the bottom
    var maxHeight: CGFloat = 220

    var body: some View {
        if let image = sprites.image(for: id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .mask {
                    // reveal from the BOTTOM up: the visible band is the lowest `progress` of the image
                    GeometryReader { g in
                        let p = min(1, max(0.08, progress))
                        Rectangle()
                            .frame(width: g.size.width, height: g.size.height * p)
                            .offset(y: g.size.height * (1 - p))
                    }
                }
                .frame(maxHeight: maxHeight)
        }
    }
}

// MARK: - idle

struct IdleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let w = model.window
        VStack(spacing: 18) {
            StreakBadge()
            Image(systemName: "moon.stars.fill").font(.system(size: 56)).foregroundStyle(.indigo)
            Text("Večierka o \(clockFormat.string(from: w.bedtime))").font(.title2.bold())
            Text("Budíček o \(clockFormat.string(from: w.wake))").font(.title3).foregroundStyle(.secondary)
            Text("Stavať môžeš od \(clockFormat.string(from: w.startOpens)) do \(clockFormat.string(from: w.startCloses())).")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            LevelInfo()
        }
        .padding()
        .navigationTitle("Dnes")
    }
}

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
                    Text(n > 0 ? "nepretrž ju 💪" : "prvá dobrá noc ju zapáli").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.orange.opacity(n > 0 ? 0.18 : 0.08), in: Capsule())
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
                Text("Level \(next.level) o \(next.nights) \(next.nights == 1 ? "noc" : next.nights < 5 ? "noci" : "nocí")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - can start

struct CanStartView: View {
    @Environment(AppModel.self) private var model
    @State private var briefing = false

    var body: some View {
        let w = model.window
        VStack(spacing: 20) {
            StreakBadge()
            Text("Čas na stavbu 🏗️").font(.largeTitle.bold())
            Text("Večierka \(clockFormat.string(from: w.bedtime)) · budíček \(clockFormat.string(from: w.wake))")
                .foregroundStyle(.secondary)
            Button {
                if model.needsFirstNightBriefing { briefing = true } else { model.startNight() }
            } label: {
                Text("Začať stavbu").font(.title2.bold()).frame(maxWidth: .infinity).padding()
            }
            .sheet(isPresented: $briefing) { FirstNightBriefing() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Stavbu začni najneskôr o \(clockFormat.string(from: w.startCloses())). Po štarte máš \(model.debugWindow != nil && model.debugGrace < 60 ? "\(Int(model.debugGrace)) s" : "5 minút") na nastavenie podcastu či rozprávky, potom nechaj SleepHole v popredí a zamkni telefón.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.debugWindow != nil {
                Button("Zrušiť rýchlu noc", role: .cancel) { model.cancelFastNight() }.font(.footnote)
            }
            LevelInfo()
        }
        .padding()
        .navigationTitle("Dnes")
    }
}

// MARK: - night

struct NightView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmAbandon = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            if let rec = model.active {
                let total = rec.wake.timeIntervalSince(rec.startedAt ?? rec.bedtime)
                let progress = min(1, max(0, now.timeIntervalSince(rec.startedAt ?? now) / max(1, total)))
                VStack(spacing: 16) {
                    Text(clockFormat.string(from: now)).font(.system(size: 64, weight: .thin, design: .rounded))
                    if let collapsed = model.collapsedAt, collapsed <= now {
                        Text("Stavba sa zrútila 🧱").font(.title2.bold()).foregroundStyle(.orange)
                        Text("Nevadí. Noc pokračuje a budík zazvoní o \(clockFormat.string(from: rec.wake)).")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else {
                        ConstructionSite(buildingId: rec.buildingId, progress: progress)
                        Text(model.catalog?[rec.buildingId]?.nameSK ?? "").font(.headline)
                        if let graceEnds = model.graceEnds, graceEnds > now {
                            Text("Príprava: ešte \(Int(graceEnds.timeIntervalSince(now).rounded(.up))) s na podcast či rozprávku")
                                .font(.callout).foregroundStyle(.yellow)
                        } else {
                            Text("Zamkni telefón a dobrú noc 🌙").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Text("Budík o \(clockFormat.string(from: rec.wake))").font(.footnote).foregroundStyle(.secondary)
                    if rec.window.canConfirm(at: now) {
                        ConfirmPanel()
                    }
                    Spacer()
                    Button("Zrušiť noc", role: .destructive) { confirmAbandon = true }
                        .font(.footnote)
                        .confirmationDialog("Zrušiť dnešnú noc? Budova sa zmení na ruinu.",
                                            isPresented: $confirmAbandon, titleVisibility: .visible) {
                            Button("Zrušiť noc", role: .destructive) { model.abandonNight() }
                        }
                }
                .padding()
            }
        }
        .background { NightSky() }
        .preferredColorScheme(.dark)
    }
}

/// The building under construction + an animated tower crane + a breathing "Stavba prebieha" label.
/// The animation runs only while the night is healthy – it is the visible proof that building goes on.
struct ConstructionSite: View {
    @Environment(SpriteLibrary.self) private var sprites
    let buildingId: String
    let progress: Double
    static let frames = 16
    static let frameDuration = 0.22          // one slewing cycle ≈ 3.5 s

    private var siteId: String {
        (sprites.catalog?[buildingId]?.footprint.first ?? 1) == 2 ? "o-site-2" : "o-site-1"
    }

    /// Dev aid: `-previewProgress 0.6` overrides the progress (screenshots).
    private var shownProgress: Double {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-previewProgress"), args.indices.contains(i + 1),
           let p = Double(args[i + 1]) { return p }
        return progress
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let frame = Int(t / Self.frameDuration) % Self.frames
            let breath = (1 + sin(t * 2 * .pi / 4)) / 2            // 0…1, 4 s period
            VStack(spacing: 14) {
                // Stage: the crane's mast stands behind the building's right side; the pair is centred.
                ZStack(alignment: .bottom) {
                    if let crane = sprites.image(for: String(format: "o-crane-%02d", frame)) {
                        Image(uiImage: crane)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 250)
                            .offset(x: 45)
                    }
                    BuildingImage(id: siteId, maxHeight: 110)       // building site under the building
                        .frame(width: 190)
                        .offset(x: -40, y: 6)
                    BuildingImage(id: buildingId, progress: shownProgress, maxHeight: 150)
                        .frame(width: 190)
                        .offset(x: -40, y: -4)
                }
                .frame(width: 320, height: 260)
                Text("Stavba prebieha")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                    .opacity(0.45 + 0.55 * breath)
                    .scaleEffect(0.97 + 0.06 * breath)
                ProgressView(value: progress)
                    .tint(.yellow.opacity(0.8))
                    .frame(maxWidth: 200)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Calm night background: deep blue gradient with a few softly twinkling stars.
struct NightSky: View {
    private struct Star { let x, y, size, phase: Double }
    private static let stars: [Star] = {
        var rng = SeededGenerator(seed: 42)
        return (0..<60).map { _ in
            Star(x: .random(in: 0...1, using: &rng), y: .random(in: 0...0.75, using: &rng),
                 size: .random(in: 1...2.4, using: &rng), phase: .random(in: 0...(2 * .pi), using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                for s in Self.stars {
                    let a = 0.25 + 0.35 * (1 + sin(t * 0.8 + s.phase)) / 2
                    let r = CGRect(x: s.x * size.width, y: s.y * size.height, width: s.size, height: s.size)
                    gc.fill(Path(ellipseIn: r), with: .color(.white.opacity(a)))
                }
            }
            .background(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.16),
                                                Color(red: 0.09, green: 0.10, blue: 0.24),
                                                Color(red: 0.03, green: 0.03, blue: 0.07)],
                                       startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }
}

// MARK: - alarm

struct AlarmView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Dobré ráno ☀️").font(.largeTitle.bold())
            ConfirmPanel()
            Spacer()
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}

/// Shake or type the wake code (D15).
struct ConfirmPanel: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 12) {
            Label("Zatras telefónom", systemImage: "iphone.radiowaves.left.and.right").font(.headline)
            Text("alebo zadaj kód z Nastavení").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Kód", text: $code)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    .multilineTextAlignment(.center)
                Button("Vstal som") {
                    wrong = !model.confirm(code: code)
                    if wrong { code = "" }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty)
            }
            if wrong { Text("Nesprávny kód").font(.footnote).foregroundStyle(.red) }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onShake { model.confirm() }
    }
}

// MARK: - result

struct ResultView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let rec = model.shownResult, let outcome = rec.outcome {
            let name = model.catalog?[rec.buildingId]?.nameSK ?? "budova"
            VStack(spacing: 18) {
                switch outcome {
                case .complete:
                    BuildingImage(id: rec.buildingId)
                    Text("Hotovo! 🎉").font(.largeTitle.bold())
                    Text("Postavil si: \(name)").font(.title3)
                case .unfinished:
                    BuildingImage(id: rec.buildingId, progress: 0.6)
                    Text("Rozostavaná 🚧").font(.largeTitle.bold())
                    Text("\(name) čaká na dokončenie – ďalšia dobrá noc ju dostavia.").multilineTextAlignment(.center)
                case .ruins, .missed:
                    BuildingImage(id: (model.catalog?[rec.buildingId]?.footprint.first ?? 1) == 2 ? "o-ruin-2" : "o-ruin-1")
                    Text("Dnes to nevyšlo").font(.largeTitle.bold())
                    Text("Aj to patrí k mestu – zajtra nová šanca 🌱").multilineTextAlignment(.center)
                }
                if outcome == .complete, !rec.isDebug { StreakBadge() }
                if let level = model.levelUp {
                    Label("Odomkol si level \(level)!", systemImage: "star.fill")
                        .font(.headline).foregroundStyle(.yellow)
                }
                if rec.isDebug { Text("(rýchla testovacia noc – do mesta sa nepočíta)").font(.caption).foregroundStyle(.secondary) }
                Button("Pokračovať") { model.acknowledgeResult() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding()
            .navigationTitle("Výsledok noci")
        }
    }
}
