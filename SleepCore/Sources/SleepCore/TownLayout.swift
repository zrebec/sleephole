import Foundation

/// A grid cell. `col` grows East (+x, screen down-right), `row` grows South (+z, screen down-left).
public struct Cell: Codable, Hashable, Sendable, CustomStringConvertible {
    public let col: Int, row: Int
    public init(_ col: Int, _ row: Int) { self.col = col; self.row = row }
    public var description: String { "(\(col),\(row))" }
    public func offset(_ dc: Int, _ dr: Int) -> Cell { Cell(col + dc, row + dr) }
}

/// A building placed in the town.
public struct Placement: Codable, Equatable, Sendable {
    public let catalogId: String
    public let origin: Cell          // top-left (north-west-most) cell
    public let size: Int             // 1 or 2 (square footprints only)

    public var cells: [Cell] {
        (0..<size).flatMap { dc in (0..<size).map { dr in origin.offset(dc, dr) } }
    }
    /// Footprint centre in tile units (for IsoProjection).
    public var centre: (x: Double, z: Double) {
        (Double(origin.col) + Double(size - 1) / 2, Double(origin.row) + Double(size - 1) / 2)
    }
    /// Painter's-algorithm depth: the front-most covered tile (plan §3.3).
    public var depth: Int { origin.col + size - 1 + origin.row + size - 1 }
}

/// Deterministic town layout that grows outward from the centre (plan §7.1).
///
/// Every cell with `col % 5 == 0 || row % 5 == 0` is road → blocks of 4×4 lots = four 2×2 quadrants.
/// Blocks are filled one by one in a square spiral around the centre; 2×2 buildings never straddle a road.
///
/// Streets come first (SimCity style): the 20 road cells around every started block are drawn, plus the ring of
/// the next, still empty block in spiral order – so the player sees where the town is going to grow.
public struct TownLayout: Codable, Equatable, Sendable {
    public static let blockPitch = 5
    public private(set) var placements: [Placement] = []
    public private(set) var litRoads: Set<Cell> = []

    public init(placements: [Placement] = [], litRoads: Set<Cell> = []) {
        self.placements = placements
        self.litRoads = litRoads
    }

    // MARK: grid

    static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }
    static func floorDiv(_ a: Int, _ n: Int) -> Int { Int((Double(a) / Double(n)).rounded(.down)) }

    public static func isRoad(_ c: Cell) -> Bool { mod(c.col, blockPitch) == 0 || mod(c.row, blockPitch) == 0 }
    static func block(_ c: Cell) -> Cell { Cell(floorDiv(c.col, blockPitch), floorDiv(c.row, blockPitch)) }

    /// Blocks in spiral order around the centre (the 4 blocks touching the origin crossroad first).
    static func blocks(ring k: Int) -> [Cell] {
        // block b spans cells 5b+1…5b+4; its "ring" is max(|2bx+1|, |2by+1|) = 1, 3, 5, …
        let ring = 2 * k - 1
        var out: [Cell] = []
        for bx in -k...(k - 1) {
            for by in -k...(k - 1) where max(abs(2 * bx + 1), abs(2 * by + 1)) == ring {
                out.append(Cell(bx, by))
            }
        }
        return out.sorted {
            let a0 = atan2(Double(2 * $0.row + 1), Double(2 * $0.col + 1))
            let a1 = atan2(Double(2 * $1.row + 1), Double(2 * $1.col + 1))
            return (a0, $0.col, $0.row) < (a1, $1.col, $1.row)
        }
    }

    /// A block has four 2×2 quadrants. Small buildings fill quadrants from the front (south-east, nearest
    /// the viewer), big ones take whole quadrants from the back – they meet in the middle.
    static let quadrantsFrontFirst: [(Int, Int)] = [(2, 2), (2, 0), (0, 2), (0, 0)]
    static let smallLotOrder: [(Int, Int)] = quadrantsFrontFirst.flatMap { q in
        [(1, 1), (1, 0), (0, 1), (0, 0)].map { (q.0 + $0.0, q.1 + $0.1) }
    }
    static let bigLotOrder: [(Int, Int)] = quadrantsFrontFirst.reversed()

    static func lot(_ block: Cell, _ o: (Int, Int)) -> Cell {
        Cell(block.col * blockPitch + 1 + o.0, block.row * blockPitch + 1 + o.1)
    }

    public var occupied: Set<Cell> { Set(placements.flatMap(\.cells)) }

    // MARK: placement

    /// Where a building of footprint `size` would go next: the first block (spiral order) with room.
    public func nextOrigin(size: Int) -> Cell {
        let taken = occupied
        for k in 1...10_000 {
            for block in Self.blocks(ring: k) {
                if size == 1 {
                    if let o = Self.smallLotOrder.first(where: { !taken.contains(Self.lot(block, $0)) }) {
                        return Self.lot(block, o)
                    }
                } else if let o = Self.bigLotOrder.first(where: { o in
                    [(0, 0), (1, 0), (0, 1), (1, 1)].allSatisfy { !taken.contains(Self.lot(block, (o.0 + $0.0, o.1 + $0.1))) }
                }) {
                    return Self.lot(block, o)
                }
            }
        }
        fatalError("town is full")
    }

    @discardableResult
    public mutating func place(_ entry: CatalogEntry) -> Placement {
        let size = max(1, entry.footprint.first ?? 1)
        let p = Placement(catalogId: entry.id, origin: nextOrigin(size: size), size: size)
        placements.append(p)
        return p
    }

    // MARK: roads

    /// The 20 road cells around a block: `col` in `5bx...5bx+5` and `row` in `5by...5by+5`, roads only.
    static func ring(of block: Cell) -> Set<Cell> {
        var out = Set<Cell>()
        for col in block.col * blockPitch...(block.col + 1) * blockPitch {
            for row in block.row * blockPitch...(block.row + 1) * blockPitch where isRoad(Cell(col, row)) {
                out.insert(Cell(col, row))
            }
        }
        return out
    }

    /// Road cells touching (8-neighbourhood) an occupied lot – the streets that really have houses on them.
    public var builtRoads: Set<Cell> {
        var roads = Set<Cell>()
        for cell in occupied {
            for dc in -1...1 {
                for dr in -1...1 {
                    let n = cell.offset(dc, dr)
                    if Self.isRoad(n) { roads.insert(n) }
                }
            }
        }
        return roads
    }

    /// Road cells that are drawn: the street rings of all started blocks (blocks holding an occupied lot) plus the
    /// ring of the frontier block – the first block in spiral order without any occupied lot. Streets are always
    /// one block ahead of the houses, also in an empty town.
    public var drawnRoads: Set<Cell> {
        let taken = occupied
        let started = Set(taken.map { Self.block($0) })
        var roads = Set<Cell>()
        for block in started { roads.formUnion(Self.ring(of: block)) }
        search: for k in 1...10_000 {
            for block in Self.blocks(ring: k) where !started.contains(block) {
                roads.formUnion(Self.ring(of: block))
                break search
            }
        }
        return roads
    }

    /// Straight road cells of the drawn streets that touch an occupied lot (the lights stay next to houses).
    private var lightableCells: Set<Cell> {
        Self.straightCells(in: drawnRoads).intersection(builtRoads)
    }

    /// Lights up to `count` unlit straight road cells nearest to the centre ("Osvetlená ulica", §7.3).
    /// Returns the upgraded cells (empty if there is nothing to light).
    @discardableResult
    public mutating func upgradeStreets(count: Int = 4) -> [Cell] {
        let picked = Array(lightableCells.subtracting(litRoads)
            .sorted { ($0.col * $0.col + $0.row * $0.row, $0.col, $0.row) < ($1.col * $1.col + $1.row * $1.row, $1.col, $1.row) }
            .prefix(count))
        litRoads.formUnion(picked)
        return picked
    }

    public var canUpgradeStreets: Bool { !lightableCells.subtracting(litRoads).isEmpty }

    static func straightCells(in roads: Set<Cell>) -> Set<Cell> {
        roads.filter { let m = RoadTiles.mask(at: $0, roads: roads); return m == "EW" || m == "NS" }
    }
}
