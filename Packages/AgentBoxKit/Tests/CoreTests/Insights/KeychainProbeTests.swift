import Foundation
import Testing

@testable import AgentBoxCore

/// Sonda manual (`AGENTBOX_PROBE_KEYCHAIN=1`): lê a credencial real pelo `/usr/bin/security` e chama o endpoint. Nunca imprime o token.
struct KeychainProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AGENTBOX_PROBE_KEYCHAIN"] == "1"))
    func realCredentialAndEndpoint() async throws {
        let c = try KeychainClaudeCredentialSource().read()
        print("probe: token length \(c.accessToken.count), expires \(String(describing: c.expiresAt))")
        let result = await ClaudeLimitsClient().fetch()
        print("probe: \(result)")
    }
}
