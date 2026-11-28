import Darwin
import Foundation

/// One reading of the process's CPU use for the power heartbeat (14b3): the process total and, per live thread, the
/// cumulative CPU seconds. Plain values, so the arithmetic below is testable without a single mach call.
struct UsageSample: Equatable {
    var at: Date
    /// User + system CPU seconds of the whole process (`getrusage(RUSAGE_SELF)` – includes threads that already died).
    var processCPU: TimeInterval
    /// Live threads by id: a code name (never anything else) and the cumulative user + system seconds.
    var threads: [UInt64: Thread]

    struct Thread: Equatable {
        var name: String
        var cpu: TimeInterval
    }
}

/// The context a beat reports next to the CPU numbers (whole percentages and enums only).
struct HeartbeatContext: Equatable {
    var battery: String
    var state: String
    var thermal: String
    var app: String
}

enum PowerHeartbeat {
    /// Real seconds between beats of a real night; a scaled developer night shrinks it, but never below `minimumScaled`.
    static let baseInterval: TimeInterval = 1800
    static let minimumScaled: TimeInterval = 30
    /// A thread below this many CPU seconds since the last beat is not worth a mention.
    static let topThreshold: TimeInterval = 0.1
    static let maxTopThreads = 2
    static let maxNameLength = 20

    static func interval(timeScale: Double?) -> TimeInterval {
        guard let s = timeScale, s > 0 else { return baseInterval }
        return max(minimumScaled, baseInterval * s)
    }

    /// "main" stays, "com.apple.AURemoteIO" -> "AURemoteIO"; spaces go, at most `maxNameLength` characters.
    static func shortName(_ raw: String) -> String {
        let last = raw.split(separator: ".").last.map(String.init) ?? raw
        let clean = String(last.filter { !$0.isWhitespace }.prefix(maxNameLength))
        return clean.isEmpty ? "?" : clean
    }

    /// The up-to-two busiest threads since `prev`: a thread new since then counts from 0, a vanished one is ignored.
    static func top(prev: UsageSample, cur: UsageSample) -> [(name: String, delta: TimeInterval)] {
        let deltas = cur.threads.map { id, t -> (name: String, delta: TimeInterval, id: UInt64) in
            (shortName(t.name), max(0, t.cpu - (prev.threads[id]?.cpu ?? 0)), id)
        }
        return deltas.filter { $0.delta >= topThreshold }
            .sorted { $0.delta != $1.delta ? $0.delta > $1.delta : $0.id < $1.id }
            .prefix(maxTopThreads).map { ($0.name, $0.delta) }
    }

    /// "hb batt=65 state=charging thermal=serious app=bg cpu=+42.1s/1800s top=main:+30.2s,AURemoteIO:+6.0s"
    static func line(prev: UsageSample, cur: UsageSample, context c: HeartbeatContext, maxLength: Int) -> String {
        let cpu = max(0, cur.processCPU - prev.processCPU)
        let real = max(0, cur.at.timeIntervalSince(prev.at))
        var s = "hb batt=\(c.battery) state=\(c.state) thermal=\(c.thermal) app=\(c.app) cpu=+\(oneDecimal(cpu))s/\(Int(real.rounded()))s"
        let busiest = top(prev: prev, cur: cur)
        if !busiest.isEmpty {
            s += " top=" + busiest.map { "\($0.name):+\(oneDecimal($0.delta))s" }.joined(separator: ",")
        }
        return String(s.prefix(maxLength))
    }

    private static func oneDecimal(_ x: Double) -> String { String(format: "%.1f", x) }
}

/// The thin reader: mach / rusage calls, no logic. Called on the main actor, so `mach_thread_self()` is the main thread.
enum ProcessUsageReader {
    static func read(at: Date) -> UsageSample {
        UsageSample(at: at, processCPU: processCPU(), threads: threads())
    }

    /// `getrusage(RUSAGE_SELF)`: user + system time of the whole process, dead threads included – exact for the total.
    static func processCPU() -> TimeInterval {
        var u = rusage()
        guard getrusage(RUSAGE_SELF, &u) == 0 else { return 0 }
        func s(_ t: timeval) -> TimeInterval { TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000 }
        return s(u.ru_utime) + s(u.ru_stime)
    }

    private static func threads() -> [UInt64: UsageSample.Thread] {
        let me = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, me) }
        let mainID = id(of: me)

        var list: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return [:] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
                          vm_size_t(Int(count) * MemoryLayout<thread_act_t>.stride))
        }
        var out: [UInt64: UsageSample.Thread] = [:]
        for i in 0..<Int(count) {
            let port = list[i]
            defer { mach_port_deallocate(mach_task_self_, port) }
            guard let tid = id(of: port), let cpu = cpuSeconds(of: port) else { continue }
            out[tid] = .init(name: tid == mainID ? "main" : name(of: port, id: tid), cpu: cpu)
        }
        return out
    }

    private static func id(of port: thread_act_t) -> UInt64? {
        var info = thread_identifier_info_data_t()
        var n = mach_msg_type_number_t(MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) {
                thread_info(port, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &n)
            }
        }
        return kr == KERN_SUCCESS ? info.thread_id : nil
    }

    private static func cpuSeconds(of port: thread_act_t) -> TimeInterval? {
        var info = thread_basic_info()
        var n = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &n)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        func s(_ t: time_value_t) -> TimeInterval { TimeInterval(t.seconds) + TimeInterval(t.microseconds) / 1_000_000 }
        return s(info.user_time) + s(info.system_time)
    }

    /// The pthread name (a code label), else `t<id>`.
    private static func name(of port: thread_act_t, id: UInt64) -> String {
        if let p = pthread_from_mach_thread_np(port) {
            var buf = [CChar](repeating: 0, count: 64)
            if pthread_getname_np(p, &buf, buf.count) == 0 {
                let n = String(cString: buf)
                if !n.isEmpty { return n }
            }
        }
        return "t\(id)"
    }
}
