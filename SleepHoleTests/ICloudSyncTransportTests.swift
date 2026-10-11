import Foundation
import Testing
@testable import SleepHole

/// Phase SYNC, step S2b: the iCloud transport's own rules, with a temporary folder standing in for the container and a
/// stand-in for the `NSMetadataQuery` listing. What only a real device can show (the query itself, the real container)
/// is on the checklist in the plan.

/// A container that is a temporary folder (or nothing, or "not signed in").
struct FixedContainer: ICloudContainerLocating {
    var root: URL?
    var isSignedIn = true
    func root() async -> URL? { root }
}

/// The listing over a folder (every file is current) or over a list the test controls.
@MainActor
final class FakeListing: ICloudFileListing {
    var gathered = true
    /// With a folder: every `*.json` in it, downloaded. Without: `files`.
    var folder: URL?
    var files: [ICloudFileEntry] = []
    private(set) var requests: [URL] = []
    /// Called when a download is asked for (the test may flip the file to downloaded).
    var onRequest: ((URL) -> Void)?
    private(set) var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private(set) var stopped = false

    init(folder: URL? = nil) { self.folder = folder }

    func waitUntilGathered(timeout: TimeInterval) async -> Bool {
        if gathered { return true }
        try? await Task.sleep(for: .seconds(timeout))
        return gathered
    }

    func entries() -> [ICloudFileEntry] {
        guard let folder else { return files }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.map { ICloudFileEntry(url: $0, isDownloaded: true, isDownloading: false) }
    }

    func requestDownload(of url: URL) {
        requests.append(url)
        onRequest?(url)
    }

    func subscribe(_ id: UUID, _ continuation: AsyncStream<Void>.Continuation) { subscribers[id] = continuation }
    func unsubscribe(_ id: UUID) { subscribers[id] = nil }
    func stop() { stopped = true }

    /// "Another device's file appeared or changed."
    func signal() { for continuation in subscribers.values { continuation.yield() } }
}

@MainActor
struct ICloudSyncTransportTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sleephole-icloud-\(UUID().uuidString)", isDirectory: true)
    var sync: URL { root.appendingPathComponent(ICloudSyncTransport.folderName, isDirectory: true) }

    func transport(_ id: String = "A", listing: FakeListing, container: FixedContainer? = nil,
                   gatherWait: TimeInterval = 0.1, downloadWait: TimeInterval = 0.2) -> ICloudSyncTransport {
        ICloudSyncTransport(deviceId: id, container: container ?? FixedContainer(root: root), listing: listing,
                            gatherWait: gatherWait, downloadWait: downloadWait, pollInterval: 0.01)
    }

    /// A file of another device in the sync folder.
    @discardableResult
    func put(_ text: String, as name: String) throws -> URL {
        try FileManager.default.createDirectory(at: sync, withIntermediateDirectories: true)
        let url = sync.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func text(_ datas: [Data]) -> [String] { datas.map { String(decoding: $0, as: UTF8.self) } }

    // MARK: availability

    @Test func itIsAvailableOnlyWhenSignedInAndTheContainerResolves() async {
        let listing = FakeListing()
        #expect(await transport(listing: listing).isAvailable())
        #expect(!(await transport(listing: listing, container: FixedContainer(root: root, isSignedIn: false)).isAvailable()))
        #expect(!(await transport(listing: listing, container: FixedContainer(root: nil)).isAvailable()))
    }

    // MARK: reading

    @Test func anEmptyListingGivesAnEmptyAnswerOnlyWhenItIsGathered() async throws {
        let listing = FakeListing()
        #expect(try await transport(listing: listing).readOthers().isEmpty)          // gathered, no other device's file

        listing.gathered = false                                                     // iCloud's listing has not arrived
        await #expect(throws: ICloudSyncError.listingNotReady) { try await transport(listing: listing).readOthers() }
    }

    @Test func aMissingContainerIsAnErrorNotAnEmptyAnswer() async {
        let listing = FakeListing()
        await #expect(throws: ICloudSyncError.containerUnavailable) {
            try await transport(listing: listing, container: FixedContainer(root: nil)).readOthers()
        }
        await #expect(throws: ICloudSyncError.containerUnavailable) {
            try await transport(listing: listing, container: FixedContainer(root: nil)).write(Data("x".utf8))
        }
    }

    @Test func itReadsEveryOtherDevicesFileAndNeverItsOwn() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try put("own", as: "A.json")
        try put("from b", as: "B.json")
        try put("from c", as: "C.json")
        let listing = FakeListing(folder: sync)
        #expect(text(try await transport("A", listing: listing).readOthers()) == ["from b", "from c"])
        #expect(text(try await transport("B", listing: listing).readOthers()) == ["own", "from c"])
        #expect(listing.requests.isEmpty)
    }

    @Test func aFileThatIsNotDownloadedIsAskedForAndReadOnceItArrives() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try put("from b", as: "B.json")
        let listing = FakeListing()
        listing.files = [ICloudFileEntry(url: url, isDownloaded: false, isDownloading: false)]
        listing.onRequest = { [unowned listing] url in                               // the download takes a moment
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                listing.files = [ICloudFileEntry(url: url, isDownloaded: true, isDownloading: false)]
            }
        }
        #expect(text(try await transport(listing: listing, downloadWait: 2).readOthers()) == ["from b"])
        #expect(listing.requests == [url])                                           // asked for exactly once
    }

    @Test func anEmptyAnswerIsNeverGivenWhileAnotherDevicesFileIsStillOnItsWay() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try put("from b", as: "B.json")
        let listing = FakeListing()
        listing.files = [ICloudFileEntry(url: url, isDownloaded: false, isDownloading: true)]
        await #expect(throws: ICloudSyncError.otherDeviceFileNotReadable) { try await transport(listing: listing).readOthers() }
        #expect(listing.requests == [url])
    }

    @Test func downloadedFilesAreReturnedAndThePendingOneIsLeftOutThisTime() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let b = try put("from b", as: "B.json")
        let c = try put("from c", as: "C.json")
        let listing = FakeListing()
        listing.files = [ICloudFileEntry(url: b, isDownloaded: false, isDownloading: false),
                         ICloudFileEntry(url: c, isDownloaded: true, isDownloading: false)]
        #expect(text(try await transport(listing: listing).readOthers()) == ["from c"])
        #expect(listing.requests == [b])
    }

    @Test func aDownloadedFileThatCannotBeReadIsAnErrorWhenNothingElseWasRead() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let gone = sync.appendingPathComponent("B.json")                             // listed, but not on the disk
        let listing = FakeListing()
        listing.files = [ICloudFileEntry(url: gone, isDownloaded: true, isDownloading: false)]
        await #expect(throws: (any Error).self) { try await transport(listing: listing).readOthers() }
    }

    // MARK: writing

    @Test func writingCreatesTheSyncFolderAndReplacesOnlyItsOwnFile() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let t = transport("A/..x", listing: FakeListing())                           // the id becomes a safe file name
        #expect(t.deviceId == "A___x")
        #expect(!FileManager.default.fileExists(atPath: sync.path))
        try await t.write(Data("one".utf8))
        try await t.write(Data("two".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: sync.path)
        #expect(names == ["A___x.json"])
        #expect(try String(contentsOf: sync.appendingPathComponent("A___x.json"), encoding: .utf8) == "two")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents").path))   // never in Documents
    }

    // MARK: the change signal

    @Test(.timeLimit(.minutes(1))) func theStreamPassesTheListingsSignalOnAndUnsubscribesWhenItEnds() async throws {
        let listing = FakeListing()
        let t = transport(listing: listing)
        var task: Task<Int, Never>?
        do {
            let stream = t.changes
            task = Task { @MainActor in
                var seen = 0
                for await _ in stream { seen += 1; if seen == 2 { break } }
                return seen
            }
            while listing.subscribers.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
            listing.signal()
            try await Task.sleep(for: .milliseconds(30))
            listing.signal()
        }
        #expect(await task?.value == 2)
        while !listing.subscribers.isEmpty { try await Task.sleep(for: .milliseconds(5)) }   // the ended stream unsubscribed
        #expect(listing.subscribers.isEmpty)
    }

    // MARK: the real listing's waiting logic (no query is started)

    final class Signals { var n = 0 }

    /// A listing without a query and a counter of the signals its subscriber receives.
    func listingWithSubscriber() -> (MetadataQueryListing, Signals, Task<Void, Never>, UUID) {
        let listing = MetadataQueryListing(ownName: "A.json", startsQuery: false)
        let signals = Signals()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let id = UUID()
        listing.subscribe(id, continuation)
        let counting = Task { @MainActor in for await _ in stream { signals.n += 1 } }
        return (listing, signals, counting, id)
    }

    @Test(.timeLimit(.minutes(1))) func aGatheringThatEndsAfterAWaiterGaveUpTellsTheSubscribersToReadAtOnce() async throws {
        let (listing, signals, counting, _) = listingWithSubscriber()
        defer { counting.cancel(); listing.stop() }
        #expect(await listing.waitForGathering(timeout: 0.02) == false)             // iCloud's listing has not arrived
        #expect(signals.n == 0 && !listing.isGathered)
        listing.didFinishGathering()                                                // … and now it has
        while signals.n == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(signals.n == 1 && listing.isGathered)
        listing.didFinishGathering()                                                // it is told once per missed gathering
        try await Task.sleep(for: .milliseconds(60))
        #expect(signals.n == 1)
    }

    @Test(.timeLimit(.minutes(1))) func aGatheringThatAWaiterSawNeedsNoSignal() async throws {
        let (listing, signals, counting, _) = listingWithSubscriber()
        defer { counting.cancel(); listing.stop() }
        let waiting = Task { @MainActor in await listing.waitForGathering(timeout: 30) }
        try await Task.sleep(for: .milliseconds(30))
        listing.didFinishGathering()
        #expect(await waiting.value)                                                // the waiter got its answer itself
        try await Task.sleep(for: .milliseconds(60))
        #expect(signals.n == 0)
        #expect(await listing.waitForGathering(timeout: 0.01))                      // gathered: answers at once
    }

    @Test func aStoppedListingGathersAgainAndTheLastSubscriberLeavingStopsIt() async throws {
        let (listing, _, counting, id) = listingWithSubscriber()
        defer { counting.cancel(); listing.stop() }
        let other = UUID()
        let (_, second) = AsyncStream<Void>.makeStream()
        listing.subscribe(other, second)
        listing.didFinishGathering()
        #expect(listing.isGathered)

        listing.unsubscribe(id)                                                     // one subscriber is left: it keeps listening
        #expect(listing.isGathered)
        listing.unsubscribe(other)                                                  // the last one (the switch was turned off)
        #expect(!listing.isGathered)                                                // a restart must gather again …
        #expect(await listing.waitForGathering(timeout: 0.01) == false)             // … not answer "gathered" with an empty result

        listing.didFinishGathering()
        listing.stop()
        #expect(!listing.isGathered)
    }
}
