import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// Bug B19 (owner 2026-10-03): a stop of the sleep sound during a night is remembered – the next night starts
/// silent – while the chosen sound and duration stay and ▶ plays them again.
extension AppModelTests {
    /// Ends the running night that started on `day` (confirmed one minute after the wake time).
    private func finishNight(_ h: Harness, day: Int) {
        h.clock.now = date(day + 1, 6, 30) + 60; h.model.refresh()
        #expect(h.model.confirm(code: "1234"))
        h.model.acknowledgeResult()
    }

    private func startNight(_ h: Harness, day: Int) {
        h.clock.now = date(day, 22, 25); h.model.refresh()
        h.model.startNight()
    }

    @Test func aStopDuringTheNightMakesTheNextNightSilent() {
        let h = harness(at: date(5, 22, 25))
        h.model.settings.ambience = .rainTent
        h.model.settings.ambienceMinutes = 30
        startNight(h, day: 5)
        #expect(h.model.sleepSound?.ambience == .rainTent && h.model.settings.playsAtStart)
        h.model.stopSleepSound()
        #expect(h.model.sleepSound == nil && h.model.settings.ambienceOff == true && !h.model.settings.playsAtStart)
        #expect(h.model.settings.ambience == .rainTent && h.model.settings.ambienceMinutes == 30)   // the choice stays
        finishNight(h, day: 5)

        startNight(h, day: 6)
        #expect(h.model.active != nil && h.model.sleepSound == nil && !h.model.sleepSoundPlaying)
        #expect(h.model.settings.ambience == .rainTent && h.model.settings.ambienceMinutes == 30)
        finishNight(h, day: 6)
        startNight(h, day: 7)
        #expect(h.model.sleepSound == nil)                                 // still silent until ▶ is pressed
    }

    @Test func playingAfterAStopSwitchesTheSoundBackOn() {
        let h = harness(at: date(5, 22, 25))
        h.model.settings.ambience = .rainTent
        startNight(h, day: 5)
        h.model.stopSleepSound()
        h.clock.now = date(5, 23)
        h.model.playSleepSound(.rainTent, minutes: 15)                    // the sheet's ▶ (or Settings ▶)
        #expect(h.model.settings.ambienceOff == nil && h.model.settings.playsAtStart)
        #expect(h.model.sleepSoundPlaying && h.model.sleepSound?.endsAt == date(5, 23, 15))
        finishNight(h, day: 5)

        startNight(h, day: 6)
        #expect(h.model.sleepSound?.ambience == .rainTent)
        #expect(h.model.sleepSound?.endsAt == date(6, 22, 25) + 15 * 60)  // the minutes chosen at night are kept too
    }

    @Test func theSettingsSwitchControlsTheNextNight() {
        let h = harness(at: date(5, 22, 25))
        h.model.settings.ambience = .brownNoise
        h.model.settings.playsAtStart = false                              // Settings → "Play when the night starts"
        startNight(h, day: 5)
        #expect(h.model.sleepSound == nil)
        h.model.playSleepSound(.brownNoise, minutes: nil)                   // ▶ during the night switches it on again
        #expect(h.model.settings.playsAtStart && h.model.sleepSoundPlaying)
        finishNight(h, day: 5)
        startNight(h, day: 6)
        #expect(h.model.sleepSound?.ambience == .brownNoise)
    }

    @Test func aTimerThatRanOutIsNotAStop() {
        let h = harness(at: date(5, 22, 25))
        h.model.settings.ambience = .pinkNoise
        h.model.settings.ambienceMinutes = 5
        startNight(h, day: 5)
        #expect(h.model.sleepSoundPlaying)
        h.clock.now = date(5, 22, 40); h.model.refresh()
        #expect(!h.model.sleepSoundPlaying)                                // the timer is over …
        #expect(h.model.settings.ambienceOff == nil && h.model.settings.playsAtStart)   // … nothing was stopped
        finishNight(h, day: 5)
        startNight(h, day: 6)
        #expect(h.model.sleepSound?.ambience == .pinkNoise)
    }

    @Test func aStopWithoutANightChangesNothing() {
        let h = harness(at: date(5, 12))
        h.model.stopSleepSound()                                           // no night / nap running: nothing to remember
        #expect(h.model.settings.ambienceOff == nil)
    }

    @Test func aStopDuringANapIsRememberedToo() {
        let h = harness(at: date(5, 13, 5))
        h.model.startNap()
        #expect(h.model.active?.isNap == true && h.model.sleepSound != nil)
        h.model.stopSleepSound()
        #expect(h.model.settings.ambienceOff == true)
        h.clock.now = date(5, 13, 35); h.model.refresh()                   // the nap is over …
        #expect(h.model.confirm(code: "1234"))
        h.model.acknowledgeResult()
        h.clock.now = date(5, 22, 25); h.model.refresh()
        h.model.startNight()                                               // … and the night starts silent too
        #expect(h.model.sleepSound == nil)
    }

    @Test func settingsFromOlderBuildsAndBackupsStillLoad() throws {
        // a settings JSON saved before the flag existed has no "ambienceOff" key
        let old = try JSONEncoder().encode(AppSettings())
        let json = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
        #expect(json["ambienceOff"] == nil)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: old)
        #expect(loaded.ambienceOff == nil && loaded.playsAtStart)

        var off = AppSettings()
        off.playsAtStart = false
        #expect(off.ambienceOff == true)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off))
        #expect(back.ambienceOff == true && !back.playsAtStart)
        off.playsAtStart = true
        #expect(off.ambienceOff == nil)
    }

    @Test func theFlagTravelsInTheBackup() throws {
        let a = harness(at: date(5, 12))
        a.model.settings.playsAtStart = false
        let data = try a.model.makeBackup().encoded()
        let b = harness(at: date(9, 12))
        #expect(b.model.settings.playsAtStart)
        try b.model.restore(try BackupFile.decode(data))
        #expect(!b.model.settings.playsAtStart && b.model.settings.ambienceOff == true)
    }
}
