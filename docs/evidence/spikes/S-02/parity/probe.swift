import Foundation
import SwiftTerm
final class D: TerminalDelegate { func send(source: Terminal, data: ArraySlice<UInt8>) {} }
let cases: [(String, String)] = [
    ("wide plain", "日本語 ok"),
    ("overwrite first half-cell of wide", "日本語\r.x"),
    ("overwrite second cell of wide (CUP col2)", "日本語\u{1b}[1;2Hx"),
    ("EL from col 2 (mid wide)", "日本語\u{1b}[1;2H\u{1b}[K"),
    ("EL from col 3", "日本語\u{1b}[1;3H\u{1b}[K"),
    ("wide at last col wrap", String(repeating: "a", count: 9) + "日本"),
    ("CUP past, no text", "ab\u{1b}[1;6Hc"),
    ("erase chars ECH mid-wide", "日本語\u{1b}[1;2H\u{1b}[2X"),
    ("ICH mid-wide", "日本語\u{1b}[1;2H\u{1b}[2@"),
    ("DCH mid-wide", "日本語\u{1b}[1;2H\u{1b}[1P"),
]
for (name, input) in cases {
    let t = Terminal(delegate: D(), options: TerminalOptions(cols: 10, rows: 3, scrollback: 10))
    t.feed(buffer: Array(input.utf8)[...])
    let d = t.getBufferAsData(kind: .active, encoding: .utf8)
    let first = d.split(separator: 10, maxSplits: 1, omittingEmptySubsequences: false).first.map { Array($0) } ?? []
    let hex = first.map { b -> String in b == 0 ? "\\0" : (b == 0x20 ? "_" : String(UnicodeScalar(b).isASCII ? String(UnicodeScalar(b)) : String(format: "<%02x>", b))) }.joined()
    print(name.padding(toLength: 44, withPad: " ", startingAt: 0), "total=\(d.count)", hex)
}
