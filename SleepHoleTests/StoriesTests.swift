import AVFoundation
import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// Sound stories (owner 2026-09-30): random scenes of Kenney CC0 sounds over a bed loop.
@MainActor
struct StoriesTests {
    init() { AudioKeeper.muted = true }

    @Test func everySceneOfEveryWorldIsPlayable() throws {
        var rng = SeededGenerator(seed: 7)
        for world in StoryWorld.allCases {
            var teller = StoryTeller(world: world)
            var seen = Set<String>()
            var last: String?
            for _ in 0..<60 {
                let scene = teller.next(using: &rng)
                #expect(scene.name != last)                                   // never the same scene twice in a row
                last = scene.name
                seen.insert(scene.name)
                #expect(!scene.events.isEmpty, "\(world) \(scene.name)")
                #expect(scene.pause >= 6 && scene.pause <= 90 && scene.length > scene.pause)
                for e in scene.events {
                    #expect(e.at >= 0 && (0...1).contains(e.volume) && (-1...1).contains(e.pan))
                    #expect(AudioKeeper.sample(e.sample) != nil, "missing \(e.sample)")
                }
            }
            #expect(seen == Set(StoryTeller.scenes[world]!), "\(world) plays all its scenes")
        }
    }

    @Test func randomButReproducibleFromTheSeed() {
        var a = SeededGenerator(seed: 42), b = SeededGenerator(seed: 42), c = SeededGenerator(seed: 43)
        var t1 = StoryTeller(world: .forest), t2 = StoryTeller(world: .forest), t3 = StoryTeller(world: .forest)
        let s1 = (0..<5).map { _ in t1.next(using: &a).events }
        let s2 = (0..<5).map { _ in t2.next(using: &b).events }
        let s3 = (0..<5).map { _ in t3.next(using: &c).events }
        #expect(s1 == s2 && s1 != s3)
    }

    @Test func everySampleGroupAndBedIsBundled() {
        for (group, count) in StoryTeller.samples {
            for n in 0..<count { #expect(Bundle.main.url(forResource: "st_\(group)_\(n).caf", withExtension: nil) != nil) }
            #expect(Bundle.main.url(forResource: "st_\(group)_\(count).caf", withExtension: nil) == nil)
        }
        for a in AudioKeeper.Ambience.allCases where a.storyWorld != nil {
            #expect(a.loopFile == "bed_\(a.storyWorld!.rawValue).caf")
            #expect(AudioKeeper.sample(a.loopFile!) != nil)
        }
    }

    @Test func aStoryPlaysOverItsBedAndStopsWhenSwitchedAway() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyCave, volume: 0.3)
        #expect(audio.isLoopPlaying && audio.storyWorld == .cave && audio.currentGain == 0.3)
        let deadline = Date() + 20                                        // the first scene starts after 2–5 s
        while audio.storySoundsPlayed == 0, Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        #expect(audio.storySoundsPlayed > 0)
        audio.setVolume(0.3, ambience: .storyWorkshop)                   // another world
        #expect(audio.storyWorld == .workshop && audio.isLoopPlaying)
        audio.setVolume(0.3, ambience: .brownNoise)                      // not a story any more
        #expect(audio.storyWorld == nil && !audio.isLoopPlaying)
        audio.stop()
    }
}
