import AVFoundation
import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// Sound stories (owner 2026-09-30): random scenes of CC0 clips over chapter beds; the journey walks through
/// six chapters in order.
@MainActor
struct StoriesTests {
    init() { AudioKeeper.muted = true }

    /// Plays `count` scenes of `world` and returns them.
    func play(_ world: StoryWorld, _ count: Int, seed: UInt64 = 7) -> [StoryScene] {
        var rng = SeededGenerator(seed: seed)
        var teller = StoryTeller(world: world)
        return (0..<count).map { _ in teller.next(using: &rng) }
    }

    @Test func everySceneOfEveryChapterIsPlayable() {
        var seen: [StoryChapter: Set<String>] = [:]
        for world in StoryWorld.allCases {
            let scenes = play(world, world == .journey ? 700 : 150)
            for (a, b) in zip(scenes, scenes.dropFirst()) where a.chapter == b.chapter {
                #expect(a.name != b.name)                                   // never the same scene twice in a row
            }
            for scene in scenes {
                seen[scene.chapter, default: []].insert(scene.name)
                #expect(!scene.events.isEmpty, "\(scene.chapter) \(scene.name)")
                #expect(scene.pause >= 6 && scene.length >= scene.pause)
                for e in scene.events {
                    #expect(e.at >= 0 && (0...1).contains(e.volume) && (-1...1).contains(e.pan))
                    #expect(AudioKeeper.sample(e.sample) != nil, "missing \(e.sample)")
                }
            }
        }
        for chapter in StoryChapter.allCases {
            #expect(seen[chapter, default: []].isSuperset(of: chapter.scenes.keys), "\(chapter) plays all its scenes")
        }
    }

    @Test func theJourneyWalksThroughItsChaptersInOrder() {
        let scenes = play(.journey, 700)
        var order: [StoryChapter] = []
        var lengths: [StoryChapter: TimeInterval] = [:]
        for (i, s) in scenes.enumerated() {
            if order.last != s.chapter {
                order.append(s.chapter)
                if let opening = s.chapter.opening { #expect(s.name == opening) }   // walking to the next place
                #expect(i == 0 || s.chapter != .cabin)
            }
            lengths[s.chapter, default: 0] += s.length
        }
        #expect(order == StoryWorld.journey.chapters)                     // in order, never back
        for c in order.dropLast() {
            #expect(lengths[c]! >= StoryTeller.chapterLength.lowerBound, "\(c) lasts 10–20 min")
            #expect(lengths[c]! <= StoryTeller.chapterLength.upperBound + 200)
        }
        let after = scenes.filter { $0.chapter == .after }
        #expect(after.map(\.pause).reduce(0, +) / Double(after.count) > 30)   // a sleepy ending
    }

    @Test func singleChapterWorldsStayInTheirChapter() {
        for world in [StoryWorld.forest, .cave, .workshop] {
            #expect(Set(play(world, 120).map(\.chapter)) == [world.chapters[0]])
        }
    }

    @Test func randomButReproducibleFromTheSeed() {
        #expect(play(.forest, 5, seed: 42).map(\.events) == play(.forest, 5, seed: 42).map(\.events))
        #expect(play(.forest, 5, seed: 42).map(\.events) != play(.forest, 5, seed: 43).map(\.events))
    }

    @Test func everyClipAndBedIsBundled() {
        for (group, count) in StoryTeller.samples {
            for n in 0..<count { #expect(Bundle.main.url(forResource: "st_\(group)_\(n).caf", withExtension: nil) != nil) }
            #expect(Bundle.main.url(forResource: "st_\(group)_\(count).caf", withExtension: nil) == nil, "\(group)")
        }
        let format = AudioKeeper.sample("st_grass_0.caf")?.format
        for (group, count) in StoryTeller.samples {                      // one format for the story players
            for n in 0..<count { #expect(AudioKeeper.sample("st_\(group)_\(n).caf")?.format == format) }
        }
        for chapter in StoryChapter.allCases { #expect(AudioKeeper.sample(chapter.bed) != nil, "\(chapter.bed)") }
        for a in AudioKeeper.Ambience.allCases where a.storyWorld != nil {
            #expect(a.loopFile == a.storyWorld!.chapters[0].bed)
        }
    }

    @Test func aStoryPlaysOverItsBedAndTheJourneyCrossfades() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyJourney, volume: 0.3)
        #expect(audio.isLoopPlaying && audio.storyWorld == .journey && audio.storyChapter == .cabin)
        #expect(audio.currentBedFile == "bed_forest.caf")
        let deadline = Date() + 20                                        // the first scene starts after 2–5 s
        while audio.storySoundsPlayed == 0, Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        #expect(audio.storySoundsPlayed > 0)
        audio.crossfadeBed(to: StoryChapter.wind.bed, seconds: 0.4)      // the next chapter
        #expect(audio.currentBedFile == "bed_wind.caf" && audio.isLoopPlaying)
        try? await Task.sleep(for: .seconds(0.8))
        audio.setVolume(0.2, ambience: .storyJourney)                     // a volume change keeps the chapter's bed
        #expect(audio.currentBedFile == "bed_wind.caf")
        audio.stopEngineForTesting()
        #expect(audio.ensureRunning() && audio.isLoopPlaying && audio.currentBedFile == "bed_wind.caf")
        audio.setVolume(0.3, ambience: .storyCave)                        // another world
        #expect(audio.storyWorld == .cave && audio.currentBedFile == "bed_cave.caf")
        audio.setVolume(0.3, ambience: .brownNoise)                       // not a story any more
        #expect(audio.storyWorld == nil && !audio.isLoopPlaying)
        audio.stop()
    }
}
