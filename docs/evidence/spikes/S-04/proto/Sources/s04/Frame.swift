import Foundation

// Frame: u32 len (BE, counts kind+payload) | u8 kind | payload
// kind 1 control (UTF-8 text), 2 output (u64 seq BE | bytes), 3 input (bytes)
enum Kind: UInt8 { case control = 1, output = 2, input = 3 }

func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    var off = 0
    while off < bytes.count {
        let n = bytes[off...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if n < 0 { if errno == EINTR || errno == EAGAIN { usleep(1000); continue }; return false }
        off += n
    }
    return true
}

func encodeFrame(_ kind: Kind, _ payload: [UInt8]) -> [UInt8] {
    var f = [UInt8](); f.reserveCapacity(5 + payload.count)
    let len = UInt32(payload.count + 1)
    f += [UInt8(len >> 24), UInt8((len >> 16) & 255), UInt8((len >> 8) & 255), UInt8(len & 255), kind.rawValue]
    f += payload
    return f
}

func outputPayload(seq: UInt64, _ bytes: ArraySlice<UInt8>) -> [UInt8] {
    var p = [UInt8]()
    for i in (0..<8).reversed() { p.append(UInt8((seq >> UInt64(i * 8)) & 255)) }
    p += bytes
    return p
}

/// Incremental frame parser.
struct FrameParser {
    var buf = [UInt8]()
    mutating func push(_ d: ArraySlice<UInt8>) -> [(Kind, [UInt8])] {
        buf += d
        var out = [(Kind, [UInt8])](); var pos = 0
        while buf.count - pos >= 5 {
            let len = Int(buf[pos]) << 24 | Int(buf[pos+1]) << 16 | Int(buf[pos+2]) << 8 | Int(buf[pos+3])
            if len < 1 || len > 1 << 20 { buf.removeAll(); return out }   // frameTooLarge
            if buf.count - pos - 4 < len { break }
            let k = Kind(rawValue: buf[pos+4])
            let payload = Array(buf[(pos+5)..<(pos+4+len)])
            if let k { out.append((k, payload)) }
            pos += 4 + len
        }
        if pos > 0 { buf.removeFirst(pos) }
        return out
    }
}

func b64(_ b: [UInt8]) -> String { Data(b).base64EncodedString() }
func unb64(_ s: String) -> [UInt8] { [UInt8](Data(base64Encoded: s) ?? Data()) }
