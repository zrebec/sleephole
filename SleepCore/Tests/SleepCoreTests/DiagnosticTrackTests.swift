import Foundation
import Testing
@testable import SleepCore

/// 13ab: the tolerant journal decoding (B61) and the diagnostic track's model.
@Suite struct DiagnosticTrackTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func json(_ s: String) -> Data { Data(s.utf8) }

    // MARK: lossy decoding

    @Test func anUnknownKindIsSkippedAndTheOthersKeepTheirOrder() {
        let data = json("""
        [{"kind":"started","at":10},{"kind":"someNewKind","at":11},{"kind":"locked","at":12},{"kind":"returned","at":13}]
        """)
        let events = NightEvent.decodeLossy(data)
        #expect(events?.map(\.kind) == [.started, .locked, .returned])
        #expect(events?.map(\.at.timeIntervalSinceReferenceDate) == [10, 12, 13])
    }

    @Test func aMalformedElementIsSkipped() {
        let data = json("""
        [{"kind":"started","at":10},42,"text",{"kind":"locked"},{"at":5},null,{"kind":"confirmed","at":20}]
        """)
        #expect(NightEvent.decodeLossy(data)?.map(\.kind) == [.started, .confirmed])
    }

    @Test func bytesThatAreNoArrayAreReportedAsUnreadable() {
        #expect(NightEvent.decodeLossy(json("{\"kind\":\"started\"}")) == nil)
        #expect(NightEvent.decodeLossy(json("not json")) == nil)
        #expect(NightEvent.decodeLossy(Data()) == nil)
        #expect(NightEvent.decodeLossy(json("[]"))?.isEmpty == true)
    }

    @Test func knownEventsReEncodeByteIdentically() throws {
        let events = [NightEvent(.started, at: t0), NightEvent(.leftApp, at: t0 + 60.5), NightEvent(.confirmed, at: t0 + 3600)]
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]       // key order of a plain encoder varies run to run
        let plain = try enc.encode(events)
        let lossy = try #require(NightEvent.decodeLossy(plain))
        #expect(lossy == events)
        #expect(try enc.encode(lossy) == plain)
    }

    struct Holder: Codable, Equatable {
        var id: String
        @LossyNightEvents var events: [NightEvent]
    }

    @Test func theWrapperDecodesLeniently() throws {
        let data = json("""
        {"id":"x","events":[{"kind":"started","at":1},{"kind":"newThing","at":2},7,{"kind":"returned","at":3}]}
        """)
        let h = try JSONDecoder().decode(Holder.self, from: data)
        #expect(h.events.map(\.kind) == [.started, .returned])
        #expect(h.id == "x")
    }

    @Test func theWrapperEncodesLikeAPlainArray() throws {
        struct Plain: Codable { var id: String; var events: [NightEvent] }
        let events = [NightEvent(.started, at: t0), NightEvent(.returned, at: t0 + 3)]
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        #expect(try enc.encode(Holder(id: "a", events: events)) == (try enc.encode(Plain(id: "a", events: events))))
    }

    @Test func theWrapperStillRefusesBytesThatAreNoArray() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Holder.self, from: json("{\"id\":\"x\",\"events\":5}"))
        }
    }

    // MARK: the track

    @Test func entriesAreStoredInOrderAndRoundTrip() {
        var log = DiagLog()
        log.append("ctx.app", "v=1.1 ios=26.1", at: t0)
        log.append("life", "inactive", at: t0 + 1)
        log.append("power", nil, at: t0 + 2)
        let back = DiagLog.decode(log.encoded())
        #expect(back == log)
        #expect(back.entries.map(\.k) == ["ctx.app", "life", "power"])
        #expect(back.entries[2].v == nil)
    }

    @Test func aValueIsCutTo160Characters() {
        var log = DiagLog()
        log.append("x", String(repeating: "a", count: 500), at: t0)
        #expect(log.entries[0].v?.count == DiagLog.maxValueLength)
        #expect(DiagLog.maxValueLength == 160)
    }

    @Test func theCapEndsTheTrackWithOneFinalEntry() {
        var log = DiagLog()
        for i in 0..<(DiagLog.maxEntries + 50) { log.append("e", "\(i)", at: t0 + Double(i)) }
        #expect(DiagLog.maxEntries == 800)
        #expect(log.entries.count == 801)
        #expect(log.entries.last?.k == "diag.cap")
        #expect(log.entries.filter { $0.k == "diag.cap" }.count == 1)
        #expect(log.entries[799].v == "799")
        #expect(log.isFull)
        let before = log
        log.append("late", nil, at: t0 + 9999)
        #expect(log == before)
    }

    @Test func missingOrBrokenStoredBytesGiveAnEmptyTrack() {
        #expect(DiagLog.decode(nil).entries.isEmpty)
        #expect(DiagLog.decode(Data("junk".utf8)).entries.isEmpty)
        let partly = DiagLog.decode(Data("[{\"at\":1,\"k\":\"a\"},{\"nope\":1},{\"at\":2,\"k\":\"b\",\"v\":\"x\"}]".utf8))
        #expect(partly.entries.map(\.k) == ["a", "b"])
    }

    @Test func onlyTracksFinalizedMoreThan30DaysAgoAreStale() {
        let now = t0 + 100 * 86_400
        #expect(!DiagLog.isStale(finalizedAt: nil, now: now))
        #expect(!DiagLog.isStale(finalizedAt: now - 5 * 86_400, now: now))
        #expect(!DiagLog.isStale(finalizedAt: now - 29 * 86_400, now: now))
        #expect(DiagLog.isStale(finalizedAt: now - 40 * 86_400, now: now))
    }
}
