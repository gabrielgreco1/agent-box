import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxUI
import AppKit
import Darwin
import Foundation
import Synchronization
import SwiftTerm

// agentbox-bench: mede os orçamentos AR-702 (latência de eco), AR-703 (vazão e hitch do main) e AR-704/AR-706
// (memória por terminal) com o `agentboxd` real e `TerminalSurfaceView` real (Metal). Chamado por scripts/bench.sh.
// Uso: agentbox-bench --out <arquivo.json> [--quick] [--no-present]

struct Options {
    var out: String?
    var quick = false
    var measurePresent = true
}

func parseOptions() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--out": o.out = it.next()
        case "--quick": o.quick = true
        case "--no-present": o.measurePresent = false
        default:
            FileHandle.standardError.write(Data("agentbox-bench: opção desconhecida \(a)\n".utf8))
            exit(64)
        }
    }
    return o
}

// MARK: Utilidades

nonisolated func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

nonisolated struct Stats: Codable {
    var count: Int
    var p50: Double
    var p95: Double
    var p99: Double
    var max: Double
    var mean: Double

    init(_ values: [Double]) {
        let s = values.sorted()
        func pct(_ p: Double) -> Double { s.isEmpty ? 0 : s[Swift.max(0, Swift.min(s.count - 1, Int((Double(s.count) * p).rounded(.up)) - 1))] }
        count = s.count
        p50 = pct(0.50)
        p95 = pct(0.95)
        p99 = pct(0.99)
        max = s.last ?? 0
        mean = s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count)
    }
}

func physFootprint(pid: Int32) -> UInt64 {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    return rc == 0 ? info.ri_phys_footprint : 0
}

func mib(_ bytes: UInt64) -> Double { Double(bytes) / 1_048_576 }

func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

// MARK: Daemon

nonisolated final class Daemon: Sendable {
    private let child = ChildDaemon(home: ChildDaemon.temporaryHome(prefix: "abb"))
    var socket: String { child.socketPath }
    var pid: Int32 { child.pid }

    func start() async throws {
        guard let exe = ChildDaemon.defaultExecutable(relativeTo: URL(fileURLWithPath: CommandLine.arguments[0])) else {
            throw NSError(domain: "bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "agentboxd não encontrado"])
        }
        try child.start(executable: exe)
        let client = PTYClient(configuration: PTYClientConfiguration(socketPath: socket, build: "bench"))
        for _ in 0 ..< 100 {
            if (try? await client.start()) != nil {
                await client.stop()
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "agentboxd não subiu em \(exe.path)"])
    }

    func stop() {
        child.terminate()
        child.removeHome()
    }
}

// MARK: Pane de teste

nonisolated final class Counter: Sendable {
    private let n = Mutex(0)
    func add(_ k: Int) { n.withLock { $0 += k } }
    var value: Int { n.withLock { $0 } }
}

@MainActor
final class Pane {
    let host: TerminalHostView
    let window: NSWindow
    let binding: TerminalSessionBinding
    let sessionID: SessionID
    let echo = EchoWaiter()
    let fedBytes = Counter()
    var t0: UInt64 = 0

    init(client: PTYClient, argv: [String], size: NSSize = NSSize(width: 580, height: 400), index: Int) async throws {
        host = TerminalHostView(terminalID: "bench-\(index)")
        window = NSWindow(contentRect: NSRect(x: CGFloat(40 + index * 30), y: CGFloat(40 + index * 30), width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .ignoresCycle, .transient]
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        host.surface.suspendsRenderingWhenNotVisible = false
        let dims = host.surface.terminalDimensions
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "TERM": "xterm-256color", "HOME": NSHomeDirectory()]
        env["AB_BENCH"] = "1"
        let create = CreateRequest(
            sessionID: SessionID(), argv: argv, cwd: "/tmp", env: env, cols: UInt16(dims.cols), rows: UInt16(dims.rows), ringBytes: 4 << 20,
            coldLog: false, owner: SessionOwner(terminalID: "bench-\(index)", runID: "bench"))
        let created = try await client.create(create)
        sessionID = created.session.sessionID
        binding = TerminalSessionBinding(client: client, sessionID: sessionID, host: host)
        let echo = self.echo
        let fed = self.fedBytes
        binding.frameObserver.set { data in
            fed.add(data.count)
            echo.observe(data)
        }
        try await binding.start()
    }

    func close() {
        binding.stop()
        window.orderOut(nil)
    }
}

/// Espera o eco de um byte no stream alimentado ao emulador.
nonisolated final class EchoWaiter: Sendable {
    private struct State {
        var expected: UInt8 = 0
        var continuation: CheckedContinuation<UInt64, Never>?
    }
    private let state = Mutex(State())

    func arm(_ byte: UInt8, _ continuation: CheckedContinuation<UInt64, Never>) {
        state.withLock {
            $0.expected = byte
            $0.continuation = continuation
        }
    }

    func observe(_ data: Data) {
        let cont: CheckedContinuation<UInt64, Never>? = state.withLock { s in
            guard s.continuation != nil, data.contains(s.expected) else { return nil }
            let c = s.continuation
            s.continuation = nil
            return c
        }
        cont?.resume(returning: nowNs())
    }

    func timeout() {
        let cont = state.withLock { s -> CheckedContinuation<UInt64, Never>? in
            let c = s.continuation
            s.continuation = nil
            return c
        }
        cont?.resume(returning: 0)
    }
}

/// Último quadro apresentado pelo renderer (callback estático do SwiftTerm).
nonisolated final class PresentClock: Sendable {
    static let shared = PresentClock()
    private let last = Mutex<UInt64>(0)
    func install() { TerminalView.onFramePresented = { PresentClock.shared.last.withLock { $0 = nowNs() } } }
    func lastPresent() -> UInt64 { last.withLock { $0 } }
}

/// Mede um monitor de stall do main thread: intervalos entre disparos de um timer de 2 ms.
@MainActor
final class MainStallMonitor {
    private var timer: DispatchSourceTimer?
    private var lastFire = nowNs()
    private(set) var gaps: [Double] = []

    func start() {
        lastFire = nowNs()
        gaps = []
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(100))
        t.setEventHandler { [self] in
            let n = nowNs()
            gaps.append(Double(n - lastFire) / 1e6)
            lastFire = n
        }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }
    var maxGapMs: Double { gaps.max() ?? 0 }
}

// MARK: Cenários

/// Digita `count` teclas (ping-pong) no pane de `cat` e mede tecla -> emulador (e -> quadro apresentado).
@MainActor
func measureEcho(on pane: Pane, count: Int, interval: Duration = .milliseconds(20), present: Bool) async -> (fed: [Double], presented: [Double], timeouts: Int) {
    var fed: [Double] = []
    var presented: [Double] = []
    var timeouts = 0
    let letters = Array("abcdefghijklmnopqrstuvwxyz".utf8)
    for i in 0 ..< count {
        let ch = letters[i % letters.count]
        let echo = pane.echo
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { echo.timeout() }
        }
        let t1: UInt64 = await withCheckedContinuation { continuation in
            echo.arm(ch, continuation)
            pane.t0 = nowNs()
            pane.host.surface.send(data: [ch][...])
        }
        timeoutTask.cancel()
        if t1 == 0 {
            timeouts += 1
            continue
        }
        fed.append(Double(t1 - pane.t0) / 1e6)
        if present {
            // Próximo quadro apresentado depois da atualização do emulador.
            var t2: UInt64 = 0
            for _ in 0 ..< 200 {
                let p = PresentClock.shared.lastPresent()
                if p > t1 { t2 = p; break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            if t2 > 0 { presented.append(Double(t2 - pane.t0) / 1e6) }
        }
        try? await Task.sleep(for: interval)
    }
    return (fed, presented, timeouts)
}

struct EchoResult: Codable {
    var keysSent: Int
    var timeouts: Int
    var keyToEmulatorMs: Stats
    var keyToPresentedFrameMs: Stats?
}

func echoResult(_ r: (fed: [Double], presented: [Double], timeouts: Int), sent: Int, present: Bool) -> EchoResult {
    EchoResult(keysSent: sent, timeouts: r.timeouts, keyToEmulatorMs: Stats(r.fed), keyToPresentedFrameMs: present && !r.presented.isEmpty ? Stats(r.presented) : nil)
}

func makeBigFile(megabytes: Int) throws -> URL {
    var chunk = Data()
    var i = 0
    while chunk.count < 1 << 20 {
        chunk.append(Data("\u{1b}[3\(i % 8)mline \(i) \u{1b}[1;4\(i % 8)m the quick brown fox jumps over the lazy dog 0123456789\u{1b}[0m\r\n".utf8))
        i += 1
    }
    let url = URL(fileURLWithPath: "/tmp/ab-bench-\(UInt32.random(in: 0 ... 0xFFFFFF)).ansi")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let h = try FileHandle(forWritingTo: url)
    for _ in 0 ..< megabytes { try h.write(contentsOf: chunk) }
    try h.close()
    return url
}

@MainActor
func runAll(_ opts: Options) async throws -> [String: Any] {
    let daemon = Daemon()
    try await daemon.start()
    defer { daemon.stop() }
    let client = PTYClient(configuration: PTYClientConfiguration(socketPath: daemon.socket, build: "bench"))
    try await client.start()
    if opts.measurePresent { PresentClock.shared.install() }
    let keys = opts.quick ? 60 : 300
    let enc = JSONEncoder()
    func json<T: Encodable>(_ v: T) -> Any { (try? JSONSerialization.jsonObject(with: enc.encode(v))) ?? [:] }
    var report: [String: Any] = [:]
    var failures: [String] = []

    // D. Memória por terminal (AR-704), primeiro: o processo ainda está limpo: N panes com 5 mil linhas de scrollback preenchidas.
    log("bench: memória")
    do {
        let n = opts.quick ? 4 : 8
        try await Task.sleep(for: .seconds(1))
        let appBefore = physFootprint(pid: getpid())
        let daemonBefore = physFootprint(pid: daemon.pid)
        var panes: [Pane] = []
        let fill = "yes 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' | head -n 6000; sleep 600"
        for i in 0 ..< n { panes.append(try await Pane(client: client, argv: ["/bin/sh", "-c", fill], index: i)) }
        try await Task.sleep(for: .seconds(4))
        let appAfter = physFootprint(pid: getpid())
        let daemonAfter = physFootprint(pid: daemon.pid)
        let perView = (mib(appAfter) - mib(appBefore)) / Double(n)
        let perSession = (mib(daemonAfter) - mib(daemonBefore)) / Double(n)
        report["AR-704"] = [
            "panes": n, "scrollbackLines": 5000, "paneSizePt": "580x400 (2x2 numa janela de 1440 com sidebar de 280)",
            "appFootprintMiBBefore": mib(appBefore), "appFootprintMiBAfter": mib(appAfter), "perViewMiB": perView,
            "daemonFootprintMiBBefore": mib(daemonBefore), "daemonFootprintMiBAfter": mib(daemonAfter), "perDaemonSessionMiB": perSession,
        ] as [String: Any]
        if perView > 30 { failures.append("AR-704: view de terminal \(String(format: "%.1f", perView)) MiB > 30 MiB") }
        if perSession > 25 { failures.append("AR-704: sessão no daemon \(String(format: "%.1f", perSession)) MiB > 25 MiB") }
        for p in panes {
            try? await client.kill(sessionID: p.sessionID, mode: .force)
            try? await Task.sleep(for: .milliseconds(300))
            p.close()
        }
    }
    // A. AR-702 em repouso: 1 pane `cat`.
    log("bench: eco em repouso (\(keys) teclas)")
    do {
        let pane = try await Pane(client: client, argv: ["/bin/cat"], index: 0)
        try await Task.sleep(for: .milliseconds(600))  // assenta o redraw forçado do attach
        _ = await measureEcho(on: pane, count: 20, present: false)  // aquecimento
        let r = await measureEcho(on: pane, count: keys, present: opts.measurePresent)
        let res = echoResult(r, sent: keys, present: opts.measurePresent)
        report["AR-702-idle"] = json(res)
        let p95 = res.keyToPresentedFrameMs?.p95 ?? res.keyToEmulatorMs.p95
        report["AR-702-idle-p95-ms"] = p95
        if p95 > 16 || res.timeouts > 0 { failures.append("AR-702 repouso: p95 \(String(format: "%.1f", p95)) ms > 16 ms (ou eco perdido)") }
        try? await client.kill(sessionID: pane.sessionID, mode: .force)
        try? await Task.sleep(for: .milliseconds(300))
        pane.close()
    }

    // B. AR-702 com 4 panes visíveis despejando saída (3 flooders) e eco no quarto: `yes` (AC-T07) e `cat` de 50 MB em laço.
    let floodFile = try makeBigFile(megabytes: 50)
    defer { try? FileManager.default.removeItem(at: floodFile) }
    for (name, command) in [
        ("yes", "yes | head -c 400000000"),
        ("cat", "while :; do cat \(floodFile.path); done"),
    ] {
        log("bench: eco com 4 panes (3 x \(name)) (\(keys) teclas)")
        var flooders: [Pane] = []
        for i in 1 ... 3 { flooders.append(try await Pane(client: client, argv: ["/bin/sh", "-c", command], index: i)) }
        let pane = try await Pane(client: client, argv: ["/bin/cat"], index: 0)
        try await Task.sleep(for: .milliseconds(800))
        let fedBefore = flooders.map { $0.fedBytes.value }
        let started = nowNs()
        let stall = MainStallMonitor()
        stall.start()
        let r = await measureEcho(on: pane, count: keys, present: opts.measurePresent)
        stall.stop()
        let seconds = Double(nowNs() - started) / 1e9
        let res = echoResult(r, sent: keys, present: opts.measurePresent)
        let rates = zip(flooders, fedBefore).map { Double($0.fedBytes.value - $1) / 1_048_576 / seconds }
        report["AR-702-4panes-\(name)"] = [
            "echo": json(res), "floodersMiBPerSecond": rates, "mainMaxGapMs": stall.maxGapMs, "mainGapP99Ms": Stats(stall.gaps).p99,
        ] as [String: Any]
        let p95 = res.keyToPresentedFrameMs?.p95 ?? res.keyToEmulatorMs.p95
        report["AR-702-loaded-\(name)-p95-ms"] = p95
        if p95 > 33 || res.timeouts > 0 { failures.append("AR-702 4 panes (\(name)): p95 \(String(format: "%.1f", p95)) ms > 33 ms (ou eco perdido)") }
        if stall.maxGapMs > 100 { failures.append("AR-703 4 panes (\(name)): main parado \(String(format: "%.0f", stall.maxGapMs)) ms > 100 ms") }
        for p in flooders + [pane] {
            try? await client.kill(sessionID: p.sessionID, mode: .force)
            try? await Task.sleep(for: .milliseconds(300))
            p.close()
        }
    }

    // C. AR-703: `cat` de 50 MB num pane, hitch do main e eco em outro pane.
    log("bench: cat de 50 MB")
    do {
        let megabytes = opts.quick ? 10 : 50
        let file = try makeBigFile(megabytes: megabytes)
        defer { try? FileManager.default.removeItem(at: file) }
        let probe = try await Pane(client: client, argv: ["/bin/cat"], index: 1)
        try await Task.sleep(for: .milliseconds(600))
        let stall = MainStallMonitor()
        stall.start()
        let t0 = nowNs()
        let big = try await Pane(client: client, argv: ["/bin/cat", file.path], index: 0)
        let target = megabytes << 20
        let echoTask = Task { @MainActor in await measureEcho(on: probe, count: keys / 2, present: opts.measurePresent) }
        var done = false
        let deadline = ContinuousClock.now + .seconds(120)
        while ContinuousClock.now < deadline {
            if big.fedBytes.value >= target { done = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let elapsed = Double(nowNs() - t0) / 1e9
        let r = await echoTask.value
        stall.stop()
        let res = echoResult(r, sent: keys / 2, present: opts.measurePresent)
        report["AR-703-cat"] = [
            "megabytes": megabytes, "completed": done, "seconds": elapsed, "MiBPerSecond": Double(megabytes) / elapsed,
            "mainMaxGapMs": stall.maxGapMs, "mainGapP99Ms": Stats(stall.gaps).p99,
            "otherPaneEcho": json(res),
        ] as [String: Any]
        let p95 = res.keyToPresentedFrameMs?.p95 ?? res.keyToEmulatorMs.p95
        if stall.maxGapMs > 100 { failures.append("AR-703: main parado \(String(format: "%.0f", stall.maxGapMs)) ms > 100 ms") }
        if p95 > 33 || res.timeouts > 0 { failures.append("AR-703: eco em outro pane p95 \(String(format: "%.1f", p95)) ms > 33 ms") }
        if !done { failures.append("AR-703: cat de \(megabytes) MB não terminou em 120 s") }
        for p in [big, probe] {
            try? await client.kill(sessionID: p.sessionID, mode: .force)
            try? await Task.sleep(for: .milliseconds(300))
            p.close()
        }
    }

    await client.stop()

    report["failures"] = failures
    report["passed"] = failures.isEmpty
    return report
}

// MARK: main

let options = parseOptions()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    do {
        var report = try await runAll(options)
        var host = utsname()
        uname(&host)
        let machine = withUnsafePointer(to: &host.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
        report["machine"] = [
            "arch": machine, "os": ProcessInfo.processInfo.operatingSystemVersionString, "cpus": ProcessInfo.processInfo.activeProcessorCount,
            "date": ISO8601DateFormatter().string(from: Date()), "swiftTerm": "1.99.0 (2dad6a1)", "quick": options.quick,
        ] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let out = options.out {
            try FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: out))
        }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        let failures = report["failures"] as? [String] ?? []
        for f in failures { log("FALHOU: \(f)") }
        exit(failures.isEmpty ? 0 : 1)
    } catch {
        log("agentbox-bench: erro: \(error)")
        exit(2)
    }
}
app.run()
