import AppKit
import SwiftTerm
import QuartzCore

// usage: app <mode: main|bg> <metal: 1|0> <seconds> <workload: ansi|scroll>
let argv = CommandLine.arguments
let mode = argv.count > 1 ? argv[1] : "main"
let useMetal = (argv.count > 2 ? argv[2] : "1") == "1"
let seconds = Double(argv.count > 3 ? argv[3] : "10") ?? 10
let workload = argv.count > 4 ? argv[4] : "ansi"

struct LCG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 } }
func makeData(_ n: Int, scroll: Bool) -> [UInt8] {
    var out = [UInt8](); out.reserveCapacity(n + 4096)
    var r = LCG(s: 7); var line = 0
    let words = ["error","warning","fn","let","struct","π≈3.14","日本語","héllo","████▓▒░","└──","✓","→"]
    while out.count < n {
        var s = ""
        if scroll {
            s = "\u{1b}[3\(r.next()%8)m\(line) "; line += 1
            for _ in 0..<12 { s += words[Int(r.next()%UInt64(words.count))] + " " }
            s += "\u{1b}[0m\r\n"
        } else {
            let k = r.next() % 8
            switch k {
            case 0,1: s = "\u{1b}[38;2;\(r.next()%256);\(r.next()%256);\(r.next()%256)m\u{1b}[48;5;\(r.next()%256)m"
            case 2: s = "\u{1b}[\(r.next()%30+1);\(r.next()%100+1)H"
            case 3: s = "\u{1b}[0m\r\n"
            case 4: s = "\u{1b}[K"
            default: for _ in 0..<(r.next()%5+1) { s += words[Int(r.next()%UInt64(words.count))] + " " }
            }
        }
        out.append(contentsOf: Array(s.utf8))
    }
    return out
}
let payload = makeData(4 * 1024 * 1024, scroll: workload == "scroll")

final class Stats: @unchecked Sendable {
    let lock = NSLock(); var fed = 0
    func add(_ n: Int) { lock.lock(); fed += n; lock.unlock() }
    func get() -> Int { lock.lock(); defer { lock.unlock() }; return fed }
}
let stats = Stats()

@MainActor final class Del: NSObject, TerminalViewDelegate, NSApplicationDelegate {
    var sends = 0
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) { sends += 1 }
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    var views: [TerminalView] = []
    var window: NSWindow!
    var intervals: [Double] = []
    var workMs: [Double] = []
    var lastTS: Double = 0
    var link: CADisplayLink?
    var offsets = [0, 1_000_003, 2_000_029, 3_000_017]
    var startT = 0.0

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1200, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = content
        let w = content.bounds.width / 2, h = content.bounds.height / 2
        for i in 0..<4 {
            let v = TerminalView(frame: NSRect(x: CGFloat(i % 2) * w, y: CGFloat(i / 2) * h, width: w, height: h))
            v.terminalDelegate = self
            content.addSubview(v)
            views.append(v)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        var metalOK = 0
        if useMetal { for v in views { do { try v.setUseMetal(true) } catch { print("setUseMetal error: \(error)") } ; if v.isUsingMetalRenderer { metalOK += 1 } } }
        print("views=\(views.count) metalActive=\(metalOK) mode=\(mode) workload=\(workload) screen=\(NSScreen.main?.maximumFramesPerSecond ?? -1)Hz")
        startT = CACurrentMediaTime()
        link = content.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
        if mode == "bg" {
            #if BG
            for (i, v) in views.enumerated() {
                let q = DispatchQueue(label: "feed\(i)")
                q.async { [payload] in
                    var off = self.offsets[i]; let deadline = CACurrentMediaTime() + seconds
                    while CACurrentMediaTime() < deadline {
                        let e = min(off + 65536, payload.count)
                        v.feed(byteArray: payload[off..<e])
                        stats.add(e - off)
                        off = e >= payload.count ? 0 : e
                    }
                }
            }
            #endif
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) { self.finish() }
    }

    @objc func tick(_ l: CADisplayLink) {
        let t0 = CACurrentMediaTime()
        if lastTS != 0 { intervals.append((t0 - lastTS) * 1000) }
        lastTS = t0
        if mode == "main" && t0 - startT < seconds {
            // AR-406 budget: <=256 KiB/pane/frame, 4 ms total per frame
            let budgetEnd = t0 + 0.004
            for (i, v) in views.enumerated() {
                if CACurrentMediaTime() >= budgetEnd { break }
                let off = offsets[i]
                let e = min(off + 64 * 1024, payload.count)
                v.feed(byteArray: payload[off..<e])
                stats.add(e - off)
                offsets[i] = e >= payload.count ? 0 : e
            }
        }
        workMs.append((CACurrentMediaTime() - t0) * 1000)
    }

    func pct(_ a: [Double], _ p: Double) -> Double { let s = a.sorted(); return s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * p))] }
    func finish() {
        let ivs = Array(intervals.dropFirst(5))
        let total = Double(stats.get()) / 1_048_576
        let refresh = 1000.0 / Double(NSScreen.main?.maximumFramesPerSecond ?? 60)
        let dropped = ivs.filter { $0 > refresh * 1.5 }.count
        print(String(format: "RESULT mode=%@ metal=%d workload=%@ frames=%d interval_ms p50=%.2f p95=%.2f p99=%.2f max=%.2f dropped(>1.5x %.1fms)=%d  mainWork_ms p50=%.2f p99=%.2f max=%.2f  fed=%.1f MiB (%.1f MiB/s total, %.1f/pane)",
                     mode, useMetal ? 1 : 0, workload, ivs.count, pct(ivs, 0.5), pct(ivs, 0.95), pct(ivs, 0.99), ivs.max() ?? 0, refresh, dropped,
                     pct(workMs, 0.5), pct(workMs, 0.99), workMs.max() ?? 0, total, total / seconds, total / seconds / 4))
        exit(0)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let del = MainActor.assumeIsolated { Del() }
app.delegate = del
app.run()
