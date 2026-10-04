import SwiftUI

/// Settings → Developer → Vibration test: play every night vibration and see whether Core Haptics works.
struct VibrationTestView: View {
    @State private var result = Haptics.lastResult

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
