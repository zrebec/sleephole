import SwiftUI
import AVFoundation
import SleepCore

/// 13r: the calm volume reminder under "Alarm at …" on a running night or nap. The app's alarm plays through the media
/// volume, which the side buttons also turn down with the night sound. The volume is only read (KVO) while the view
/// exists – this view never activates or configures the audio session (AudioKeeper owns it).
struct VolumeNote: View {
    @State private var volume: Double
    @State private var observation: NSKeyValueObservation?

    init() { _volume = State(initialValue: Self.reading()) }

    var body: some View {
        VStack(spacing: 0) {
            if let level = VolumeReminder.level(volume: volume) {
                Text(level == .off
                     ? L("🔇 The sound is off – the app's alarm won't be heard. Turn it up with the button on the side of the phone.")
                     : L("🔈 The sound is turned down – the app's alarm will be quiet. Turn it up with the button on the side of the phone."))
                    .font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                    .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            volume = Self.reading()
            #if DEBUG && targetEnvironment(simulator)
            if let flip = Self.fakeFlip {
                Task { try? await Task.sleep(for: .seconds(flip.after)); volume = flip.volume }
                return
            }
            if Self.fake != nil { return }
            #endif
            observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
                guard let v = change.newValue else { return }
                Task { @MainActor in volume = Double(v) }
            }
        }
        .onDisappear { observation?.invalidate(); observation = nil }
    }

    private static func reading() -> Double {
        #if DEBUG && targetEnvironment(simulator)
        if let f = fake { return f }
        #endif
        return Double(AVAudioSession.sharedInstance().outputVolume)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// `-fakeVolume 0.12[,S,0.6]` (simulator and DEBUG only). With S,V the volume becomes V after S seconds.
    static var fakeParts: [String]? {
        DevArgs.value(after: "-fakeVolume").map { $0.split(separator: ",").map(String.init) }
    }
    static var fake: Double? { fakeParts?.first.flatMap(Double.init) }
    static var fakeFlip: (after: Double, volume: Double)? {
        guard let p = fakeParts, p.count > 2, let after = Double(p[1]), let v = Double(p[2]) else { return nil }
        return (after, v)
    }
    #endif
}
