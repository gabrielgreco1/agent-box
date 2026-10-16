import Foundation

public enum CaptureError: Error, Equatable, LocalizedError {
    case invalidConfiguration, invalidWireData, identityMismatch, unsafePath, corruptStore
    case quotaExceeded, missingResult, invalidColumn

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Configuração de captura inválida."
        case .invalidWireData: "Evento de captura inválido ou fora dos limites."
        case .identityMismatch: "O evento não pertence ao computador verificado."
        case .unsafePath: "O armazenamento de captura não é um arquivo privado seguro."
        case .corruptStore: "Os dados salvos estão corrompidos; nenhuma captura foi sobrescrita."
        case .quotaExceeded: "O limite local de capturas ou resultados foi atingido."
        case .missingResult: "Resultado não encontrado."
        case .invalidColumn: "Coluna inválida ou não selecionada na captura."
        }
    }
}

public struct CaptureConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var hosts: [String]
    public var pathPrefixes: [String]
    public var includeJSON: Bool
    public var jsonFields: [String]
    public var maxBodyBytes: Int
    public var maxEvents: Int
    public var retentionSeconds: Int

    enum CodingKeys: String, CodingKey {
        case enabled, hosts
        case pathPrefixes = "path_prefixes", includeJSON = "include_json", jsonFields = "json_fields"
        case maxBodyBytes = "max_body_bytes", maxEvents = "max_events", retentionSeconds = "retention_seconds"
    }

    public init(enabled: Bool = false, hosts: [String] = [], pathPrefixes: [String] = [],
                includeJSON: Bool = false, jsonFields: [String] = [], maxBodyBytes: Int = 4_096,
                maxEvents: Int = 256, retentionSeconds: Int = 3_600) {
        self.enabled = enabled; self.hosts = hosts; self.pathPrefixes = pathPrefixes
        self.includeJSON = includeJSON; self.jsonFields = jsonFields
        self.maxBodyBytes = maxBodyBytes; self.maxEvents = maxEvents; self.retentionSeconds = retentionSeconds
    }

    public func validated() throws -> Self {
        guard (1...65_536).contains(maxBodyBytes), (1...1_000).contains(maxEvents),
              (1...86_400).contains(retentionSeconds), hosts.count <= 64,
              pathPrefixes.count <= 32, jsonFields.count <= 32,
              Set(hosts).count == hosts.count, Set(jsonFields).count == jsonFields.count,
              (!enabled || !hosts.isEmpty), (!includeJSON || !jsonFields.isEmpty),
              hosts.allSatisfy(CaptureSanitizer.validHost),
              pathPrefixes.allSatisfy(CaptureSanitizer.validPathPrefix),
              jsonFields.allSatisfy(CaptureSanitizer.validField) else { throw CaptureError.invalidConfiguration }
        return self
    }
}

public enum CaptureScalar: Equatable, Sendable, Codable {
    case string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self), number.isFinite { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else { throw CaptureError.invalidWireData }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let text): try value.encode(text)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }
}

public struct CaptureEvent: Codable, Equatable, Sendable {
    public let sequence: Int
    public let requestID: String
    public let source: String
    public let method: String
    public let url: String
    public let status: Int?
    public let mime: String?
    public let timestamp: String
    public let durationMS: Double?
    public let bodyJSON: [String: CaptureScalar]?
    public let bodySHA256: String?
    public let omission: String?

    enum CodingKeys: String, CodingKey {
        case sequence, source, method, url, status, mime, timestamp, omission
        case requestID = "request_id", durationMS = "duration_ms", bodyJSON = "body_json", bodySHA256 = "body_sha256"
    }

    public init(sequence: Int, requestID: String, source: String, method: String, url: String,
                status: Int? = nil, mime: String? = nil, timestamp: String, durationMS: Double? = nil,
                bodyJSON: [String: CaptureScalar]? = nil, bodySHA256: String? = nil, omission: String? = nil) {
        self.sequence = sequence; self.requestID = requestID; self.source = source; self.method = method
        self.url = url; self.status = status; self.mime = mime; self.timestamp = timestamp
        self.durationMS = durationMS; self.bodyJSON = bodyJSON; self.bodySHA256 = bodySHA256; self.omission = omission
    }
}

public struct CaptureBatch: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let captureID: UUID
    public let coverageVersion: String
    public let computerID: String
    public let enabled: Bool
    public let coverage: [String]
    public let gaps: [String]
    public let events: [CaptureEvent]
    public let nextCursor: Int
    public let dropped: Int

    enum CodingKeys: String, CodingKey {
        case enabled, coverage, gaps, events, dropped
        case schemaVersion = "schema_version", captureID = "capture_id"
        case coverageVersion = "coverage_version", computerID = "computer_id", nextCursor = "next_cursor"
    }

    public init(schemaVersion: Int, captureID: UUID, coverageVersion: String,
                computerID: String, enabled: Bool, coverage: [String],
                gaps: [String], events: [CaptureEvent], nextCursor: Int, dropped: Int) {
        self.schemaVersion = schemaVersion; self.captureID = captureID
        self.coverageVersion = coverageVersion; self.computerID = computerID; self.enabled = enabled
        self.coverage = coverage; self.gaps = gaps; self.events = events
        self.nextCursor = nextCursor; self.dropped = dropped
    }
}

public struct CaptureIdentity: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let terminalID: UUID
    public let ownerRunID: UUID?
    public let computerID: UUID

    public init(sessionID: UUID, terminalID: UUID, ownerRunID: UUID? = nil, computerID: UUID) {
        self.sessionID = sessionID; self.terminalID = terminalID
        self.ownerRunID = ownerRunID; self.computerID = computerID
    }
}

public struct CaptureRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let captureID: UUID
    public let identity: CaptureIdentity
    public let event: CaptureEvent
    public let evidenceSHA256: String
    public var duplicateCount: Int
    public let firstObservedAt: Date
    public var lastObservedAt: Date
    public let expiresAt: Date
}

public struct CaptureAppendResult: Equatable, Sendable {
    public let inserted: Int
    public let duplicates: Int
    public let reportedDropped: Int
    public let localDropped: Int
}

public struct CaptureStatus: Equatable, Sendable {
    public let coverage: [String]
    public let gaps: [String]
    public let reportedDropped: Int
    public let localDropped: Int
    public let retainedEvents: Int
}

enum CaptureSanitizer {
    private static let sensitiveNames = ["token", "secret", "password", "passwd", "cookie", "authorization", "auth", "key", "credential", "session"]

    static func validHost(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 253 && value == value.lowercased() &&
        value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 } &&
        !value.hasPrefix(".") && !value.hasSuffix(".") && !value.hasPrefix("-") &&
        !value.hasSuffix("-") && !value.contains("..")
    }

    static func validPathPrefix(_ value: String) -> Bool {
        value.hasPrefix("/") && value.utf8.count <= 200 &&
        value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) ||
            (48...57).contains($0) || [47, 95, 46, 45].contains($0) } &&
        !value.contains("..") && !value.contains("//")
    }

    static func validField(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 &&
        value.utf8.first.map({ (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }) == true &&
        value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) ||
            (48...57).contains($0) || $0 == 95 } &&
        !sensitiveNames.contains(where: { value.lowercased().contains($0) })
    }

    static func validTimestamp(_ value: String) -> Bool {
        guard (20...40).contains(value.utf8.count) else { return false }
        let plain = ISO8601DateFormatter()
        if plain.date(from: value) != nil { return true }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) != nil
    }

    static func sanitized(_ event: CaptureEvent, configuration: CaptureConfiguration) throws -> CaptureEvent {
        guard event.sequence >= 0, (1...128).contains(event.requestID.utf8.count),
              event.requestID.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }),
              ["browser", "http_tool"].contains(event.source),
              ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "OTHER"].contains(event.method),
              let parts = URLComponents(string: event.url),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased(), validHost(host),
              parts.user == nil, parts.password == nil,
              event.url.utf8.count <= 4_096,
              event.status.map({ (100...599).contains($0) }) ?? true,
              event.durationMS.map({ $0.isFinite && $0 >= 0 && $0 < 3_600_000 }) ?? true,
              validTimestamp(event.timestamp),
              event.bodySHA256.map({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) ?? true else {
            throw CaptureError.invalidWireData
        }
        guard configuration.hosts.contains(host) else { throw CaptureError.invalidConfiguration }
        let approvedPath = configuration.pathPrefixes.sorted { $0.count > $1.count }
            .first(where: { parts.path.hasPrefix($0) }) ?? ""
        var safeURL = URLComponents()
        safeURL.scheme = scheme; safeURL.host = host; safeURL.port = parts.port
        safeURL.path = approvedPath
        guard let url = safeURL.string, url.utf8.count <= 4_096 else { throw CaptureError.invalidWireData }
        let safeBody: [String: CaptureScalar]?
        if configuration.includeJSON, let body = event.bodyJSON {
            guard body.count <= 64 else { throw CaptureError.invalidWireData }
            var selected: [String: CaptureScalar] = [:]
            for (key, value) in body where configuration.jsonFields.contains(key) {
                guard validField(key) else { throw CaptureError.invalidWireData }
                if case .string(let text) = value {
                    guard text.utf8.count <= 2_048, !text.contains("\0") else { throw CaptureError.invalidWireData }
                }
                selected[key] = value
            }
            safeBody = selected
        } else { safeBody = nil }
        if let safeBody {
            guard try JSONEncoder().encode(safeBody).count <= min(configuration.maxBodyBytes, 65_536) else {
                throw CaptureError.invalidWireData
            }
        }
        return CaptureEvent(sequence: event.sequence, requestID: event.requestID, source: event.source,
            method: event.method, url: url, status: event.status,
            mime: event.mime.flatMap { $0.utf8.count <= 128 && !$0.contains("\0") ? $0 : nil },
            timestamp: event.timestamp, durationMS: event.durationMS, bodyJSON: safeBody,
            bodySHA256: event.bodySHA256?.lowercased(),
            omission: event.omission.flatMap { $0.utf8.count <= 128 && !$0.contains("\0") ? $0 : nil })
    }
}
