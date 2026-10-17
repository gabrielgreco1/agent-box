import Foundation
import Darwin
import SwiftTerm

/// Client side: connects to the daemon, keeps a SwiftTerm Terminal (queries are NOT answered; the daemon answers).
final class DClient {
    let fd: Int32
    let delegate = NullDelegate()
    var term: Terminal
    let lock = NSLock()
    var lastOutput = Date()
    var replyQueue = [String]()
    var snapInfo = ""
    var rxBytes = 0
    var running = true
    var firstSeq: UInt64? = nil
    var lastEnd: UInt64 = 0
    var gap = false

    init?(path: String, cols: Int, rows: Int) {
        let sfd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { p in p.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) } }
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sfd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        if r != 0 { Darwin.close(sfd); return nil }
        fd = sfd
        term = Terminal(delegate: delegate, options: TerminalOptions(cols: cols, rows: rows, scrollback: 2000))
        Thread.detachNewThread { [self] in readLoop() }
    }

    func readLoop() {
        var p = FrameParser(); var b = [UInt8](repeating: 0, count: 65536)
        while running {
            let n = read(fd, &b, b.count)
            if n <= 0 { return }
            for (k, payload) in p.push(b[0..<n]) {
                lock.lock()
                switch k {
                case .control:
                    let s = String(decoding: payload, as: UTF8.self)
                    if s.hasPrefix("snap ") {
                        let parts = s.split(separator: " ").map(String.init)
                        snapInfo = "\(parts[1])..\(parts[2]) \(parts[4])"
                        let pre = unb64(parts[3])
                        term.feed(buffer: pre[...])
                        lastEnd = UInt64(parts[2])!
                        firstSeq = UInt64(parts[1])
                    } else { replyQueue.append(s) }
                case .output:
                    var seq: UInt64 = 0
                    for i in 0..<8 { seq = seq << 8 | UInt64(payload[i]) }
                    let bytes = payload[8...]
                    if let _ = firstSeq, lastEnd != 0, seq != lastEnd, !(seq < lastEnd) { gap = true }
                    if seq >= lastEnd || lastEnd == 0 { lastEnd = seq + UInt64(bytes.count) }
                    // replay frames carry seq < snap end; they continue contiguously from startSeq
                    term.feed(buffer: bytes); rxBytes += bytes.count
                    lastOutput = Date()
                case .input: break
                }
                lock.unlock()
            }
        }
    }

    func control(_ s: String) { _ = writeAll(fd, encodeFrame(.control, [UInt8](s.utf8))) }
    func input(_ s: String) { _ = writeAll(fd, encodeFrame(.input, [UInt8](s.utf8))) }
    func waitIdle(idleMs: Int = 400, maxMs: Int = 6000) {
        let t0 = Date()
        while true {
            usleep(50_000)
            lock.lock(); let idle = Date().timeIntervalSince(lastOutput) * 1000; lock.unlock()
            if idle >= Double(idleMs) || Date().timeIntervalSince(t0) * 1000 > Double(maxMs) { return }
        }
    }
    func snapshot() -> String { lock.lock(); defer { lock.unlock() }; return Snapshot.capture(term) }
    func remoteReply(_ prefix: String, timeout: Double = 3) -> String? {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < timeout {
            lock.lock()
            if let i = replyQueue.firstIndex(where: { $0.hasPrefix(prefix) }) { let r = replyQueue.remove(at: i); lock.unlock(); return r }
            lock.unlock(); usleep(20_000)
        }
        return nil
    }
    func close() { running = false; Darwin.shutdown(fd, SHUT_RDWR); Darwin.close(fd) }
}

struct Scenario {
    let name: String
    let argv: [String]
    let startupMs: Int
    let script: [(Int, String)]      // (delay ms before, input)
    var env: [String: String] = [:]
}

func lineDiff(_ a: String, _ b: String) -> String {
    let x = a.split(separator: "\n", omittingEmptySubsequences: false), y = b.split(separator: "\n", omittingEmptySubsequences: false)
    var out = [String]()
    for i in 0..<max(x.count, y.count) {
        let l = i < x.count ? String(x[i]) : "<none>", r = i < y.count ? String(y[i]) : "<none>"
        if l != r { out.append("  row \(i): A=\(l.debugDescription)\n         B=\(r.debugDescription)") }
        if out.count >= 6 { out.append("  ..."); break }
    }
    return out.joined(separator: "\n")
}

func runHarness(exe: String, work: String, reps: Int, only: String?) {
    let esc = "\u{1b}"
    var file200 = ""; for i in 1...200 { file200 += "line \(i) the quick brown fox jumps over the lazy dog\n" }
    try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true); try? FileManager.default.createDirectory(atPath: "/tmp/s04s", withIntermediateDirectories: true)
    try? file200.write(toFile: "\(work)/l200.txt", atomically: true, encoding: .utf8)
    try? "seed\n".write(toFile: "\(work)/v.txt", atomically: true, encoding: .utf8)
    let flood = "yes 'flood line of plain text 0123456789 abcdefghijklmnopqrstuvwxyz' | head -c 8000000"
    let sc: [Scenario] = [
        Scenario(name: "modes", argv: ["/bin/sh", "-c", "printf '\(esc)[?2004h\(esc)[?1h\(esc)=\(esc)[?25l\(esc)[?1000h\(esc)[?1006h\(esc)]0;spike title\u{07}hello modes\\n'; exec sleep 600"], startupMs: 500, script: []),
        Scenario(name: "zsh", argv: ["/bin/zsh", "-f", "-i"], startupMs: 800, script: [(200, "echo hello-spike\r"), (300, "ls /etc | head -5\r"), (400, "partial command typed")]),
        Scenario(name: "less", argv: ["/usr/bin/less", "-N", "\(work)/l200.txt"], startupMs: 500, script: [(200, " "), (200, "jjj")]),
        Scenario(name: "vim", argv: ["/usr/bin/vim", "-u", "NONE", "-n", "\(work)/v.txt"], startupMs: 900, script: [(200, "ihello from spike\rsecond line\(esc)"), (300, ":set number\r"), (300, "ggOtop\(esc)")]),
        Scenario(name: "vim-after-flood", argv: ["/bin/sh", "-c", "\(flood); exec /usr/bin/vim -u NONE -n \(work)/v.txt"], startupMs: 3000, script: [(300, "ihello after flood\(esc)"), (300, ":set number\r")]),
        Scenario(name: "flood-nocut", argv: ["/bin/sh", "-c", "\(flood); printf '\(esc)[?2004h'; exec sleep 600"], startupMs: 3000, script: []),
        Scenario(name: "alt-overflow", argv: ["/bin/sh", "-c", "printf '\(esc)[?1049h\(esc)[?25l\(esc)[?1000h'; yes \"$(printf '\(esc)[H\(esc)[31mrow of alt content\(esc)[0m')\" | head -c 8000000; printf '\(esc)[3;5HFINAL MARKER'; exec sleep 600"], startupMs: 3000, script: []),
        Scenario(name: "claude", argv: ["claude"], startupMs: 6000, script: [], env: ["CLAUDE_CONFIG_DIR": "\(work)/claude-cfg"]),
        Scenario(name: "codex", argv: ["codex"], startupMs: 6000, script: [], env: ["CODEX_HOME": "\(work)/codex-home"]),
    ]
    let cols = 100, rows = 30
    var summary = [String]()
    for s in sc where only == nil || only! == s.name {
        var pass0 = 0, pass1 = 0, ok2 = 0, fails = [String]()
        var infoCut = ""
        for rep in 1...reps {
            let sock = "/tmp/s04s/\(s.name.prefix(6))\(rep).sock"
            try? FileManager.default.removeItem(atPath: sock)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = ["daemon", sock, "\(cols)", "\(rows)", "\(4 << 20)", work] + s.argv
            var env = ProcessInfo.processInfo.environment; for (k, v) in s.env { env[k] = v }; p.environment = env
            p.standardOutput = FileHandle.nullDevice; FileManager.default.createFile(atPath: "\(work)/daemon-\(s.name).log", contents: nil); p.standardError = FileHandle(forWritingAtPath: "\(work)/daemon-\(s.name).log")
            try! p.run()
            var a: DClient? = nil
            for _ in 0..<100 { if let c = DClient(path: sock, cols: cols, rows: rows) { a = c; break }; usleep(50_000) }
            guard let A = a else { fails.append("rep \(rep): daemon did not start"); p.terminate(); continue }
            A.control("attach \(cols) \(rows) 0")
            let O = DClient(path: sock, cols: cols, rows: rows)!   // observer: stays attached the whole time (ground truth for the post-redraw state)
            O.control("attach \(cols) \(rows) 0")
            usleep(UInt32(s.startupMs) * 1000); A.waitIdle(idleMs: 500, maxMs: 15000)
            for (d, inp) in s.script { usleep(UInt32(d) * 1000); A.input(inp) }
            A.waitIdle(idleMs: 500, maxMs: 6000)
            let sa = A.snapshot()
            A.control("snapshot")
            let dref = A.remoteReply("text").map { String(decoding: unb64(String($0.dropFirst(5))), as: UTF8.self) } ?? "<timeout>"
            A.close()
            usleep(300_000)
            guard let B = DClient(path: sock, cols: cols, rows: rows) else { fails.append("rep \(rep): B connect failed"); p.terminate(); continue }
            B.control("attach \(cols) \(rows) 0")
            B.waitIdle(idleMs: 500, maxMs: 6000)
            let sb0 = B.snapshot()
            infoCut = B.snapInfo
            B.control("redraw")
            usleep(150_000)
            B.waitIdle(idleMs: 700, maxMs: 6000)
            let sb1 = B.snapshot()
            let so = O.snapshot(); O.close()
            B.control("kill"); usleep(100_000)
            B.close(); p.terminate(); p.waitUntilExit()
            if rep == 1 { for (n, t) in [("A", sa), ("Bre", sb0), ("Bdr", sb1), ("O", so), ("D", dref)] { try? t.write(toFile: "\(work)/last-\(s.name)-\(n).txt", atomically: true, encoding: .utf8) } }
            let e0 = sa == sb0, e1 = so == sb1, e2 = dref == sa
            if e0 { pass0 += 1 }; if e1 { pass1 += 1 }; if e2 { ok2 += 1 }
            if (!e0 || !e1) && fails.count < 2 {
                fails.append("rep \(rep) replay-only equal=\(e0), after-redraw equal=\(e1)\n" + (e0 ? "" : "  [A vs B-replay]\n" + lineDiff(sa, sb0)) + (e1 ? "" : "\n  [Observer vs B-redraw]\n" + lineDiff(so, sb1)))
            }
            print("  \(s.name) rep \(rep): replay=\(e0) redraw=\(e1) daemonRef=\(e2) snap=\(B.snapInfo) gap=\(B.gap)")
            fflush(stdout)
        }
        let line = "SUMMARY \(s.name): replay-only \(pass0)/\(reps), after-redraw \(pass1)/\(reps), daemon-ref==A \(ok2)/\(reps)  (last attach: \(infoCut))"
        print(line); summary.append(line)
        for f in fails { print("  FAIL " + f) }
    }
    print("\n==== ALL ====\n" + summary.joined(separator: "\n"))
}
