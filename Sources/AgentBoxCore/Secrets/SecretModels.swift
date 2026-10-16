import Foundation

public struct SecretReference: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let sourceLabel: String
    public let createdAt: Date
    public init(id: UUID = UUID(), name: String, sourceLabel: String, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.sourceLabel = sourceLabel; self.createdAt = createdAt
    }
}

public enum SecretGrantScope: String, Codable, CaseIterable, Sendable {
    case project, session, terminal, agentRun
    public var label: String {
        switch self {
        case .project: return "Projeto"
        case .session: return "Sessão"
        case .terminal: return "Terminal"
        case .agentRun: return "Execução do agente"
        }
    }
}

public enum SecretGrantUse: String, Codable, CaseIterable, Sendable {
    case tool, environment
    public var label: String { self == .tool ? "Ferramenta" : "Ambiente do processo" }
}

public struct SecretGrant: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let secretID: UUID
    public let scope: SecretGrantScope
    public let scopeID: UUID
    public let use: SecretGrantUse
    public let destination: String
    public let delegable: Bool
    public let expiresAt: Date?
    public private(set) var revision: Int
    public private(set) var revokedAt: Date?
    public let createdAt: Date

    public init(id: UUID = UUID(), secretID: UUID, scope: SecretGrantScope, scopeID: UUID,
                use: SecretGrantUse, destination: String, delegable: Bool = false,
                expiresAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id; self.secretID = secretID; self.scope = scope; self.scopeID = scopeID
        self.use = use; self.destination = destination; self.delegable = delegable
        self.expiresAt = expiresAt; self.revision = 1; self.revokedAt = nil; self.createdAt = createdAt
    }
    public mutating func revoke(at date: Date) {
        guard revokedAt == nil else { return }
        revokedAt = date; revision += 1
    }
    public func permits(_ request: SecretAccessRequest, at date: Date) -> Bool {
        secretID == request.secretID && scope == request.scope && scopeID == request.scopeID &&
        use == request.use && destination == request.destination && revokedAt == nil &&
        (expiresAt.map { $0 > date } ?? true)
    }
}

public struct SecretAccessRequest: Equatable, Sendable {
    public let secretID: UUID
    public let scope: SecretGrantScope
    public let scopeID: UUID
    public let use: SecretGrantUse
    public let destination: String
    public init(secretID: UUID, scope: SecretGrantScope, scopeID: UUID,
                use: SecretGrantUse, destination: String) {
        self.secretID = secretID; self.scope = scope; self.scopeID = scopeID
        self.use = use; self.destination = destination
    }
}

public struct SecretDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var references: [SecretReference]
    public var grants: [SecretGrant]
    public init(schemaVersion: Int = 1, references: [SecretReference] = [], grants: [SecretGrant] = []) {
        self.schemaVersion = schemaVersion; self.references = references; self.grants = grants
    }
}

public enum SecretError: Error, LocalizedError, Equatable {
    case unsupportedSchema
    case invalidName
    case duplicateName(String)
    case duplicatesInFile([String])
    case missingSecret
    case missingGrant
    case duplicateGrant
    case invalidDestination
    case invalidExpiry
    case denied
    case keychain(Int)
    case invalidStoredValue
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema: return "Versão de credenciais não suportada; os dados foram preservados."
        case .invalidName: return "Use um nome de variável válido."
        case .duplicateName(let name): return "Já existe uma entrada chamada \(name). Nenhum valor foi substituído."
        case .duplicatesInFile(let names): return "O arquivo contém nomes repetidos: \(names.joined(separator: ", ")). Revise antes de importar."
        case .missingSecret: return "A referência de credencial não existe."
        case .missingGrant: return "A concessão não existe."
        case .duplicateGrant: return "Já existe uma concessão ativa para este escopo, uso e destino."
        case .invalidDestination: return "Informe um destino específico para a concessão."
        case .invalidExpiry: return "O prazo da concessão precisa estar no futuro."
        case .denied: return "Esta operação não tem uma concessão ativa para o destino e escopo solicitados."
        case .keychain(let code): return "Keychain retornou erro \(code). Verifique o acesso do aplicativo."
        case .invalidStoredValue: return "O valor armazenado não é UTF-8 válido."
        }
    }
}
