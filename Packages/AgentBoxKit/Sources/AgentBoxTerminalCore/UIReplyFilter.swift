import Foundation

/// Política de respostas do emulador da UI (08 AR-105, AR-520, 00 T6). Diferente do headless do daemon
/// (`QueryReplyFilter`), o da UI é o respondente quando há cliente anexado: responde DA/DSR/tamanho e consultas de
/// cor. **Nunca** devolve o clipboard: `OSC 52 ; <sel> ; ?` não gera resposta em nenhuma circunstância.
public enum UIReplyFilter {
    public static func allows(_ reply: [UInt8]) -> Bool {
        // `ESC ] 52 ;` (7-bit) ou `OSC` C1 (0x9d) `52 ;`.
        let sevenBit: [UInt8] = [0x1b, 0x5d, 0x35, 0x32, 0x3b]
        if reply.starts(with: sevenBit) { return false }
        if reply.first == 0x9d, reply.dropFirst().starts(with: [0x35, 0x32, 0x3b]) { return false }
        return true
    }
}

/// Sanitização do que vai ao PTY numa colagem ou arrasto (08 §A3): remove ESC e os controles C0/C1, exceto `\t` e `\n`,
/// para que texto colado não feche o bracketed paste (`ESC [ 201 ~`) nem injete sequências.
public enum PasteSanitizer {
    public static func sanitize(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0a: result.append(scalar)
            case 0x00 ... 0x1f, 0x7f, 0x80 ... 0x9f: continue
            default: result.append(scalar)
            }
        }
        return String(result)
    }
}
