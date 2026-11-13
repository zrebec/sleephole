import SwiftUI
import SleepCore

/// 13r: the calm volume reminder under "Alarm at …" on a running night or nap, and (13ad, B54) on the alarm screen. The
/// app's alarm plays through the media volume, which the side buttons also turn down with the night sound. The volume
/// is the model's (`AppModel.mediaVolume`, fed by the ONE `MediaVolumeWatcher` of the night) – this view observes
/// nothing itself and never touches the audio session (AudioKeeper owns it).
struct VolumeNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let level = VolumeReminder.level(volume: model.mediaVolume) {
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
    }
}
