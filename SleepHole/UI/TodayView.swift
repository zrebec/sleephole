import SleepCore
import SwiftUI

/// "Dnes" – driven by `AppModel.phase` (plan §9).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    /// The "Good night" splash after "Go to sleep" / "Nap" (true = nap).
    @State private var splash: Bool?

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
            .animation(.easeInOut(duration: 0.35 * Motion.pace), value: model.phase)
            // full screen: a background on a Group is sized to each child's content (owner bug 2026-10-02: the nap
            // result showed a small 16:9 patch of sky with black bars) – the night screen covers it with its NightSky
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { LivingSky(semicircle: true) }
            .overlay {
                if let nap = splash {
                    GoodNightSplash(nap: nap) { withAnimation { splash = nil } }
                }
            }
            .onChange(of: model.phase) { old, new in
                // only a fresh start – not a night resumed at launch
                guard new == .building, old == .canStart || old == .idle, let rec = model.active,
                      let started = rec.startedAt, Date().timeIntervalSince(started) < 5 else { return }
                splash = rec.isNap
            }
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
    /// The hero cat: 62 % of the screen width (250 pt on a 402 pt wide phone), at most this wide.
    static let buddyMaxWidth: CGFloat = 260

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            let w = model.window
            let canSleep = model.phase == .canStart
            let napReason = model.napBlockReason(at: now)
            ScrollView {
                VStack(spacing: 16) {
                    if let expiry = AppExpiry.date, AppExpiry.isSoon(at: now) { ExpiryCard(expiry: expiry, now: now) }
                    if let at = model.safetyAlarmAt, at > now { SafetyAlarmCard(at: at) }
                    if model.showsMonthlySchedulePrompt { MonthlyScheduleCard().appearIn(delay: 0) }
                    StatusBadges().appearIn(delay: 0.05)
                    // the hero (plan P2b): only the cat – the town has its own tab. A tap pets it (purr, arched back, wink).
                    // Centred on cat + bed (the canvas is not centred on them); the arch's tail reaches above the box,
                    // the cloud below it.
                    BuddyView.centred(
                        BuddyView(state: model.buddyState(at: now), cloud: true, onPet: { model.petBuddy() },
                                  hold: AppModel.forcedBuddyReaction)
                            .containerRelativeFrame(.horizontal) { w, _ in min(Self.buddyMaxWidth, w * 0.62) })
                        .padding(.top, 40)
                        .padding(.bottom, 22)
                        .appearIn(delay: 0.1)

                    VStack(spacing: 12) {
                        Text(L("Bedtime \(Fmt.time(w.bedtime)) · wake-up \(Fmt.time(w.wake))"))
                            .font(.title3.bold())
                        actionButton(L("🌙 Go to sleep"), enabled: canSleep, prominent: true) {
                            if model.needsFirstNightBriefing { briefing = true } else { model.startNight() }
                        }
                        Text(sleepCaption(canSleep: canSleep, now: now, w: w))
                            .font(.callout).cardCaption().multilineTextAlignment(.center)
                    }
                    .padding()
                    .glassCard(cornerRadius: 28)
                    .appearIn(delay: 0.15)

                    VStack(spacing: 12) {
                        actionButton(L("😴 Nap (\(model.settings.nap.minutes) min)"), enabled: napReason == nil,
                                     prominent: false) { model.startNap() }
                        Text(napReason ?? L("You can nap until \(Fmt.time(model.settings.nap.windowEnd)). An alarm rings at the end; a complete nap earns +\(NapPlan.reward(.complete)) 🪙."))
                            .font(.callout).cardCaption().multilineTextAlignment(.center)
                    }
                    .padding()
                    .glassCard(cornerRadius: 28)
                    .appearIn(delay: 0.2)

                    JokerCard().appearIn(delay: 0.25)

                    if model.debugWindow != nil {
                        Button(L("Cancel quick night"), role: .cancel) { model.cancelFastNight() }.font(.footnote)
                    }
                    LevelInfo().appearIn(delay: 0.3)
                }
                .padding()
            }
            // no rubber-band scrolling when everything fits (owner 2026-09-30: "Dnes" could be dragged around)
            .scrollBounceBehavior(.basedOnSize)
            .sheet(isPresented: $briefing) { FirstNightBriefing() }
        }
        .navigationTitle(L("Today"))
        .todayWeather()                                   // the weather badge top right + the refresh loop
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
        // `.disabled` goes last: the button style reads `isEnabled` to draw its calm disabled look
        Button(action: action) {
            Text(title).font(.title2.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .controlSize(.large)
        .glassButton(prominent: prominent)
        .tint(prominent ? .indigo : .teal)
        .disabled(!enabled)
    }
}

/// Days 1–3 of every month (owner 2026-09-30): "does your bedtime still fit?" – changing it is free now.
struct MonthlyScheduleCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.settings.schedule
        VStack(alignment: .leading, spacing: 10) {
            Text(L("New month 🌙")).font(.headline)
            Text(L("Do bedtime \(Fmt.time(s.bedtime)) and wake-up \(Fmt.time(s.wake)) still fit you? Until the 3rd you can change them for free."))
                .font(.subheadline)
            HStack {
                Button(L("It fits")) { model.answerMonthlyPrompt(adjust: false) }
                    .buttonStyle(.bordered)
                Spacer()
                Button(L("Adjust")) { model.answerMonthlyPrompt(adjust: true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .indigo)
    }
}

/// The app stops launching when its provisioning profile runs out (audit 2026-10-03, B2). Shown 48 h ahead.
struct ExpiryCard: View {
    let expiry: Date
    let now: Date

    /// The card's text (the same as the notifications'); the date always carries its year.
    static func message(for expiry: Date) -> String { Notifications.expiryBody(expiry) }

    var body: some View {
        let hours = max(0, Int(expiry.timeIntervalSince(now) / 3600))
        VStack(alignment: .leading, spacing: 6) {
            Label(hours >= 1 ? L("SleepHole stops working in \(hours) h") : L("SleepHole stops working within the hour"),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(Self.message(for: expiry))
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .orange)
    }
}

/// After an early "I'm up" (phase F6b, bug B11): the system alarm stays on at the wake time in case the owner falls
/// asleep again – until he switches it off. Shown on Today and on the result screen.
struct SafetyAlarmCard: View {
    @Environment(AppModel.self) private var model
    let at: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Safety alarm at \(Fmt.time(at))"), systemImage: "alarm.fill")
                .font(.headline)
            Text(L("You confirmed early – the alarm stays on in case you fall asleep again."))
                .font(.subheadline).cardCaption()
            Button(L("I'm really up – switch it off")) { model.switchOffSafetyAlarm() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .indigo)
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
    @State private var confirmPause = false

    /// "9:41" left of a pause.
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

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
                        BuddyView(state: .asleep).frame(width: 138)         // the cat never judges
                    } else if rec.isNap {
                        NapResting(progress: progress, buddy: model.buddyState(at: now))
                        if let graceEnds = model.graceEnds, graceEnds > now {
                            Text(L("Setup: \(Int(graceEnds.timeIntervalSince(now).rounded(.up))) s left for a story or sound"))
                                .font(.callout).foregroundStyle(.yellow)
                        } else {
                            Text(L("Lock your phone and have a nice rest 🧸")).font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        let pauseEnds = model.pauseEnds(at: now)
                        ConstructionSite(buildingId: rec.buildingId, progress: progress, resting: pauseEnds != nil,
                                         buddy: model.buddyState(at: now))
                            .scaleEffect(compact ? 0.6 : 1, anchor: .top)
                            .frame(height: compact ? 190 : nil, alignment: .top)
                        Text(model.catalog?[rec.buildingId]?.displayName ?? "").font(.headline)
                        if let graceEnds = model.graceEnds, graceEnds > now {
                            let left = Int(graceEnds.timeIntervalSince(now).rounded(.up))
                            Text(left >= 60 ? L("Setup until \(Fmt.time(graceEnds)) (\(Plural.minutes(Double(left))) left)")
                                            : L("Setup: \(left) s left for a podcast or story"))
                                .font(.callout).foregroundStyle(.yellow)
                        } else if let pauseEnds {
                            Text(L("Pause: \(Self.countdown(pauseEnds.timeIntervalSince(now))) left – you can leave SleepHole now"))
                                .font(.callout).foregroundStyle(.yellow).multilineTextAlignment(.center)
                        } else {
                            Text(L("Lock your phone and good night 🌙")).font(.callout).foregroundStyle(.secondary)
                            if let use = model.awayBudgetUse(at: now), use.used >= 1 {
                                Text(L("Out of the app tonight: \(Int(use.used)) s of \(Int(use.budget)) s"))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
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
                    pauseButton(now: now)
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

    /// "🌙 Pause" (D17): shown once the setup is over; the first pause of a night is free, the next ones cost coins.
    @ViewBuilder
    private func pauseButton(now: Date) -> some View {
        let block = model.pauseBlock(at: now)
        let price = model.nextPausePrice
        switch block {
        case .nap?, .collapsed?, .setup?, .running?:
            EmptyView()
        case .notEnoughCoins(let missing)?:
            Text(L("🌙 Next pause: \(price) 🪙 (\(missing) 🪙 short)")).font(.footnote).foregroundStyle(.secondary)
        case nil:
            Button { confirmPause = true } label: {
                Label(price > 0 ? L("Pause · \(price) 🪙") : L("Pause · free"), systemImage: "moon.zzz.fill")
            }
            .buttonStyle(.bordered)
            .confirmationDialog(L("Start a pause?"), isPresented: $confirmPause, titleVisibility: .visible) {
                Button(price > 0 ? L("Start the pause for \(price) 🪙") : L("Start the pause")) { model.startPause() }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(price > 0
                     ? L("For \(Plural.minutes(PausePolicy.duration)) you can leave SleepHole. This pause costs \(price) 🪙.")
                     : L("For \(Plural.minutes(PausePolicy.duration)) you can leave SleepHole. The first pause of a night is free – a night without any pause pays +\(PausePolicy.undisturbedBonus) 🪙."))
            }
        }
    }
}

/// Nap screen: the sleep buddy (it sleeps with you, wakes for the setup and the alarm) and the time left.
struct NapResting: View {
    let progress: Double
    var buddy: BuddyState = .asleep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(spacing: 14) {
            BuddyView(state: buddy).frame(width: 180)
            Text(L("Nap")).font(.headline).foregroundStyle(.yellow)
                .opacity(dimmed ? 0.5 : 1)
                .onAppear {                                  // a slow implicit pulse – no timeline
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: Motion.t(2.5)).repeatForever(autoreverses: true)) { dimmed = true }
                }
            ProgressView(value: progress).tint(.yellow.opacity(0.8)).frame(maxWidth: 200)
        }
    }
}

/// The building under construction + an animated tower crane + a breathing "Stavba prebieha" label.
/// The animation runs only while the night is healthy – it is the visible proof that building goes on.
struct ConstructionSite: View {
    @Environment(SpriteLibrary.self) private var sprites
    let buildingId: String
    let progress: Double
    /// A pause is on (D17): the crane stands still.
    var resting = false
    /// The sleep buddy beside the site (nil = none). It sits OUTSIDE the timeline below, so the 20 fps crane
    /// does not re-draw it, and it scales with the site in the compact morning layout.
    var buddy: BuddyState?
    static let frames = 16
    static let stageSize = CGSize(width: 320, height: 260)
    static let buddyWidth: CGFloat = 110
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
            let frame = resting ? 0 : Int(t / Self.frameDuration) % Self.frames
            let breath = (1 + sin(t * 2 * .pi / 4)) / 2            // 0…1, 4 s period
            VStack(spacing: 14) {
                // Stage: the crane's mast stands behind the building's right side; the pair is centred.
                ZStack(alignment: .bottom) {
                    if let crane = sprites.image(for: String(format: "o-crane-%02d", frame)) {
                        Image(uiImage: crane)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 250)
                            .offset(x: 45 + shift)
                    }
                    BuildingImage(id: siteId, maxHeight: 110)       // building site under the building
                        .frame(width: 190)
                        .offset(x: -40 + shift, y: 6)
                    BuildingImage(id: buildingId, progress: shownProgress, maxHeight: 150)
                        .frame(width: 190)
                        .offset(x: -40 + shift, y: -4)
                }
                .frame(width: Self.stageSize.width, height: Self.stageSize.height)
                Text(resting ? L("Pause – the crane is resting 🌙") : L("Building in progress"))
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
        .overlay {
            // the buddy stands at the bottom-left of the stage, in front of the site's empty corner
            if let buddy {
                GeometryReader { g in
                    let left = (g.size.width - Self.stageSize.width) / 2
                    let h = Self.buddyWidth / BuddyView.boxAspect
                    BuddyView(state: buddy)
                        .frame(width: Self.buddyWidth)
                        .position(x: left - 24 + Self.buddyWidth / 2, y: Self.stageSize.height + 4 - h / 2)
                }
            }
        }
    }

    /// With the buddy the building and the crane move right to make room for it.
    private var shift: CGFloat { buddy == nil ? 0 : 28 }
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
                PreviewButtons(playing: model.sleepSoundPlaying,
                               play: { model.playSleepSound(ambience, minutes: minutes); dismiss() },
                               stop: { model.stopSleepSound() })
            }
            .navigationTitle(L("Sleep sound"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                ambience = model.settings.ambience == .silence ? .brownNoise : model.settings.ambience
                minutes = model.settings.ambienceMinutes             // the last choice, also "All night" (B19)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - alarm

struct AlarmView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // the awake cat greets the owner – left out when it does not fit (small phone, number pad up)
        ViewThatFits(in: .vertical) {
            content(withBuddy: true)
            content(withBuddy: false)
        }
        .padding()
        .preferredColorScheme(.dark)
    }

    private func content(withBuddy: Bool) -> some View {
        VStack(spacing: withBuddy ? 12 : 24) {
            Text(L("Good morning ☀️")).font(.largeTitle.bold())
            if withBuddy { BuddyView(state: model.buddyState()).frame(width: 159) }
            ConfirmPanel()
            Spacer()
        }
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
            Text(L("or enter the code from Settings")).font(.callout).cardCaption()
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
        .glassCard()
        .onShake { model.confirm() }
    }
}

// MARK: - result

struct ResultView: View {
    @Environment(AppModel.self) private var model
    @State private var celebrationClosed = false
    @State private var confetti = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let rec = model.shownResult, let outcome = rec.outcome {
            let name = model.catalog?[rec.buildingId]?.displayName ?? L("building")
            FitOrScroll { _ in
            VStack(spacing: 18) {
                if rec.isNap {
                    Text(verbatim: outcome == .complete ? "😴" : outcome == .unfinished ? "🥱" : "🧸").font(.system(size: 90))
                        .popIn(delay: 0.1)
                    Text(outcome == .complete ? L("Nap complete!") : outcome == .unfinished ? L("Nap cut short")
                         : L("Nap didn't work out")).font(.largeTitle.bold())
                    Text(outcome == .complete ? L("Well rested 💙") : L("No worries, again tomorrow 🌱"))
                        .multilineTextAlignment(.center)
                } else {
                switch outcome {
                case .complete:
                    // the WOW (owner 2026-10-02): rays, the building lands, twinkles burst, then the coins pop
                    ZStack {
                        SunRays().frame(width: 340, height: 340)
                        DustPuff(delay: Motion.landing).frame(width: 340, height: 260)
                        BuildingImage(id: rec.buildingId).dropIn(delay: 0.15)
                        SparkleBurst(delay: Motion.landing + 0.1).frame(width: 340, height: 300)
                    }
                    .frame(height: 260)
                    Text(L("Done! 🎉")).font(.largeTitle.bold()).popIn(delay: 0.6)
                    Text(L("You built: \(name)")).font(.title3).appearIn(delay: 0.8)
                case .unfinished:
                    BuildingImage(id: rec.buildingId, progress: 0.6)
                    Text(L("Unfinished 🚧")).font(.largeTitle.bold())
                    Text(L("\(name) is waiting – your next good night will finish it.")).multilineTextAlignment(.center)
                case .ruins, .missed, .excused:
                    BuildingImage(id: (model.catalog?[rec.buildingId]?.footprint.first ?? 1) == 2 ? "o-ruin-2" : "o-ruin-1")
                    Text(L("Not this time")).font(.largeTitle.bold())
                    Text(L("That's part of the town too – new chance tomorrow 🌱")).multilineTextAlignment(.center)
                }
                }
                if !rec.isDebug, model.lastReward > 0 {
                    VStack(spacing: 2) {
                        Text(verbatim: "+\(model.lastReward) 🪙").font(.title.bold()).foregroundStyle(Color.readableYellow)
                            .popIn(delay: 0.5)
                        if model.lastStreakBonus > 0 {
                            Text(L("including a +\(model.lastStreakBonus) bonus for \(Economy.streakBonusEvery) nights in a row 🔥"))
                                .font(.footnote).cardCaption()
                        }
                        if model.lastUndisturbedBonus > 0 {
                            Text(L("including +\(model.lastUndisturbedBonus) for a night without a pause 🌙"))
                                .font(.footnote).cardCaption()
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
                    .glassCard()
                }
                if outcome == .complete, !rec.isDebug, !rec.isNap { StatusBadges() }
                if let level = model.levelUp {
                    Label(L("Level \(level) unlocked!"), systemImage: "star.fill")
                        .font(.headline).foregroundStyle(Color.readableYellow)
                        .symbolEffect(.bounce, options: .repeat(3))
                }
                if rec.isDebug { Text(L("(quick test night – doesn't count for the town)")).font(.caption).cardCaption() }
                if let at = model.safetyAlarmAt { SafetyAlarmCard(at: at) }
                Button(L("Continue")) { model.acknowledgeResult() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding()
            }
            .navigationTitle(rec.isNap ? L("Nap") : L("Night result"))
            .background {
                // a few seconds of confetti for a finished building (the level-up card has its own)
                if outcome == .complete, !rec.isNap, model.levelUp == nil, confetti, !reduceMotion {
                    ConfettiView().ignoresSafeArea().allowsHitTesting(false).transition(.opacity)
                        .task {
                            try? await Task.sleep(for: .seconds(5))           // owner 2026-10-02: 5 s
                            withAnimation(.easeOut(duration: 1.5)) { confetti = false }
                        }
                }
            }
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
