import Foundation
import os

/// Phase SYNC, step S2b: the sync files in the user's iCloud Drive container. Every device writes ITS OWN file
/// `sync/<device id>.json` and reads the files of the others; the files sit in a `sync/` folder directly under the
/// container's root – NOT in its `Documents` folder, so they never show in the Files app.
///
/// Three small parts, each replaceable in the tests:
/// * `ICloudContainer` (`ICloudContainerLocating`) – finds the container's folder (off the main thread, cached),
/// * `ICloudFileListing` – tells which files of the other devices exist and whether each is downloaded
///   (`MetadataQueryListing` is the real one: an `NSMetadataQuery` on the main run loop),
/// * `ICloudSyncTransport` – the `SyncTransport`: waits for the listing, reads the other files through
///   `NSFileCoordinator`, writes this device's file, and passes the listing's change signal on.
///
/// The one rule that matters: **an empty answer from `readOthers()` means "the listing really holds no other device's
/// file"**. The engine treats its first successful read as first contact; an empty answer given only because iCloud's
/// listing had not arrived yet (or a file had not been downloaded yet) would let a new device stamp its settings as
/// newer than the ones of the user's old device. So the transport waits for the listing, gives pending downloads a
/// little time and otherwise throws.

// MARK: - errors

enum ICloudSyncError: Error, LocalizedError, Equatable {
    /// The container's folder cannot be found (not signed in to iCloud, iCloud Drive off, no entitlement).
    case containerUnavailable
    /// The query had not finished its first gathering within the limit.
    case listingNotReady
    /// Another device's file exists, but none could be read (still downloading, or the read failed).
    case otherDeviceFileNotReadable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable: "The iCloud folder is not available."
        case .listingNotReady: "iCloud has not listed the sync files yet."
        case .otherDeviceFileNotReadable: "Another device's sync file is not downloaded yet."
        }
    }
}

// MARK: - the container

/// Where the container is; replaceable in the tests.
protocol ICloudContainerLocating: Sendable {
    /// The user is signed in to iCloud. Called on every sync, so it must be cheap.
    var isSignedIn: Bool { get }
    /// The container's root folder; nil when it cannot be resolved.
    func root() async -> URL?
}

/// Finds the app's iCloud container once. `url(forUbiquityContainerIdentifier:)` may block for seconds the first time,
/// so it runs on a global queue, never on the main thread; a found URL is cached.
final class ICloudContainer: ICloudContainerLocating {
    static let identifier = "iCloud.sk.zrebec.sleephole"

    let identifier: String
    private let cached = OSAllocatedUnfairLock<URL?>(initialState: nil)

    init(identifier: String = ICloudContainer.identifier) { self.identifier = identifier }

    /// Cheap: the system keeps the token.
    var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// The container's root folder; nil when it cannot be resolved (nothing is cached then, the next call tries again).
    func root() async -> URL? {
        if let url = cached.withLock({ $0 }) { return url }
        let identifier = identifier
        let url: URL? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: FileManager.default.url(forUbiquityContainerIdentifier: identifier))
            }
        }
        if let url { cached.withLock { $0 = url } }
        return url
    }
}

// MARK: - the listing of the other devices' files

/// One file of the sync folder as the listing sees it.
struct ICloudFileEntry: Sendable, Equatable {
    let url: URL
    /// The newest version is on this device (`NSMetadataUbiquitousItemDownloadingStatusCurrent`).
    let isDownloaded: Bool
    /// A download is running right now.
    let isDownloading: Bool

    var name: String { url.lastPathComponent }
}

/// What the transport needs from the system's file listing. `@MainActor` because the real one lives on the main run
/// loop; the tests use a stand-in over a temporary folder.
@MainActor
protocol ICloudFileListing: Sendable {
    /// Waits until the first gathering of the listing has finished (true) or `timeout` seconds have passed (false).
    func waitUntilGathered(timeout: TimeInterval) async -> Bool
    /// Every `*.json` file of the sync folder, this device's own included.
    func entries() -> [ICloudFileEntry]
    /// Starts downloading a file of another device (a no-op when it is current).
    func requestDownload(of url: URL)
    /// Registers a stream that gets a signal whenever another device's file appeared, changed or finished downloading.
    func subscribe(_ id: UUID, _ continuation: AsyncStream<Void>.Continuation)
    /// The real listing ends its query when the last subscriber leaves.
    func unsubscribe(_ id: UUID)
    /// Stops the observation (the transport is gone).
    func stop()
}

/// The real listing: ONE `NSMetadataQuery` (ubiquitous data scope = the container outside `Documents`) started on the
/// main run loop, on demand. It signals for other devices' files only – never for this device's own file.
@MainActor
final class MetadataQueryListing: ICloudFileListing {
    private let ownName: String
    private let folderName: String
    /// false only in the tests of the waiting logic: no real query is started.
    private let startsQuery: Bool
    private var query: NSMetadataQuery?
    private var observers: [any NSObjectProtocol] = []
    private var gathered = false
    /// A waiter gave up before the first gathering ended: when it ends the engine is told to read at once (a read that
    /// failed with "not ready" has nothing else to wake it up).
    private var missedGathering = false
    private var waiters: [UUID: Waiter] = [:]
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]

    private struct Waiter {
        let continuation: CheckedContinuation<Bool, Never>
        let timer: Task<Void, Never>
    }

    init(ownName: String, folderName: String = ICloudSyncTransport.folderName, startsQuery: Bool = true) {
        self.ownName = ownName
        self.folderName = folderName
        self.startsQuery = startsQuery
    }

    // MARK: query

    /// Creates and starts the query once. The observers exist before `start()`, so no notification is missed.
    private func startIfNeeded() {
        guard startsQuery, query == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        q.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*.json")
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didFinishGathering() }
            },
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] note in
                // read the notification where it arrives, hand over only plain values
                let folder = self?.folderName ?? ""
                let added = Self.entries(in: note.userInfo?[NSMetadataQueryUpdateAddedItemsKey], folder: folder)
                let changed = Self.entries(in: note.userInfo?[NSMetadataQueryUpdateChangedItemsKey], folder: folder)
                MainActor.assumeIsolated { self?.didUpdate(added + changed) }
            },
        ]
        query = q
        q.start()
    }

    /// Items of the sync folder as plain values; `NSMetadataItem` never leaves this function.
    private nonisolated static func entries(in items: Any?, folder: String) -> [ICloudFileEntry] {
        (items as? [NSMetadataItem] ?? []).compactMap { entry(from: $0, folder: folder) }
    }

    private nonisolated static func entry(from item: NSMetadataItem, folder: String) -> ICloudFileEntry? {
        guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
              url.pathExtension == "json", url.deletingLastPathComponent().lastPathComponent == folder else { return nil }
        let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        let downloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false
        return ICloudFileEntry(url: url, isDownloaded: status == NSMetadataUbiquitousItemDownloadingStatusCurrent,
                               isDownloading: downloading)
    }

    func didFinishGathering() {
        gathered = true
        let all = waiters
        waiters = [:]
        for waiter in all.values { waiter.timer.cancel(); waiter.continuation.resume(returning: true) }
        if missedGathering {
            missedGathering = false
            signal()
        }
    }

    /// The first gathering of the current query has ended (tests).
    var isGathered: Bool { gathered }

    /// Other devices' files that appeared or changed. A file that is not current is asked for; the signal comes when it
    /// is (the download's own progress updates are no news).
    private func didUpdate(_ items: [ICloudFileEntry]) {
        var news = false
        for item in items where item.name != ownName {
            if item.isDownloaded { news = true } else if !item.isDownloading { requestDownload(of: item.url) }
        }
        if news { signal() }
    }

    private func signal() {
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield() { subscribers[id] = nil }
        }
    }

    // MARK: ICloudFileListing

    func waitUntilGathered(timeout: TimeInterval) async -> Bool {
        startIfNeeded()
        return await waitForGathering(timeout: timeout)
    }

    /// The waiting half of `waitUntilGathered` (tests call it without a query).
    func waitForGathering(timeout: TimeInterval) async -> Bool {
        if gathered { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            let timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.timedOut(id)
            }
            waiters[id] = Waiter(continuation: continuation, timer: timer)
        }
    }

    func timedOut(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        missedGathering = true
        waiter.continuation.resume(returning: false)
    }

    func entries() -> [ICloudFileEntry] {
        startIfNeeded()
        guard let query else { return [] }
        query.disableUpdates()                               // the results must not change under the loop
        defer { query.enableUpdates() }
        return query.results.compactMap { ($0 as? NSMetadataItem).flatMap { Self.entry(from: $0, folder: folderName) } }
    }

    func requestDownload(of url: URL) {
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    func subscribe(_ id: UUID, _ continuation: AsyncStream<Void>.Continuation) {
        startIfNeeded()
        subscribers[id] = continuation
    }

    /// The last one to leave ends the query: nobody watches the other devices' files any more (the engine unsubscribes
    /// when the user switches syncing off), so nothing may be listed or downloaded. It starts again, from scratch, with
    /// the next `subscribe` / `waitUntilGathered`.
    func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty { stop() }
    }

    func stop() {
        query?.stop()
        query = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        for continuation in subscribers.values { continuation.finish() }
        subscribers = [:]
        for waiter in waiters.values { waiter.timer.cancel(); waiter.continuation.resume(returning: false) }
        waiters = [:]
        gathered = false                                     // a restarted listing has to gather again, not answer "gathered"
        missedGathering = false
    }
}

// MARK: - the transport

final class ICloudSyncTransport: SyncTransport {
    /// The folder under the container's root that holds the sync files.
    static let folderName = "sync"
    /// Serial: one file operation at a time, never on the main actor and never on the cooperative pool (a coordinated
    /// read may wait for iCloud).
    private static let fileQueue = DispatchQueue(label: "sk.zrebec.sleephole.sync.files", qos: .utility)

    let deviceId: String
    private let container: any ICloudContainerLocating
    private let listing: any ICloudFileListing
    /// How long `readOthers()` waits for the first gathering of the listing.
    private let gatherWait: TimeInterval
    /// How long it waits for files of other devices that are not downloaded yet.
    private let downloadWait: TimeInterval
    private let pollInterval: TimeInterval

    init(deviceId: String, container: any ICloudContainerLocating, listing: any ICloudFileListing,
         gatherWait: TimeInterval = 10, downloadWait: TimeInterval = 8, pollInterval: TimeInterval = 0.25) {
        self.deviceId = SyncDevice.fileSafe(deviceId)
        self.container = container
        self.listing = listing
        self.gatherWait = gatherWait
        self.downloadWait = downloadWait
        self.pollInterval = pollInterval
    }

    /// The real transport on a real iPhone: the app's container and an `NSMetadataQuery` listing.
    @MainActor
    convenience init(deviceId: String) {
        let safe = SyncDevice.fileSafe(deviceId)
        self.init(deviceId: safe, container: ICloudContainer(),
                  listing: MetadataQueryListing(ownName: Self.fileName(forDevice: safe)))
    }

    deinit {
        let listing = listing
        Task { @MainActor in listing.stop() }
    }

    static func fileName(forDevice id: String) -> String { SyncDevice.fileSafe(id) + ".json" }
    private var ownName: String { Self.fileName(forDevice: deviceId) }

    private func syncFolder() async -> URL? {
        await container.root()?.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    // MARK: SyncTransport

    func isAvailable() async -> Bool {
        guard container.isSignedIn else { return false }
        return await container.root() != nil
    }

    func write(_ data: Data) async throws {
        guard let folder = await syncFolder() else { throw ICloudSyncError.containerUnavailable }
        let url = folder.appendingPathComponent(ownName)
        try await onFileQueue { try Self.coordinatedWrite(data, to: url, in: folder) }
    }

    func readOthers() async throws -> [Data] {
        guard await syncFolder() != nil else { throw ICloudSyncError.containerUnavailable }
        guard await listing.waitUntilGathered(timeout: gatherWait) else { throw ICloudSyncError.listingNotReady }

        // files of other devices that are not downloaded are asked for, and given a little time to arrive
        let own = ownName
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(downloadWait))
        var requested = Set<URL>()
        var others: [ICloudFileEntry]
        while true {
            others = await listing.entries().filter { $0.name != own }.sorted { $0.name < $1.name }
            let pending = others.filter { !$0.isDownloaded }
            for entry in pending where requested.insert(entry.url).inserted { await listing.requestDownload(of: entry.url) }
            if pending.isEmpty || clock.now >= deadline { break }
            try await Task.sleep(for: .seconds(pollInterval))
        }

        var datas: [Data] = []
        var firstFailure: Error?
        for entry in others where entry.isDownloaded {
            let url = entry.url
            do { datas.append(try await onFileQueue { try Self.coordinatedRead(url) }) } catch { firstFailure = firstFailure ?? error }
        }
        // `[]` only when the listing holds no other device's file at all – never because nothing could be read
        if datas.isEmpty, !others.isEmpty { throw firstFailure ?? ICloudSyncError.otherDeviceFileNotReadable }
        return datas
    }

    /// The stream owns the observation: its termination closure keeps the listing alive and unsubscribes.
    var changes: AsyncStream<Void> {
        let listing = listing
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            Task { @MainActor in listing.subscribe(id, continuation) }
            continuation.onTermination = { _ in Task { @MainActor in listing.unsubscribe(id) } }
        }
    }

    // MARK: files

    private func onFileQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.fileQueue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private static func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func coordinatedWrite(_ data: Data, to url: URL, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var result: Result<Void, Error> = .success(())
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            result = Result { try data.write(to: writeURL, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}
