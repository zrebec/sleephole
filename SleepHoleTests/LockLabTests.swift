import Foundation
import Testing
@testable import SleepHole

@MainActor
struct LockLabTests {
    @Test func sampleLineFormatsEveryField() {
        let line = LockLab.sampleLine(lit: true, protectedData: false, app: "background", brightness: 0.5,
                                      battery: "charging", acceleration: 0.01234, rotation: 1.5,
                                      gravity: (0.1, -0.987, 0.005), orientation: "faceUp",
                                      backgroundRemaining: 4.26)
        #expect(line == "s lit=1 data=0 app=background bright=0.50 batt=charging acc=0.012 rot=1.50 grav=0.10,-0.99,0.01 orient=faceUp bg=4.3")
    }

    @Test func sampleLineShowsUnknownLitAndDark() {
        let unknown = LockLab.sampleLine(lit: nil, protectedData: true, app: "active", brightness: 1, battery: "unknown",
                                         acceleration: 0, rotation: 0, gravity: (0, 0, 0), orientation: "unknown", backgroundRemaining: .greatestFiniteMagnitude)
        #expect(unknown.hasSuffix(" bg=inf"))
        #expect(unknown.hasPrefix("s lit=? data=1 app=active"))
        let dark = LockLab.sampleLine(lit: false, protectedData: true, app: "active", brightness: 1, battery: "full",
                                      acceleration: 0, rotation: 0, gravity: (0, 0, 0), orientation: "portrait", backgroundRemaining: 0)
        #expect(dark.hasPrefix("s lit=0 "))
    }

    @Test func peaksAreKeptAndReadingResetsThem() {
        var p = LockLab.Peaks()
        p.feed(acceleration: (0.3, 0.4, 0), rotation: (0, 0, 1), gravity: (0, 0, -1))
        p.feed(acceleration: (0.03, 0, 0), rotation: (0, 0, 0.5), gravity: (0, -1, 0))
        let r = p.readAndReset()
        #expect(abs(r.acceleration - 0.5) < 1e-9)
        #expect(r.rotation == 1)
        #expect(r.gravity.y == -1)
        let again = p.readAndReset()
        #expect(again.acceleration == 0 && again.rotation == 0)
        #expect(again.gravity.y == -1)
    }

    @Test func recordsOnlyADebugNightWithTheFlag() {
        #expect(LockLab.shouldRecord(arguments: ["-lockLab"], isDebugNight: true))
        #expect(!LockLab.shouldRecord(arguments: ["-lockLab"], isDebugNight: false))
        #expect(!LockLab.shouldRecord(arguments: [], isDebugNight: true))
        #expect(!LockLab.shouldRecord(arguments: [], isDebugNight: false))
    }

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("lablog-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func linesAreAppendedWithATimestamp() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lab = LockLab(directory: dir)
        lab.start()
        #expect(lab.isRunning)
        lab.start()                                   // harmless
        lab.note("hello lab")
        lab.stop()
        #expect(!lab.isRunning)
        let text = try String(contentsOf: lab.fileURL, encoding: .utf8)
        #expect(text.contains("=== lab started"))
        #expect(text.contains("  hello lab\n"))
        #expect(text.contains("=== lab stopped ==="))
        #expect(text.range(of: #"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}  "#, options: .regularExpression) != nil)
    }

    @Test func aFileOver2MBIsEmptiedAtStart() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lab = LockLab(directory: dir)
        try Data(count: 2_100_000).write(to: lab.fileURL)
        lab.start()
        lab.stop()
        let size = try FileManager.default.attributesOfItem(atPath: lab.fileURL.path)[.size] as? Int ?? 0
        #expect(size < 10_000)
    }
}
