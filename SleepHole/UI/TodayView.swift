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
            // the long result screen has its own "Continue"; the bar hid it on 6.1" phones (B38). Set on the content
            // inside this tab's NavigationStack, so it affects only Today and the bar returns when the phase leaves .result
            .toolbarVisibility(model.phase == .result ? .hidden : .automatic, for: .tabBar)
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
    @State private var confirmEarly = false
    /// The hero cat: 50 % of the screen width (200 pt on a 402 pt wide phone), at most this wide.
    static let buddyMaxWidth: CGFloat = 200

    /// The start of the minute containing `d`.
    static func minuteStart(_ d: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (d.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    var body: some View {
        // Ticks aligned to whole minutes (:00 and :30), so the caption's setup time and the buttons that open at
        // whole minutes switch exactly when the clock's minute changes (owner 2026-10-23, B37).
        TimelineView(.periodic(from: Self.minuteStart(.now), by: 30)) { ctx in
            let now = ctx.date
            let w = model.window
            let canSleep = model.phase == .canStart
            let early = model.canStartEarly
            let napReason = model.napBlockReason(at: now)
            ScrollView {
                VStack(spacing: 16) {
                    if let expiry = AppExpiry.date, AppExpiry.isSoon(at: now) { ExpiryCard(expiry: expiry, now: now) }
                    if let at = model.safetyAlarmAt, at > now { SafetyAlarmCard(at: at) }
                    if model.showsChangeWeekCard { ChangeWeekCard().appearIn(delay: 0) }
                    StatusBadges().appearIn(delay: 0.05)
                    // the hero (plan P2b): only the cat – the town has its own tab. A tap pets it (purr, arched back, wink).
                    // Centred on cat + bed (the canvas is not centred on them); the arch's tail reaches above the box,
                    // the cloud below it.
                    BuddyView.centred(
                        BuddyView(state: model.buddyState(at: now), cloud: true, onPet: { model.petBuddy() },
                                  hold: AppModel.forcedBuddyReaction, outfit: model.buddyOutfit)
                            .containerRelativeFrame(.horizontal) { w, _ in min(Self.buddyMaxWidth, w * 0.5) })
                        .overlay(alignment: .top) {
                            // the buddy talks (phase TALK): an overlay, so Today's layout does not change
                            BuddyBubble(now: now)
                                .containerRelativeFrame(.horizontal) { w, _ in min(330, w - 32) }
                                .offset(y: 80)
                        }
                        .padding(.top, 25)
                        .padding(.bottom, 14)
                        .appearIn(delay: 0.1)

                    VStack(spacing: 10) {
                        Text(L("Bedtime \(Fmt.time(w.bedtime)) · wake-up \(Fmt.time(w.wake))"))
                            .font(.headline)
                        actionButton(early ? L("🌙 Go to sleep early today") : L("🌙 Go to sleep"),
                                     enabled: canSleep || early, prominent: true) {
                            if model.needsFirstNightBriefing { briefing = true }
                            else if early { confirmEarly = true }        // an early start asks first
                            else { model.startNight() }
                        }
                        .confirmationDialog(L("Go to sleep now?"), isPresented: $confirmEarly, titleVisibility: .visible) {
                            Button(L("Start tonight's building")) { model.startNight(early: true) }
                            Button(L("Not yet"), role: .cancel) {}
                        } message: {
                            Text(L("Your bedtime is at \(Fmt.time(w.bedtime)), so tonight you'll be without your phone for longer. You have \(Plural.minutes(SleepRules().earlySetup)) from now to set up; your alarm rings at \(Fmt.time(w.wake)) as always."))
                        }
                        Text(sleepCaption(canSleep: canSleep, early: early, played: model.tonightPlayed, now: now, w: w))
                            .font(.subheadline).cardCaption().multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        actionButton(L("😴 Nap (\(model.settings.nap.minutes) min)"), enabled: napReason == nil,
                                     prominent: false) { model.startNap() }
                        Text(napReason ?? L("Until \(Fmt.time(model.settings.nap.windowEnd)) · a complete nap earns +\(NapPlan.reward(.complete)) 🪙"))
                            .font(.subheadline).cardCaption().multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .glassCard(cornerRadius: 28)
                    .appearIn(delay: 0.15)

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
            .sheet(isPresented: $briefing) { FirstNightBriefing(early: model.canStartEarly) }
        }
        .navigationTitle(L("Today"))
        .timeSensitiveWarning()                           // the warning triangle top left (only while the switch is off)
        .todayWeather()                                   // the weather badge top right + the refresh loop
    }

    /// The setup end shown in the caption: if the night started now (canSleep means `now` is in the normal start
    /// window, never an early start), so it follows a start after bedtime (owner 2026-10-23, B37).
    static func captionSetupEnd(now: Date, w: NightWindow, rules: SleepRules) -> Date {
        w.setupEnds(start: now, rules: rules)
    }

    private func sleepCaption(canSleep: Bool, early: Bool, played: Bool, now: Date, w: NightWindow) -> String {
        if early {
            return L("Tired already? You can start tonight's building now – the night without your phone will just be longer. Your alarm stays at \(Fmt.time(w.wake)).")
        }
        if canSleep {
            return L("Start building by \(Fmt.time(w.startCloses(model.nextNightRules))). You have until \(Fmt.time(Self.captionSetupEnd(now: now, w: w, rules: model.nextNightRules))) to set up (podcast, bedtime story), then keep SleepHole open and lock your phone.")
        }
        if now > w.startCloses(model.nextNightRules) {
            return L("It's too late to build tonight 🌙 Tomorrow from \(Fmt.time(w.startOpens)).")
        }
        if played {
            return L("You've already built tonight 🌙 You can build again tomorrow from \(Fmt.time(w.startOpens)).")
        }
        return L("You can build from \(Fmt.time(w.startOpens)) to \(Fmt.time(w.startCloses(model.nextNightRules))) · early start from \(Fmt.time(w.earlyStartOpens))")
    }

    @ViewBuilder
    private func actionButton(_ title: String, enabled: Bool, prominent: Bool, action: @escaping () -> Void) -> some View {
        // `.disabled` goes last: the button style reads `isEnabled` to draw its calm disabled look
        Button(action: action) {
            Text(title).font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 0)
        }
        .controlSize(.large)
        .glassButton(prominent: prominent)
        .tint(prominent ? .indigo : .teal)
        .disabled(!enabled)
    }
}

/// Shown once when a schedule lock has ended (owner 2026-10-15): "does your bedtime still fit?" – a new change week
/// can be opened now.
struct ChangeWeekCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("You can open a change week again 🌙")).font(.headline)
            Text(L("Does your bedtime still fit?")).font(.subheadline)
            HStack {
                Button(L("It fits")) { model.answerChangeWeekCard(adjust: false) }
                    .buttonStyle(.bordered)
                Spacer()
                Button(L("Adjust")) { model.answerChangeWeekCard(adjust: true) }
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

/// iOS's "Time Sensitive Notifications" switch is off: the warnings could stay silent during a Focus. Today shows only
/// this triangle (top left, the mirror of the weather badge); a tap opens Settings at the notifications section.
/// Switch on: no bar item at all (an empty one would leave an empty capsule on iOS 26).
struct TimeSensitiveWarningModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.toolbar {
            if model.timeSensitiveOff {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showNotificationSettings() } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                    .tint(.orange)
                    .accessibilityLabel(L("Time Sensitive Notifications are off"))
                }
            }
        }
    }
}

extension View {
    func timeSensitiveWarning() -> some View { modifier(TimeSensitiveWarningModifier()) }
}

// MARK: - night

/// The full-height layout when everything fits; scrolls only when it does not (e.g. with the confirm panel on a
/// small phone, or with the keyboard up). A plain ScrollView made the night screen narrow and always scrollable
/// (owner 2026-09-30). It is ONE ScrollView with ONE view identity: an earlier `ViewThatFits` switched between a fixed
/// and a scrolling copy when the keyboard appeared, so the confirm panel was rebuilt and its code field lost
/// its text and focus (bug B31, 2026-10-15).
struct FitOrScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                MinHeightLayout(minHeight: geo.size.height) { content() }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

/// Gives its single child at least `minHeight` – by PROPOSING that height, so a `Spacer` inside it really expands
/// (a plain `.frame(minHeight:)` would only enlarge the frame around the child). Taller content keeps its own height;
/// content that does not fill the space is centred.
private struct MinHeightLayout: Layout {
    let minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: max(ideal.height, minHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        // content without a Spacer stays centred, as `ViewThatFits` did (the result screen); with one it fills
        let size = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: bounds.height))
        child.place(at: CGPoint(x: bounds.minX, y: bounds.minY + max(0, bounds.height - size.height) / 2),
                    anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}

struct NightView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmAbandon = false
    @State private var soundSheet = false
    @State private var confirmPause = false
    @State private var confirmReroll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                FitOrScroll {
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
                            Text(L("Setup: \(Int(graceEnds.timeIntervalSince(now).rounded(.up)))s left for a story or sound"))
                                .font(.callout).foregroundStyle(.yellow)
                        } else {
                            Text(L("Lock your phone and have a nice rest 🧸")).font(.callout).foregroundStyle(.secondary)
                            budgetNote(now: now, warningsOnly: true)
                        }
                    } else {
                        let pauseEnds = model.pauseEnds(at: now)
                        ConstructionSite(buildingId: rec.buildingId, progress: progress, resting: pauseEnds != nil,
                                         buddy: model.buddyState(at: now), startedAt: rec.startedAt)
                            .id(rec.buildingId)
                            .transition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: Motion.t(0.5)), value: rec.buildingId)
                            .scaleEffect(compact ? 0.6 : 1, anchor: .top)
                            .frame(height: compact ? 190 : nil, alignment: .top)
                        let buildingName = model.catalog?[rec.buildingId]?.displayName ?? ""
                        let inSetup = model.graceEnds.map { $0 > now } ?? false
                        if inSetup && model.isNewInTown(rec) {
                            // same line as the name – nothing below may move during the setup (11b6 lesson)
                            HStack(spacing: 8) {
                                Text(buildingName).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                                Text(L("New in town")).font(.caption.weight(.semibold)).lineLimit(1)
                                    .foregroundStyle(.black).padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.yellow))
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(buildingName + ", " + L("New in town"))
                        } else {
                            Text(buildingName).font(.headline)
                        }
                        if let graceEnds = model.graceEnds, graceEnds > now {
                            let left = Int(graceEnds.timeIntervalSince(now).rounded(.up))
                            Text(left >= 60 ? L("Setup until \(Fmt.time(graceEnds)) (\(Plural.minutes(Double(left))) left)")
                                            : L("Setup: \(left)s left for a podcast or story"))
                                .font(.callout).foregroundStyle(.yellow)
                            rerollSection(now: now)
                        } else if let pauseEnds {
                            Text(L("Pause: \(Self.countdown(pauseEnds.timeIntervalSince(now))) left – you can leave SleepHole now"))
                                .font(.callout).foregroundStyle(.yellow).multilineTextAlignment(.center)
                        } else {
                            Text(L("Lock your phone and good night 🌙")).font(.callout).foregroundStyle(.secondary)
                            budgetNote(now: now)
                        }
                    }
                    Text(L("Alarm at \(Fmt.time(rec.wake))")).font(.footnote).foregroundStyle(.secondary)
                    if now < rec.window.confirmOpens {
                        if let at = model.earlyShakeAt, now.timeIntervalSince(at) < AppModel.earlyShakeNoteSeconds {
                            Text(L("Too early 🌙 Getting up can be confirmed from \(Fmt.time(rec.window.confirmOpens))."))
                                .font(.footnote.weight(.semibold)).foregroundStyle(.orange).multilineTextAlignment(.center)
                        } else {
                            Text(L("You can confirm getting up from \(Fmt.time(rec.window.confirmOpens)) – shake your phone or enter your code."))
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
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
                    Spacer(minLength: 0)
                    Button(rec.isNap ? L("End nap") : L("Cancel night"), role: .destructive) { confirmAbandon = true }
                        .font(.footnote)
                        .confirmationDialog(rec.isNap ? L("End the nap? It won't earn coins.")
                                                      : L("End tonight early? The building stays as a ruin – a good night repairs it later 🛠️"),
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
        .onShake { model.shakeBeforeConfirm() }
    }

    /// Seconds out of the app tonight (owner 2026-10-08): a grey footnote while there is plenty of budget, an orange
    /// notice when the next trip may be the last, and when it is used up. Naps show only the two notices.
    @ViewBuilder
    private func budgetNote(now: Date, warningsOnly: Bool = false) -> some View {
        if let use = model.awayBudgetUse(at: now), use.used >= 1 {
            switch model.awayBudgetState(at: now) {
            case .low:
                Text(L("Out of the app tonight: \(Int(use.used))s of \(Int(use.budget))s – the next trip may be your last 🌙"))
                    .font(.footnote.weight(.semibold)).foregroundStyle(.orange).multilineTextAlignment(.center)
            case .spent:
                Text(L("Tonight's \(Int(use.budget))s out of the app are used up – please stay with SleepHole now: one more trip and tonight's building comes down 🌙"))
                    .font(.callout.weight(.semibold)).foregroundStyle(.orange).multilineTextAlignment(.center)
            default:
                if !warningsOnly {
                    Text(L("Out of the app tonight: \(Int(use.used))s of \(Int(use.budget))s"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Another building" (build 11b6): during the setup a different building can be drawn for coins.
    @ViewBuilder
    private func rerollSection(now: Date) -> some View {
        switch model.rerollOffer(at: now) {
        case .available(let price, let left)?:
            Button { confirmReroll = true } label: {
                Label(price > 0 ? L("Another building · \(price) 🪙") : L("Another building · free (test night)"),
                      systemImage: "dice")
            }
            .buttonStyle(.bordered)
            .task {
                #if DEBUG
                if DevArgs.list.contains("-rerollDialog") { try? await Task.sleep(for: .seconds(2)); confirmReroll = true }
                #endif
            }
            .confirmationDialog(L("Draw another building for \(price) 🪙?"), isPresented: $confirmReroll,
                                titleVisibility: .visible) {
                Button(price > 0 ? L("Draw for \(price) 🪙") : L("Draw (free)")) { model.rerollBuilding() }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(L("Tonight's building changes at once. The coins are spent even if the night does not work out.")
                     + " " + (left == 1 ? L("This is tonight's last draw.") : L("At most \(Reroll.maxPerNight) draws a night.")))
            }
        case .notEnoughCoins(let price)?:
            Text(L("Not enough coins for another building (\(price) 🪙)")).font(.footnote).foregroundStyle(.secondary)
        case .usedUp?:
            Text(L("No more draws tonight 🎲")).font(.footnote).foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    /// "🌙 Pause" (D17): shown once the setup is over; the first pause of a night is free, the next ones cost coins.
    @ViewBuilder
    private func pauseButton(now: Date) -> some View {
        let block = model.pauseBlock(at: now)
        let price = model.nextPausePrice
        switch block {
        case .nap?, .collapsed?, .setup?, .running?:
            EmptyView()
        case .tooLate(let opens)?:
            // only until confirming opens – afterwards the line would be stale ("from 6:30" at 6:40)
            if now < opens {
                Text(L("A pause no longer fits – you can confirm getting up from \(Fmt.time(opens))."))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
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
            ProgressView(value: progress).progressViewStyle(ThickProgressStyle()).frame(maxWidth: 240)
        }
    }
}

/// A taller progress bar (10h, owner 2026-10-23): a 12 pt capsule, yellow fill on a soft translucent track.
/// Used with `ProgressView(value:)`, so VoiceOver still reads the percentage.
struct ThickProgressStyle: ProgressViewStyle {
    static let height: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        let f = min(1, max(0, configuration.fractionCompleted ?? 0))
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.yellow.opacity(0.8))
                    .frame(width: max(Self.height, g.size.width * f))
                    .opacity(f > 0 ? 1 : 0)
            }
        }
        .frame(height: Self.height)
        .animation(.linear(duration: 0.9), value: f)
    }
}

/// Where the construction scaffold goes over a building on the night screen (10h). Pure, so it is unit-tested.
enum ScaffoldGeometry {
    /// The scaffold's frame in the building image's own coordinates (origin top-left, points). All sprites share one
    /// points-per-pixel scale, so the scaffold is drawn at the building's scale (the shown width / its pixel width) and
    /// the two ground anchors (SpriteKit anchors, y from the bottom) land on the same point.
    static func frame(buildingSize: CGSize, buildingPx: [Int], buildingAnchor: [Double],
                      scaffoldPx: [Int], scaffoldAnchor: [Double]) -> CGRect {
        let s = buildingSize.width / CGFloat(max(1, buildingPx[0]))
        let w = CGFloat(scaffoldPx[0]) * s, h = CGFloat(scaffoldPx[1]) * s
        let groundX = CGFloat(buildingAnchor[0]) * CGFloat(buildingPx[0]) * s
        let groundY = (1 - CGFloat(buildingAnchor[1])) * CGFloat(buildingPx[1]) * s
        return CGRect(x: groundX - CGFloat(scaffoldAnchor[0]) * w, y: groundY - (1 - CGFloat(scaffoldAnchor[1])) * h,
                      width: w, height: h)
    }

    /// The scaffold stays while the building time runs and fades when it is over.
    static func isVisible(progress: Double) -> Bool { progress < 1 }

    /// Only a screen that appears right after the start lets the scaffold grow; later it is simply there.
    static func growsOnAppear(startedAt: Date?, now: Date) -> Bool {
        guard let startedAt else { return false }
        let d = now.timeIntervalSince(startedAt)
        return d >= -1 && d < 10
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

    /// The night's start: a screen that appears right after it lets the scaffold grow (10h); nil = no growth.
    var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scaffoldReveal: Double

    init(buildingId: String, progress: Double, resting: Bool = false, buddy: BuddyState? = nil, startedAt: Date? = nil) {
        self.buildingId = buildingId
        self.progress = progress
        self.resting = resting
        self.buddy = buddy
        self.startedAt = startedAt
        _scaffoldReveal = State(initialValue: ScaffoldGeometry.growsOnAppear(startedAt: startedAt, now: Date()) ? 0 : 1)
    }

    /// The scaffold over the building, anchors on the same ground point and at the building's scale (plan §3.3).
    @ViewBuilder private var scaffold: some View {
        let fp = sprites.catalog?[shownBuildingId]?.footprint.first ?? 1
        let id = fp == 2 ? "o-scaffold-2" : "o-scaffold-1"
        if let b = sprites.catalog?[shownBuildingId], let sc = sprites.catalog?[id], let image = sprites.image(for: id) {
            GeometryReader { g in
                let r = ScaffoldGeometry.frame(buildingSize: g.size, buildingPx: b.size, buildingAnchor: b.anchor,
                                               scaffoldPx: sc.size, scaffoldAnchor: sc.anchor)
                let visible = ScaffoldGeometry.isVisible(progress: shownProgress)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: r.width, height: r.height)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(width: r.width, height: r.height * max(0.001, scaffoldReveal))
                    }
                    .opacity(visible ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: Motion.t(1)), value: visible)
                    .offset(x: r.minX, y: r.minY)
                    .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard scaffoldReveal < 1 else { return }
                if reduceMotion { scaffoldReveal = 1 } else {
                    withAnimation(.easeOut(duration: Motion.t(1))) { scaffoldReveal = 1 }
                }
            }
        }
    }

    private var siteId: String {
        (sprites.catalog?[shownBuildingId]?.footprint.first ?? 1) == 2 ? "o-site-2" : "o-site-1"
    }

    /// Dev aid: `-previewBuilding l3-police` overrides the building (screenshots).
    private var shownBuildingId: String { DevArgs.value(after: "-previewBuilding") ?? buildingId }

    /// Dev aid: `-previewProgress 0.6` overrides the progress (screenshots).
    private var shownProgress: Double {
        let args = DevArgs.list
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
                    BuildingImage(id: shownBuildingId, progress: shownProgress, maxHeight: 150)
                        .overlay { scaffold }                       // in front of the building, like in the town
                        .frame(width: 190)
                        .offset(x: -40 + shift, y: -4)
                }
                .frame(width: Self.stageSize.width, height: Self.stageSize.height)
                Text(resting ? L("Pause – the crane is resting 🌙") : L("Building in progress"))
                    .font(.headline)
                    .foregroundStyle(.yellow)
                    .opacity(0.45 + 0.55 * breath)
                    .scaleEffect(0.97 + 0.06 * breath)
                ProgressView(value: shownProgress)
                    .progressViewStyle(ThickProgressStyle())
                    .frame(maxWidth: 260)
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
    @FocusState private var codeFocused: Bool

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
                    .focused($codeFocused)
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
        .onAppear {
            // Debug aid for the simulator (B31 proof): focus the code field so the software keyboard shows up
            if DevArgs.list.contains("-focusWakeCode") { codeFocused = true }
        }
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
            FitOrScroll {
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
                    if !rec.isNap, let b = model.townBuilding(for: rec.window.key), Population.residents(of: b) > 0 {
                        Label(L("\(Population.residents(of: b)) people moved in"), systemImage: "person.2.fill")
                            .font(.subheadline).foregroundStyle(.secondary).appearIn(delay: 1.0)
                    }
                case .unfinished:
                    BuildingImage(id: rec.buildingId, progress: 0.6)
                    Text(L("Unfinished 🚧")).font(.largeTitle.bold())
                    Text(L("\(name) is waiting – your next good night will finish it.")).multilineTextAlignment(.center)
                    if let late = rec.window.minutesLate(confirmedAt: rec.confirmedAt), !rec.isNap {
                        Text(L("You confirmed \(Plural.minutes(TimeInterval(late) * 60)) after the alarm – within \(Plural.minutes(NightWindow.onTimeConfirm)) the building would be complete."))
                            .font(.footnote).cardCaption().multilineTextAlignment(.center)
                    }
                case .ruins, .missed, .excused:
                    BuildingImage(id: (model.catalog?[rec.buildingId]?.footprint.first ?? 1) == 2 ? "o-ruin-2" : "o-ruin-1")
                    Text(L("Not this time")).font(.largeTitle.bold())
                    Text(L("That's part of the town too – new chance tomorrow 🌱")).multilineTextAlignment(.center)
                }
                }
                if !rec.isDebug, model.lastReward > 0 {
                    VStack(spacing: 8) {
                        Text(verbatim: "+\(model.lastReward) 🪙").font(.title.bold()).foregroundStyle(Color.readableYellow)
                            .popIn(delay: 0.5)
                        if !rec.isNap, let receipt = model.lastReceipt { CoinReceiptView(receipt: receipt).appearIn(delay: 0.8) }
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


// MARK: - coin receipt (11a)

/// The night's coins, one line per part like a shop receipt, so nobody has to ask "why 370?".
struct CoinReceiptView: View {
    let receipt: Economy.Receipt
    @Environment(\.dynamicTypeSize) private var typeSize

    /// One row: label left, amount right; at accessibility sizes the amount goes under the label so nothing wraps mid-word.
    @ViewBuilder private func row(_ label: Text, _ amount: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                label.fixedSize(horizontal: false, vertical: true)
                Text(verbatim: amount).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                label.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: amount).monospacedDigit().fixedSize()
            }
        }
    }

    private func icon(_ kind: Economy.Receipt.Kind) -> String {
        switch kind {
        case .building, .unfinishedBuilding: "🏠"
        case .withoutPause, .calmHours: "🌙"
        case .streak: "🔥"
        case .luckyNight: "🍀"
        case .achievements: "🏆"
        }
    }

    private func text(_ kind: Economy.Receipt.Kind) -> String {
        switch kind {
        case .building(let level): L("Building, level \(level)")
        case .unfinishedBuilding(let level): L("Unfinished building, level \(level) (half)")
        case .withoutPause: L("Without a pause")
        case .calmHours(let calm, let total): L("Calm hours \(calm) of \(total)")
        case .streak(let run): L("Night \(run) in a row")
        case .luckyNight: L("Lucky night ×2")
        case .achievements: L("Achievements")
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(receipt.lines.enumerated()), id: \.offset) { _, line in
                row(Text(verbatim: "\(icon(line.kind)) \(text(line.kind))"), "+\(line.amount) 🪙")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(text(line.kind)), plus \(line.amount) coins"))
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.cardCaption)
        .padding(.horizontal, 24)
        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 320)
    }
}
