import AgentBoxDocker
import AgentBoxProtocol
import AgentBoxStore
import Foundation
import Testing

@testable import AgentBoxCore

/// `ProxyService` (T3-02): cadastro com segredo fora do SQLite e `Import from agentbox CLI…`.
@Suite("T3-02 - ProxyService e importador da chave Zyte")
struct ProxyServiceTests {
    struct Env {
        let root: URL
        let store: AgentBoxStore
        let service: ProxyService
        let secrets: ProxySecretFileStore
    }

    private func make() async throws -> Env {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("abx-proxysvc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try await AgentBoxStore.open(paths: StorePaths(root: root))
        let secrets = ProxySecretFileStore(root: root)
        return Env(root: root, store: store, service: ProxyService(store: store, secrets: secrets), secrets: secrets)
    }

    private func writeEnv(_ env: Env, _ text: String) throws -> URL {
        let url = env.root.appendingPathComponent("cli.env")
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    @Test func savingStoresSecretInFileNotInSQLite() async throws {
        let env = try await make(); defer { try? FileManager.default.removeItem(at: env.root) }
        let saved = try await env.service.save(ProxyProfile(name: "corp", scheme: .http, host: "p.example", port: 3128, username: "bob"), secret: "TOPSECRETVALUE")
        #expect(saved.secretID == ProxySecretFileStore.secretID(proxyID: saved.id) && saved.secretStorage == .file)
        #expect(try env.secrets.load(secretID: try #require(saved.secretID)) == "TOPSECRETVALUE")
        // nenhum byte do banco (nem WAL) contém o valor
        try await env.store.close()
        let dbDir = env.root.appendingPathComponent("db")
        for url in try FileManager.default.contentsOfDirectory(at: dbDir, includingPropertiesForKeys: nil) {
            let data = try Data(contentsOf: url)
            #expect(data.range(of: Data("TOPSECRETVALUE".utf8)) == nil, "\(url.lastPathComponent) contém o segredo")
        }
    }

    @Test func updateWithoutSecretKeepsTheCurrentOne() async throws {
        let env = try await make(); defer { try? FileManager.default.removeItem(at: env.root) }
        var saved = try await env.service.save(ProxyProfile(name: "corp", scheme: .http, host: "p.example", port: 3128, username: "bob"), secret: "v1")
        saved.host = "other.example"
        saved = try await env.service.save(saved)
        #expect(try env.secrets.load(secretID: try #require(saved.secretID)) == "v1")
        _ = try await env.service.save(saved, secret: "v2")
        #expect(try env.secrets.load(secretID: try #require(saved.secretID)) == "v2")
    }

    @Test func nameMustBeUnique() async throws {
        let env = try await make(); defer { try? FileManager.default.removeItem(at: env.root) }
        _ = try await env.service.save(ProxyProfile(name: "dup", scheme: .http, host: "a", port: 1))
        await #expect(throws: ProxyServiceError.nameInUse("dup")) {
            _ = try await env.service.save(ProxyProfile(name: "dup", scheme: .http, host: "b", port: 2))
        }
    }

    @Test func deleteRemovesTheSecretFile() async throws {
        let env = try await make(); defer { try? FileManager.default.removeItem(at: env.root) }
        let saved = try await env.service.save(ProxyProfile(name: "gone", scheme: .socks5, host: "a", port: 1, username: "u"), secret: "pw")
        let secretID = try #require(saved.secretID)
        try await env.service.delete(id: saved.id)
        #expect(try env.secrets.load(secretID: secretID) == nil)
        #expect(try await env.store.proxy(id: saved.id) == nil)
    }

    @Test func egressConfigReadsTheSecretOnlyForTheChosenProxy() async throws {
        let env = try await make(); defer { try? FileManager.default.removeItem(at: env.root) }
        let saved = try await env.service.save(ProxyProfile(name: "corp", scheme: .socks5, host: "10.0.0.5", port: 1080, username: "bob"), secret: "pw-123456")
        let direct = try await env.service.egressConfig(for: nil)
        #expect(direct.config.via == "direct" && direct.config.upstream == nil)
        let chosen = try await env.service.egressConfig(for: saved.id, allowCIDRs: ["172.30.0.0/24"])
        #expect(chosen.config.via == "corp" && chosen.config.upstream?.password == "pw-123456" && chosen.config.upstream?.username == "bob")
        #expect(chosen.config.allowCIDRs == ["172.30.0.0/24"])
        try env.secrets.remove(secretID: try #require(saved.secretID))
        await #expect(throws: ProxyServiceError.secretMissing(proxy: "corp")) { _ = try await env.service.egressConfig(for: saved.id) }
    }

    // MARK: Import from agentbox CLI…

    @Test func zyteImportReadsOnlyTheKeyAndRequiresConfirmation() async throws {
        let env = try await make(); defer { try? FileManager.default.removeItem(at: env.root) }
        let file = try writeEnv(env, """
        # chave do Zyte
        ZYTE_API_KEY=abcdef0123456789abcdef0123456789
        CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-SHOULDNEVERBEIMPORTED
        CONCURRENCY=4
        ZYTE_BUDGET_USD=1.00
        ZYTE_USD_PER_REQUEST=0.00013
        ZYTE_USD_PER_RENDER=0.0015
        """)
        await #expect(throws: ProxyServiceError.importNotConfirmed) { _ = try await env.service.importZyteFromCLI(envFile: file, confirmed: false) }
        #expect(try await env.store.proxies().isEmpty, "sem confirmação não grava nada")

        let result = try await env.service.importZyteFromCLI(envFile: file, confirmed: true)
        #expect(!result.updatedExisting)
        let proxy = result.proxy
        #expect(proxy.preset == .zyte && proxy.host == "proxy.zyte.com" && proxy.port == 8011 && proxy.scheme == .http && proxy.name == "zyte")
        #expect(proxy.pricePerRequestMicros == 130 && proxy.pricePerRenderMicros == 1500, "preços são informativos")
        #expect(try env.secrets.load(secretID: try #require(proxy.secretID)) == "abcdef0123456789abcdef0123456789")
        // nada além da chave foi importado: o token do Claude e o teto de orçamento ficam de fora (P13)
        let stored = try String(contentsOf: env.secrets.directory.appendingPathComponent(try #require(proxy.secretID)), encoding: .utf8)
        #expect(!stored.contains("SHOULDNEVERBEIMPORTED"))
        let upstream = EgressUpstream(profile: proxy, secret: stored)
        #expect(upstream.username == stored && upstream.password == "")

        // o arquivo original não foi tocado
        #expect(try String(contentsOf: file, encoding: .utf8).contains("ZYTE_BUDGET_USD=1.00"))

        // reimportar atualiza a chave sem duplicar nem perder o resto
        _ = try writeEnv(env, "ZYTE_API_KEY=ffffffffffffffffffffffffffffffff\n")
        let again = try await env.service.importZyteFromCLI(envFile: file, confirmed: true)
        #expect(again.updatedExisting && again.proxy.id == proxy.id && again.proxy.pricePerRequestMicros == 130)
        #expect(try await env.store.proxies().count == 1)
        #expect(try env.secrets.load(secretID: try #require(proxy.secretID)) == "ffffffffffffffffffffffffffffffff")
    }

    @Test func zyteImportFailsCleanlyWithoutFileOrKey() async throws {
        let env = try await make(); defer { try? FileManager.default.removeItem(at: env.root) }
        await #expect(throws: ProxyServiceError.cliEnvNotFound("missing.env")) {
            _ = try await env.service.importZyteFromCLI(envFile: env.root.appendingPathComponent("missing.env"), confirmed: true)
        }
        let nokey = try writeEnv(env, "CONCURRENCY=4\n# ZYTE_API_KEY=commented\nZYTE_API_KEY=\n")
        await #expect(throws: ProxyServiceError.cliKeyNotFound) { _ = try await env.service.importZyteFromCLI(envFile: nokey, confirmed: true) }
        #expect(try await env.store.proxies().isEmpty)
    }

    @Test func dotEnvParsingHandlesQuotesExportAndComments() {
        let data = Data("export ZYTE_API_KEY=\"quoted-key\"\nZYTE_USD_PER_REQUEST='0.5' # c\nOTHER=1\n  \n".utf8)
        let values = DotEnv.read(data, keys: ["ZYTE_API_KEY", "ZYTE_USD_PER_REQUEST"])
        #expect(values == ["ZYTE_API_KEY": "quoted-key", "ZYTE_USD_PER_REQUEST": "0.5"])
        #expect(DotEnv.read(Data("ZYTE_API_KEY=abc # trailing\n".utf8), keys: ["ZYTE_API_KEY"])["ZYTE_API_KEY"] == "abc")
        #expect(DotEnv.micros("0.00013") == 130 && DotEnv.micros("-1") == nil && DotEnv.micros("abc") == nil && DotEnv.micros(nil) == nil)
    }

    /// Roda o importador contra o `.env` REAL do CLI antigo (só leitura) num banco e numa pasta descartáveis.
    /// Só com `AGENTBOX_TEST_REAL_ZYTE_ENV=1`. Grava evidência SEM o valor da chave.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AGENTBOX_TEST_REAL_ZYTE_ENV"] == "1"))
    func importsFromTheRealCLIEnvFile() async throws {
        let env = try await make(); defer { try? FileManager.default.removeItem(at: env.root) }
        let real = ProxyService.defaultCLIEnvFile()
        let before = try FileManager.default.attributesOfItem(atPath: real.path)[.modificationDate] as? Date
        let result = try await env.service.importZyteFromCLI(envFile: real, confirmed: true)
        let after = try FileManager.default.attributesOfItem(atPath: real.path)[.modificationDate] as? Date
        #expect(before == after, "o .env do CLI não foi modificado")
        let secretID = try #require(result.proxy.secretID)
        let value = try #require(try env.secrets.load(secretID: secretID))
        #expect(!value.isEmpty)
        let secretPath = env.secrets.directory.appendingPathComponent(secretID).path
        let mode = (try FileManager.default.attributesOfItem(atPath: secretPath)[.posixPermissions] as? NSNumber)?.intValue
        #expect(mode == 0o600)
        if let dir = ProcessInfo.processInfo.environment["AGENTBOX_EVIDENCE_DIR"] {
            let out = URL(fileURLWithPath: dir).appendingPathComponent("slice3/T3-02/zyte-import.json")
            try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            let summary: [String: Any] = [
                "source": "~/orca/projects/agentbox/.env (somente leitura; arquivo não modificado)",
                "proxy": ["name": result.proxy.name, "preset": result.proxy.preset.rawValue, "host": result.proxy.host, "port": result.proxy.port,
                          "scheme": result.proxy.scheme.rawValue, "price_per_request_micros": result.proxy.pricePerRequestMicros as Any,
                          "price_per_render_micros": result.proxy.pricePerRenderMicros as Any, "secret_storage": result.proxy.secretStorage.rawValue],
                "secret": "armazenado em arquivo 0600 (TODO T2-10: Vault); valor NÃO registrado aqui",
                "secret_file_mode": String(mode ?? 0, radix: 8),
                "imported_only": ["ZYTE_API_KEY", "ZYTE_USD_PER_REQUEST", "ZYTE_USD_PER_RENDER"],
                "ignored": "demais chaves do .env (token do Claude, concorrência, ZYTE_BUDGET_USD): sem teto de orçamento (P13)",
            ]
            try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: out)
        }
    }
}
