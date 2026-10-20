import Foundation
import Security

public protocol SecretValueStoring {
    func put(id: UUID, value: String) throws
    func read(id: UUID) throws -> String
    func delete(id: UUID) throws
}

/// Values live in the user's Keychain, keyed by an opaque UUID. No value is written to metadata.
public struct KeychainSecretStore: SecretValueStoring {
    private let service = "com.racky.secret.v1"
    public init() {}
    private func key(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
    public func put(id: UUID, value: String) throws {
        var attributes = key(id)
        attributes[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretError.keychain(Int(status)) }
    }
    public func read(id: UUID) throws -> String {
        var query = key(id)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw SecretError.keychain(Int(status)) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretError.invalidStoredValue
        }
        return value
    }
    public func delete(id: UUID) throws {
        let status = SecItemDelete(key(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretError.keychain(Int(status))
        }
    }
}

public struct SecretRepository {
    public let url: URL
    public init(url: URL = AppPaths.applicationSupport.appendingPathComponent("secret-references.json")) {
        self.url = url
    }
    public func load() throws -> SecretDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return SecretDocument() }
        let document = try JSONDecoder().decode(SecretDocument.self, from: Data(contentsOf: url))
        try validate(document)
        return document
    }
    public func save(_ document: SecretDocument) throws {
        try validate(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func validate(_ document: SecretDocument) throws {
        guard document.schemaVersion == 1 else { throw SecretError.unsupportedSchema }
        guard Set(document.references.map(\.id)).count == document.references.count,
              Set(document.references.map(\.name)).count == document.references.count,
              Set(document.grants.map(\.id)).count == document.grants.count else {
            throw SecretError.duplicateName("ID ou nome")
        }
        let known = Set(document.references.map(\.id))
        guard document.grants.allSatisfy({ known.contains($0.secretID) && !$0.destination.isEmpty }) else {
            throw SecretError.missingSecret
        }
    }
}

public struct SecretVault<Backend: SecretValueStoring> {
    public let backend: Backend
    public let repository: SecretRepository
    public init(backend: Backend, repository: SecretRepository = SecretRepository()) {
        self.backend = backend; self.repository = repository
    }

    @discardableResult public func add(name: String, value: String,
                                       sourceLabel: String = "Manual") throws -> SecretReference {
        guard Self.validName(name) else { throw SecretError.invalidName }
        var document = try repository.load()
        guard !document.references.contains(where: { $0.name == name }) else {
            throw SecretError.duplicateName(name)
        }
        let reference = SecretReference(name: name, sourceLabel: sourceLabel)
        try backend.put(id: reference.id, value: value)
        document.references.append(reference)
        do { try repository.save(document) }
        catch { try? backend.delete(id: reference.id); throw error }
        return reference
    }

    /// A batch is all-or-nothing for metadata. Newly inserted Keychain items are rolled back on failure.
    @discardableResult public func importEnv(_ parsed: EnvParseResult,
                                              sourceLabel: String) throws -> [SecretReference] {
        guard parsed.duplicateNames.isEmpty else { throw SecretError.duplicatesInFile(parsed.duplicateNames) }
        var document = try repository.load()
        var seenNames: Set<String> = [], repeatedNames: Set<String> = []
        for entry in parsed.entries where !seenNames.insert(entry.name).inserted {
            repeatedNames.insert(entry.name)
        }
        guard repeatedNames.isEmpty else { throw SecretError.duplicatesInFile(repeatedNames.sorted()) }
        for entry in parsed.entries {
            guard Self.validName(entry.name) else { throw SecretError.invalidName }
            guard !document.references.contains(where: { $0.name == entry.name }) else {
                throw SecretError.duplicateName(entry.name)
            }
        }
        let references = parsed.entries.map { SecretReference(name: $0.name, sourceLabel: sourceLabel) }
        var inserted: [UUID] = []
        do {
            for (entry, reference) in zip(parsed.entries, references) {
                try backend.put(id: reference.id, value: entry.value)
                inserted.append(reference.id)
            }
            document.references.append(contentsOf: references)
            try repository.save(document)
        } catch {
            for id in inserted { try? backend.delete(id: id) }
            throw error
        }
        return references
    }

    @discardableResult public func grant(secretID: UUID, scope: SecretGrantScope, scopeID: UUID,
                                         use: SecretGrantUse, destination: String,
                                         delegable: Bool = false, expiresAt: Date? = nil,
                                         now: Date = Date()) throws -> SecretGrant {
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { throw SecretError.invalidDestination }
        guard expiresAt.map({ $0 > now }) ?? true else { throw SecretError.invalidExpiry }
        var document = try repository.load()
        guard document.references.contains(where: { $0.id == secretID }) else { throw SecretError.missingSecret }
        guard !document.grants.contains(where: { $0.secretID == secretID && $0.scope == scope &&
            $0.scopeID == scopeID && $0.use == use && $0.destination == destination &&
            $0.revokedAt == nil && ($0.expiresAt.map { $0 > now } ?? true) }) else {
            throw SecretError.duplicateGrant
        }
        let grant = SecretGrant(secretID: secretID, scope: scope, scopeID: scopeID,
                                use: use, destination: destination, delegable: delegable,
                                expiresAt: expiresAt, createdAt: now)
        document.grants.append(grant)
        try repository.save(document)
        return grant
    }

    public func revoke(grantID: UUID, at date: Date = Date()) throws {
        var document = try repository.load()
        guard let index = document.grants.firstIndex(where: { $0.id == grantID }) else {
            throw SecretError.missingGrant
        }
        document.grants[index].revoke(at: date)
        try repository.save(document)
    }

    /// For trusted broker code only. Exact scope and destination match is required; delegation is never implicit.
    public func resolve(_ request: SecretAccessRequest, at date: Date = Date()) throws -> String {
        let document = try repository.load()
        guard document.references.contains(where: { $0.id == request.secretID }),
              document.grants.contains(where: { $0.permits(request, at: date) }) else {
            throw SecretError.denied
        }
        return try backend.read(id: request.secretID)
    }

    private static func validName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }
}
