#if DEBUG   // developer screen: not part of Release builds
import SwiftUI

/// Settings → Developer → Vibration test: play every night vibration and see whether Core Haptics works.
struct VibrationTestView: View {
    @Environment(AppModel.self) private var model
    @State private var result = Haptics.lastResult
    private var bg: BackgroundVibrationTest { .shared }

    var body: some View {
        List {
            Section {
                ForEach(Haptic.allCases, id: \.self) { h in
                    Button(Self.title(h)) {
                        Haptics.play(h)
                        result = Haptics.lastResult
                    }
                }
            } footer: {
                Text(verbatim: (Haptics.supportsHaptics ? "Taptic Engine ✓" : "Taptic Engine ✗") + " · " + result)
            }
            backgroundSection
            Section {
                Label(L("Settings → Sounds & Haptics → System Haptics: on"), systemImage: "iphone.radiowaves.left.and.right")
                Label(L("Settings → Sounds & Haptics → Haptics: Always Play"), systemImage: "bell.slash")
                Label(L("Settings → Accessibility → Touch → Vibration: on"), systemImage: "hand.tap")
            } header: {
                Text(L("If you feel nothing, check on the iPhone"))
            } footer: {
                Text(L("iOS lets apps vibrate only while they are on screen. At night the warnings vibrate through their notification – that needs the settings above. They are time sensitive, so they arrive during a Focus too – if iOS asks, keep them allowed."))
            }
        }
        .navigationTitle(L("Vibration test"))
        .onAppear {
            if DevArgs.list.contains("-fakeVibrationResult") { bg.fakeResult() }      // screenshots
            if DevArgs.list.contains("-startVibrationProbe"), bg.phase == .idle { startBackgroundTest() }
        }
    }

    private func startBackgroundTest() {
        bg.start(audio: model.audio, nightOrNapRunning: model.active != nil)
    }

    @ViewBuilder private var backgroundSection: some View {
        let nightRunning = model.active != nil
        Section {
            switch bg.phase {
            case .idle:
                Button(L("Start the background test")) { startBackgroundTest() }
                    .disabled(!BackgroundVibrationProbe.canStart(nightOrNapRunning: nightRunning, testRunning: false))
            case .running:
                if let began = bg.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, Int(ceil(began.addingTimeInterval(BackgroundVibrationProbe.countdown).timeIntervalSince(ctx.date))))
                        Text(left > 0 ? L("Lock the phone now and keep it in your hand – \(left)s")
                                      : L("The three calls are running…"))
                    }
                }
                Button(L("Cancel test"), role: .destructive) { bg.cancel() }
            case .finished:
                Button(L("Start the background test")) { startBackgroundTest() }
                    .disabled(!BackgroundVibrationProbe.canStart(nightOrNapRunning: nightRunning, testRunning: false))
            }
            ForEach(bg.lines) { line in
                HStack {
                    Text(verbatim: ProbeLog.timeFormat.string(from: line.at)).font(.caption2.monospacedDigit())
                    VStack(alignment: .leading) {
                        Text(verbatim: line.kind.logName).font(.caption.monospaced())
                        Text(verbatim: "\(line.appState) · " + (line.locked ? L("phone locked") : L("phone unlocked")) + " · "
                             + (line.audioRunning ? L("audio on") : L("audio off")))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if bg.phase == .finished { Text(L("Tell Claude which of the three you felt.")) }
        } header: {
            Text(L("Vibration in the background"))
        } footer: {
            Text(nightRunning ? L("Not while a night or a nap is running.")
                              : L("Plays a silent keep-alive like the night, then vibrates three ways while the phone is locked: 20s countdown, three calls 6s apart."))
        }
    }

    static func title(_ h: Haptic) -> String {
        switch h {
        case .start: L("Start of a night")
        case .relief: L("Back in time")
        case .purr: L("Purr")
        case .pet: L("Petting the cat")
        }
    }
}
#endif
