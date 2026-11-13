import Foundation
import Testing
@testable import SleepHole

/// 13ad-6: in the simulator `-fakeVolume V,S,V2` flips from V to V2 after S seconds, and every later re-read of the
/// volume (the alarm, its ticks, the audio coming back) returns the CURRENT value – the flip is not undone.
#if DEBUG && targetEnvironment(simulator)
@MainActor
@Suite(.serialized)
struct MediaVolumeFakeTests {
    /// Waits for the flip (up to 10 s) instead of a fixed sleep.
    func waitUntil(_ done: () -> Bool) async {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func aReReadAfterTheFlipReturnsTheFlippedValue() async {
        let saved = MediaVolumeWatcher.fakeParts
        defer { MediaVolumeWatcher.fakeParts = saved; MediaVolumeWatcher.fakeCurrent = nil }
        MediaVolumeWatcher.fakeParts = ["0.5", "0.05", "0.0"]
        let w = MediaVolumeWatcher()
        var seen: [Double] = []
        w.start { seen.append($0) }
        defer { w.stop() }
        #expect(MediaVolumeWatcher.reading() == 0.5)
        #expect(seen == [0.5])
        await waitUntil { seen.count == 2 }
        #expect(seen == [0.5, 0.0])
        #expect(MediaVolumeWatcher.reading() == 0.0)            // the re-read keeps the flip
        #expect(MediaVolumeWatcher.reading() == 0.0)
    }

    @Test func aNewNightStartsAtTheFirstValueAgain() async {
        let saved = MediaVolumeWatcher.fakeParts
        defer { MediaVolumeWatcher.fakeParts = saved; MediaVolumeWatcher.fakeCurrent = nil }
        MediaVolumeWatcher.fakeParts = ["0.5", "0.05", "0.0"]
        let w = MediaVolumeWatcher()
        w.start { _ in }
        await waitUntil { MediaVolumeWatcher.reading() == 0 }
        #expect(MediaVolumeWatcher.reading() == 0)
        w.start { _ in }
        defer { w.stop() }
        #expect(MediaVolumeWatcher.reading() == 0.5)
    }

    @Test func withoutAFlipTheFakeStaysPut() {
        let saved = MediaVolumeWatcher.fakeParts
        defer { MediaVolumeWatcher.fakeParts = saved; MediaVolumeWatcher.fakeCurrent = nil }
        MediaVolumeWatcher.fakeParts = ["0.12"]
        let w = MediaVolumeWatcher()
        w.start { _ in }
        defer { w.stop() }
        #expect(MediaVolumeWatcher.reading() == 0.12)
    }
}
#endif
