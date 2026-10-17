import Foundation

/// Identidade do LaunchAgent do daemon (08 §0.1): label, plist embutido e chave do socket.
public struct BackgroundAgentIdentity: Sendable, Equatable {
    public var label: String
    /// Arquivo em `Contents/Library/LaunchAgents/`.
    public var plistName: String
    /// Valor de `SecureSocketWithKey`: o launchd publica o caminho do socket nesta variável do domínio do usuário.
    public var socketKey: String
    public var isTest: Bool

    public init(label: String, socketKey: String, isTest: Bool) {
        self.label = label
        plistName = "\(label).plist"
        self.socketKey = socketKey
        self.isTest = isTest
    }

    /// Produto: major do protocolo `1` (06 §1.10: label, plist e variável carregam a major).
    public static func production(major: Int = 1) -> BackgroundAgentIdentity {
        BackgroundAgentIdentity(label: "app.agentbox.ptyd.v\(major)", socketKey: "AGENTBOX_PTYD_SOCK_V\(major)", isTest: false)
    }

    /// Testes (08 §0.1): `app.agentbox.ptyd.test-<n>`, com a chave do socket própria para nunca colidir com a do produto.
    public static func test(suffix: String) -> BackgroundAgentIdentity {
        BackgroundAgentIdentity(label: "app.agentbox.ptyd.test-\(suffix)", socketKey: "AGENTBOX_PTYD_SOCK_TEST_\(suffix.uppercased())", isTest: true)
    }

    /// Sufixo estável de 8 hex derivado do `AGENTBOX_HOME` (FNV-1a de 32 bits): o mesmo home sempre dá o mesmo label.
    public static func testSuffix(forHome home: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in home.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }

    /// `AGENTBOX_HOME` definido isola o daemon num label de teste (`AGENTBOX_TEST_N` fixa o sufixo).
    public static func resolve(environment: [String: String]) -> BackgroundAgentIdentity {
        if let home = environment["AGENTBOX_HOME"], !home.isEmpty {
            let fixed = environment["AGENTBOX_TEST_N"].flatMap { $0.isEmpty ? nil : $0 }
            return .test(suffix: fixed ?? testSuffix(forHome: home))
        }
        return .production()
    }
}
