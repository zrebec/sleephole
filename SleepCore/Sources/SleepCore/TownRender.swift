import Foundation

/// Dimetric 2:1 projection shared with the sprite renderer (plan §3.3). Scene units = sprite pixels,
/// SpriteKit convention (y up).
public enum IsoProjection {
    public static let tileWidth = 256.0
    public static let tileHeight = 128.0

    /// Footprint centre (tile units, x = col, z = row) → scene point.
    public static func scenePoint(x: Double, z: Double) -> ScenePoint {
        ScenePoint(x: (x - z) * tileWidth / 2, y: -(x + z) * tileHeight / 2)
    }

    /// Scene point → the grid cell under it (on the ground plane).
    public static func cell(at p: ScenePoint) -> Cell {
        let a = p.x / (tileWidth / 2), b = -p.y / (tileHeight / 2)       // a = x − z, b = x + z
        return Cell(Int(((a + b) / 2).rounded()), Int(((b - a) / 2).rounded()))
    }
}

public struct ScenePoint: Equatable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct SceneRect: Equatable, Sendable {
    public var minX: Double, minY: Double, maxX: Double, maxY: Double
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }
    public func contains(_ p: ScenePoint) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }
    public func union(_ o: SceneRect) -> SceneRect {
        SceneRect(minX: min(minX, o.minX), minY: min(minY, o.minY), maxX: max(maxX, o.maxX), maxY: max(maxY, o.maxY))
    }
    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var mid: ScenePoint { ScenePoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }
}

/// One sprite to draw. The app turns each into an `SKSpriteNode` 1:1.
public struct SpriteInstance: Equatable, Sendable {
    public enum Layer: Int, Sendable { case ground, road, object }
    public let spriteId: String
    public let position: ScenePoint          // where the sprite's anchor goes
    public let anchor: [Double]
    public let size: [Double]
    public let zPosition: Double
    public let layer: Layer
    /// 1 = whole sprite; < 1 = only the lowest fraction is shown (unfinished building).
    public let reveal: Double
    /// Index into `TownSnapshot.buildings` (tap → details), nil for terrain/roads/overlays.
    public let buildingIndex: Int?

    /// Sprite bounds in scene space.
    public var frame: SceneRect {
        let left = position.x - anchor[0] * size[0], bottom = position.y - anchor[1] * size[1]
        return SceneRect(minX: left, minY: bottom, maxX: left + size[0], maxY: bottom + size[1])
    }
}

/// Everything the town scene needs: sprites in draw order + the camera bounds.
public struct TownRenderModel: Equatable, Sendable {
    public let sprites: [SpriteInstance]
    public let bounds: SceneRect
    public let buildingCount: Int
}

public enum TownRender {
    /// A ruin older than this many days is overgrown with flowers ("never cruel").
    public static let flowersAfterDays = 7
    public static let unfinishedReveal = 0.6
    static let margin = 2

    public static func build(_ town: TownSnapshot, catalog: Catalog, today: NightKey,
                             calendar: Calendar) -> TownRenderModel {
        var sprites: [SpriteInstance] = []
        let roads = town.layout.drawnRoads
        let occupied = town.layout.occupied
        let cells = occupied.union(roads)

        // Ground: grass everywhere in the bounding box (+margin) except under roads.
        let cols = cells.map(\.col), rows = cells.map(\.row)
        let (c0, c1) = ((cols.min() ?? 0) - margin, (cols.max() ?? 0) + margin)
        let (r0, r1) = ((rows.min() ?? 0) - margin, (rows.max() ?? 0) + margin)
        for c in c0...c1 {
            for r in r0...r1 where !roads.contains(Cell(c, r)) {
                let id = (c + r) % 2 == 0 ? "t-grass-a" : "t-grass-b"
                if let s = instance(id, catalog, x: Double(c), z: Double(r), z0: -1_000_000 + Double(c + r),
                                    layer: .ground) { sprites.append(s) }
            }
        }
        for cell in roads.sorted(by: { ($0.col + $0.row, $0.col) < ($1.col + $1.row, $1.col) }) {
            let id = RoadTiles.spriteId(at: cell, roads: roads, lit: town.layout.litRoads, catalog: catalog)
            if let s = instance(id, catalog, x: Double(cell.col), z: Double(cell.row),
                                z0: -500_000 + Double(cell.col + cell.row), layer: .road) { sprites.append(s) }
        }

        // Buildings (painter's order by the front-most covered tile, plan §3.3).
        for (i, b) in town.buildings.enumerated() {
            let fp = b.placement.size
            let (x, z) = b.placement.centre
            let depth = Double(b.placement.depth) * 10
            switch b.state {
            case .complete:
                sprites += instance(b.buildingId, catalog, x: x, z: z, z0: depth, layer: .object, index: i).map { [$0] } ?? []
            case .unfinished:
                sprites += instance(b.buildingId, catalog, x: x, z: z, z0: depth, layer: .object,
                                    reveal: unfinishedReveal, index: i).map { [$0] } ?? []
                sprites += instance("o-scaffold-\(fp)", catalog, x: x, z: z, z0: depth + 1, layer: .object).map { [$0] } ?? []
            case .ruins:
                let old = daysBetween(b.nightKey, today, calendar) >= flowersAfterDays
                let id = old ? "o-ruin-flowers-\(fp)" : "o-ruin-\(fp)"
                sprites += instance(id, catalog, x: x, z: z, z0: depth, layer: .object, index: i).map { [$0] } ?? []
            }
        }

        let bounds = sprites.map(\.frame).reduce(nil as SceneRect?) { $0?.union($1) ?? $1 }
            ?? SceneRect(minX: -256, minY: -256, maxX: 256, maxY: 256)
        return TownRenderModel(sprites: sprites.sorted { $0.zPosition < $1.zPosition }, bounds: bounds,
                               buildingCount: town.buildings.count)
    }

    /// Buildings whose sprite rectangle contains `p`, front-most first. Rectangles overlap (transparent
    /// margins, shadows), so the app picks the first candidate with an opaque pixel at `p`.
    public static func buildingCandidates(at p: ScenePoint, in model: TownRenderModel) -> [SpriteInstance] {
        model.sprites.reversed().filter { $0.buildingIndex != nil && $0.frame.contains(p) }
    }

    /// Position of `p` inside the sprite's image, in pixels from the TOP-left (for alpha lookups).
    public static func pixel(of p: ScenePoint, in s: SpriteInstance) -> (x: Int, y: Int) {
        let f = s.frame
        return (Int(p.x - f.minX), Int(f.maxY - p.y))
    }

    /// Keeps the camera centre inside the town bounds.
    public static func clamp(_ p: ScenePoint, to bounds: SceneRect) -> ScenePoint {
        ScenePoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    static func daysBetween(_ a: NightKey, _ b: NightKey, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: a.noon(calendar), to: b.noon(calendar)).day ?? 0
    }

    private static func instance(_ id: String, _ catalog: Catalog, x: Double, z: Double, z0: Double,
                                 layer: SpriteInstance.Layer, reveal: Double = 1, index: Int? = nil) -> SpriteInstance? {
        guard let e = catalog[id] else { return nil }
        return SpriteInstance(spriteId: id, position: IsoProjection.scenePoint(x: x, z: z), anchor: e.anchor,
                              size: e.size.map(Double.init), zPosition: z0, layer: layer, reveal: reveal,
                              buildingIndex: index)
    }
}
