import SleepCore
import SpriteKit
import SwiftUI

/// SKView wrapper with UIKit gestures (smooth pan with inertia, pinch around the fingers, taps).
struct TownSpriteView: UIViewRepresentable {
    let model: TownRenderModel
    let focus: ScenePoint?
    let version: Int
    let imageProvider: (String) -> UIImage?
    let onTap: (Int?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.allowsTransparency = true          // the living sky shows around the floating town
        view.backgroundColor = .clear
        view.ignoresSiblingOrder = false
        view.preferredFramesPerSecond = 60
        let scene = TownScene(size: CGSize(width: 400, height: 800))
        scene.imageProvider = imageProvider
        view.presentScene(scene)
        context.coordinator.scene = scene
        context.coordinator.view = view

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        [pan, pinch, tap, doubleTap].forEach { view.addGestureRecognizer($0) }
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        scene.show(model, focus: focus)
        context.coordinator.shownVersion = version
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        context.coordinator.onTap = onTap
        guard context.coordinator.shownVersion != version else { return }
        context.coordinator.shownVersion = version
        context.coordinator.scene?.show(model, focus: focus)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var scene: TownScene?
        weak var view: SKView?
        var onTap: (Int?) -> Void
        var shownVersion = -1

        init(onTap: @escaping (Int?) -> Void) { self.onTap = onTap }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let view else { return }
            let t = g.translation(in: view)
            scene?.pan(by: t)
            g.setTranslation(.zero, in: view)
            if g.state == .ended { scene?.fling(velocity: g.velocity(in: view)) }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let view else { return }
            scene?.zoom(by: g.scale, at: g.location(in: view), in: view)
            g.scale = 1
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            onTap(scene?.building(atView: g.location(in: view)))
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            scene?.animateZoom(in: g.location(in: view), view: view)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// "Mesto" tab.
struct TownTab: View {
    @Environment(AppModel.self) private var model
    @Environment(SpriteLibrary.self) private var sprites
    @State private var selected: Int?
    @State private var renaming = false
    @State private var showNumbers = false

    var body: some View {
        let snapshot = model.townSnapshot
        let render = model.townRender
        NavigationStack {
            ZStack(alignment: .top) {
                LivingSky()
                if let render {
                    TownSpriteView(model: render, focus: model.townFocus, version: model.townVersion,
                                   imageProvider: { sprites.image(for: $0) },
                                   onTap: { selected = $0 })
                        .ignoresSafeArea(edges: [.horizontal, .bottom])
                }
                header(snapshot)
            }
            .navigationTitle(L("Town"))
            .toolbar(.hidden, for: .navigationBar)          // the header card already names the town
            .renameTownAlert(isPresented: $renaming)
            .onAppear { if DevArgs.list.contains("-openTownNumbers") { showNumbers = true } }   // screenshots
            .sheet(isPresented: $showNumbers) {
                if let snapshot { TownNumbersSheet(town: snapshot) }
            }
            .sheet(item: Binding(get: { selected.map(SelectedBuilding.init) }, set: { selected = $0?.index })) { sel in
                if let b = snapshot?.buildings[safe: sel.index] {
                    BuildingSheet(building: b)
                        .presentationDetents([.fraction(0.42)])
                }
            }
        }
    }

    @ViewBuilder
    private func header(_ snapshot: TownSnapshot?) -> some View {
        let count = snapshot?.buildings.filter { $0.state == .complete }.count ?? 0
        let people = snapshot.map { TownStats.population($0) } ?? 0
        VStack(spacing: 2) {
            Button {
                renaming = true
            } label: {
                Label { Text(verbatim: model.townName) } icon: { Image(systemName: "pencil").font(.caption) }
                    .font(.headline)
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("Rename the town"))
            Text(TownStats.sizeName(residents: people)).font(.caption).foregroundStyle(.secondary)
            Button {
                showNumbers = true
            } label: {
                HStack(spacing: 14) {
                    Label { Text(verbatim: "\(count)") } icon: { Image(systemName: "building.2.fill") }
                    Label { Text(verbatim: "\(people)") } icon: { Image(systemName: "person.2.fill") }
                    Text(verbatim: "🪙 \(model.coins)")
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("The town in numbers"))
            if (snapshot?.buildings.isEmpty ?? true) {
                Text(L("Your first building appears after your first night 🌙")).font(.caption)
            }
        }
        .font(.subheadline.bold())
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassCard(cornerRadius: 18)
        .padding(.top, 8)
    }
}

/// "My Town ✎" – the pencil after the text.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon.cardCaption() }
    }
}

private struct SelectedBuilding: Identifiable {
    let index: Int
    var id: Int { index }
}

struct BuildingSheet: View {
    @Environment(AppModel.self) private var model
    let building: TownBuilding

    var body: some View {
        let name = model.catalog?[building.buildingId]?.displayName ?? L("Building")
        VStack(spacing: 10) {
            BuildingImage(id: sheetSprite, progress: building.state == .unfinished ? 0.6 : 1, maxHeight: 130)
            Text(name).font(.title2.bold())
            Text(L("Night of \(Fmt.fullDate(building.nightKey))")).foregroundStyle(.secondary)
            let residents = Population.residents(of: building)
            if residents > 0 {
                Label(L("\(residents) people live here"), systemImage: "person.2.fill").foregroundStyle(.secondary)
            }
            switch building.state {
            case .complete:
                Label(building.repairedLater ? L("Repaired 🛠️ – the ruin is a building again")
                      : building.completedLater ? L("Finished later 💪") : L("Complete 🎉"), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .unfinished:
                Label(L("Unfinished – your next good night will finish it"), systemImage: "hammer.fill").foregroundStyle(.orange)
            case .ruins:
                Label(L("Ruins – part of the town too 🌱"), systemImage: "leaf.fill").foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var sheetSprite: String {
        building.state == .ruins ? "o-ruin-\(building.placement.size)" : building.buildingId
    }
}

enum TownStats {
    /// Residents of the whole town (SleepCore `Population`, deterministic per building).
    static func population(_ town: TownSnapshot) -> Int { Population.total(town) }

    static func sizeName(residents: Int) -> String {
        switch TownSize.of(residents: residents) {
        case .hamlet: L("Hamlet")
        case .village: L("Village")
        case .smallTown: L("Small town")
        case .town: L("Town")
        case .city: L("City (large)")
        case .bigCity: L("Big city")
        case .metropolis: L("Metropolis")
        }
    }
}

/// "The town in numbers": explains why the header's building count and the Stats' "nights built" can differ.
struct TownNumbersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let town: TownSnapshot

    var body: some View {
        let complete = town.buildings.filter { $0.state == .complete }.count
        let unfinished = town.buildings.filter { $0.state == .unfinished }.count
        let ruins = town.buildings.filter { $0.state == .ruins }.count
        let people = TownStats.population(town)
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 10) {
                        row("building.2.fill", L("Complete buildings"), complete)
                        row("hammer.fill", L("Unfinished buildings"), unfinished)
                        row("leaf.fill", L("Ruins (count)"), ruins)
                        row("lightbulb.fill", L("Lit street cells"), town.layout.litRoads.count)
                        row("person.2.fill", L("Residents"), people)
                        row("moon.stars.fill", L("Nights built"), model.builtNights)
                    }
                    .padding(14)
                    .glassCard()
                    Text(L("Ruins, unfinished buildings and lit streets are part of the town too, so the numbers can differ from the nights you built."))
                        .font(.footnote).cardCaption().multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle(L("The town in numbers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func row(_ icon: String, _ title: String, _ value: Int) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 26)
            Text(title)
            Spacer()
            Text(verbatim: "\(value)").bold().monospacedDigit()
        }
        .font(.subheadline)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
