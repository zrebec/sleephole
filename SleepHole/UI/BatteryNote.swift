import SwiftUI
import SleepCore

/// 13l: the calm battery reminder on the night screen during the setup. Shown only while the view exists (the setup of a
/// night, never a nap); battery monitoring is on only for that time. It is a note – it never blocks or changes the start.
struct BatteryNote: View {
    @State private var level: Double
    @State private var plug: BatteryPlug

    /// The first reading is taken here, before the first layout pass: the night screen's fit (13e6) measures the column once
    /// the setup shows, and a card that only appeared in `onAppear` came after it and pushed "Cancel night" under the tab bar.
    /// The system gives the right level only while monitoring is on, so it is switched on here too.
    init() {
        Self.startMonitoring()
        let r = Self.reading()
        _level = State(initialValue: r.level)
        _plug = State(initialValue: r.plug)
    }

    var body: some View {
        VStack(spacing: 0) {
            if BatteryReminder.shouldRemind(level: level, plug: plug, isNap: false) {
                Text(L("🪫 The battery is at \(BatteryReminder.percent(level))%. Put the phone on the charger so it lasts until the morning."))
                    .font(.callout).foregroundStyle(.white).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))
                    .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            Self.startMonitoring(); read()
            #if DEBUG && targetEnvironment(simulator)
            if let flip = Self.fakeFlip {
                Task { try? await Task.sleep(for: .seconds(flip.after)); plug = flip.plug }
            }
            #endif
        }
        .onDisappear { Self.stopMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in read() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in read() }
    }

    private func read() {
        let r = Self.reading()
        level = r.level
        plug = r.plug
    }

    private static func startMonitoring() {
        #if DEBUG && targetEnvironment(simulator)
        if fake != nil { return }
        #endif
        BatteryMonitoring.set("batteryNote", on: true)        // shared with the diagnostic track (13ab)
    }

    private static func stopMonitoring() {
        #if DEBUG && targetEnvironment(simulator)
        if fake != nil { return }
        #endif
        BatteryMonitoring.set("batteryNote", on: false)       // the night's own claim stays
    }

    private static func reading() -> (level: Double, plug: BatteryPlug) {
        #if DEBUG && targetEnvironment(simulator)
        if let f = fake { return f }
        #endif
        let d = UIDevice.current
        let plug: BatteryPlug = switch d.batteryState {
        case .unplugged: .unplugged
        case .charging: .charging
        case .full: .full
        default: .unknown
        }
        return (Double(d.batteryLevel), plug)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// `-fakeBattery 0.24[,unplugged|charging|full[,S]]` (simulator and DEBUG only). With S the state flips after S seconds
    /// (unplugged becomes charging, anything else becomes unplugged) – screenshots of the card coming and going mid-setup.
    private static var fakeFlip: (after: Double, plug: BatteryPlug)? {
        guard let v = DevArgs.value(after: "-fakeBattery") else { return nil }
        let parts = v.split(separator: ",").map(String.init)
        guard parts.count > 2, let after = Double(parts[2]) else { return nil }
        return (after, fake?.plug == .unplugged ? .charging : .unplugged)
    }

    private static var fake: (level: Double, plug: BatteryPlug)? {
        guard let v = DevArgs.value(after: "-fakeBattery") else { return nil }
        let parts = v.split(separator: ",").map(String.init)
        guard let level = parts.first.flatMap(Double.init) else { return nil }
        let plug: BatteryPlug = switch parts.dropFirst().first {
        case "charging": .charging
        case "full": .full
        default: .unplugged
        }
        return (level, plug)
    }
    #endif
}
