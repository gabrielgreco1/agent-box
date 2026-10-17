import Foundation
import SwiftTerm
final class D2: TerminalDelegate {
    var cwdEvents = 0, titles = [String]()
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
    func hostCurrentDirectoryUpdated(source: Terminal) { cwdEvents += 1 }
    func setTerminalTitle(source: Terminal, title: String) { titles.append(title) }
}
let d = D2()
let t = Terminal(delegate: d, options: TerminalOptions(cols: 80, rows: 24, scrollback: 100))
let e = "\u{1b}", bel = "\u{07}"
t.feed(text: "\(e)]7;file://myhost/Users/x/proj%20a\(bel)")
t.feed(text: "\(e)]133;A\(bel)$ \(e)]133;B\(bel)ls\r\n\(e)]133;C\(bel)out\r\n\(e)]133;D;0\(bel)\(e)]133;A\(bel)$ ")
print("OSC7: events=\(d.cwdEvents) hostCurrentDirectory=\(t.hostCurrentDirectory ?? "nil")")
var kinds = [String]()
for r in 0..<6 { let m = t.semanticPromptMarks(at: r); if !m.isEmpty { kinds.append("row\(r):\(m.count)marks") } }
print("OSC133: marks \(kinds) rowKind0=\(String(describing: t.semanticRowKind(at: 0)))")
print("getTopVisibleRow=\(t.getTopVisibleRow())")
