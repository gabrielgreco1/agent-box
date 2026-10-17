import AgentBoxDocker
import AgentBoxProtocol
import AgentBoxStore
import Foundation

public enum ProxyServiceError: Error, Sendable, Equatable {
    case nameInUse(String)
    case secretMissing(proxy: String)
    case importNotConfirmed
    case cliEnvNotFound(String)
    case cliKeyNotFound
}

/// Resultado de `importZyteFromCLI`. Nunca carrega o valor da chave.
public struct ZyteImportResult: Sendable, Equatable {
    public var proxy: ProxyProfile
    /// `true` se já existia um proxy de mesmo nome e ele foi atualizado (a chave é regravada, o resto é preservado).
    public var updatedExisting: Bool
}

/// Proxies configurados pelo usuário (T3-02, 07 §2.6, P13): cadastro, segredo em arquivo 0600 (TODO T2-10: Vault), montagem
/// da config do egress e o importador `Import from agentbox CLI…`. Sem teto de orçamento em nenhum ponto.
public struct ProxyService: Sendable {
    public let store: AgentBoxStore
    public let secrets: ProxySecretFileStore

    public init(store: AgentBoxStore, secrets: ProxySecretFileStore) {
        self.store = store
        self.secrets = secrets
    }

    /// Cria ou atualiza um proxy. `secret` (senha, ou a chave no preset Zyte) vai para o armazenamento, nunca para o SQLite.
    /// `secret == nil` mantém o segredo atual.
    @discardableResult
    public func save(_ profile: ProxyProfile, secret: String? = nil) async throws -> ProxyProfile {
        var profile = profile
        if let other = try await store.proxy(named: profile.name), other.id != profile.id { throw ProxyServiceError.nameInUse(profile.name) }
        if let secret, !secret.isEmpty {
            let id = profile.secretID ?? ProxySecretFileStore.secretID(proxyID: profile.id)
            try secrets.store(secret, secretID: id)
            profile.secretID = id
            profile.secretStorage = .file
        }
        profile.updatedAt = Date()
        try await store.save(profile)
        return profile
    }

    public func delete(id: UUID) async throws {
        if let profile = try await store.proxy(id: id), let secretID = profile.secretID, profile.secretStorage == .file {
            try secrets.remove(secretID: secretID)
        }
        try await store.deleteProxy(id: id)
    }

    /// Config do egress para o proxy escolhido (`nil` = `direct`). O segredo é lido aqui e só vai para o arquivo 0400 do egress.
    public func egressConfig(for proxyID: UUID?, allowCIDRs: [String] = [], allowHosts: [String] = []) async throws -> (config: EgressConfigFile, caPEM: String?) {
        guard let proxyID, let profile = try await store.proxy(id: proxyID) else {
            return (EgressConfigFile.make(profile: nil, secret: nil, allowCIDRs: allowCIDRs, allowHosts: allowHosts), nil)
        }
        var secret: String?
        if let secretID = profile.secretID {
            guard profile.secretStorage == .file else { throw ProxyServiceError.secretMissing(proxy: profile.name) }  // TODO(T2-10): ler do Vault
            secret = try secrets.load(secretID: secretID)
            if secret == nil { throw ProxyServiceError.secretMissing(proxy: profile.name) }
        }
        return (EgressConfigFile.make(profile: profile, secret: secret, allowCIDRs: allowCIDRs, allowHosts: allowHosts), profile.caPEM)
    }

    // MARK: Import from agentbox CLI…

    /// Caminho padrão do `.env` do CLI antigo.
    public static func defaultCLIEnvFile() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("orca/projects/agentbox/.env")
    }

    /// `Import from agentbox CLI…` (08 AR-343, 07 CS-160): lê SÓ `ZYTE_API_KEY` (e os preços informativos) do `.env` do CLI antigo,
    /// somente leitura, e cria/atualiza o proxy com preset `zyte`. Exige confirmação explícita. Nunca loga a chave. Os demais
    /// valores do arquivo (token do Claude, `ZYTE_BUDGET_USD`...) são ignorados: não há teto de orçamento (P13).
    @discardableResult
    public func importZyteFromCLI(envFile: URL = ProxyService.defaultCLIEnvFile(), confirmed: Bool, name: String = "zyte") async throws -> ZyteImportResult {
        guard confirmed else { throw ProxyServiceError.importNotConfirmed }
        guard FileManager.default.isReadableFile(atPath: envFile.path) else { throw ProxyServiceError.cliEnvNotFound(envFile.lastPathComponent) }
        let wanted: Set<String> = ["ZYTE_API_KEY", "ZYTE_USD_PER_REQUEST", "ZYTE_USD_PER_RENDER"]
        let values = DotEnv.read(try Data(contentsOf: envFile), keys: wanted)
        guard let key = values["ZYTE_API_KEY"], !key.isEmpty else { throw ProxyServiceError.cliKeyNotFound }

        let existing = try await store.proxy(named: name)
        var profile = existing ?? ProxyProfile.zytePreset(name: name, secretID: nil)
        profile.preset = .zyte
        if existing == nil {
            profile.pricePerRequestMicros = DotEnv.micros(values["ZYTE_USD_PER_REQUEST"])
            profile.pricePerRenderMicros = DotEnv.micros(values["ZYTE_USD_PER_RENDER"])
        }
        let saved = try await save(profile, secret: key)
        return ZyteImportResult(proxy: saved, updatedExisting: existing != nil)
    }
}

/// Leitor mínimo de `.env` que devolve SÓ as chaves pedidas (o resto do arquivo nunca sai desta função).
enum DotEnv {
    static func read(_ data: Data, keys: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard keys.contains(key) else { continue }
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'", let close = value.dropFirst().firstIndex(of: quote) {
                value = String(value[value.index(after: value.startIndex)..<close])  // o que vem depois da aspa de fechamento é comentário
            } else if let hash = value.range(of: " #") {  // comentário no fim da linha (só sem aspas)
                value = String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            result[key] = value
        }
        return result
    }

    /// `0.00013` (USD) -> `130` (micro-USD). Inválido/negativo -> `nil`.
    static func micros(_ usd: String?) -> Int64? {
        guard let usd, let value = Decimal(string: usd), value >= 0 else { return nil }
        let micros = NSDecimalNumber(decimal: value * 1_000_000).rounding(accordingToBehavior: nil)
        return micros.int64Value
    }
}
