import Foundation

public enum HumanRequestKind: String, Codable, CaseIterable, Sendable {
    case login, verification, download, choice, other
}

public enum HumanRequestState: String, Codable, Sendable {
    case pending, acknowledged, resolved
}

public struct HumanRequestTarget: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let terminalID: UUID
    public let runID: UUID?
    public let computerID: UUID

    public init(sessionID: UUID, terminalID: UUID, runID: UUID?, computerID: UUID) {
        self.sessionID = sessionID
        self.terminalID = terminalID
        self.runID = runID
        self.computerID = computerID
    }
}

public struct HumanRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let target: HumanRequestTarget
    public let kind: HumanRequestKind
    /// A broker-sanitized description. Never place passwords, tokens, cookies, or raw page content here.
    public let summary: String
    public let createdAt: Date
    public var state: HumanRequestState
    public var resolvedAt: Date?

    public init(id: UUID = UUID(), target: HumanRequestTarget, kind: HumanRequestKind,
                summary: String, createdAt: Date = Date(), state: HumanRequestState = .pending,
                resolvedAt: Date? = nil) {
        self.id = id; self.target = target; self.kind = kind
        self.summary = summary; self.createdAt = createdAt
        self.state = state; self.resolvedAt = resolvedAt
    }
}

public enum HumanRequestError: LocalizedError, Equatable {
    case unsupportedSchema
    case invalidRequest
    case conflictingIdentity
    case missingRequest

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema: return "Os pedidos humanos usam uma versão de arquivo desconhecida. O arquivo foi preservado."
        case .invalidRequest: return "O pedido humano não tem identidade ou descrição válida."
        case .conflictingIdentity: return "O mesmo ID de pedido foi recebido para outro alvo."
        case .missingRequest: return "O pedido humano não foi encontrado."
        }
    }
}

public struct HumanRequestSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requests: [HumanRequest]
    /// Notification delivery is deduplicated by request ID, including after app relaunch.
    public var notifiedIDs: Set<UUID>

    public init(schemaVersion: Int = 1, requests: [HumanRequest] = [], notifiedIDs: Set<UUID> = []) {
        self.schemaVersion = schemaVersion
        self.requests = requests
        self.notifiedIDs = notifiedIDs
    }

    @discardableResult public mutating func record(_ request: HumanRequest) throws -> Bool {
        try Self.validate(request)
        if let existing = requests.first(where: { $0.id == request.id }) {
            guard existing.target == request.target && existing.kind == request.kind &&
                  existing.summary == request.summary && existing.createdAt == request.createdAt else {
                throw HumanRequestError.conflictingIdentity
            }
            return false
        }
        requests.append(request)
        return true
    }

    public mutating func acknowledge(_ id: UUID) throws {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { throw HumanRequestError.missingRequest }
        if requests[index].state == .pending { requests[index].state = .acknowledged }
    }

    public mutating func resolve(_ id: UUID, at date: Date = Date()) throws {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { throw HumanRequestError.missingRequest }
        guard requests[index].state != .pending else { throw HumanRequestError.invalidRequest }
        requests[index].state = .resolved
        requests[index].resolvedAt = requests[index].resolvedAt ?? date
    }

    /// Call before scheduling a macOS notification; a second delivery cannot cause a second sound.
    @discardableResult public mutating func claimNotification(_ id: UUID) throws -> Bool {
        guard requests.contains(where: { $0.id == id }) else { throw HumanRequestError.missingRequest }
        return notifiedIDs.insert(id).inserted
    }

    public func pendingCount(sessionID: UUID? = nil, terminalID: UUID? = nil,
                             runID: UUID? = nil, computerID: UUID? = nil) -> Int {
        requests.filter { request in
            request.state != .resolved &&
            (sessionID == nil || request.target.sessionID == sessionID) &&
            (terminalID == nil || request.target.terminalID == terminalID) &&
            (runID == nil || request.target.runID == runID) &&
            (computerID == nil || request.target.computerID == computerID)
        }.count
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw HumanRequestError.unsupportedSchema }
        guard Set(requests.map(\.id)).count == requests.count else { throw HumanRequestError.conflictingIdentity }
        try requests.forEach(Self.validate)
        guard notifiedIDs.isSubset(of: Set(requests.map(\.id))) else { throw HumanRequestError.invalidRequest }
    }

    private static func validate(_ request: HumanRequest) throws {
        let summary = request.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.utf8.count <= 512,
              !summary.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (request.state == .resolved) == (request.resolvedAt != nil) else {
            throw HumanRequestError.invalidRequest
        }
    }
}

public struct HumanRequestRepository {
    public let url: URL
    public init(url: URL = AppPaths.applicationSupport.appendingPathComponent("human-requests.json")) { self.url = url }

    public func load() throws -> HumanRequestSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return HumanRequestSnapshot() }
        let snapshot = try JSONDecoder().decode(HumanRequestSnapshot.self, from: Data(contentsOf: url))
        try snapshot.validate()
        return snapshot
    }

    public func save(_ snapshot: HumanRequestSnapshot) throws {
        try snapshot.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: url.deletingLastPathComponent().path)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
