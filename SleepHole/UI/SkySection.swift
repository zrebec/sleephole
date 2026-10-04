import SwiftUI

/// Settings → Sky: the owner's city for the real sun and moon (plan SKY). Owner's layout rule: the label on its own
/// row, the field on the row below (long city names), the status icon AFTER the field – a black ✕ that turns into a
/// green ✓ once the city is verified. Works during a running night too (it changes nothing about the night).
struct SkySection: View {
    @Environment(AppModel.self) private var model
    @State private var field: CityField?
    @FocusState private var focused: Bool

    /// `field` is for tests (a field with a fake search in a chosen state); the app creates its own on appear.
    init(field: CityField? = nil) { _field = State(initialValue: field) }

    /// Dev aid: `-cityQuery Brat` pre-fills the field so the real Apple Maps search runs (screenshots).
    private static let launchQuery: String? = {
        let a = ProcessInfo.processInfo.arguments
        return a.firstIndex(of: "-cityQuery").flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil }
    }()

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Your city")).font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    TextField(L("e.g. Bratislava"),
                              text: Binding(get: { field?.text ?? model.settings.city?.name ?? "" },
                                            set: { field?.edit($0) }))
                        .textContentType(.addressCity)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                    statusIcon
                        .frame(width: 26, height: 26)
                }
            }
            ForEach(field?.suggestions ?? []) { suggestion in
                Button {
                    focused = false
                    field?.choose(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: suggestion.title).foregroundStyle(.primary)
                        if !suggestion.subtitle.isEmpty {
                            Text(verbatim: suggestion.subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if field?.notFound == true {
                Text(L("No such city found")).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Sky")).id("sky")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let city = model.settings.city {
                    Text(L("Today shows the real sun and moon for \(city.name)."))
                } else {
                    Text(L("Type your city and Today shows the real sun and moon. Without a city the sky follows your bedtime."))
                }
                Text(L("The search uses Apple Maps. SleepHole never asks for your location."))
            }
        }
        .onAppear {
            guard field == nil else { return }
            let f = CityField(search: MapKitCitySearch(), city: model.settings.city) { model.settings.city = $0 }
            field = f
            if let q = Self.launchQuery { f.edit(q) }
        }
        .onChange(of: model.settings.city) { _, city in field?.sync(with: city) }   // e.g. a restored backup
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch field?.status ?? (model.settings.city == nil ? .empty : .verified) {
        case .verified:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityLabel(L("City verified"))
        case .checking:
            ProgressView()
        case .empty, .unverified:
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityLabel(L("City not verified"))
        }
    }
}
