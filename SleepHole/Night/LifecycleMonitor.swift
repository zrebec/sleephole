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

    static let decisionDelay: Duration = .seconds(3)      // lock signals arrive ~1.6 s after background (device log)
    static let unlockReturnWindow: Duration = .seconds(5)  // lockstate=0 fires on swipe-up; the app is active ~0.8 s later (device log #2)

    private var tokens: [NSObjectProtocol] = []
    private var lastLockSignal: Date?
    private var pendingBackground: Task<Void, Never>?
    private var pendingUnlock: Task<Void, Never>?
    private var isAway = false
    private let callObserver = CXCallObserver()
    private var callDelegate: CallDelegate?
    private var activeCalls = Set<UUID>()
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let nc = NotificationCenter.default
        func observe(_ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }
        observe(UIApplication.willResignActiveNotification) { [weak self] in self?.raw("willResignActive") }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] in self?.didEnterBackground() }
        observe(UIApplication.willEnterForegroundNotification) { [weak self] in self?.raw("willEnterForeground") }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] in self?.didBecomeActive() }
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) { [weak self] in
            self?.raw("protectedDataWillBecomeUnavailable"); self?.lockSignal("protectedData")
        }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) { [weak self] in
            self?.raw("protectedDataDidBecomeAvailable")
        }
        observe(UIApplication.willTerminateNotification) { [weak self] in self?.raw("willTerminate") }

        DarwinNotifications.shared.observe(["com.apple.springboard.lockcomplete",
                                            "com.apple.springboard.lockstate",
                                            "com.apple.springboard.hasBlankedScreen"]) { [weak self] name, state in
            self?.raw("darwin \(name.replacingOccurrences(of: "com.apple.springboard.", with: "")) state=\(state)")
            if name == "com.apple.springboard.lockcomplete" { self?.lockSignal("lockcomplete") }
            // lockstate fires on BOTH lock and unlock – the state tells which (1 = locked, 0 = unlocked)
            if name == "com.apple.springboard.lockstate", state == 0,
               UIApplication.shared.applicationState != .active {
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
        pendingBackground?.cancel(); pendingUnlock?.cancel()
        isRunning = false
        raw("monitor stopped")
    }

    // MARK: - signals

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
            } else if UIApplication.shared.applicationState != .active {
                self.isAway = true
                self.emit(.leftApp, "(background without a lock signal)", at: now)
            }
        }
    }

    private func didBecomeActive() {
        raw("didBecomeActive")
        pendingUnlock?.cancel()
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
            try? await Task.sleep(for: Self.unlockReturnWindow)
            guard let self, !Task.isCancelled else { return }
            if UIApplication.shared.applicationState != .active,
               UIApplication.shared.isProtectedDataAvailable {
                self.isAway = true
                self.emit(.leftApp, "(unlocked but did not return in 5 s)")
            }
        }
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

    func removeAll() {
        tokens.forEach { notify_cancel($0) }
        tokens.removeAll()
    }
}
