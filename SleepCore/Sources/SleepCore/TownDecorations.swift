import Foundation

/// The 12 town decorations the mystery boxes give (build 11b5c): which sprite belongs to which collectible id, and where
/// the owned ones stand. Nothing here is stored – the cells are a pure function of the town and of the ids owned, so a
/// decoration may move to another cell when the town grows.
public enum TownDecorations {
    /// `BoxCatalog.ids(.decoration)` (`decoration-01` … `decoration-12`) → sprite id, in this fixed order. Never reorder.
    public static let spriteIds: [String] = [
        "d-fountain", "d-cat-statue", "d-windmill", "d-gazebo", "d-bench-lamp", "d-flower-bed",
        "d-well", "d-sign", "d-clock-tower", "d-campfire", "d-pines", "d-stall",
    ]

    /// The sprite of a collectible id; nil for an id this version does not know (a later build's decoration).
    public static func spriteId(for collectibleId: String) -> String? {
        guard let i = BoxCatalog.ids(.decoration).firstIndex(of: collectibleId), spriteIds.indices.contains(i) else { return nil }
        return spriteIds[i]
    }

    public struct Placed: Equatable, Sendable {
        public let collectibleId: String
        public let spriteId: String
        public let cell: Cell
    }

    public struct Layout: Equatable, Sendable {
        public let placed: [Placed]
        /// The grass margin around the town (cells beyond the drawn roads and the buildings); 2 unless the decorations
        /// needed a wider one.
        public let margin: Int
    }

    /// Where the owned decorations (ids in the order they were won; unknown ids and duplicates are skipped) stand.
    ///
    /// Rule: on grass OUTSIDE the town only – never on a road cell of the grid (drawn or not), never in a block that has a
    /// building or whose street ring is drawn (those cells are lots) – inside the grass area `TownRender` draws (the
    /// bounding box of buildings and drawn roads plus the margin). The FRONT first (the largest col + row, the middle of
    /// that edge before its sides), no two decorations in 8-neighbour cells. If the free grass is too small the margin
    /// grows until every decoration fits.
    public static func layout(town: TownLayout, owned: [String]) -> Layout {
        var seen = Set<String>()
        let wanted = owned.compactMap { id -> (String, String)? in
            guard let sprite = spriteId(for: id), seen.insert(id).inserted else { return nil }
            return (id, sprite)
        }
        let base = TownRender.margin
        guard !wanted.isEmpty else { return Layout(placed: [], margin: base) }

        let roads = town.drawnRoads, occupied = town.occupied
        let cells = occupied.union(roads)
        let (cmin, cmax) = (cells.map(\.col).min() ?? 0, cells.map(\.col).max() ?? 0)
        let (rmin, rmax) = (cells.map(\.row).min() ?? 0, cells.map(\.row).max() ?? 0)
        let usedBlocks = Set(occupied.map { TownLayout.block($0) })
        var townBlock: [Cell: Bool] = [:]
        func isTown(_ b: Cell) -> Bool {
            if let v = townBlock[b] { return v }
            let v = usedBlocks.contains(b) || TownLayout.ring(of: b).isSubset(of: roads)
            townBlock[b] = v
            return v
        }

        for margin in base... {
            let (c0, c1, r0, r1) = (cmin - margin, cmax + margin, rmin - margin, rmax + margin)
            let mid = Double((c0 - r1) + (c1 - r0)) / 2                      // the middle of the front edge, as col − row
            var free: [Cell] = []
            for c in c0...c1 {
                for r in r0...r1 {
                    let cell = Cell(c, r)
                    if !TownLayout.isRoad(cell), !isTown(TownLayout.block(cell)) { free.append(cell) }
                }
            }
            free.sort {
                let a = (-($0.col + $0.row), abs(Double($0.col - $0.row) - mid), $0.col)
                let b = (-($1.col + $1.row), abs(Double($1.col - $1.row) - mid), $1.col)
                return a < b
            }
            var placed: [Placed] = []
            var taken: [Cell] = []
            for (id, sprite) in wanted {
                guard let cell = free.first(where: { f in
                    !taken.contains { abs($0.col - f.col) <= 1 && abs($0.row - f.row) <= 1 }
                }) else { break }
                taken.append(cell)
                placed.append(Placed(collectibleId: id, spriteId: sprite, cell: cell))
            }
            if placed.count == wanted.count { return Layout(placed: placed, margin: margin) }
        }
        fatalError("unreachable: the margin grows until everything fits")
    }
}
