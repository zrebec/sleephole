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

    var body: some View {
        let snapshot = model.townSnapshot
        let render = model.townRender
        NavigationStack {
            ZStack(alignment: .top) {
                if let render {
                    TownSpriteView(model: render, focus: model.townFocus, version: model.townVersion,
                                   imageProvider: { sprites.image(for: $0) },
                                   onTap: { selected = $0 })
                        .ignoresSafeArea(edges: [.horizontal, .bottom])
                }
                header(snapshot)
            }
            .navigationTitle("Mesto")
            .navigationBarTitleDisplayMode(.inline)
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
        let people = snapshot.map { TownStats.population($0, catalog: model.catalog) } ?? 0
        HStack(spacing: 14) {
            Label("\(count)", systemImage: "building.2.fill")
            Label("\(people)", systemImage: "person.2.fill")
            Text("🪙 \(model.coins)")
            if (snapshot?.buildings.isEmpty ?? true) {
                Text("Prvá budova pribudne po prvej noci 🌙").font(.caption)
            }
        }
        .font(.subheadline.bold())
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
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
        let name = model.catalog?[building.buildingId]?.nameSK ?? "Budova"
        VStack(spacing: 10) {
            BuildingImage(id: sheetSprite, progress: building.state == .unfinished ? 0.6 : 1, maxHeight: 130)
            Text(name).font(.title2.bold())
            Text("Noc \(formatted(building.nightKey))").foregroundStyle(.secondary)
            switch building.state {
            case .complete:
                Label(building.repairedLater ? "Opravená 🛠️ – z ruiny je zase budova"
                      : building.completedLater ? "Dostavaná neskôr 💪" : "Hotová 🎉", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .unfinished:
                Label("Rozostavaná – dokončí ju ďalšia dobrá noc", systemImage: "hammer.fill").foregroundStyle(.orange)
            case .ruins:
                Label("Ruina – aj to patrí k mestu 🌱", systemImage: "leaf.fill").foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var sheetSprite: String {
        building.state == .ruins ? "o-ruin-\(building.placement.size)" : building.buildingId
    }

    private func formatted(_ k: NightKey) -> String { "\(k.day). \(k.month). \(k.year)" }
}

enum TownStats {
    /// Rough population for the header (plan §7.4).
    static func population(_ town: TownSnapshot, catalog: Catalog?) -> Int {
        town.buildings.reduce(0) { sum, b in
            guard b.state != .ruins else { return sum }
            let id = b.buildingId
            let full: Int = id.hasPrefix("l1-house") ? 4 : id.hasPrefix("l1-block") ? 20
                : id.hasPrefix("l1-bigblock") ? 60 : id.hasPrefix("l4") ? 300 : 0
            return sum + (b.state == .unfinished ? full / 2 : full)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
