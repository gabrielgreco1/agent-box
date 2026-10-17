import Foundation
import SwiftTerm

final class D: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

// deterministic LCG
struct LCG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 } }

func ansiDump(targetBytes: Int) -> [UInt8] {
    var out = [UInt8](); out.reserveCapacity(targetBytes + 4096)
    var r = LCG(s: 42)
    let words = ["error","warning","fn","let","struct","π≈3.14","日本語","héllo","████▓▒░","└──","✓","→"]
    while out.count < targetBytes {
        let k = r.next() % 10
        var s = ""
        switch k {
        case 0,1,2: s = "\u{1b}[38;2;\(r.next()%256);\(r.next()%256);\(r.next()%256)m\u{1b}[48;5;\(r.next()%256)m"
        case 3: s = "\u{1b}[\(r.next()%50+1);\(r.next()%160+1)H"
        case 4: s = "\u{1b}[1;4;\(30+r.next()%8)m"
        case 5: s = "\u{1b}[0m\r\n"
        case 6: s = "\u{1b}[K"
        case 7: s = "\u{1b}[\(r.next()%5+1)A\u{1b}[\(r.next()%5+1)C"
        default:
            for _ in 0..<(r.next()%6+1) { s += words[Int(r.next()%UInt64(words.count))] + " " }
        }
        out.append(contentsOf: Array(s.utf8))
    }
    return out
}

func run(_ name: String, data: [UInt8], cols: Int = 120, rows: Int = 40, chunk: Int = 65536, reps: Int = 3) {
    var best = 0.0
    var digest = ""
    for _ in 0..<reps {
        let d = D()
        let t = Terminal(delegate: d, options: TerminalOptions(cols: cols, rows: rows, scrollback: 10_000))
        let t0 = now()
        var i = 0
        data.withUnsafeBufferPointer { _ in }
        while i < data.count {
            let e = min(i + chunk, data.count)
            t.feed(buffer: data[i..<e])
            i = e
        }
        let dt = now() - t0
        let mbs = Double(data.count) / 1_048_576 / dt
        best = max(best, mbs)
        let txt = t.getBufferAsData(kind: .active, encoding: .utf8)
        digest = "activeBytes=\(txt.count)"
        print("  \(name) run: \(String(format: "%.3f", dt)) s  \(String(format: "%.1f", mbs)) MiB/s")
    }
    print("RESULT \(name) bytes=\(data.count) best=\(String(format: "%.1f", best)) MiB/s \(digest)")
}

let args = CommandLine.arguments
let yesPath = args.count > 1 ? args[1] : "/dev/null"
let yesData = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: yesPath)))
print("loaded yes data: \(yesData.count)")
run("yes-200M", data: yesData, reps: 3)
let ansi = ansiDump(targetBytes: 64 * 1024 * 1024)
print("ansi dump generated: \(ansi.count)")
run("ansi-64M", data: ansi, reps: 3)
// small chunk (pty-like 1 KiB reads, 16 MiB)
run("ansi-16M-1KiBchunks", data: Array(ansi[0..<16*1024*1024]), chunk: 1024, reps: 2)
