import SleepCore
import SwiftUI

/// "Dnes" – driven by `AppModel.phase` (plan §9).
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle, .canStart: HomeView()
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

// MARK: - home (idle + can start): both buttons are always visible, disabled outside their windows

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var briefing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            let w = model.window
            let canSleep = model.phase == .canStart
            let napReason = model.napBlockReason(at: now)
            ScrollView {
                VStack(spacing: 18) {
                    StatusBadges()
                    Text(L("Bedtime \(Fmt.time(w.bedtime)) · wake-up \(Fmt.time(w.wake))"))
                        .font(.title3.bold())

                    actionButton(L("🌙 Go to sleep"), enabled: canSleep, prominent: true) {
                        if model.needsFirstNightBriefing { briefing = true } else { model.startNight() }
                    }
                    Text(sleepCaption(canSleep: canSleep, now: now, w: w))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    actionButton(L("😴 Nap (\(model.settings.nap.minutes) min)"), enabled: napReason == nil,
                                 prominent: false) { model.startNap() }
                    Text(napReason ?? L("You can nap until \(Fmt.time(model.settings.nap.windowEnd)). An alarm rings at the end; a complete nap earns +\(NapPlan.reward(.complete)) 🪙."))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    if model.debugWindow != nil {
                        Button(L("Cancel quick night"), role: .cancel) { model.cancelFastNight() }.font(.footnote)
                    }
                    LevelInfo()
                }
                .padding()
            }
            .sheet(isPresented: $briefing) { FirstNightBriefing() }
        }
        .navigationTitle(L("Today"))
    }

    private func sleepCaption(canSleep: Bool, now: Date, w: NightWindow) -> String {
        if canSleep {
            return L("Start building by \(Fmt.time(w.startCloses())). You have until \(Fmt.time(w.setupEnds(start: w.bedtime))) to set up (podcast, bedtime story), then keep SleepHole open and lock your phone.")
        }
        if now > w.startCloses() {
            return L("It's too late to build tonight 🌙 Tomorrow from \(Fmt.time(w.startOpens)).")
        }
        return L("You can't go to sleep yet – you can build from \(Fmt.time(w.startOpens)) to \(Fmt.time(w.startCloses())).")
    }

    @ViewBuilder
    private func actionButton(_ title: String, enabled: Bool, prominent: Bool, action: @escaping () -> Void) -> some View {
        let b = Button(action: action) {
            Text(title).font(.title2.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .controlSize(.large)
        .disabled(!enabled)
        if prominent { b.buttonStyle(.borderedProminent) } else { b.buttonStyle(.bordered) }
    }
}

// MARK: - night

/// The full-height layout when everything fits; scrolls only when it does not (e.g. with the confirm panel on a
/// small phone). A plain ScrollView made the night screen narrow and always scrollable (owner 2026-09-30).
struct FitOrScroll<Content: View>: View {
    @ViewBuilder let content: (_ scrolling: Bool) -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(false)
            ScrollView { content(true) }.scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct NightView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmAbandon = false
    @State private var soundSheet = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            if let rec = model.active {
                let total = rec.wake.timeIntervalSince(rec.startedAt ?? rec.bedtime)
                let progress = min(1, max(0, now.timeIntervalSince(rec.startedAt ?? now) / max(1, total)))
                // morning: the confirm panel needs room → smaller site, so the screen still fits without scrolling
                let compact = rec.window.canConfirm(at: now)
                FitOrScroll { scrolling in
                VStack(spacing: compact ? 12 : 16) {
                    // well below the Dynamic Island – it grows when e.g. a podcast plays (owner 2026-09-30)
                    Text(Fmt.time(now)).font(.system(size: compact ? 52 : 64, weight: .thin, design: .rounded))
                        .padding(.top, compact ? 24 : 36)
                    if let collapsed = model.collapsedAt, collapsed <= now {
                        Text(rec.isNap ? L("Your nap was interrupted 😕") : L("The building collapsed 🧱"))
                            .font(.title2.bold()).foregroundStyle(.orange)
                        Text(L("No worries. The alarm rings at \(Fmt.time(rec.wake))."))
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else if rec.isNap {
                        NapResting(progress: progress)
                        if let graceEnds = model.graceEnds, graceEnds > now {
                            Text(L("Setup: \(Int(graceEnds.timeIntervalSince(now).rounded(.up))) s left for a story or sound"))
                                .font(.callout).foregroundStyle(.yellow)
                        } else {
                            Text(L("Lock your phone and have a nice rest 🧸")).font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        ConstructionSite(buildingId: rec.buildingId, progress: progress)
                            .scaleEffect(compact ? 0.6 : 1, anchor: .top)
                            .frame(height: compact ? 190 : nil, alignment: .top)
                        Text(model.catalog?[rec.buildingId]?.displayName ?? "").font(.headline)
                        if let graceEnds = model.graceEnds, graceEnds > now {
                            let left = Int(graceEnds.timeIntervalSince(now).rounded(.up))
                            Text(left >= 60 ? L("Setup until \(Fmt.time(graceEnds)) (\(Plural.minutes(Double(left))) left)")
                                            : L("Setup: \(left) s left for a podcast or story"))
                                .font(.callout).foregroundStyle(.yellow)
                        } else {
                            Text(L("Lock your phone and good night 🌙")).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Text(L("Alarm at \(Fmt.time(rec.wake))")).font(.footnote).foregroundStyle(.secondary)
                    Button { soundSheet = true } label: {
                        if let s = model.sleepSound, s.endsAt.map({ $0 > now }) ?? true {
                            Label(s.endsAt.map { L("\(s.ambience.title) · until \(Fmt.time($0))") } ?? L("\(s.ambience.title) · all night"),
                                  systemImage: "waveform")
                        } else {
                            Label(L("Sleep sound"), systemImage: "headphones")
                        }
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $soundSheet) {
                        SleepSoundSheet().presentationDetents([.height(330)])
                    }
                    if rec.window.canConfirm(at: now) {
                        ConfirmPanel()
                    }
                    if !scrolling { Spacer(minLength: 0) }
                    Button(rec.isNap ? L("End nap") : L("Cancel night"), role: .destructive) { confirmAbandon = true }
                        .font(.footnote)
                        .confirmationDialog(rec.isNap ? L("End the nap? It won't earn coins.")
                                                      : L("Cancel tonight? The building will turn into ruins."),
                                            isPresented: $confirmAbandon, titleVisibility: .visible) {
                            Button(rec.isNap ? L("End") : L("Cancel night"), role: .destructive) { model.abandonNight() }
                        }
                }
                .frame(maxWidth: .infinity)
                .padding()
                }
            }
        }
        .background { NightSky() }
        .preferredColorScheme(.dark)
    }
}

/// Nap screen: a sleepy, breathing "zZz" moon and the time left.
struct NapResting: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breath = (1 + sin(t * 2 * .pi / 5)) / 2
            VStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Text(verbatim: "🌙").font(.system(size: 110)).scaleEffect(0.96 + 0.06 * breath)
                    Text(verbatim: "z Z z").font(.title.bold()).foregroundStyle(.white.opacity(0.4 + 0.6 * breath))
                        .offset(x: 20, y: -10 - 8 * breath)
                }
                .frame(height: 170)
                Text(L("Nap")).font(.headline).foregroundStyle(.yellow).opacity(0.5 + 0.5 * breath)
                ProgressView(value: progress).tint(.yellow.opacity(0.8)).frame(maxWidth: 200)
            }
        }
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
                Text(L("Building in progress"))
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

/// Night screen: start / change / stop the sleep sound while building (the app stays in the foreground).
struct SleepSoundSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var ambience: AudioKeeper.Ambience = .brownNoise
    @State private var minutes: Int? = 15

    var body: some View {
        NavigationStack {
            Form {
                Picker(L("Sound"), selection: $ambience) {
                    ForEach(AudioKeeper.Ambience.allCases.filter { $0 != .silence }) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Picker(L("Play for"), selection: $minutes) {
                    ForEach(AppSettings.ambienceTimerOptions, id: \.self) { Text(AppSettings.timerTitle($0)).tag($0) }
                }
                .pickerStyle(.menu)
                PreviewButtons(playing: model.sleepSound != nil,
                               play: { model.playSleepSound(ambience, minutes: minutes); dismiss() },
                               stop: { model.stopSleepSound() })
            }
            .navigationTitle(L("Sleep sound"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                ambience = model.settings.ambience == .silence ? .brownNoise : model.settings.ambience
                minutes = model.settings.ambienceMinutes ?? 15
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - alarm

struct AlarmView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text(L("Good morning ☀️")).font(.largeTitle.bold())
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
            Label(L("Shake your phone"), systemImage: "iphone.radiowaves.left.and.right").font(.headline)
            Text(L("or enter the code from Settings")).font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField(L("Code"), text: $code)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    .multilineTextAlignment(.center)
                Button(L("I'm up")) {
                    wrong = !model.confirm(code: code)
                    if wrong { code = "" }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty)
            }
            if wrong { Text(L("Wrong code")).font(.footnote).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onShake { model.confirm() }
    }
}

// MARK: - result

struct ResultView: View {
    @Environment(AppModel.self) private var model
    @State private var celebrationClosed = false

    var body: some View {
        if let rec = model.shownResult, let outcome = rec.outcome {
            let name = model.catalog?[rec.buildingId]?.displayName ?? L("building")
            FitOrScroll { _ in
            VStack(spacing: 18) {
                if rec.isNap {
                    Text(verbatim: outcome == .complete ? "😴" : outcome == .unfinished ? "🥱" : "🧸").font(.system(size: 90))
                    Text(outcome == .complete ? L("Nap complete!") : outcome == .unfinished ? L("Nap cut short")
                         : L("Nap didn't work out")).font(.largeTitle.bold())
                    Text(outcome == .complete ? L("Well rested 💙") : L("No worries, again tomorrow 🌱"))
                        .multilineTextAlignment(.center)
                } else {
                switch outcome {
                case .complete:
                    BuildingImage(id: rec.buildingId)
                    Text(L("Done! 🎉")).font(.largeTitle.bold())
                    Text(L("You built: \(name)")).font(.title3)
                case .unfinished:
                    BuildingImage(id: rec.buildingId, progress: 0.6)
                    Text(L("Unfinished 🚧")).font(.largeTitle.bold())
                    Text(L("\(name) is waiting – your next good night will finish it.")).multilineTextAlignment(.center)
                case .ruins, .missed:
                    BuildingImage(id: (model.catalog?[rec.buildingId]?.footprint.first ?? 1) == 2 ? "o-ruin-2" : "o-ruin-1")
                    Text(L("Not this time")).font(.largeTitle.bold())
                    Text(L("That's part of the town too – new chance tomorrow 🌱")).multilineTextAlignment(.center)
                }
                }
                if !rec.isDebug, model.lastReward > 0 {
                    VStack(spacing: 2) {
                        Text(verbatim: "+\(model.lastReward) 🪙").font(.title.bold()).foregroundStyle(.yellow)
                        if model.lastStreakBonus > 0 {
                            Text(L("including a +\(model.lastStreakBonus) bonus for \(Economy.streakBonusEvery) nights in a row 🔥"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !rec.isDebug { NewAchievements(achievements: model.newAchievements) }
                if let week = model.finishedWeek {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Your week in the town 📖")).font(.headline)
                        WeekJournalView(week: week,
                                        previous: model.journalWeek(monday: week.monday.adding(days: -7, calendar: .current)))
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if outcome == .complete, !rec.isDebug, !rec.isNap { StatusBadges() }
                if let level = model.levelUp {
                    Label(L("Level \(level) unlocked!"), systemImage: "star.fill")
                        .font(.headline).foregroundStyle(.yellow)
                }
                if rec.isDebug { Text(L("(quick test night – doesn't count for the town)")).font(.caption).foregroundStyle(.secondary) }
                Button(L("Continue")) { model.acknowledgeResult() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding()
            }
            .navigationTitle(rec.isNap ? L("Nap") : L("Night result"))
            .overlay {
                if let level = model.levelUp, !celebrationClosed {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ConfettiView()
                        LevelUpCard(level: level) { withAnimation { celebrationClosed = true } }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}
