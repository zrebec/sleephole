import SleepCore
import SwiftUI
import UIKit

/// Logic of the detection test (testable without UI).
@MainActor
@Observable
final class DetectionTest {
    let log = ProbeLog()
    let monitor = LifecycleMonitor()
    let audio = AudioKeeper()
    var ambience = AudioKeeper.Ambience.brownNoise
    var volume: Float = 0.15
    var audioError: String?
    /// Simulated night: starts with the test, wake in 2 h, setup grace shortened to 10 s.
    var night: NightLog?
    static let rules: SleepRules = { var r = SleepRules(); r.setupGrace = 10; return r }()

    init() {
        monitor.onRaw = { [log] text in log.add(text) }
    }

    func start() {
        UIApplication.shared.isIdleTimerDisabled = false        // auto-lock is welcome
        do {
            try audio.start(ambience: ambience, volume: volume)
            audio.onInterruption = { [log] text in log.add(text) }
            audioError = nil
        } catch {
            audioError = "Zvuk sa nespustil: \(error.localizedDescription)"
        }
        monitor.onEvent = { [weak self] kind, date in self?.night?.append(kind, at: date) }
        monitor.start()
        log.add("=== test started · audio=\(audio.isRunning) ===")
        night = newNight()
    }

    func stop() {
        monitor.stop()
        audio.stop()
        night = nil
        log.add("=== test stopped ===")
    }

    func newNight() -> NightLog {
        let now = Date()
        let window = NightWindow(key: NightKey(date: now, calendar: .current), bedtime: now, wake: now + 2 * 3600)
        var l = NightLog(window: window, buildingId: "l1-house-a-0")
        l.append(.started, at: now)
        log.add("=== simulated night started ===")
        return l
    }

    func setVolume() { audio.setVolume(volume, ambience: ambience) }
}

/// F2 spike: runs the LifecycleMonitor + background audio and logs every signal with timestamps.
struct DetectionTestView: View {
    @State private var test = DetectionTest()
    @State private var running = false

    var body: some View {
        List {
            Section {
                Toggle("Test beží", isOn: $running)
                    .onChange(of: running) { _, on in on ? test.start() : test.stop() }
                Picker("Zvuk v pozadí", selection: $test.ambience) {
                    ForEach(AudioKeeper.Ambience.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: test.ambience) { _, _ in test.setVolume() }
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $test.volume, in: 0...0.6)
                        .onChange(of: test.volume) { _, _ in test.setVolume() }
                    Image(systemName: "speaker.wave.3.fill")
                }
                if let audioError = test.audioError { Text(audioError).foregroundStyle(.red).font(.caption) }
            } footer: {
                Text("Zapni test a vyskúšaj: zamknúť telefón, odomknúť, prepnúť do inej appky, stiahnuť Control Center, otvoriť kameru zo zamknutej obrazovky, nechať sa zavolať. Nakoniec pošli záznam cez „Zdieľať“.")
            }

            if let night = test.night {
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        simulationStatus(night, now: ctx.date)
                    }
                } header: {
                    Text("Simulácia noci")
                } footer: {
                    Text("Príprava je skrátená na 10 s (v appke 5 min). Po nej sa stavba zrúti, ak je appka v pozadí dlhšie ako 10 s. Zamknutie telefónu je v poriadku.")
                }
            }

            Section("Záznam (\(test.log.entries.count))") {
                ForEach(test.log.entries.reversed()) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProbeLog.timeFormat.string(from: e.at))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Text(e.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(e.text.hasPrefix("→") ? Color.accentColor : .primary)
                    }
                }
            }
        }
        .navigationTitle("Test detekcie")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: test.log.exportText) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Vymazať", role: .destructive) { test.log.clear() }
            }
        }
    }

    @ViewBuilder
    private func simulationStatus(_ night: NightLog, now: Date) -> some View {
        let start = night.startedAt ?? now
        let graceLeft = max(0, DetectionTest.rules.setupGrace - now.timeIntervalSince(start))
        let collapsed = NightEvaluator.collapsedAt(night, rules: DetectionTest.rules)
        VStack(alignment: .leading, spacing: 6) {
            if let collapsed, collapsed <= now {
                Label("Stavba sa zrútila o \(ProbeLog.timeFormat.string(from: collapsed)) 🧱", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            } else {
                Label("Stavba stojí ✅", systemImage: "building.2.fill").foregroundStyle(.green)
            }
            if graceLeft > 0 {
                Text("Príprava: ešte \(Int(graceLeft.rounded(.up))) s").font(.caption)
            }
            Text("Čas mimo appky spolu: \(Int(NightEvaluator.awaySeconds(night))) s").font(.caption)
            Button("Nová simulácia") { test.night = test.newNight() }.font(.caption)
        }
    }


}
