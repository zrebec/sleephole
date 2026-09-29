// SleepHole sprite renderer.
// Renders Kenney CC0 3D models (OBJ) into isometric PNG sprites using SceneKit offscreen.
//
// Usage (from repo root, needs macOS with Metal; run OUTSIDE any sandbox because ModelIO
// needs to read the model files):
//   swift tools/render/render_sprites.swift tools/render/recipes.json assets/sprites [onlyId]
//
// Input:  recipes.json  – list of sprite recipes (parts = models + transforms, optional signs)
// Output: <out>/<level>/<id>.png  and  <out>/catalog.json (manifest consumed by the app)
//
// Projection contract (the app's IsoProjection MUST match this):
//   * camera azimuth 45° (looks from +x,+z corner), elevation 30° -> 2:1 dimetric
//   * 1 world unit = 1 grid tile; PPU pixels per world unit
//   * a 1x1 tile diamond is TILE_W = PPU*sqrt(2) px wide and TILE_W/2 px tall
//   * anchor = normalized position (SpriteKit convention, y from bottom) of the world
//     origin (footprint centre on the ground) inside the PNG

import AppKit
import Foundation
import Metal
import ModelIO
import SceneKit
import SceneKit.ModelIO

let PPU: Double = 181.0            // 1x1 tile diamond ≈ 256 px wide
let AZIMUTH = 45.0 * .pi / 180
let ELEVATION = 30.0 * .pi / 180
let MARGIN: Double = 0.08          // world units of padding around the projected bbox

struct Part: Codable {
    var src: String?               // path relative to KENNEY_3D root, without ".obj"
    var box: [Double]?             // OR a primitive box [w, h, d] (sits on y = pos.y)
    var color: String?             // box colour
    var texture: String?           // replace the model's colormap (Kenney "variation-*.png"),
                                   // path relative to KENNEY_3D root
    var pos: [Double]?             // x, y, z (world units, y up)
    var rot: Double?               // rotation around Y in degrees
    var scale: Double?
}

struct Sign: Codable {
    var text: String
    var pos: [Double]?             // centre of the board; omitted = auto on the +z (front) face
                                   // of the first model part, at `height` × its height
    var height: Double?            // auto placement height fraction, default 0.72
    var rot: Double?               // yaw in degrees (0 = faces +z)
    var width: Double?             // board width, default auto
    var color: String?             // board hex colour
    var textColor: String?
}

struct Recipe: Codable {
    var id: String
    var level: Int                 // 0 = support/terrain sprites, 1…4 = unlock levels
    var kind: String               // building | park | road | terrain | overlay | vehicle
    var nameSK: String
    var footprint: [Int]           // [w, d] in tiles
    var parts: [Part]
    var signs: [Sign]?
    var shadow: Bool?              // default true
    var connects: String?          // roads only: open edges, subset of "NESW"
}

struct CatalogEntry: Codable {
    var id: String
    var level: Int
    var kind: String
    var nameSK: String
    var footprint: [Int]
    var file: String
    var size: [Int]
    var anchor: [Double]
    var connects: String?
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: render_sprites.swift recipes.json outDir [onlyId]")
    exit(1)
}
let recipesURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let onlyId = args.count > 3 ? args[3] : nil
let kenney3D = URL(fileURLWithPath: "assets/Kenney Game Assets All-in-1 3/3D assets")

let recipes = try JSONDecoder().decode([Recipe].self, from: Data(contentsOf: recipesURL))

// MARK: - helpers

func color(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

var modelCache: [String: SCNNode] = [:]

func loadModel(_ src: String) -> SCNNode {
    if let cached = modelCache[src] { return cached.clone() }
    let url = kenney3D.appendingPathComponent(src + ".obj")
    guard FileManager.default.fileExists(atPath: url.path) else {
        fatalError("missing model: \(url.path)")
    }
    let asset = MDLAsset(url: url)
    asset.loadTextures()
    let node = SCNNode()
    for child in SCNScene(mdlAsset: asset).rootNode.childNodes { node.addChildNode(child) }
    node.enumerateHierarchy { n, _ in
        n.geometry?.materials.forEach { m in
            m.lightingModel = .lambert
            m.diffuse.magnificationFilter = .nearest   // Kenney colormaps are palette atlases
            m.diffuse.minificationFilter = .nearest
            m.diffuse.mipFilter = .none
            m.isDoubleSided = false
        }
    }
    modelCache[src] = node
    return node.clone()
}

var textureCache: [URL: NSImage] = [:]

func retexture(_ node: SCNNode, _ url: URL) {
    let img = textureCache[url] ?? NSImage(contentsOf: url)
    guard let img else { fatalError("missing texture \(url.path)") }
    textureCache[url] = img
    node.enumerateHierarchy { n, _ in
        guard let shared = n.geometry else { return }
        // geometry + materials are shared with the cached original -> copy before changing
        let g = shared.copy() as! SCNGeometry
        n.geometry = g
        g.materials = shared.materials.map { m in
            let c = m.copy() as! SCNMaterial
            if c.diffuse.contents != nil, !(c.diffuse.contents is NSColor) { c.diffuse.contents = img }
            return c
        }
    }
}

func makeSign(_ s: Sign) -> SCNNode {
    let text = SCNText(string: s.text, extrusionDepth: 0.02)
    text.font = NSFont.systemFont(ofSize: 1, weight: .heavy)
    text.flatness = 0.005
    text.firstMaterial?.diffuse.contents = color(s.textColor ?? "#ffffff")
    text.firstMaterial?.lightingModel = .constant
    let textNode = SCNNode(geometry: text)
    let (mn, mx) = textNode.boundingBox
    let tw = Double(mx.x - mn.x), th = Double(mx.y - mn.y)
    let h = 0.16
    let k = h * 0.72 / th
    textNode.scale = SCNVector3(k, k, k)
    let boardW = s.width ?? (tw * k + 0.12)
    textNode.position = SCNVector3(-tw * k / 2 - Double(mn.x) * k, -th * k / 2 - Double(mn.y) * k, 0.021)

    let board = SCNBox(width: boardW, height: h, length: 0.04, chamferRadius: 0.012)
    board.firstMaterial?.diffuse.contents = color(s.color ?? "#2d5aa0")
    board.firstMaterial?.lightingModel = .lambert
    let node = SCNNode(geometry: board)
    node.addChildNode(textNode)
    if let p = s.pos { node.position = SCNVector3(p[0], p[1], p[2]) }
    node.eulerAngles.y = CGFloat((s.rot ?? 0) * .pi / 180)
    return node
}

// Camera basis (world space).
let dir = SIMD3<Double>(-cos(ELEVATION) * sin(AZIMUTH), -sin(ELEVATION), -cos(ELEVATION) * cos(AZIMUTH))
let right = simd_normalize(simd_cross(dir, SIMD3<Double>(0, 1, 0)))
let up = simd_cross(right, dir)

// Key light orientation and the direction its rays travel (world space).
let KEY_EULER = SCNVector3(-55.0 * .pi / 180, -20.0 * .pi / 180, 0)
let LIGHT_DIR: SIMD3<Double> = {
    let n = SCNNode(); n.eulerAngles = KEY_EULER
    let f = n.simdWorldFront
    return SIMD3(Double(f.x), Double(f.y), Double(f.z))
}()

func worldBox(_ node: SCNNode) -> (SIMD3<Double>, SIMD3<Double>) {
    var lo = SIMD3<Double>(repeating: .infinity), hi = SIMD3<Double>(repeating: -.infinity)
    node.enumerateHierarchy { n, _ in
        guard n.geometry != nil else { return }
        let (a, b) = n.boundingBox
        for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
            let p = n.convertPosition(SCNVector3(x, y, z), to: nil)
            let v = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
            lo = simd_min(lo, v); hi = simd_max(hi, v)
        }}}
    }
    return (lo, hi)
}

// MARK: - render

let device = MTLCreateSystemDefaultDevice()!
var catalog: [CatalogEntry] = []
let catalogURL = outDir.appendingPathComponent("catalog.json")
if onlyId != nil, let data = try? Data(contentsOf: catalogURL),
   let old = try? JSONDecoder().decode([CatalogEntry].self, from: data) {
    catalog = old
}

for r in recipes where onlyId == nil || r.id == onlyId {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    let content = SCNNode()
    scene.rootNode.addChildNode(content)
    var signHost: SCNNode?         // auto signs go on the first model part (not on plates/boxes)
    for p in r.parts {
        let n: SCNNode
        if let src = p.src {
            n = loadModel(src)
            if let tex = p.texture { retexture(n, kenney3D.appendingPathComponent(tex)) }
            if signHost == nil { signHost = n }
        } else if let b = p.box {
            let g = SCNBox(width: b[0], height: b[1], length: b[2], chamferRadius: min(b[1] / 2, 0.01))
            g.firstMaterial?.diffuse.contents = color(p.color ?? "#888888")
            g.firstMaterial?.lightingModel = .lambert
            let inner = SCNNode(geometry: g); inner.position.y = CGFloat(b[1] / 2)
            n = SCNNode(); n.addChildNode(inner)
        } else { fatalError("part needs src or box in \(r.id)") }
        let pos = p.pos ?? [0, 0, 0]
        n.position = SCNVector3(pos[0], pos[1], pos[2])
        n.eulerAngles.y = CGFloat((p.rot ?? 0) * .pi / 180)
        let s = p.scale ?? 1
        n.scale = SCNVector3(s, s, s)
        content.addChildNode(n)
    }
    for s in r.signs ?? [] {
        let sign = makeSign(s)
        if s.pos == nil, let first = signHost {
            let (lo, hi) = worldBox(first)
            sign.position = SCNVector3((lo.x + hi.x) / 2, lo.y + (hi.y - lo.y) * (s.height ?? 0.72), hi.z + 0.025)
        }
        content.addChildNode(sign)
    }

    // Projected bounds: content bbox + footprint diamond (+ room for the shadow).
    var (lo, hi) = worldBox(content)
    let fw = Double(r.footprint[0]) / 2, fd = Double(r.footprint[1]) / 2
    lo = simd_min(lo, SIMD3(-fw, 0, -fd)); hi = simd_max(hi, SIMD3(fw, 0, fd))
    var pts: [SIMD3<Double>] = []
    for x in [lo.x, hi.x] { for y in [lo.y, hi.y] { for z in [lo.z, hi.z] { pts.append(SIMD3(x, y, z)) }}}
    if r.shadow ?? true {   // where the top corners' shadows land on the ground
        for x in [lo.x, hi.x] { for z in [lo.z, hi.z] {
            let top = SIMD3(x, hi.y, z)
            pts.append(top - LIGHT_DIR * (hi.y / LIGHT_DIR.y))
        }}
    }
    var sx = (Double.infinity, -Double.infinity), sy = (Double.infinity, -Double.infinity)
    for v in pts {
        let a = simd_dot(v, right), b = simd_dot(v, up)
        sx = (min(sx.0, a), max(sx.1, a)); sy = (min(sy.0, b), max(sy.1, b))
    }
    sx = (sx.0 - MARGIN, sx.1 + MARGIN); sy = (sy.0 - MARGIN, sy.1 + MARGIN)
    let wWorld = sx.1 - sx.0, hWorld = sy.1 - sy.0
    let pxW = Int((wWorld * PPU).rounded(.up)), pxH = Int((hWorld * PPU).rounded(.up))

    let cam = SCNCamera()
    cam.usesOrthographicProjection = true
    cam.orthographicScale = Double(pxH) / PPU / 2
    cam.zNear = 0.01; cam.zFar = 200
    let camNode = SCNNode(); camNode.camera = cam
    let centre = right * ((sx.0 + sx.1) / 2) + up * ((sy.0 + sy.1) / 2)
    let eye = centre - dir * 50
    camNode.simdPosition = SIMD3<Float>(Float(eye.x), Float(eye.y), Float(eye.z))
    camNode.simdLook(at: SIMD3<Float>(Float(centre.x), Float(centre.y), Float(centre.z)),
                     up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
    scene.rootNode.addChildNode(camNode)

    // Lighting: soft ambient + key light from front-left so the left face is brighter.
    let amb = SCNLight(); amb.type = .ambient; amb.intensity = 520; amb.color = color("#dfe6ff")
    let ambNode = SCNNode(); ambNode.light = amb; scene.rootNode.addChildNode(ambNode)
    let key = SCNLight(); key.type = .directional; key.intensity = 780; key.color = color("#fff4e0")
    key.castsShadow = r.shadow ?? true
    key.shadowMode = .forward
    key.shadowColor = NSColor(white: 0, alpha: 0.28)
    key.shadowRadius = 2; key.shadowSampleCount = 8
    key.orthographicScale = 6; key.shadowMapSize = CGSize(width: 2048, height: 2048)
    let keyNode = SCNNode(); keyNode.light = key
    keyNode.eulerAngles = KEY_EULER
    scene.rootNode.addChildNode(keyNode)
    if r.shadow ?? true {
        let floor = SCNFloor(); floor.reflectivity = 0
        floor.firstMaterial?.lightingModel = .shadowOnly
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
    }

    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.pointOfView = camNode
    let img = renderer.snapshot(atTime: 0, with: CGSize(width: pxW, height: pxH), antialiasingMode: .multisampling4X)

    // Anchor = where the world origin lands, normalized, y from bottom.
    // (image spans pxW/PPU × pxH/PPU world units centred on the bounds' centre)
    let ax = 0.5 - (sx.0 + sx.1) / 2 * PPU / Double(pxW)
    let ay = 0.5 - (sy.0 + sy.1) / 2 * PPU / Double(pxH)

    let dirURL = outDir.appendingPathComponent("L\(r.level)")
    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let file = "L\(r.level)/\(r.id).png"
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("png \(r.id)") }
    try png.write(to: outDir.appendingPathComponent(file))

    catalog.removeAll { $0.id == r.id }
    catalog.append(CatalogEntry(id: r.id, level: r.level, kind: r.kind, nameSK: r.nameSK,
                                footprint: r.footprint, file: file, size: [pxW, pxH],
                                anchor: [(ax * 1000).rounded() / 1000, (ay * 1000).rounded() / 1000],
                                connects: r.connects))
    print("✓ \(file) \(pxW)x\(pxH)")
}

catalog.sort { ($0.level, $0.id) < ($1.level, $1.id) }
let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
try enc.encode(catalog).write(to: catalogURL)
print("catalog: \(catalog.count) entries")
