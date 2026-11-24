#if DEBUG   // developer screen: not part of Release builds
import AudioToolbox
import Foundation
import Observation
import UIKit

/// Step 13s (W3): the timing of the "does the phone vibrate in the background?" test – pure, so it can be unit-tested.
enum BackgroundVibrationProbe {
    enum Kind: String, CaseIterable, Equatable {
        case systemVibrate      // AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        case alertVibrate       // AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        case coreHaptics        // the app's own Haptics.play(.start)
        case stop               // the keep-alive audio is stopped, the test is over

        var logName: String {
            switch self {
            case .systemVibrate: "AudioServicesPlaySystemSound(Vibrate)"
            case .alertVibrate: "AudioServicesPlayAlertSound(Vibrate)"
            case .coreHaptics: "Haptics.play(.start)"
            case .stop: "stop"
            }
        }
    }
    struct Step: Equatable { let offset: TimeInterval; let kind: Kind }

    static let countdown: TimeInterval = 20
    static let spacing: TimeInterval = 6

    /// Offsets from the start of the test: the three calls after the countdown, 6s apart, the stop 6s after the last.
    static let steps: [Step] = [
        Step(offset: countdown, kind: .systemVibrate),
        Step(offset: countdown + spacing, kind: .alertVibrate),
        Step(offset: countdown + 2 * spacing, kind: .coreHaptics),
        Step(offset: countdown + 3 * spacing, kind: .stop),
    ]

    /// The test never touches a running night's or nap's audio.
    static func canStart(nightOrNapRunning: Bool, testRunning: Bool) -> Bool { !nightOrNapRunning && !testRunning }
}

/// One line of the result list.
struct BackgroundVibrationLine: Identifiable, Equatable {
    let id = UUID()
    let kind: BackgroundVibrationProbe.Kind
    let at: Date
    let appState: String
    let locked: Bool
    let audioRunning: Bool
}

/// Owned outside the view, so the sequence survives the Developer screen (a locked phone does not close it, but
/// leaving the screen must not stop the test either).
@Observable
@MainActor
final class BackgroundVibrationTest {
    static let shared = BackgroundVibrationTest()

    enum Phase: Equatable { case idle, running, finished }
    private(set) var phase: Phase = .idle
    private(set) var startedAt: Date?
    private(set) var lines: [BackgroundVibrationLine] = []
    private var task: Task<Void, Never>?
    private var keeper: AudioKeeper?
    private var log: ProbeLog { ProbeLog() }      // fresh each time: ProbeLog writes its whole array

    /// Starts the keep-alive exactly like the night does (`AudioKeeper.start`, silent ambience) and the sequence.
    func start(audio: AudioKeeper, nightOrNapRunning: Bool) {
        guard BackgroundVibrationProbe.canStart(nightOrNapRunning: nightOrNapRunning, testRunning: phase == .running)
        else { return }
        lines = []
        do { try audio.start(ambience: .silence, volume: 0) } catch {
            log.add("bg-vibration: audio could not start: \(error.localizedDescription)")
            return
        }
        keeper = audio
        let began = Date()
        startedAt = began
        phase = .running
        log.add("bg-vibration: test started (keep-alive audio running: \(audio.isRunning))")
        task = Task { [weak self] in
            for step in BackgroundVibrationProbe.steps {
                let wait = began.addingTimeInterval(step.offset).timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self else { return }
                self.perform(step.kind)
            }
        }
    }

    func cancel() {
        guard phase == .running else { return }
        task?.cancel()
        task = nil
        keeper?.stop()
        keeper = nil
        phase = .idle
        log.add("bg-vibration: test cancelled")
    }

    private func perform(_ kind: BackgroundVibrationProbe.Kind) {
        if kind == .stop {
            keeper?.stop()
            let running = keeper?.isRunning ?? false
            keeper = nil
            task = nil
            phase = .finished
            log.add("bg-vibration: test finished (audio stopped, running now: \(running))")
            return
        }
        let line = BackgroundVibrationLine(kind: kind, at: Date(), appState: Self.stateName(UIApplication.shared.applicationState),
                                           locked: !UIApplication.shared.isProtectedDataAvailable,
                                           audioRunning: keeper?.isRunning ?? false)
        switch kind {
        case .systemVibrate: AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        case .alertVibrate: AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        case .coreHaptics: Haptics.play(.start)
        case .stop: break
        }
        lines.append(line)
        let extra = kind == .coreHaptics ? " · \(Haptics.lastResult)" : ""
        log.add("bg-vibration: \(kind.logName) · \(line.appState) · locked=\(line.locked ? "yes" : "no") · audio=\(line.audioRunning ? "yes" : "no")\(extra)")
    }

    static func stateName(_ s: UIApplication.State) -> String {
        switch s {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "?"
        }
    }

    /// Screenshots: `-fakeVibrationResult` shows a finished list.
    func fakeResult() {
        let t = Date()
        lines = BackgroundVibrationProbe.Kind.allCases.filter { $0 != .stop }.enumerated().map { i, k in
            BackgroundVibrationLine(kind: k, at: t.addingTimeInterval(Double(i) * 6), appState: "background",
                                    locked: true, audioRunning: true)
        }
        phase = .finished
    }
}
#endif
