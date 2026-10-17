import CryptoKit
import Foundation
import SQLite3

// Leitura do estado do Orca (06 §6.1; 08 AR-340). REGRA: nada do Orca é aberto, movido nem gravado. O banco
// `profile-state.db` (WAL) é COPIADO, junto com `-wal` e `-shm`, para um diretório temporário do app e só a cópia é aberta
// (`SQLITE_OPEN_READONLY`). Abrir o original, mesmo somente leitura, poderia criar/alterar o `-shm` de um Orca em uso.
// A cópia é apagada ao terminar, com sucesso ou erro.

public struct OrcaProfile: Sendable, Equatable {
    public let id: String
    public let directory: URL

    public var stateDatabase: URL { directory.appendingPathComponent("profile-state.db") }
    public var legacyJSON: URL { directory.appendingPathComponent("orca-data.json") }
    public var hasStateDatabase: Bool { FileManager.default.fileExists(atPath: stateDatabase.path) }
    public var hasLegacyJSON: Bool { FileManager.default.fileExists(atPath: legacyJSON.path) }
}

/// Descobre os dados do Orca. Padrão: `~/Library/Application Support/orca/profiles/<perfil>/`.
public struct OrcaLocator: Sendable {
    public let supportDirectory: URL

    public init(supportDirectory: URL = OrcaLocator.defaultSupportDirectory()) { self.supportDirectory = supportDirectory }

    public static func defaultSupportDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent("Library/Application Support/orca", isDirectory: true)
    }

    /// Perfis com banco de estado ou JSON legado, em ordem alfabética. Com um só, a importação segue direto; com vários, o
    /// onboarding pede a escolha. Só lista diretórios: não abre nenhum arquivo.
    public func profiles() -> [OrcaProfile] {
        let fm = FileManager.default
        let profilesDir = supportDirectory.appendingPathComponent("profiles", isDirectory: true)
        let names = ((try? fm.contentsOfDirectory(atPath: profilesDir.path)) ?? []).sorted()
        var result: [OrcaProfile] = []
        for name in names where !name.hasPrefix(".") {
            let dir = profilesDir.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let profile = OrcaProfile(id: name, directory: dir)
            if profile.hasStateDatabase || profile.hasLegacyJSON { result.append(profile) }
        }
        return result
    }

    /// Pasta de dados do Orca (a que contém `SingletonLock`) de um perfil achado por `profiles()`.
    public func dataDirectory(of profile: OrcaProfile) -> URL {
        profile.directory.deletingLastPathComponent().deletingLastPathComponent()
    }
}

// MARK: - Modelo lido

public struct OrcaRepo: Sendable, Equatable {
    public let id: String
    public let path: String
    public let displayName: String
    public let badgeColor: String?
    /// `git` ou `folder`.
    public let isFolder: Bool
    public let gitUsername: String?
}

public struct OrcaWorktreeMeta: Sendable, Equatable {
    public let repoID: String
    public let path: String
    public let displayName: String?
    public let comment: String?
    public let sortOrder: Int64?
    public let lastActivityAt: Int64?
}

public struct OrcaSettings: Sendable, Equatable {
    public var workspaceDir: String?
    public var branchPrefix: String?
    public var branchPrefixCustom: String?
    public var defaultTuiAgent: String?
    public var terminalDefaultShell: String?
    public var setupScriptLaunchMode: String?
    /// Só agentes que o Agent Box conhece entram no perfil; os outros ficam aqui para a contagem de ignorados.
    public var agentDefaultArgs: [String: String] = [:]
    public var agentDefaultEnv: [String: [String: String]] = [:]
    public var agentCmdOverrides: [String: String] = [:]
}

public enum OrcaStateSource: String, Sendable, Codable { case sqlite, legacyJSON }

public struct OrcaSnapshot: Sendable, Equatable {
    public var profileID: String
    public var source: OrcaStateSource
    public var repos: [OrcaRepo] = []
    public var worktreeMeta: [OrcaWorktreeMeta] = []
    /// Chaves `<repoId>::<path>` de worktrees com abas abertas no Orca (`workspaceSession.tabsByWorktree` não vazio).
    public var worktreesWithOpenTabs: Set<String> = []
    public var settings = OrcaSettings()
    public var notes: [String] = []
    /// SHA-256 do conteúdo lido (identifica a versão do estado para o `import_run`).
    public var fingerprint: String = ""
}

public enum OrcaReadError: Error, Sendable, Equatable {
    case noStateFound(String)
    case sqlite(String)
    case invalidJSON(String)
}

// MARK: - Leitor

public struct OrcaReader: Sendable {
    /// Domínios que o leitor entende; `domain_version` diferente de 1 pula o domínio com nota no relatório.
    static let supportedDomainVersion = 1
    static let wantedDomains = ["repos", "folderWorkspaces", "worktreeMeta", "settings", "workspaceSession"]

    private let tempRoot: URL

    public init(tempRoot: URL = FileManager.default.temporaryDirectory) { self.tempRoot = tempRoot }

    public func read(_ profile: OrcaProfile) throws -> OrcaSnapshot {
        var notes: [String] = []
        if profile.hasStateDatabase {
            do { return try readSQLite(profile) }
            catch {
                notes.append("profile-state.db could not be read (\(error)); used legacy orca-data.json")
            }
        }
        guard profile.hasLegacyJSON else { throw OrcaReadError.noStateFound(profile.directory.path) }
        var snapshot = try readLegacyJSON(profile)
        snapshot.notes = notes + snapshot.notes
        return snapshot
    }

    // MARK: SQLite (cópia)

    private func readSQLite(_ profile: OrcaProfile) throws -> OrcaSnapshot {
        let fm = FileManager.default
        let work = tempRoot.appendingPathComponent("agentbox-orca-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }

        let copy = work.appendingPathComponent("profile-state.db")
        try fm.copyItem(at: profile.stateDatabase, to: copy)
        for suffix in ["-wal", "-shm"] {
            let original = URL(fileURLWithPath: profile.stateDatabase.path + suffix)
            if fm.fileExists(atPath: original.path) {
                try fm.copyItem(at: original, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw OrcaReadError.sqlite(message)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT domain, payload, domain_version, content_hash FROM profile_state_documents"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw OrcaReadError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var domains: [String: Any] = [:]
        var notes: [String] = []
        var hasher = SHA256()
        var rows: [(String, String)] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw OrcaReadError.sqlite(String(cString: sqlite3_errmsg(db))) }
            guard let d = sqlite3_column_text(statement, 0), let p = sqlite3_column_text(statement, 1) else { continue }
            let domain = String(cString: d)
            guard Self.wantedDomains.contains(domain) else { continue }
            let version = Int(sqlite3_column_int64(statement, 2))
            let hash = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            rows.append((domain, hash))
            guard version == Self.supportedDomainVersion else {
                notes.append("Domain \(domain) skipped: unsupported domain_version \(version)")
                continue
            }
            let payload = String(cString: p)
            guard let value = try? JSONSerialization.jsonObject(with: Data(payload.utf8), options: [.fragmentsAllowed]) else {
                notes.append("Domain \(domain) skipped: payload is not valid JSON")
                continue
            }
            domains[domain] = value
        }
        for (domain, hash) in rows.sorted(by: { $0.0 < $1.0 }) { hasher.update(data: Data("\(domain)=\(hash);".utf8)) }
        var snapshot = Self.parse(domains: domains, profileID: profile.id, source: .sqlite)
        snapshot.notes = notes + snapshot.notes
        snapshot.fingerprint = Self.hex(hasher.finalize())
        return snapshot
    }

    // MARK: JSON legado

    private func readLegacyJSON(_ profile: OrcaProfile) throws -> OrcaSnapshot {
        let data = try Data(contentsOf: profile.legacyJSON)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OrcaReadError.invalidJSON(profile.legacyJSON.lastPathComponent)
        }
        var snapshot = Self.parse(domains: root, profileID: profile.id, source: .legacyJSON)
        snapshot.notes.insert("Read from legacy orca-data.json (may be outdated)", at: 0)
        snapshot.fingerprint = Self.hex(SHA256.hash(data: data))
        return snapshot
    }

    // MARK: Parse tolerante (campo desconhecido é ignorado)

    static func parse(domains: [String: Any], profileID: String, source: OrcaStateSource) -> OrcaSnapshot {
        var snapshot = OrcaSnapshot(profileID: profileID, source: source)
        func string(_ d: [String: Any], _ key: String) -> String? {
            guard let s = d[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        for item in (domains["repos"] as? [[String: Any]]) ?? [] {
            guard let id = string(item, "id"), let path = string(item, "path") else { continue }
            let name = string(item, "displayName") ?? URL(fileURLWithPath: path).lastPathComponent
            snapshot.repos.append(OrcaRepo(
                id: id, path: path, displayName: name, badgeColor: string(item, "badgeColor"),
                isFolder: (item["kind"] as? String) == "folder", gitUsername: string(item, "gitUsername")))
        }
        for item in (domains["folderWorkspaces"] as? [[String: Any]]) ?? [] {
            guard let path = string(item, "path") else { continue }
            let id = string(item, "id") ?? "folder:" + path
            let name = string(item, "displayName") ?? string(item, "name") ?? URL(fileURLWithPath: path).lastPathComponent
            snapshot.repos.append(OrcaRepo(id: id, path: path, displayName: name, badgeColor: string(item, "badgeColor"),
                                           isFolder: true, gitUsername: nil))
        }
        for (key, value) in ((domains["worktreeMeta"] as? [String: Any]) ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let meta = value as? [String: Any], let split = key.range(of: "::") else { continue }
            snapshot.worktreeMeta.append(OrcaWorktreeMeta(
                repoID: String(key[..<split.lowerBound]), path: String(key[split.upperBound...]),
                displayName: string(meta, "displayName"), comment: string(meta, "comment"),
                sortOrder: (meta["sortOrder"] as? NSNumber)?.int64Value,
                lastActivityAt: (meta["lastActivityAt"] as? NSNumber)?.int64Value))
        }
        if let session = domains["workspaceSession"] as? [String: Any], let tabs = session["tabsByWorktree"] as? [String: Any] {
            for (key, value) in tabs where !((value as? [Any])?.isEmpty ?? true) { snapshot.worktreesWithOpenTabs.insert(key) }
        }
        if let s = domains["settings"] as? [String: Any] {
            snapshot.settings.workspaceDir = string(s, "workspaceDir")
            snapshot.settings.branchPrefix = string(s, "branchPrefix")
            snapshot.settings.branchPrefixCustom = string(s, "branchPrefixCustom")
            snapshot.settings.defaultTuiAgent = string(s, "defaultTuiAgent")
            snapshot.settings.terminalDefaultShell = string(s, "terminalDefaultShell")
            snapshot.settings.setupScriptLaunchMode = string(s, "setupScriptLaunchMode")
            for (k, v) in (s["agentDefaultArgs"] as? [String: Any]) ?? [:] {
                if let text = v as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty { snapshot.settings.agentDefaultArgs[k] = text }
            }
            for (k, v) in (s["agentDefaultEnv"] as? [String: Any]) ?? [:] {
                if let env = v as? [String: Any] {
                    let strings = env.compactMapValues { $0 as? String }
                    if !strings.isEmpty { snapshot.settings.agentDefaultEnv[k] = strings }
                }
            }
            for (k, v) in (s["agentCmdOverrides"] as? [String: Any]) ?? [:] {
                if let text = v as? String, !text.isEmpty { snapshot.settings.agentCmdOverrides[k] = text }
            }
        }
        return snapshot
    }

    private static func hex(_ digest: some Sequence<UInt8>) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}
