import Foundation

/// Byte-level tracker of the state a replay cut can lose (SwiftTerm's public API does not expose
/// cursorHidden, applicationKeypad, title, mouse encoding), and of the cut points.
struct ModeState {
    var dec: [Int: Bool] = [:]      // DEC private modes seen (true = set)
    var keypadApp: Bool? = nil
    var title: [UInt8]? = nil
    var isAlt: Bool { (dec[1049] ?? false) || (dec[47] ?? false) || (dec[1047] ?? false) }

    func preamble(cursor: (x: Int, y: Int)?) -> [UInt8] {
        var s = ""
        if isAlt { s += "\u{1b}[?1049h" }
        for k in dec.keys.sorted() where k != 1049 && k != 47 && k != 1047 {
            s += "\u{1b}[?\(k)\(dec[k]! ? "h" : "l")"
        }
        if let kp = keypadApp { s += kp ? "\u{1b}=" : "\u{1b}>" }
        var out = [UInt8](s.utf8)
        if let t = title { out += [0x1b, 0x5d, 0x30, 0x3b] + t + [0x07] }
        if let c = cursor { out += [UInt8]("\u{1b}[\(c.y + 1);\(c.x + 1)H".utf8) }
        return out
    }
}

struct CutEvent { var seq: UInt64; var before: ModeState }

struct Tracker {
    enum St { case normal, esc, csi, osc, oscEsc }
    var st = St.normal
    var buf = [UInt8]()
    var escSeq: UInt64 = 0
    var state = ModeState()
    var atEsc = ModeState()

    /// Feed one byte at absolute offset `seq`. Returns a cut event when a cut-point sequence completes.
    mutating func feed(_ b: UInt8, seq: UInt64) -> CutEvent? {
        switch st {
        case .normal:
            if b == 0x1b { st = .esc; escSeq = seq; atEsc = state }
        case .esc:
            switch b {
            case 0x5b: st = .csi; buf.removeAll(keepingCapacity: true)
            case 0x5d: st = .osc; buf.removeAll(keepingCapacity: true)
            case 0x63: st = .normal; state = ModeState(); return CutEvent(seq: escSeq, before: atEsc)   // ESC c
            case 0x3d: st = .normal; state.keypadApp = true
            case 0x3e: st = .normal; state.keypadApp = false
            case 0x1b: escSeq = seq; atEsc = state
            default: st = .normal
            }
        case .csi:
            if b >= 0x40 && b <= 0x7e {
                st = .normal
                let s = String(decoding: buf, as: UTF8.self)
                if s.hasPrefix("?") && (b == 0x68 || b == 0x6c) {
                    var cut = false
                    for p in s.dropFirst().split(separator: ";").compactMap({ Int($0) }) {
                        state.dec[p] = (b == 0x68)
                        if b == 0x68 && (p == 1049 || p == 47 || p == 1047) { cut = true }
                    }
                    if cut { return CutEvent(seq: escSeq, before: atEsc) }
                } else if b == 0x4a && (s == "2" || s == "3") {
                    return CutEvent(seq: escSeq, before: atEsc)
                }
            } else if b == 0x1b { st = .esc; escSeq = seq; atEsc = state } else { buf.append(b); if buf.count > 64 { st = .normal } }
        case .osc:
            if b == 0x07 { finishOsc(); st = .normal }
            else if b == 0x1b { st = .oscEsc }
            else { buf.append(b); if buf.count > 512 { st = .normal } }
        case .oscEsc:
            if b == 0x5c { finishOsc(); st = .normal } else { st = .normal }
        }
        return nil
    }

    mutating func finishOsc() {
        if buf.count >= 2, (buf[0] == 0x30 || buf[0] == 0x32), buf[1] == 0x3b { state.title = Array(buf[2...]) }
    }
}
