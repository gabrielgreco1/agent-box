import Foundation
import Darwin
import SwiftTerm

final class NullDelegate: TerminalDelegate {
    var onSend: ((ArraySlice<UInt8>) -> Void)?
    func send(source: Terminal, data: ArraySlice<UInt8>) { onSend?(data) }
}

final class Client {
    let fd: Int32
    var parser = FrameParser()
    var attached = false
    var src: DispatchSourceRead?
    init(fd: Int32) { self.fd = fd }
}

/// Prototype of rackyd: one session, forkpty, 4 MiB ring, headless emulator, cut points, preamble.
final class Daemon {
    let q = DispatchQueue(label: "ptyd")
    let ringCap: Int
    var ring: [UInt8]
    var endSeq: UInt64 = 0
    var tracker = Tracker()
    var cuts: [(seq: UInt64, preamble: [UInt8])] = []
    var ckpts: [(seq: UInt64, preamble: [UInt8])] = []   // mitigation: periodic mode checkpoints (S04_CHECKPOINTS=1)
    let useCkpt = ProcessInfo.processInfo.environment["S04_CHECKPOINTS"] == "1"
    var lastCkpt: UInt64 = 0
    let termDelegate = NullDelegate()
    var term: Terminal
    var cols: Int, rows: Int
    var master: Int32 = -1
    var pid: pid_t = 0
    var clients: [Client] = []
    var readSrc: DispatchSourceRead?
    var acceptSrc: DispatchSourceRead?
    var exited = false
    var inputBytes = [Int](repeating: 0, count: 6)

    init(cols: Int, rows: Int, ringBytes: Int) {
        self.cols = cols; self.rows = rows; ringCap = ringBytes
        ring = [UInt8](repeating: 0, count: ringBytes)
        term = Terminal(delegate: termDelegate, options: TerminalOptions(cols: cols, rows: rows, scrollback: 2000))
        termDelegate.onSend = { [weak self] d in   // DA/DSR answers come from the daemon (AR-105), origin 0x05
            guard let self else { return }
            self.inputBytes[5] += d.count
            _ = writeAll(self.master, Array(d))
        }
    }

    func spawn(argv: [String], cwd: String, env: [String: String]) {
        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        let cargv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        let cenv: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let ccwd = strdup(cwd)
        var m: Int32 = 0
        let p = forkpty(&m, nil, nil, &ws)
        if p == 0 {
            chdir(ccwd)
            execve(argv[0].hasPrefix("/") ? argv[0] : findInPath(argv[0], env["PATH"] ?? "/usr/bin:/bin"), cargv, cenv)
            _exit(127)
        }
        master = m; pid = p
        let fl = fcntl(master, F_GETFL); _ = fcntl(master, F_SETFL, fl | O_NONBLOCK)
        let s = DispatchSource.makeReadSource(fileDescriptor: master, queue: q)
        s.setEventHandler { [weak self] in self?.onMasterReadable() }
        s.resume(); readSrc = s
    }

    func findInPath(_ name: String, _ path: String) -> String {
        for d in path.split(separator: ":") { let c = "\(d)/\(name)"; if access(c, X_OK) == 0 { return c } }
        return name
    }

    func onMasterReadable() {
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = read(master, &buf, buf.count)
        if n <= 0 { if n == 0 || (errno != EAGAIN && errno != EINTR) { exited = true; readSrc?.cancel() }; return }
        process(buf[0..<n])
    }

    func process(_ chunk: ArraySlice<UInt8>) {
        if useCkpt && tracker.st == .normal && endSeq - lastCkpt >= 65536 {
            ckpts.append((endSeq, tracker.state.preamble(cursor: term.getCursorLocation()))); lastCkpt = endSeq
        }
        let base = chunk.startIndex
        var fedUpTo = base
        for i in chunk.indices {
            let seq = endSeq + UInt64(i - base)
            if let cut = tracker.feed(chunk[i], seq: seq) {
                // feed the emulator up to the ESC of the cut sequence, then capture the cursor
                let escOff = base + (cut.seq >= endSeq ? Int(cut.seq - endSeq) : 0)
                let upTo = max(fedUpTo, escOff)
                if upTo > fedUpTo { term.feed(buffer: chunk[fedUpTo..<upTo]); fedUpTo = upTo }
                let pre = cut.before.preamble(cursor: term.getCursorLocation())
                cuts.append((cut.seq, pre))
            }
        }
        if fedUpTo < chunk.endIndex { term.feed(buffer: chunk[fedUpTo...]) }
        // write ring
        var off = 0
        let bytes = Array(chunk)
        while off < bytes.count {
            let pos = Int((endSeq + UInt64(off)) % UInt64(ringCap))
            let k = min(bytes.count - off, ringCap - pos)
            ring.replaceSubrange(pos..<(pos + k), with: bytes[off..<(off + k)])
            off += k
        }
        let seq0 = endSeq
        endSeq += UInt64(bytes.count)
        let start = ringStart
        cuts.removeAll { $0.seq < start }
        ckpts.removeAll { $0.seq < start }
        // stream to attached clients (16 KiB frames)
        for c in clients where c.attached {
            var o = 0
            while o < bytes.count {
                let e = min(o + 32768, bytes.count)
                if !writeAll(c.fd, encodeFrame(.output, outputPayload(seq: seq0 + UInt64(o), bytes[o..<e]))) { dropClient(c); break }
                o = e
            }
        }
    }

    var ringStart: UInt64 { endSeq > UInt64(ringCap) ? endSeq - UInt64(ringCap) : 0 }

    func ringBytes(from: UInt64, to: UInt64) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(Int(to - from))
        var s = from
        while s < to {
            let pos = Int(s % UInt64(ringCap))
            let k = min(Int(to - s), ringCap - pos)
            out += ring[pos..<(pos + k)]
            s += UInt64(k)
        }
        return out
    }

    func resizeBoth(_ c: Int, _ r: Int) {
        cols = c; rows = r
        var ws = winsize(ws_row: UInt16(r), ws_col: UInt16(c), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &ws)
        term.resize(cols: c, rows: r)
    }

    func dropClient(_ c: Client) { c.src?.cancel(); close(c.fd); clients.removeAll { $0 === c } }

    func send(_ c: Client, _ kind: Kind, _ s: String) { _ = writeAll(c.fd, encodeFrame(kind, [UInt8](s.utf8))) }

    func handle(_ c: Client, _ kind: Kind, _ payload: [UInt8]) {
        switch kind {
        case .input:
            inputBytes[0] += payload.count - 0
            _ = writeAll(master, payload)
        case .output: break
        case .control:
            let parts = String(decoding: payload, as: UTF8.self).split(separator: " ").map(String.init)
            switch parts.first {
            case "attach":     // attach COLS ROWS REDRAW
                let nc = Int(parts[1])!, nr = Int(parts[2])!, redraw = parts[3] == "1"
                var forced = false
                if nc != cols || nr != rows { resizeBoth(nc, nr); forced = true }
                let start = ringStart
                let cut = cuts.last
                let (startSeq, pre): (UInt64, [UInt8])
                if let cut { (startSeq, pre) = (cut.seq, cut.preamble) }
                else if let k = ckpts.first { (startSeq, pre) = (k.seq, [0x1b, 0x63] + k.preamble) }
                else { (startSeq, pre) = (start, [0x1b, 0x63]) }     // no cut in ring: start of ring preceded by ESC c
                send(c, .control, "snap \(startSeq) \(endSeq) \(b64(pre)) \(cut == nil ? (ckpts.isEmpty ? "nocut" : "ckpt") : "cut")")
                var seq = startSeq
                let data = ringBytes(from: startSeq, to: endSeq)
                var o = 0
                while o < data.count {
                    let e = min(o + 32768, data.count)
                    _ = writeAll(c.fd, encodeFrame(.output, outputPayload(seq: seq, data[o..<e])))
                    seq += UInt64(e - o); o = e
                }
                c.attached = true
                if redraw && !forced { forceRedraw() }
            case "redraw": forceRedraw(); send(c, .control, "ok")
            case "snapshot": send(c, .control, "text \(b64([UInt8](Snapshot.capture(term).utf8)))")
            case "kill": kill(pid, SIGKILL); send(c, .control, "ok")
            case "info": send(c, .control, "info end=\(endSeq) start=\(ringStart) cuts=\(cuts.count) exited=\(exited)")
            default: break
            }
        }
    }

    /// cols-1 then cols 50 ms later => SIGWINCH twice; TUIs redraw.
    func forceRedraw() {
        let c = cols, r = rows
        resizeBoth(max(1, c - 1), r)
        q.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in self?.resizeBoth(c, r) }
    }

    func listen(path: String) {
        unlink(path)
        let ls = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) }
        }
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(ls, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        chmod(path, 0o600)
        Darwin.listen(ls, 8)
        let s = DispatchSource.makeReadSource(fileDescriptor: ls, queue: q)
        s.setEventHandler { [weak self] in
            guard let self else { return }
            let fd = accept(ls, nil, nil); if fd < 0 { return }
            var one: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, 4)
            var big: Int32 = 1 << 20; setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &big, 4)
            let c = Client(fd: fd)
            self.clients.append(c)
            let rs = DispatchSource.makeReadSource(fileDescriptor: fd, queue: self.q)
            rs.setEventHandler { [weak self, weak c] in
                guard let self, let c else { return }
                var b = [UInt8](repeating: 0, count: 65536)
                let n = read(fd, &b, b.count)
                if n <= 0 { self.dropClient(c); return }
                for (k, p) in c.parser.push(b[0..<n]) { self.handle(c, k, p) }
            }
            rs.resume(); c.src = rs
        }
        s.resume(); acceptSrc = s
    }
}

enum Snapshot {
    /// Visible screen as text (trailing spaces trimmed) + public mode flags + cursor.
    static func capture(_ t: Terminal) -> String {
        let d = t.getDims()
        var lines = [String]()
        for r in 0..<d.rows {
            let l = t.getLine(row: r)?.translateToString(trimRight: true) ?? ""
            lines.append(l)
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        let cur = t.getCursorLocation()
        return lines.joined(separator: "\n") + "\n--modes alt=\(t.isCurrentBufferAlternate) bp=\(t.bracketedPasteMode) appCursor=\(t.applicationCursor) mouse=\(t.mouseMode) cursor=\(cur.x),\(cur.y) size=\(d.cols)x\(d.rows)"
    }
}

nonisolated(unsafe) var theDaemon: Daemon?
func runDaemon(sock: String, cols: Int, rows: Int, ringBytes: Int, cwd: String, argv: [String]) -> Never {
    let d = Daemon(cols: cols, rows: rows, ringBytes: ringBytes)
    theDaemon = d
    var env = ProcessInfo.processInfo.environment
    for k in env.keys where k.hasPrefix("CLAUDE") || k.hasPrefix("ORCA_") || k.hasPrefix("RACKY") || k == "TERM_PROGRAM" { if k != "CLAUDE_CONFIG_DIR" { env[k] = nil } }
    env["TERM"] = "xterm-256color"; env["COLORTERM"] = "truecolor"; env["LANG"] = "en_US.UTF-8"
    d.q.sync { d.spawn(argv: argv, cwd: cwd, env: env); d.listen(path: sock) }
    dispatchMain()
}
