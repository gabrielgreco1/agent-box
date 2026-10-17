import Foundation
import SwiftTerm
final class D: TerminalDelegate { func send(source: Terminal, data: ArraySlice<UInt8>) {} }
struct LCG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 } }
func ansiDump(targetBytes: Int) -> [UInt8] {
    var out = [UInt8](); var r = LCG(s: 42)
    let words = ["error","warning","fn","let","struct","π≈3.14","héllo","████▓▒░","└──","✓","→"]
    while out.count < targetBytes {
        let k = r.next() % 10; var s = ""
        switch k {
        case 0,1,2: s = "\u{1b}[38;2;\(r.next()%256);\(r.next()%256);\(r.next()%256)m\u{1b}[48;5;\(r.next()%256)m"
        case 3: s = "\u{1b}[\(r.next()%50+1);\(r.next()%160+1)H"
        case 4: s = "\u{1b}[1;4;\(30+r.next()%8)m"
        case 5: s = "\u{1b}[0m\r\n"
        case 6: s = "\u{1b}[K"
        case 7: s = "\u{1b}[\(r.next()%5+1)A\u{1b}[\(r.next()%5+1)C"
        default: for _ in 0..<(r.next()%6+1) { s += words[Int(r.next()%UInt64(words.count))] + " " }
        }
        out.append(contentsOf: Array(s.utf8))
    }
    return out
}
let size = Int(CommandLine.arguments[2])!
let data = ansiDump(targetBytes: size)
let t = Terminal(delegate: D(), options: TerminalOptions(cols: 120, rows: 40, scrollback: 10_000))
var i = 0
while i < data.count { let e = min(i+65536, data.count); t.feed(buffer: data[i..<e]); i = e }
let txt = t.getBufferAsData(kind: .active, encoding: .utf8)
try! txt.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
var grid = ""
for y in 0..<40 {
    var line = ""
    for x in 0..<120 { if let cd = t.getCharData(col: x, row: y) { line += String(cd.getCharacter()) } else { line += "?" } }
    grid += line + "\n"
}
try! grid.write(toFile: CommandLine.arguments[1] + ".grid", atomically: true, encoding: .utf8)
print("bytes", txt.count, "nul", txt.filter { $0 == 0 }.count)
