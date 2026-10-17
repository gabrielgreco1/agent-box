import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxStore
import CryptoKit
import Foundation
import Security

// Importador dos JSONs do Agent Box antigo (08 AR-340/341). Regras comuns: dry-run mostra contagens e conflitos antes
// de gravar; idempotente (`source_fingerprint` + ids legados reaproveitados); lê CÓPIAS (`legacy-import-<ts>/`); nunca
// escreve na origem; registra `import_run`; campo desconhecido é ignorado e contado.

public struct LegacyImportReport: Codable, Sendable, Equatable {
    public struct FileReport: Codable, Sendable, Equatable {
        public enum Outcome: String, Codable, Sendable { case imported, ignored, absent, unreadable }
        public var name: String
        public var outcome: Outcome
    }
    public var dryRun: Bool
    public var sourcePath: String
    public var fingerprint: String
    /// A mesma origem (mesmo fingerprint) já foi importada por completo: nada foi regravado.
    public var alreadyImported: Bool
    public var files: [FileReport]
    /// Só contagens (chaves estáveis, ex.: `sessions.new`, `secrets.alreadyPresent`). Nunca nomes nem valores.
    public var counts: [String: Int]
    public var legacyCopyPath: String?

    public func count(_ key: String) -> Int { counts[key] ?? 0 }
}

/// Leitura dos valores do Keychain antigo (`com.agentbox.secret.v1`), um segredo por vez.
public protocol LegacySecretReading: Sendable {
    func readLegacySecret(id: UUID) async throws -> String?
}

public struct LegacyImporterConfig: Sendable {
    public var knownFiles = ["workspace.json", "library.json", "AgentRuns.json", "computer-policy.json", "docker-connection.json",
                             "secret-references.json", "secrets.json", "browser-computers.json"]
    public var ignoredFiles = ["ControlBroker.json", "human-requests.json", "agent-launch-bindings.json",
                               "scraping-box-assignments.json", "directory-bookmarks.json", "image-update.json"]
    public init() {}
}

public struct LegacyJSONImporter: Sendable {
    private let store: AgentBoxStore
    private let vault: SecretVault?
    private let sourceDirectory: URL
    private let home: URL
    private let clock: @Sendable () -> Date
    private let secretReader: (any LegacySecretReading)?
    private let confirmSecretRead: @Sendable (_ secretName: String) async -> Bool
    private let config = LegacyImporterConfig()

    /// `confirmSecretRead` decide, por segredo, se o Keychain antigo pode ser lido (cada leitura pode pedir senha).
    /// Sem leitor ou sem confirmação, o segredo é pulado e contado: nunca importamos valores sem consentimento.
    public init(store: AgentBoxStore, vault: SecretVault? = nil, sourceDirectory: URL,
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                secretReader: (any LegacySecretReading)? = nil,
                confirmSecretRead: @escaping @Sendable (String) async -> Bool = { _ in false },
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store; self.vault = vault; self.sourceDirectory = sourceDirectory; self.home = home
        self.secretReader = secretReader; self.confirmSecretRead = confirmSecretRead; self.clock = clock
    }

    private struct SourceFile { var name: String; var data: Data }

    // MARK: Execução

    public func run(dryRun: Bool) async throws -> LegacyImportReport {
        let started = clock()
        let dir = sourceDirectory
        let known = config.knownFiles, ignored = config.ignoredFiles
        // Leitura da origem: somente `read`, em bloco bloqueante.
        let sources = await BlockingIOBridge.run { Self.readSources(dir, names: known + ignored) }
        let fingerprint = Self.fingerprint(sources)
        var counts: [String: Int] = [:]
        var files: [LegacyImportReport.FileReport] = []

        if !dryRun, let prior = try await completedRun(fingerprint: fingerprint) {
            _ = prior
            return LegacyImportReport(dryRun: false, sourcePath: dir.path, fingerprint: fingerprint, alreadyImported: true,
                                      files: sources.map { .init(name: $0.name, outcome: ignored.contains($0.name) ? .ignored : .imported) },
                                      counts: [:], legacyCopyPath: nil)
        }

        // Real: copia primeiro e interpreta as CÓPIAS (a origem nunca é reaberta para escrita).
        var copyDir: URL?
        var parsedSources = sources
        if !dryRun, !sources.isEmpty {
            let target = store.paths.root.appendingPathComponent("legacy-import-\(Self.stamp(started))", isDirectory: true)
            let copied = await BlockingIOBridge.run { Self.copy(sources, to: target) }
            copyDir = target
            parsedSources = copied
        }
        func data(_ name: String) -> Data? { parsedSources.first { $0.name == name }?.data }

        for name in known + ignored {
            let present = parsedSources.contains { $0.name == name }
            files.append(.init(name: name, outcome: !present ? .absent : ignored.contains(name) ? .ignored : .imported))
        }
        func markUnreadable(_ name: String) {
            if let i = files.firstIndex(where: { $0.name == name }) { files[i].outcome = .unreadable }
        }

        var memoriesMarkdown = "", agentsMarkdown = ""
        if let d = data("workspace.json") {
            if let obj = Self.object(d) { try await importWorkspace(obj, dryRun: dryRun, counts: &counts, at: started) } else { markUnreadable("workspace.json") }
        }
        if let d = data("AgentRuns.json") {
            if let obj = Self.object(d) { try await importRuns(obj, dryRun: dryRun, counts: &counts) } else { markUnreadable("AgentRuns.json") }
        }
        for (file, key) in [("docker-connection.json", "legacy.docker_connection"), ("computer-policy.json", "legacy.computer_policy")] {
            guard let d = data(file) else { continue }
            if Self.object(d) == nil { markUnreadable(file); continue }
            let json = String(decoding: d, as: UTF8.self)
            let isNew = try await store.settingJSON(key) == nil
            if isNew { counts["settings.new", default: 0] += 1 } else { counts["settings.alreadyPresent", default: 0] += 1 }
            if isNew && !dryRun { _ = try await store.setSettingIfAbsent(key: key, json: json, at: started) }
        }
        if let d = data("library.json") {
            if let obj = Self.object(d) {
                (agentsMarkdown, memoriesMarkdown) = try await importLibrary(obj, dryRun: dryRun, counts: &counts, at: started)
            } else { markUnreadable("library.json") }
        }
        if let d = data("browser-computers.json") {
            // Computadores antigos viram `computer` órfãos só na Fatia 3 (T3-01); aqui só contamos.
            if let obj = Self.object(d) ?? Self.array(d).map({ ["items": $0] }) {
                counts["computers.deferred"] = Self.firstArrayCount(obj)
            } else { markUnreadable("browser-computers.json") }
        }
        for file in ["secret-references.json", "secrets.json"] {
            guard let d = data(file) else { continue }
            if let obj = Self.object(d) { try await importSecrets(obj, dryRun: dryRun, counts: &counts) } else { markUnreadable(file) }
        }

        if !dryRun, let copyDir {
            let memories = memoriesMarkdown, agents = agentsMarkdown
            await BlockingIOBridge.run {
                Self.writeExport(memories, name: "memories.md", in: copyDir)
                Self.writeExport(agents, name: "saved-agents.md", in: copyDir)
            }
        }

        let report = LegacyImportReport(dryRun: dryRun, sourcePath: dir.path, fingerprint: fingerprint, alreadyImported: false,
                                        files: files, counts: counts, legacyCopyPath: copyDir?.path)
        let summary = String(decoding: try JSONEncoder().encode(report.counts), as: UTF8.self)
        // `pending` > 0: há segredos sem consentimento ou ilegíveis; uma nova execução ainda tem trabalho.
        let pending = report.count("secrets.skipped.unconfirmed") + report.count("secrets.skipped.unreadable") + report.count("secrets.skipped.noVault")
        let status = dryRun ? "dry_run" : (pending > 0 ? "completed_pending_secrets" : "completed")
        try await store.recordImportRun(ImportRunRow(
            source: "agentbox_json", sourcePath: dir.path, fingerprint: fingerprint, dryRun: dryRun, status: status,
            summaryJSON: summary, startedAt: started, finishedAt: clock()))
        return report
    }

    private func completedRun(fingerprint: String) async throws -> ImportRunRow? {
        try await store.importRuns(source: "agentbox_json").first { $0.fingerprint == fingerprint && !$0.dryRun && $0.status == "completed" }
    }

    // MARK: workspace.json

    private static let workspaceKeys: Set<String> = ["sessions", "layouts", "selectedSessionID", "sidebarWidth", "sidebarCollapsed"]
    private static let sessionKeys: Set<String> = ["id", "title", "terminals", "createdAt"]
    private static let terminalKeys: Set<String> = ["id", "title", "provider", "cwd", "arguments", "createdAt", "agentDefinitionID", "nativeConversation"]
    private static let layoutKeys: Set<String> = ["sessionID", "root", "focusedTerminalID"]

    private func importWorkspace(_ root: [String: Any], dryRun: Bool, counts: inout [String: Int], at now: Date) async throws {
        counts["unknownFields", default: 0] += Set(root.keys).subtracting(Self.workspaceKeys).count
        let sessions = root["sessions"] as? [[String: Any]] ?? []
        let layouts = (root["layouts"] as? [[String: Any]] ?? []).reduce(into: [String: [String: Any]]()) { acc, l in
            if let id = (l["sessionID"] as? String)?.lowercased() { acc[id] = l }
            counts["unknownFields", default: 0] += Set(l.keys).subtracting(Self.layoutKeys).count
        }
        var existingProjects = Dictionary(try await store.projects(includeArchived: true).map { ($0.rootPath, $0) }, uniquingKeysWith: { a, _ in a })
        for (index, s) in sessions.enumerated() {
            counts["unknownFields", default: 0] += Set(s.keys).subtracting(Self.sessionKeys).count
            guard let idString = s["id"] as? String, let sessionID = UUID(uuidString: idString) else { counts["sessions.invalid", default: 0] += 1; continue }
            if try await store.session(id: sessionID) != nil { counts["sessions.alreadyPresent", default: 0] += 1; continue }
            let rawTerminals = s["terminals"] as? [[String: Any]] ?? []
            let cwd = rawTerminals.compactMap { $0["cwd"] as? String }.first(where: { !$0.isEmpty }) ?? home.path
            let created = Self.date(s["createdAt"]) ?? now

            var projectID: UUID?
            if let gitRoot = Self.gitRoot(of: cwd) {
                if let p = existingProjects[gitRoot] { projectID = p.id }
                else {
                    let p = Project(name: URL(fileURLWithPath: gitRoot).lastPathComponent, kind: .git, rootPath: gitRoot,
                                    source: .manual, importSourceID: "agentbox_json", sortIndex: existingProjects.count, createdAt: now)
                    existingProjects[gitRoot] = p
                    projectID = p.id
                    counts["projects.new", default: 0] += 1
                    if !dryRun { try await store.save(p) }
                }
            }
            let session = Session(
                id: sessionID, kind: projectID == nil ? .clean : .folder, projectID: projectID, folderPath: cwd,
                title: (s["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Imported session",
                sortIndex: index, createdAt: created)

            var tab: Tab?
            var terminals: [Terminal] = []
            let tabID = UUID.v7()
            for t in rawTerminals {
                counts["unknownFields", default: 0] += Set(t.keys).subtracting(Self.terminalKeys).count
                guard let tid = (t["id"] as? String).flatMap(UUID.init(uuidString:)) else { counts["terminals.invalid", default: 0] += 1; continue }
                let provider = TerminalProvider(rawValue: (t["provider"] as? String) ?? "") ?? .custom
                var spec = LaunchSpec(provider: provider, extraArgs: (t["arguments"] as? [String]) ?? [])
                var native: String?
                if let conv = t["nativeConversation"] as? [String: Any], let id = conv["nativeSessionID"] as? String, !id.isEmpty {
                    native = id; spec.resumeOf = id
                }
                terminals.append(Terminal(
                    id: tid, tabID: tabID, provider: provider, title: (t["title"] as? String) ?? "Terminal",
                    cwd: (t["cwd"] as? String) ?? cwd, launchSpec: spec, nativeConversationID: native,
                    state: .interrupted, createdAt: Self.date(t["createdAt"]) ?? created))
            }
            if !terminals.isEmpty {
                let ids = Set(terminals.map(\.id))
                let layoutJSON = layouts[idString.lowercased()]
                var layout = (layoutJSON?["root"]).flatMap { Self.layout(from: $0, valid: ids) }
                if layout?.isValid != true { layout = PaneLayout.leaf(Pane(content: .terminal(terminals[0].id))) }
                let focused = (layoutJSON?["focusedTerminalID"] as? String).flatMap(UUID.init(uuidString:))
                    .flatMap { ids.contains($0) ? $0 : nil } ?? layout?.terminalIDs.first
                tab = Tab(id: tabID, sessionID: sessionID, title: session.title, layout: layout!, focusedTerminalID: focused, createdAt: created)
            }
            counts["sessions.new", default: 0] += 1
            counts["tabs.new", default: 0] += tab == nil ? 0 : 1
            counts["terminals.new", default: 0] += terminals.count
            if !dryRun { try await store.saveBundle(session: session, tabs: tab.map { [$0] } ?? [], terminals: terminals) }
        }
    }

    /// `WorkspaceNode` antigo (Codable sintetizado): `{"terminal":{"_0":"<uuid>"}}` ou `{"split":{axis,fraction,first,second}}`.
    static func layout(from node: Any, valid: Set<UUID>) -> PaneLayout? {
        guard let dict = node as? [String: Any] else { return nil }
        if let t = dict["terminal"] {
            let raw = (t as? [String: Any])?["_0"] ?? t
            guard let id = (raw as? String).flatMap(UUID.init(uuidString:)), valid.contains(id) else { return nil }
            return .leaf(Pane(content: .terminal(id)))
        }
        if let s = dict["split"] as? [String: Any] {
            let first = s["first"].flatMap { layout(from: $0, valid: valid) }
            let second = s["second"].flatMap { layout(from: $0, valid: valid) }
            switch (first, second) {
            case (let a?, let b?):
                let axis = SplitAxis(rawValue: (s["axis"] as? String) ?? "") ?? .horizontal
                let ratio = min(max((s["fraction"] as? Double) ?? 0.5, PaneLayout.minRatio), PaneLayout.maxRatio)
                return .split(axis: axis, ratio: ratio, first: a, second: b)
            case (let a?, nil): return a
            case (nil, let b?): return b
            default: return nil
            }
        }
        return nil
    }

    static func gitRoot(of path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        for _ in 0..<40 {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.path }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return nil
    }

    // MARK: AgentRuns.json

    private static let runKeys: Set<String> = ["id", "kind", "provider", "terminalID", "parentRunID", "parentTerminalID", "processID",
                                               "nativeSessionID", "nativeAgentID", "nativeAgentType", "nativeHookSource", "startedAt", "endedAt", "status"]

    private func importRuns(_ root: [String: Any], dryRun: Bool, counts: inout [String: Int]) async throws {
        counts["unknownFields", default: 0] += Set(root.keys).subtracting(["schemaVersion", "runs"]).count
        let raw = root["runs"] as? [[String: Any]] ?? []
        let ids = Set(raw.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) })
        // Pais primeiro (FK); depois por início.
        let ordered = raw.sorted {
            let a = ($0["parentRunID"] as? String) == nil ? 0 : 1, b = ($1["parentRunID"] as? String) == nil ? 0 : 1
            return a != b ? a < b : (Self.date($0["startedAt"]) ?? .distantPast) < (Self.date($1["startedAt"]) ?? .distantPast)
        }
        var roots: [UUID: UUID] = [:]
        for r in ordered {
            counts["unknownFields", default: 0] += Set(r.keys).subtracting(Self.runKeys).count
            guard let id = (r["id"] as? String).flatMap(UUID.init(uuidString:)) else { counts["agentRuns.invalid", default: 0] += 1; continue }
            if let existing = try await store.agentRun(id: id) { counts["agentRuns.alreadyPresent", default: 0] += 1; roots[id] = existing.rootRunID; continue }
            let parent = (r["parentRunID"] as? String).flatMap(UUID.init(uuidString:)).flatMap { ids.contains($0) && roots[$0] != nil ? $0 : nil }
            let provider = TerminalProvider(rawValue: (r["provider"] as? String) ?? "") ?? .custom
            let finished = (r["status"] as? String) == "finished"
            let started = Self.date(r["startedAt"]) ?? Date(timeIntervalSince1970: 0)
            let run = AgentRun(
                id: id, terminalID: (r["terminalID"] as? String).flatMap(UUID.init(uuidString:)), parentRunID: parent,
                rootRunID: parent.flatMap { roots[$0] } ?? id, kind: (r["kind"] as? String) == "nativeSubagent" ? .nativeSubagent : .main,
                harness: provider, agentType: r["nativeAgentType"] as? String, providerSessionID: r["nativeSessionID"] as? String,
                providerAgentID: r["nativeAgentID"] as? String, activity: finished ? .done : .unknown,
                statusReason: "Imported from the previous Agent Box", startedAt: started,
                endedAt: finished ? (Self.date(r["endedAt"]) ?? started) : nil)
            counts["agentRuns.new", default: 0] += 1
            roots[id] = run.rootRunID
            if !dryRun { try await store.saveActivity(ActivityProjection(runs: [run], guardRunID: id)) }
        }
    }

    // MARK: library.json

    private func importLibrary(_ root: [String: Any], dryRun: Bool, counts: inout [String: Int], at now: Date) async throws -> (agents: String, memories: String) {
        let allowed: Set<String> = ["schemaVersion", "agents", "memories", "skills", "history", "agentRevisions", "memoryRevisions"]
        counts["unknownFields", default: 0] += Set(root.keys).subtracting(allowed).count
        var agentsMD = "# Saved agents from the previous Agent Box\n\n"
        for a in root["agents"] as? [[String: Any]] ?? [] {
            guard let id = (a["id"] as? String).flatMap(UUID.init(uuidString:)), let name = a["name"] as? String else { counts["profiles.invalid", default: 0] += 1; continue }
            agentsMD += "## \(name)\n\n\((a["summary"] as? String) ?? "")\n\n```\n\((a["instructions"] as? String) ?? "")\n```\n\n"
            if try await store.profiles().contains(where: { $0.id == id }) { counts["profiles.alreadyPresent", default: 0] += 1; continue }
            let provider = TerminalProvider(rawValue: (a["provider"] as? String) ?? "") ?? .claude
            counts["profiles.new", default: 0] += 1
            if !dryRun { try await store.save(LaunchProfile(id: id, name: name, provider: provider, source: .manual, createdAt: now, updatedAt: now)) }
        }
        var memoriesMD = "# Memories from the previous Agent Box\n\n"
        for m in root["memories"] as? [[String: Any]] ?? [] {
            counts["memories.exported", default: 0] += 1
            memoriesMD += "## \((m["title"] as? String) ?? "Untitled")\n\n_scope: \((m["scope"] as? String) ?? "?")_\n\n\((m["content"] as? String) ?? "")\n\n"
        }
        let skillRoots = [".claude/skills", ".agents/skills", ".codex/skills"].map { home.appendingPathComponent($0).path + "/" }
        for s in root["skills"] as? [[String: Any]] ?? [] {
            guard let path = s["sourcePath"] as? String else { counts["skills.invalid", default: 0] += 1; continue }
            if !FileManager.default.fileExists(atPath: path) { counts["skills.missing", default: 0] += 1 }
            else if skillRoots.contains(where: { path.hasPrefix($0) }) { counts["skills.inCatalogRoots", default: 0] += 1 }
            else { counts["skills.outsideCatalogRoots", default: 0] += 1 }
        }
        return (agentsMD, memoriesMD)
    }

    // MARK: secret-references.json

    private func importSecrets(_ root: [String: Any], dryRun: Bool, counts: inout [String: Int]) async throws {
        counts["unknownFields", default: 0] += Set(root.keys).subtracting(["schemaVersion", "references", "grants"]).count
        // `grants` (concessões por destino) foram descartadas no rebuild (08 §2); só contamos.
        counts["secrets.grantsDropped"] = (root["grants"] as? [Any])?.count ?? 0
        for ref in root["references"] as? [[String: Any]] ?? [] {
            guard let id = (ref["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let name = ref["name"] as? String, !name.isEmpty else { counts["secrets.invalid", default: 0] += 1; continue }
            if try await store.secret(named: name) != nil { counts["secrets.alreadyPresent", default: 0] += 1; continue }
            if dryRun { counts["secrets.candidates", default: 0] += 1; continue }
            guard let vault, let secretReader else { counts["secrets.skipped.noVault", default: 0] += 1; continue }
            guard await confirmSecretRead(name) else { counts["secrets.skipped.unconfirmed", default: 0] += 1; continue }
            guard let value = try? await secretReader.readLegacySecret(id: id) else { counts["secrets.skipped.unreadable", default: 0] += 1; continue }
            let env = SecretVault.isValidEnvName(name) ? name : nil
            do {
                try await vault.create(NewSecret(name: name, value: value, defaultEnvName: env, importedFrom: "agentbox:secret-references.json"))
                counts["secrets.new", default: 0] += 1
            } catch SecretError.duplicateName {
                counts["secrets.alreadyPresent", default: 0] += 1
            }
        }
    }

    // MARK: E/S da origem (blocos bloqueantes)

    private static func readSources(_ dir: URL, names: [String]) -> [SourceFile] {
        var out: [SourceFile] = []
        for name in names {
            let url = dir.appendingPathComponent(name)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  (attrs[.size] as? Int ?? 0) <= 64 * 1024 * 1024,
                  let data = try? Data(contentsOf: url) else { continue }
            out.append(SourceFile(name: name, data: data))
        }
        return out
    }

    private static func fingerprint(_ sources: [SourceFile]) -> String {
        var hasher = SHA256()
        for s in sources.sorted(by: { $0.name < $1.name }) {
            hasher.update(data: Data("\(s.name):\(SHA256.hash(data: s.data).map { String(format: "%02x", $0) }.joined())\n".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Copia para `legacy-import-<ts>/` (0700/0600) e devolve o conteúdo lido DAS CÓPIAS.
    private static func copy(_ sources: [SourceFile], to dir: URL) -> [SourceFile] {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var out: [SourceFile] = []
        for s in sources {
            let url = dir.appendingPathComponent(s.name)
            guard fm.createFile(atPath: url.path, contents: s.data, attributes: [.posixPermissions: 0o600]),
                  let back = try? Data(contentsOf: url) else { continue }
            out.append(SourceFile(name: s.name, data: back))
        }
        return out
    }

    private static func writeExport(_ text: String, name: String, in dir: URL) {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    private static func object(_ data: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
    private static func array(_ data: Data) -> [Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [Any] }
    private static func firstArrayCount(_ obj: [String: Any]) -> Int { obj.values.compactMap { ($0 as? [Any])?.count }.max() ?? 0 }

    /// JSONEncoder padrão do app antigo: segundos desde 2001-01-01. Valores > 1,5e9 são tratados como epoch Unix.
    private static func date(_ any: Any?) -> Date? {
        guard let v = (any as? Double) ?? (any as? Int).map(Double.init) else { return nil }
        return v > 1.5e9 ? Date(timeIntervalSince1970: v) : Date(timeIntervalSinceReferenceDate: v)
    }
}

/// Leitor do Keychain antigo (`com.agentbox.secret.v1`, conta = UUID da referência). Só o importador o usa, e só depois
/// da confirmação do usuário por segredo.
public struct SystemLegacySecretReader: LegacySecretReading {
    public init() {}
    public func readLegacySecret(id: UUID) async throws -> String? {
        await BlockingIOBridge.run {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.agentbox.secret.v1",
                kSecAttrAccount as String: id.uuidString, kSecReturnData as String: kCFBooleanTrue as Any,
                kSecMatchLimit as String: kSecMatchLimitOne]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
