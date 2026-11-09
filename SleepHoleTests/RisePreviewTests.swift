import AVFoundation
import Foundation
import SleepCore
import SwiftData
import Testing
import UIKit
@testable import SleepHole

/// 13z / B47: "Try the rise" must go on looping for the whole rise.
@Suite(.serialized) @MainActor
struct RisePreviewTests {
    /// LONG (about 70 s): the preview of a 120 s rise is still playing after 35 s and 65 s.
    @Test func theRisePreviewKeepsLooping() async throws {
        SoundFX.previewAlarmRise("alarm_gentle", start: 0.3, end: 1, rise: 120)
        defer { SoundFX.stopPreview() }
        #expect(SoundFX.isPreviewPlaying)
        try await Task.sleep(for: .seconds(35))
        #expect(SoundFX.isPreviewPlaying)
        try await Task.sleep(for: .seconds(30))
        #expect(SoundFX.isPreviewPlaying)
    }

    @Test func stoppingStopsItAndRestoresTheIdleTimer() async throws {
        UIApplication.shared.isIdleTimerDisabled = false
        SoundFX.previewAlarmRise("alarm_gentle", start: 0.3, end: 1, rise: 30)
        #expect(UIApplication.shared.isIdleTimerDisabled)
        #expect(SoundFX.riseState != nil)
        SoundFX.stopPreview()
        #expect(!SoundFX.isPreviewPlaying)
        #expect(SoundFX.riseState == nil)
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        #expect(!SoundFX.idleTimerSaved)
    }

    @Test func anotherPreviewReplacesTheRiseAndKeepsTheOriginalIdleValue() {
        UIApplication.shared.isIdleTimerDisabled = false
        SoundFX.previewAlarmRise("alarm_gentle", start: 0.3, end: 1, rise: 30)
        SoundFX.previewAlarmRise("alarm_gentle", start: 0.3, end: 1, rise: 30)   // a second tap
        SoundFX.previewAlarm("alarm_gentle", seconds: 1)
        #expect(SoundFX.riseState == nil)
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        SoundFX.stopPreview()
    }

    /// A night or nap starting stops a running rise preview (it must never play on into the night).
    @Test func startingANapStopsTheRisePreview() throws {
        let c = try ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                   JokerRecord.self, BoxRecord.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let day = DateComponents(year: 2026, month: 10, day: 5, hour: 13, minute: 30)
        let clock = FakeClock(Calendar.current.date(from: day)!)
        var settings = AppSettings()
        settings.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        let wasMuted = AudioKeeper.muted
        AudioKeeper.muted = true
        defer { AudioKeeper.muted = wasMuted }
        let m = AppModel(context: c.mainContext, catalog: SpriteLibrary.loadFromBundle().catalog!, clock: clock,
                         settings: settings, servicesEnabled: true)
        UIApplication.shared.isIdleTimerDisabled = false
        SoundFX.previewAlarmRise("alarm_gentle", start: 0.3, end: 1, rise: 120)
        #expect(SoundFX.riseState != nil)
        m.startNap()
        defer { m.abandonNight() }
        #expect(m.active?.isNap == true)
        #expect(!SoundFX.isPreviewPlaying)
        #expect(SoundFX.riseState == nil)
        #expect(!SoundFX.idleTimerSaved)
    }

    /// Moved here from ServicesTests.shakeAndSounds: it touches the same static preview, so it must be serialized with these.
    @Test func previewAlarmWithAMissingFileIsHarmless() {
        SoundFX.previewAlarm("alarm_gentle", seconds: 0.1)
        SoundFX.previewAlarm("missing")
        SoundFX.stopPreview()
    }
}
