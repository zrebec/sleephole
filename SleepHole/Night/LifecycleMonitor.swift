import CallKit
import notify
import Foundation
import SleepCore
import UIKit

/// Turns UIKit / system signals into `NightEvent`s (plan §6.2).
///
/// iOS has no public "user locked the phone" API, so several signals are combined:
///  * Darwin notification `com.apple.springboard.lockcomplete` (immediate, undocumented but long-lived)
///  * `protectedDataWillBecomeUnavailable` (documented, but arrives ~10 s after the lock)
///  * `isProtectedDataAvailable` and the screen brightness at the moment of backgrounding
/// On `didEnterBackground` the monitor waits `decisionDelay` and then decides lock vs. left-app.
/// Every raw signal is also reported via `onRaw` for the F2 spike log.
@MainActor
final class LifecycleMonitor {
    var onEvent: ((NightEventKind, Date) -> Void)?
    var onRaw: ((String) -> Void)?
    /// iOS tells the running app that it is about to be terminated: swiped away in the app switcher (owner 2026-10-04,
    /// R4: that counts as leaving the app) or the phone restarts / shuts down. Called synchronously on the main
    /// thread – the process dies right after, so whatever must survive has to be saved before this returns.
    var onTerminate: (() -> Void)?

    static let decisionDelay: Duration = .seconds(3)      // lock signals arrive ~1.6 s after background (device log)
    static let unlockReturnWindow: Duration = .seconds(5)  // lockstate=0 fires on swipe-up; the app is active ~0.8 s later (device log #2)

    /// An idle lock screen switches itself off after ~7 s (device log), so a glance at the clock stays free; a screen
    /// that stays lit for 8 s while the app is not active (and Face ID has recognised the owner) is being used
    /// (camera from the lock screen, widgets, …) → left the app.
    nonisolated static let lockScreenWindow: Duration = .seconds(8)

    // Seams for tests (hosted tests always see the app as active and cannot wait 8 s per case); production defaults.
    var isAppActive: () -> Bool = { UIApplication.shared.applicationState == .active }
    var isProtectedDataAvailable: () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
    var screenWindow: Duration = LifecycleMonitor.lockScreenWindow
    var unlockWindow: Duration = LifecycleMonitor.unlockReturnWindow
    /// A lit lock screen with the phone HELD IN A HAND counts as use after this long, recognised or not (owner
    /// 2026-10-09: filming with the lock-screen camera without Face ID); then it is re-checked every `heldInterval`.
    nonisolated static let lockScreenHeldWindow: Duration = .seconds(12)
    var heldWindow: Duration = LifecycleMonitor.lockScreenHeldWindow
    var heldInterval: Duration = .seconds(1)
    var motion: any HandMotion = CoreMotionHold()

    private var tokens: [NSObjectProtocol] = []
    private var lastLockSignal: Date?
    private var pendingBackground: Task<Void, Never>?
    private var pendingUnlock: Task<Void, Never>?
    private var pendingScreenOn: Task<Void, Never>?
    /// The "lit while held" watch: runs (with the motion sensor) only while the screen is lit, the app is not active and
    /// no trip is open.
    private var pendingHeld: Task<Void, Never>?
    private var isAway = false {
        didSet { if isAway { endHeldWatch() } else { lockTrip = false } }
    }
    /// The open trip began as lock-screen use (`.usedLockScreen`), not as a real leave. An unlock into another app
    /// during such a trip still emits `.leftApp` (in gentle mode the lock-screen trip itself is free).
    private var lockTrip = false
    /// Protected data is locked, as told by the two notifications. `isProtectedDataAvailable` stays true for several
    /// seconds after a lock, so "Face ID has recognised the owner" must come from the notifications, not from that flag.
    private var dataLocked = false
    /// A `.screenOn` was emitted and its `.screenOff` has not been yet.
    private var screenLit = false
    private let callObserver = CXCallObserver()
    private var callDelegate: CallDelegate?
    private var activeCalls = Set<UUID>()
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        dataLocked = !isProtectedDataAvailable()
        screenLit = false
        let nc = NotificationCenter.default
        func observe(_ name: Notification.Name, queue: OperationQueue? = .main, _ handler: @escaping @MainActor () -> Void) {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: queue) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }
        observe(UIApplication.willResignActiveNotification) { [weak self] in self?.raw("willResignActive") }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] in self?.didEnterBackground() }
        observe(UIApplication.willEnterForegroundNotification) { [weak self] in self?.raw("willEnterForeground") }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] in self?.didBecomeActive() }
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) { [weak self] in
            self?.dataProtectionChanged(locked: true)
        }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) { [weak self] in
            self?.dataProtectionChanged(locked: false)
        }
        // `queue: nil` = the block runs in place, on the posting (main) thread, before the notification returns: a hop
        // to the main queue could come too late – the process is about to die
        observe(UIApplication.willTerminateNotification, queue: nil) { [weak self] in
            self?.raw("willTerminate")
            self?.onTerminate?()
        }

        DarwinNotifications.shared.observe(["com.apple.springboard.lockcomplete",
                                            "com.apple.springboard.lockstate",
                                            "com.apple.springboard.hasBlankedScreen"]) { [weak self] name, state in
            self?.raw("darwin \(name.replacingOccurrences(of: "com.apple.springboard.", with: "")) state=\(state)")
            if name == "com.apple.springboard.lockcomplete" { self?.lockSignal("lockcomplete") }
            if name == "com.apple.springboard.hasBlankedScreen" { self?.screenChanged(blanked: state == 1) }
            // lockstate fires on BOTH lock and unlock – the state tells which (1 = locked, 0 = unlocked)
            if name == "com.apple.springboard.lockstate", state == 0,
               self?.isAppActive() == false {
                self?.unlockCandidate()
            }
        }

        let delegate = CallDelegate { [weak self] call in self?.callChanged(call) }
        callDelegate = delegate
        callObserver.setDelegate(delegate, queue: .main)
        raw("monitor started · protectedData=\(UIApplication.shared.isProtectedDataAvailable)")
    }

    func stop() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        DarwinNotifications.shared.removeAll()
        callObserver.setDelegate(nil, queue: nil)
        pendingBackground?.cancel(); pendingUnlock?.cancel(); pendingScreenOn?.cancel()
        endHeldWatch()
        isRunning = false
        raw("monitor stopped")
    }

    // MARK: - signals

    /// The two protected-data notifications. Every lock / screen-off posts "will become unavailable" at once; a wake that
    /// Face ID recognises posts "did become available" ~0.5 s after the screen comes on (sometimes twice). Only a real
    /// change of the state is reported.
    func dataProtectionChanged(locked: Bool) {
        raw(locked ? "protectedDataWillBecomeUnavailable" : "protectedDataDidBecomeAvailable")
        let changed = dataLocked != locked
        dataLocked = locked
        if changed { emit(locked ? .dataLocked : .ownerRecognised, "") }
        // Face ID recognised the owner only AFTER the window ran out (a tap on a widget, …): the lit screen is being used
        // → the trip starts now. A recognition inside the window is left to the check at its end.
        if changed, !locked, screenLit, pendingScreenOn == nil, !isAway, !isAppActive() {
            isAway = true; lockTrip = true
            emit(.usedLockScreen, "(recognised after the window)")
        }
        if locked { lockSignal("protectedData") }
    }

    private func lockSignal(_ source: String) {
        lastLockSignal = Date()
        if isAway {                       // left the app, then locked → away interval ends at the lock
            isAway = false
            emit(.locked, "(\(source), ends away)")
        }
    }

    private func didEnterBackground() {
        let now = Date()
        let brightness = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.brightness }.first ?? -1
        raw(String(format: "didEnterBackground · protectedData=%@ · brightness=%.2f · calls=%d",
                   UIApplication.shared.isProtectedDataAvailable ? "yes" : "no", brightness, activeCalls.count))
        pendingBackground?.cancel()
        pendingBackground = Task { [weak self] in
            try? await Task.sleep(for: Self.decisionDelay)
            guard let self, !Task.isCancelled else { return }
            self.pendingBackground = nil
            if let lock = self.lastLockSignal, abs(lock.timeIntervalSince(now)) < 2.5 {
                self.emit(.locked, "(background by lock)", at: now)
            } else if !self.isAppActive() {
                self.isAway = true
                self.emit(.leftApp, "(background without a lock signal)", at: now)
            }
        }
    }

    private func didBecomeActive() {
        raw("didBecomeActive")
        pendingUnlock?.cancel()
        pendingScreenOn?.cancel(); pendingScreenOn = nil
        endHeldWatch()
        screenLit = false                 // while the app is active no `.screenOff` is owed
        if pendingBackground != nil {     // came back before the decision → nothing happened
            pendingBackground?.cancel(); pendingBackground = nil
            raw("(short background ignored)")
            return
        }
        isAway = false
        emit(.returned, "")
    }

    /// The phone was unlocked while our app sat in the background after a lock. If the app does not
    /// become active within `unlockReturnWindow`, the owner is using the phone elsewhere (lock-screen
    /// notifications, camera, …) → left the app, stamped at the END of the window (the window is free).
    func unlockCandidate() {
        emit(.unlocked, "(lockstate=0 while inactive)")
        pendingUnlock?.cancel()
        pendingUnlock = Task { [weak self] in
            try? await Task.sleep(for: self?.unlockWindow ?? Self.unlockReturnWindow)
            guard let self, !Task.isCancelled else { return }
            // `isAway`: another path (lit lock screen, background) has already reported the trip – no second `.leftApp`,
            // unless that trip is only lock-screen use: unlocking into another app is a real leave (care-not-enforcement
            // mode, owner 2026-10-09 – the lock-screen trip itself may be free)
            if !self.isAway || self.lockTrip, !self.isAppActive(), self.isProtectedDataAvailable() {
                self.isAway = true; self.lockTrip = false
                self.emit(.leftApp, "(unlocked but did not return in 5 s)")
            }
        }
    }

    /// `hasBlankedScreen`: the screen went off (`blanked`) or came on. With the phone locked and the app in the
    /// background, a screen that stays lit for `screenWindow` with Face ID done means the owner is using the lock
    /// screen (camera, …): left the app, stamped at the END of the window. It ends with the screen going off.
    func screenChanged(blanked: Bool) {
        if blanked {
            pendingScreenOn?.cancel(); pendingScreenOn = nil
            endHeldWatch()
            if screenLit { screenLit = false; emit(.screenOff, "") }       // before the `.locked` below
            // the `protectedDataWillBecomeUnavailable` lock signal may fire at the same moment: `isAway` makes sure
            // that exactly one of the two emits `.locked`
            if isAway, !isAppActive() {
                isAway = false
                emit(.locked, "(screen off, ends away)")
            }
            return
        }
        if !isAppActive(), !screenLit { screenLit = true; emit(.screenOn, "") }
        guard !isAppActive(), !isAway else { return }
        if pendingHeld == nil { startHeldWatch() }
        pendingScreenOn?.cancel()
        pendingScreenOn = Task { [weak self] in
            try? await Task.sleep(for: self?.screenWindow ?? Self.lockScreenWindow)
            guard let self, !Task.isCancelled else { return }
            self.pendingScreenOn = nil
            let active = self.isAppActive(), recognised = !self.dataLocked
            self.raw("screen on for \(Int(Self.lockScreenWindow.components.seconds)) s · active=\(active) · protectedData=\(self.isProtectedDataAvailable()) · recognised=\(recognised)")
            if !active, !self.isAway, recognised {
                self.isAway = true; self.lockTrip = true
                self.emit(.usedLockScreen, "(screen on while locked)")
            }
        }
    }

    /// Lit for `heldWindow` without a break, app not active, no trip open, phone in a hand → used the lock screen,
    /// whether or not Face ID recognised anyone. Whichever path reports the trip first wins (`isAway`).
    private func startHeldWatch() {
        motion.start()
        pendingHeld = Task { [weak self] in
            try? await Task.sleep(for: self?.heldWindow ?? Self.lockScreenHeldWindow)
            while let self, !Task.isCancelled {
                guard self.screenLit, !self.isAppActive(), !self.isAway else { self.endHeldWatch(); return }
                let held = self.motion.isHeld()
                let numbers = self.motion.describe()
                self.raw("lit \(Int(Self.lockScreenHeldWindow.components.seconds)) s · held=\(held)" + (numbers.isEmpty ? "" : " · \(numbers)"))
                if held {
                    self.isAway = true; self.lockTrip = true      // also ends the watch
                    self.emit(.usedLockScreen, "(lit 12 s while held)")
                    return
                }
                try? await Task.sleep(for: self.heldInterval)
            }
        }
    }

    private func endHeldWatch() {
        pendingHeld?.cancel(); pendingHeld = nil
        motion.stop()
    }

    func callChanged(_ call: CallInfo) {
        raw("call \(call.uuid.uuidString.prefix(4)) outgoing=\(call.isOutgoing) connected=\(call.hasConnected) ended=\(call.hasEnded)")
        if call.hasEnded {
            if activeCalls.remove(call.uuid) != nil, activeCalls.isEmpty { emit(.callEnded, "") }
        } else if activeCalls.insert(call.uuid).inserted, activeCalls.count == 1 {
            emit(.callStarted, "")
        }
    }

    // MARK: - output

    private func raw(_ text: String) { onRaw?(text) }

    private func emit(_ kind: NightEventKind, _ note: String, at date: Date = Date()) {
        onRaw?("→ \(kind.rawValue) \(note)")
        onEvent?(kind, date)
    }
}

struct CallInfo: Sendable {
    let uuid: UUID, isOutgoing: Bool, hasConnected: Bool, hasEnded: Bool
}

private final class CallDelegate: NSObject, CXCallObserverDelegate, @unchecked Sendable {
    let handler: @MainActor (CallInfo) -> Void
    init(_ handler: @escaping @MainActor (CallInfo) -> Void) { self.handler = handler }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let info = CallInfo(uuid: call.uuid, isOutgoing: call.isOutgoing,
                            hasConnected: call.hasConnected, hasEnded: call.hasEnded)
        let handler = self.handler
        MainActor.assumeIsolated { handler(info) }
    }
}

/// Darwin notify center via `notify_register_dispatch` (gives access to the notification's state).
@MainActor
final class DarwinNotifications {
    static let shared = DarwinNotifications()
    private var tokens: [Int32] = []

    func observe(_ names: [String], handler: @escaping @MainActor (String, UInt64) -> Void) {
        removeAll()
        for name in names {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, .main) { token in
                var state: UInt64 = 0
                notify_get_state(token, &state)
                MainActor.assumeIsolated { handler(name, state) }
            }
            if status == NOTIFY_STATUS_OK { tokens.append(token) }
        }
    }

    /// The current state of a Darwin notification (0 when nobody has posted one yet), read without observing it.
    static func currentState(of name: String) -> UInt64 {
        var token: Int32 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return 0 }
        defer { notify_cancel(token) }
        var state: UInt64 = 0
        notify_get_state(token, &state)
        return state
    }

    func removeAll() {
        tokens.forEach { notify_cancel($0) }
        tokens.removeAll()
    }
}
