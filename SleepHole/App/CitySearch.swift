import Foundation
import MapKit
import Observation

// City search for the real sky (plan SKY, owner 2026-10-02): Apple Maps through `MKLocalSearchCompleter` (the
// suggestions while typing) and `MKLocalSearch` (the coordinates of the chosen city). NO location permission and no
// tracking: nothing here ever asks where the phone is, and the completer's region is never set.

/// One line of the suggestion list.
struct CitySuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        id = title + "\u{1F}" + subtitle
    }

    /// The text that finds exactly this suggestion again with `CitySearch.resolve`.
    var query: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
}

/// Where cities come from. `MapKitCitySearch` in the app, a fake in the tests (tests never touch the network).
@MainActor
protocol CitySearch: Sendable {
    /// Completions for what is typed so far – at most 5; empty when there are none or the network is away.
    func suggestions(for text: String) async -> [CitySuggestion]
    /// The best match for `text` as a city; nil = nothing found / offline.
    func resolve(_ text: String) async -> SkyCity?
}

/// The city logic of the Settings field, without any view (plan SKY, §3): typing → `.unverified` at once, the check
/// runs ≈ 0.5 s after the last keystroke; a verified city is stored through `onChange`.
@MainActor
@Observable
final class CityField {
    enum Status: Equatable { case empty, unverified, checking, verified }

    private(set) var text: String
    private(set) var suggestions: [CitySuggestion] = []
    private(set) var status: Status
    /// "No such city found": nothing to suggest and nothing resolved.
    private(set) var notFound = false
    /// The stored city. Editing the text does NOT remove it – only a newly verified city replaces it and only an
    /// empty field removes it.
    private(set) var city: SkyCity?

    @ObservationIgnored private let search: any CitySearch
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let onChange: (SkyCity?) -> Void
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(search: any CitySearch, city: SkyCity?, debounce: Duration = .milliseconds(500),
         onChange: @escaping (SkyCity?) -> Void) {
        self.search = search
        self.city = city
        delay = debounce
        self.onChange = onChange
        text = city?.name ?? ""
        status = city == nil ? .empty : .verified
    }

    /// The text field's new content (every keystroke).
    func edit(_ new: String) {
        pending?.cancel()
        pending = nil
        text = new
        notFound = false
        let typed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            suggestions = []
            status = .empty
            store(nil)
            return
        }
        status = .unverified
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.check(typed)
        }
    }

    /// A tapped suggestion: resolve exactly that line.
    func choose(_ suggestion: CitySuggestion) {
        pending?.cancel()
        status = .checking
        notFound = false
        pending = Task { [weak self] in
            guard let self else { return }
            let found = await search.resolve(suggestion.query)
            guard !Task.isCancelled else { return }
            if let found {
                accept(found)
            } else {
                status = .unverified
                notFound = true
            }
        }
    }

    /// The stored city changed elsewhere (a restored backup): show it.
    func sync(with other: SkyCity?) {
        guard other != city else { return }
        pending?.cancel()
        pending = nil
        city = other
        text = other?.name ?? ""
        status = other == nil ? .empty : .verified
        suggestions = []
        notFound = false
    }

    /// Waits for the pending check (tests, instead of sleeping).
    func settle() async { await pending?.value }

    // MARK: - private

    private func check(_ typed: String) async {
        async let list = search.suggestions(for: typed)
        async let resolved = search.resolve(typed)
        let (candidates, found) = await (list, resolved)
        guard !Task.isCancelled else { return }
        if let found, Self.same(found.name, typed) {
            accept(found)
        } else {
            suggestions = Array(candidates.prefix(5))
            notFound = candidates.isEmpty && found == nil
            status = .unverified
        }
    }

    private func accept(_ found: SkyCity) {
        store(found)
        text = found.name
        suggestions = []
        notFound = false
        status = .verified
    }

    private func store(_ new: SkyCity?) {
        guard new != city else { return }
        city = new
        onChange(new)
    }

    /// Equal ignoring case and diacritics ("bratislava" = "Bratislava", "Zilina" = "Žilina").
    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(b.trimmingCharacters(in: .whitespacesAndNewlines),
                     options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == .orderedSame
    }
}

/// Apple Maps. `MKLocalSearchCompleter` is delegate-based: each query waits for its callback (with a watchdog, in
/// case the network never answers) and a newer query cancels the older one.
@MainActor
final class MapKitCitySearch: NSObject, CitySearch, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var waiting: CheckedContinuation<[CitySuggestion], Never>?
    private var generation = 0
    private static let timeout: Duration = .seconds(6)

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // no address filter here: with `.locality` the completer lists Bratislava's districts but not "Bratislava"
        // itself (tried in the simulator); `resolve` below does use it, so a tapped street or region still ends in a city
    }

    /// Only cities (localities) for `resolve` – no streets or postcodes.
    private static let cities = MKAddressFilter(including: .locality)

    func suggestions(for text: String) async -> [CitySuggestion] {
        finish([])                                   // a newer query cancels the older one
        completer.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        generation += 1
        let mine = generation
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[CitySuggestion], Never>) in
                waiting = continuation
                completer.queryFragment = query
                Task { [weak self] in
                    try? await Task.sleep(for: Self.timeout)
                    if self?.generation == mine { self?.finish([]) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.generation == mine { self?.finish([]) }
            }
        }
    }

    func resolve(_ text: String) async -> SkyCity? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        request.addressFilter = Self.cities
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        return Self.city(from: item)
    }

    /// The city's own name (the locality) when the item has one, else the item's name; its coordinate.
    static func city(from item: MKMapItem) -> SkyCity? {
        let name: String?
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26.0, *) {
            name = item.addressRepresentations?.cityName ?? item.name
            coordinate = item.location.coordinate
        } else {
            name = item.placemark.locality ?? item.name
            coordinate = item.placemark.coordinate
        }
        guard let name, !name.isEmpty, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return SkyCity(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func finish(_ list: [CitySuggestion]) {
        guard let continuation = waiting else { return }
        waiting = nil
        continuation.resume(returning: list)
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let list = completer.results.prefix(5).map { CitySuggestion(title: $0.title, subtitle: $0.subtitle) }
        Task { @MainActor [weak self] in self?.finish(list) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in self?.finish([]) }
    }
}
