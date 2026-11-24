import Observation
import SleepCore
import SwiftUI
import UIKit

// MARK: - brightness

/// The one number the rest screen turns down and gives back.
@MainActor
protocol ScreenBrightness: AnyObject {
    var brightness: CGFloat { get set }
}

/// The brightness of the app's window scene (not the deprecated `UIScreen.main`).
@MainActor
final class SceneScreenBrightness: ScreenBrightness {
    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }
    var brightness: CGFloat {
        get { screen?.brightness ?? 0.5 }
        set { screen?.brightness = newValue }
    }
}

/// Turns the screen down for the rest screen and gives back exactly what it found. The remembered value lives in memory
/// only. A second `dim` while dimmed keeps the first value; `restore` without a `dim` does nothing. A screen that reads
/// brightness 0 is never dimmed – a 0 is never saved and so never restored (13ad). The rest screen is still shown then:
/// the reading is 0 both at a lock (the controller's `appActive` check keeps the rest away there) and, possibly, with the
/// slider at its minimum – where the black screen and the "Lock the phone" line must not be lost.
@MainActor
final class BrightnessDimmer {
    static let level: CGFloat = 0.1
    private let screen: ScreenBrightness
    private var saved: CGFloat?
    /// Diagnostic lines (`bright dim from=80 to=10`, `bright restore to=80`); set by the controller.
    var onDiag: ((String, String?) -> Void)?

    init(screen: ScreenBrightness) { self.screen = screen }

    var isDimmed: Bool { saved != nil }

    /// True when the screen is dimmed afterwards (already was, or now is); false when the reading is 0 and nothing was done.
    @discardableResult
    func dim() -> Bool {
        guard saved == nil else { return true }
        let now = screen.brightness
        guard now > 0 else { onDiag?("bright", "skip at=0"); return false }
        saved = now
        if now > Self.level { screen.brightness = min(now, Self.level) }
        onDiag?("bright", "dim from=\(Self.percent(now)) to=\(Self.percent(min(now, Self.level)))")
        return true
    }

    func restore() {
        guard let value = saved else { return }
        saved = nil
        screen.brightness = value
        onDiag?("bright", "restore to=\(Self.percent(value))")
    }

    private static func percent(_ b: CGFloat) -> Int { Int((min(max(b, 0), 1) * 100).rounded()) }
}

// MARK: - the controller

/// The rest screen's state (13k). The rule is `SleepCore.RestScreen`; this collects the facts, counts touches, dims the
/// screen and publishes `resting`. It is only a look: it writes nothing to the night.
@MainActor
@Observable
final class RestController {
    /// The black rest screen is on.
    private(set) var resting = false

    /// What the model knows (set by `AppModel`).
    struct Night {
        var isBuilding: Bool, setupEnds: Date?, pauseRunning: Bool
    }
    @ObservationIgnored var night: () -> Night = { Night(isBuilding: false, setupEnds: nil, pauseRunning: false) }
    @ObservationIgnored var now: () -> Date = { Date() }
    /// Off in unit tests and in `-screenshot` runs without `-restAfter`.
    @ObservationIgnored var enabled = true
    @ObservationIgnored var delay = RestScreen.defaultDelay
    /// A sheet or dialog of the night screen is open / the wake-code field has the keyboard (set by the views).
    @ObservationIgnored var nightDialogOpen = false
    @ObservationIgnored var codeFieldFocused = false

    @ObservationIgnored private let dimmer: BrightnessDimmer
    @ObservationIgnored private var lastTouch = Date.distantPast
    @ObservationIgnored private var activeSince = Date.distantPast
    @ObservationIgnored private var buildingSince = Date.distantPast
    @ObservationIgnored private var wasBuilding = false
    @ObservationIgnored var sceneActive = true               // internal: unit tests set it (the test host is not active)
    /// The application is really in front (not only the scene flag): a lock or a screen-off keeps `sceneActive` stale for
    /// a moment. Replaced in unit tests.
    @ObservationIgnored var appActive: () -> Bool = { UIApplication.shared.applicationState == .active }
    /// Diagnostic lines of the night's track (`rest on`, `rest off why=…`, `rest blocked why=…`, `bright …`); set by the model.
    @ObservationIgnored var onDiag: ((String, String?) -> Void)? {
        didSet { dimmer.onDiag = onDiag }
    }
    /// The black screen ended by a touch or VoiceOver (not by the volume wake, which comes from a fresh reading).
    @ObservationIgnored var onWoke: (() -> Void)?
    @ObservationIgnored private var blockedNoted: Set<String> = []
    /// Is a view controller presented over the window (sheets, dialogs)? Replaced in unit tests.
    @ObservationIgnored var uikitPresentation: () -> Bool = {
        let root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        return root?.presentedViewController != nil
    }
    @ObservationIgnored private var keyboardUp = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(screen: ScreenBrightness? = nil) {
        dimmer = BrightnessDimmer(screen: screen ?? SceneScreenBrightness())
        sceneActive = UIApplication.shared.applicationState == .active
        let nc = NotificationCenter.default
        func watch(_ name: Notification.Name, _ body: @escaping @MainActor (RestController) -> Void) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            })
        }
        watch(UIApplication.willResignActiveNotification) { c in c.sceneActive = false; c.evaluate() }
        watch(UIApplication.didBecomeActiveNotification) { c in
            c.sceneActive = true; c.activeSince = c.now(); c.evaluate()
        }
        watch(UIAccessibility.voiceOverStatusDidChangeNotification) { c in c.evaluate() }
        watch(UIResponder.keyboardWillShowNotification) { c in c.keyboardUp = true; c.evaluate() }
        watch(UIResponder.keyboardWillHideNotification) { c in c.keyboardUp = false }
        // best effort: never leave the phone dim when the app goes away
        watch(UIApplication.willTerminateNotification) { c in c.dimmer.restore() }
        watch(UIScene.didDisconnectNotification) { c in c.dimmer.restore() }
    }

    /// Any touch in the window. A touch on the rest screen only wakes it.
    func touched() {
        lastTouch = now()
        wake()
    }

    /// The black screen ends (a tap, VoiceOver's activate, the media volume turned down); the 30 s start again.
    func wake(why: String = "touch") {
        lastTouch = now()
        guard resting else { return }
        dimmer.restore()                       // the brightness first, then the picture
        resting = false
        onDiag?("rest", "off why=\(why)")
        if why != "volume" { onWoke?() }
    }

    /// Called every second by the model's ticker and whenever a fact changes.
    func evaluate() {
        let n = now()
        let night = night()
        if night.isBuilding && !wasBuilding { buildingSince = n; blockedNoted = [] }
        wasBuilding = night.isBuilding
        guard enabled else { if resting { stop(why: "disabled") }; return }
        let facts = RestScreen.Facts(isBuilding: night.isBuilding, setupEnds: night.setupEnds,
                                     pauseRunning: night.pauseRunning, sceneActive: sceneActive && appActive(),
                                     voiceOverRunning: UIAccessibility.isVoiceOverRunning,
                                     presentationOpen: presentationOpen)
        let blocker = RestScreen.blocker(facts, now: n)
        if resting {
            if let blocker { stop(why: Self.why(blocker)) }          // a latched state: touches wake it, nothing else
        } else {
            let last = max(lastTouch, activeSince, buildingSince)
            if RestScreen.shouldRest(facts, now: n, lastActivity: last, delay: delay) {
                start()
            } else if let blocker, let setupEnds = night.setupEnds,
                      n.timeIntervalSince(max(last, setupEnds)) >= delay {
                noteBlocked(blocker)                                 // it would be resting now if it could
            }
        }
    }

    private func start() {
        dimmer.dim()                                                 // a reading of 0 is never saved nor dimmed, the rest still shows
        resting = true
        onDiag?("rest", "on")
    }

    private func stop(why: String) {
        dimmer.restore()
        resting = false
        onDiag?("rest", "off why=\(why)")
    }

    private static func why(_ blocker: RestScreen.Blocker) -> String {
        blocker == .presentation ? "sheet" : blocker.rawValue
    }

    /// "rest blocked why=…": once per reason per night, only for the reasons a user can act on.
    private func noteBlocked(_ blocker: RestScreen.Blocker) {
        let reason: String
        switch blocker {
        case .pause: reason = "pause"
        case .voiceOver: reason = "voiceOver"
        case .presentation: reason = (codeFieldFocused || keyboardUp) ? "keyboard" : "sheet"
        case .phase, .inactive: return
        }
        guard blockedNoted.insert(reason).inserted else { return }
        onDiag?("rest", "blocked why=\(reason)")
    }

    private var presentationOpen: Bool {
        if nightDialogOpen || codeFieldFocused || keyboardUp { return true }
        return uikitPresentation()
    }
}

// MARK: - touches

/// Counts every touch in the window without taking any of them: it never recognises, never cancels, never delays.
private final class TouchCounter: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTouch: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { onTouch?() }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { onTouch?() }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
}

/// Puts the touch counter on the app's window (invisible; sits in the background of the root view).
struct RestTouchCatcher: UIViewRepresentable {
    let controller: RestController

    func makeUIView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.isUserInteractionEnabled = false
        v.controller = controller
        return v
    }
    func updateUIView(_ view: CatcherView, context: Context) { view.controller = controller }

    final class CatcherView: UIView {
        var controller: RestController?
        private var counter: TouchCounter?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let counter { counter.view?.removeGestureRecognizer(counter); self.counter = nil }
            guard let window else { return }
            let c = TouchCounter(target: nil, action: nil)
            c.onTouch = { [weak self] in
                MainActor.assumeIsolated { self?.controller?.touched() }
            }
            window.addGestureRecognizer(c)
            counter = c
        }
    }
}

// MARK: - the screen

/// Black, a dim clock and one line. A tap anywhere (or VoiceOver's activate) brings the night screen back.
struct RestScreenView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 64

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let minute = Int(ctx.date.timeIntervalSince1970 / 60)
            let jump = RestScreen.offset(minute: minute)
            let ink = Color.white.opacity(contrast == .increased ? 0.8 : 0.5)
            let time = Fmt.time(ctx.date)
            let line = L("🔒 Lock the phone – it saves the battery")
            ZStack {
                Color.black
                VStack(spacing: 14) {
                    Text(time)
                        .font(.system(size: clockSize, weight: .thin, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(line)
                        .font(.body).multilineTextAlignment(.center)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 24)
                .offset(x: jump.x, y: jump.y)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(time + ". " + line)
                .accessibilityHint(L("Show the night screen"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.rest.wake() }
                .accessibilityIdentifier("restScreen")
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { model.rest.wake() }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
