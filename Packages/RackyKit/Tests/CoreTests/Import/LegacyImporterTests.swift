import RackyPlatform
import RackyProtocol
import RackyStore
import CryptoKit
import Foundation
import Testing

@testable import RackyCore

/// Keychain antigo falso: valores por UUID; ids ausentes devolvem `nil` (item apagado).
struct FakeLegacyKeychain: LegacySecretReading {
    var values: [UUID: String]
    func readLegacySecret(id: UUID) async throws -> String? { values[id] }
}

/// Origem fake no formato real dos JSONs antigos (Codable sintetizado do app antigo; datas em segundos desde 2001).
struct LegacyFixture {
    let base: URL
    let source: URL
    let repo: URL
    let plainDir: URL
    let t1 = UUID(), t2 = UUID(), t3 = UUID(), s1 = UUID(), s2 = UUID(), s3 = UUID()
    let run1 = UUID(), run2 = UUID(), run3 = UUID()
    let agent1 = UUID(), secA = UUID(), secB = UUID(), secC = UUID()

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("racky-legacy-\(UUID().uuidString)", isDirectory: true)
        source = base.appendingPathComponent("Racky", isDirectory: true)
        repo = base.appendingPathComponent("code/repo", isDirectory: true)
        plainDir = base.appendingPathComponent("scratch/one", isDirectory: true)
        for dir in [source, repo.appendingPathComponent(".git"), repo.appendingPathComponent("sub"), plainDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try write()
    }

    func remove() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        try? FileManager.default.removeItem(at: base)
    }

    private func terminal(_ id: UUID, cwd: String, provider: String = "claude", native: String? = nil) -> [String: Any] {
        var t: [String: Any] = ["id": id.uuidString, "title": "T-\(provider)", "provider": provider, "cwd": cwd,
                                "arguments": ["--model", "opus"], "createdAt": 800_000_000.5]
        if let native { t["nativeConversation"] = ["provider": provider, "nativeSessionID": native] }
        return t
    }

    private func write() throws {
        let workspace: [String: Any] = [
            "sessions": [
                ["id": s1.uuidString, "title": "Repo work", "createdAt": 800_000_000.0,
                 "terminals": [terminal(t1, cwd: repo.appendingPathComponent("sub").path, native: "aaaaaaaa-1111-2222-3333-444444444444"),
                               terminal(t2, cwd: repo.path, provider: "codex")]],
                ["id": s2.uuidString, "title": "Scratch", "createdAt": 800_000_100.0, "terminals": [terminal(t3, cwd: plainDir.path, provider: "shell")]],
                ["id": s3.uuidString, "title": "Empty", "createdAt": 800_000_200.0, "terminals": [], "futureField": 1],
            ],
            "layouts": [
                ["sessionID": s1.uuidString, "focusedTerminalID": t2.uuidString,
                 "root": ["split": ["id": UUID().uuidString, "axis": "horizontal", "fraction": 0.4,
                                    "first": ["terminal": ["_0": t1.uuidString]], "second": ["terminal": ["_0": t2.uuidString]]]]],
                ["sessionID": s2.uuidString, "root": ["terminal": ["_0": t3.uuidString]], "focusedTerminalID": t3.uuidString],
            ],
            "selectedSessionID": s1.uuidString, "sidebarWidth": 300, "sidebarCollapsed": false, "brandNewTopLevel": true,
        ]
        let runs: [String: Any] = ["schemaVersion": 1, "runs": [
            ["id": run1.uuidString, "kind": "terminal", "provider": "claude", "terminalID": t1.uuidString, "processID": 99, "startedAt": 800_000_001.0, "status": "running"],
            ["id": run2.uuidString, "kind": "nativeSubagent", "provider": "claude", "terminalID": t1.uuidString, "parentRunID": run1.uuidString,
             "nativeAgentType": "Explore", "startedAt": 800_000_002.0, "endedAt": 800_000_050.0, "status": "finished"],
            ["id": run3.uuidString, "kind": "terminal", "provider": "codex", "terminalID": UUID().uuidString, "startedAt": 800_000_003.0, "status": "finished", "mystery": 1],
        ]]
        let library: [String: Any] = [
            "schemaVersion": 1,
            "agents": [["id": agent1.uuidString, "name": "Reviewer", "summary": "reviews", "instructions": "INSTRUCTIONS-TEXT", "provider": "claude",
                        "skillIDs": [], "memoryIDs": [], "revision": 1, "archived": false, "createdAt": 1.0, "updatedAt": 2.0]],
            "memories": [["id": UUID().uuidString, "title": "Prefers tabs", "content": "MEMORY-TEXT", "scope": "preference", "scopeKey": "x"]],
            "skills": [["id": UUID().uuidString, "name": "s", "summary": "", "sourcePath": base.appendingPathComponent("home/.claude/skills/a/SKILL.md").path, "content": "c", "sha256": "h"],
                       ["id": UUID().uuidString, "name": "s2", "summary": "", "sourcePath": "/nonexistent/skill/SKILL.md", "content": "c", "sha256": "h"]],
            "history": [], "agentRevisions": [], "memoryRevisions": [],
        ]
        let secrets: [String: Any] = ["schemaVersion": 1, "references": [
            ["id": secA.uuidString, "name": "ZYTE_API_KEY", "sourceLabel": ".env", "createdAt": 1.0],
            ["id": secB.uuidString, "name": "GITHUB_TOKEN", "sourceLabel": "Manual", "createdAt": 1.0],
            ["id": secC.uuidString, "name": "GONE_FROM_KEYCHAIN", "sourceLabel": "Manual", "createdAt": 1.0],
        ], "grants": [["id": UUID().uuidString]]]
        try put("workspace.json", workspace); try put("AgentRuns.json", runs); try put("library.json", library)
        try put("secret-references.json", secrets)
        try put("docker-connection.json", ["schemaVersion": 1]); try put("computer-policy.json", ["schemaVersion": 1, "mode": "ask"])
        try put("ControlBroker.json", ["x": 1]); try put("human-requests.json", ["x": 1])
        try put("browser-computers.json", ["schemaVersion": 1, "computers": [["id": UUID().uuidString], ["id": UUID().uuidString]]])
        try FileManager.default.createDirectory(at: base.appendingPathComponent("home/.claude/skills/a"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: base.appendingPathComponent("home/.claude/skills/a/SKILL.md").path, contents: Data("x".utf8))
    }

    func put(_ name: String, _ object: Any) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: source.appendingPathComponent(name))
    }

    var home: URL { base.appendingPathComponent("home", isDirectory: true) }

    func fingerprint() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.map { url in
            let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            return "\(url.lastPathComponent)|\(m)|\(SHA256.hash(data: (try? Data(contentsOf: url)) ?? Data()))"
        }.sorted()
    }

    func openStore(_ name: String = "ab") async throws -> RackyStore {
        try await RackyStore.open(paths: StorePaths(root: base.appendingPathComponent(name, isDirectory: true)))
    }
}

@Suite struct LegacyImporterTests {
    private func importer(_ f: LegacyFixture, store: RackyStore, vault: SecretVault? = nil, confirm: @escaping @Sendable (String) async -> Bool = { _ in false },
                          keychain: FakeLegacyKeychain? = nil) -> LegacyJSONImporter {
        LegacyJSONImporter(store: store, vault: vault, sourceDirectory: f.source, home: f.home,
                           secretReader: keychain ?? FakeLegacyKeychain(values: [f.secA: "zyte-VALUE-1", f.secB: "gh-VALUE-2"]),
                           confirmSecretRead: confirm)
    }

    private func vault(_ store: RackyStore) -> SecretVault {
        SecretVault(store: store, keyring: VaultKeyring(backend: InMemoryMasterKeyBackend()))
    }

    @Test func dryRunReportsCountsWithoutWritingAnything() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        let store = try await f.openStore()
        let before = f.fingerprint()
        let report = try await importer(f, store: store).run(dryRun: true)

        #expect(report.dryRun && !report.alreadyImported && report.legacyCopyPath == nil)
        #expect(report.count("sessions.new") == 3 && report.count("tabs.new") == 2 && report.count("terminals.new") == 3)
        #expect(report.count("projects.new") == 1, "sessão no repo git vira projeto; a de pasta solta fica clean")
        #expect(report.count("agentRuns.new") == 3)
        #expect(report.count("profiles.new") == 1 && report.count("memories.exported") == 1)
        #expect(report.count("skills.inCatalogRoots") == 1 && report.count("skills.missing") == 1)
        #expect(report.count("settings.new") == 2)
        #expect(report.count("secrets.candidates") == 3 && report.count("secrets.new") == 0 && report.count("secrets.grantsDropped") == 1)
        #expect(report.count("computers.deferred") == 2)
        #expect(report.count("unknownFields") >= 3, "campos desconhecidos são contados: \(report.counts)")
        #expect(report.files.filter { $0.outcome == .ignored }.map(\.name).sorted() == ["ControlBroker.json", "human-requests.json"])

        // Nada gravado: nem linhas, nem cópia, nem origem alterada.
        let snapshot = try await store.snapshot()
        #expect(snapshot.sessions.isEmpty && snapshot.projects.isEmpty && snapshot.terminals.isEmpty && snapshot.profiles.isEmpty)
        let leftoverSecrets = try await store.secrets()
        let leftoverSetting = try await store.settingJSON("legacy.docker_connection")
        #expect(leftoverSecrets.isEmpty && leftoverSetting == nil)
        #expect(!FileManager.default.fileExists(atPath: store.paths.root.appendingPathComponent("legacy-import-x").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.paths.root.path).allSatisfy { !$0.hasPrefix("legacy-import-") })
        #expect(f.fingerprint() == before)
        let runs = try await store.importRuns()
        #expect(runs.count == 1 && runs[0].dryRun && runs[0].status == "dry_run")
        #expect(!runs[0].summaryJSON.contains("ZYTE") && !runs[0].summaryJSON.contains("GITHUB"), "o resumo guarda só contagens")
        try await store.close()
    }

    @Test func realImportMapsEverythingAndCopiesSourcesFirst() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        let store = try await f.openStore()
        let before = f.fingerprint()
        let report = try await importer(f, store: store).run(dryRun: false)
        #expect(!report.dryRun && report.count("sessions.new") == 3)

        let snapshot = try await store.snapshot()
        #expect(snapshot.sessions.count == 3 && snapshot.tabs.count == 2 && snapshot.terminals.count == 3 && snapshot.projects.count == 1)
        let repoSession = try #require(snapshot.sessions.first { $0.id == f.s1 })
        let project = try #require(snapshot.projects.first)
        #expect(repoSession.kind == .folder && repoSession.projectID == project.id && project.rootPath == f.repo.path && project.kind == .git)
        #expect(repoSession.folderPath == f.repo.appendingPathComponent("sub").path && repoSession.title == "Repo work")
        let clean = try #require(snapshot.sessions.first { $0.id == f.s2 })
        #expect(clean.kind == .clean && clean.projectID == nil && clean.folderPath == f.plainDir.path)
        #expect(snapshot.sessions.first { $0.id == f.s3 }?.kind == .clean)
        #expect(!snapshot.tabs.contains { $0.sessionID == f.s3 }, "sessão sem terminais não ganha tab")

        let tab = try #require(snapshot.tabs.first { $0.sessionID == f.s1 })
        guard case .split(_, let ratio, _, _) = tab.layout else { Issue.record("layout should be a split"); return }
        #expect(ratio == 0.4 && Set(tab.layout.terminalIDs) == [f.t1, f.t2] && tab.focusedTerminalID == f.t2 && tab.layout.isValid)

        let t1 = try #require(snapshot.terminals.first { $0.id == f.t1 })
        #expect(t1.state == .interrupted && t1.provider == .claude && t1.launchSpec.extraArgs == ["--model", "opus"])
        #expect(t1.nativeConversationID == "aaaaaaaa-1111-2222-3333-444444444444" && t1.launchSpec.resumeOf == t1.nativeConversationID, "[Resume] possível")
        #expect(snapshot.terminals.first { $0.id == f.t2 }?.provider == .codex)

        // Agent runs: running vira `unknown`; filho aponta para o pai; terminal inexistente não quebra.
        let r1 = try #require(try await store.agentRun(id: f.run1))
        #expect(r1.activity == .unknown && r1.endedAt == nil && r1.kind == .main)
        let r2 = try #require(try await store.agentRun(id: f.run2))
        #expect(r2.parentRunID == f.run1 && r2.rootRunID == f.run1 && r2.activity == .done && r2.kind == .nativeSubagent && r2.agentType == "Explore")
        #expect(try await store.agentRun(id: f.run3)?.terminalID == nil)

        #expect(snapshot.profiles.map(\.name) == ["Reviewer"])
        let dockerSetting = try await store.settingJSON("legacy.docker_connection")
        let policySetting = try await store.settingJSON("legacy.computer_policy")
        #expect(dockerSetting != nil && policySetting?.contains("ask") == true)

        // Cópia dos JSONs + exportações; a origem não mudou.
        let copy = URL(fileURLWithPath: try #require(report.legacyCopyPath))
        let copied = try FileManager.default.contentsOfDirectory(atPath: copy.path)
        #expect(copied.contains("workspace.json") && copied.contains("ControlBroker.json") && copied.contains("memories.md") && copied.contains("saved-agents.md"))
        #expect(try String(contentsOf: copy.appendingPathComponent("memories.md"), encoding: .utf8).contains("MEMORY-TEXT"))
        #expect(try String(contentsOf: copy.appendingPathComponent("saved-agents.md"), encoding: .utf8).contains("INSTRUCTIONS-TEXT"))
        #expect(((try FileManager.default.attributesOfItem(atPath: copy.path))[.posixPermissions] as? Int) == 0o700)
        #expect(f.fingerprint() == before)
        try await store.close()
    }

    @Test func sourceDirectoryIsNeverWrittenEvenWhenReadOnly() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        let store = try await f.openStore()
        for name in try FileManager.default.contentsOfDirectory(atPath: f.source.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: f.source.appendingPathComponent(name).path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: f.source.path)
        let before = f.fingerprint()
        _ = try await importer(f, store: store).run(dryRun: false)
        #expect(f.fingerprint() == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.source.path).count == before.count, "nenhum arquivo novo na origem")
        try await store.close()
    }

    @Test func realImportIsIdempotentByFingerprintAndByRow() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        let store = try await f.openStore()
        let v = vault(store)
        let imp = importer(f, store: store, vault: v, confirm: { _ in true },
                           keychain: FakeLegacyKeychain(values: [f.secA: "a", f.secB: "b", f.secC: "c"]))
        let first = try await imp.run(dryRun: false)
        #expect(first.count("secrets.new") == 3)

        let again = try await imp.run(dryRun: false)
        #expect(again.alreadyImported && again.counts.isEmpty, "mesma origem: nada é regravado")
        let snap = try await store.snapshot()
        #expect(snap.sessions.count == 3 && snap.terminals.count == 3 && snap.projects.count == 1 && snap.profiles.count == 1)
        #expect(try await store.secrets().count == 3)
        let copies = try FileManager.default.contentsOfDirectory(atPath: store.paths.root.path).filter { $0.hasPrefix("legacy-import-") }
        #expect(copies.count == 1, "a repetição não cria nova cópia")

        // Origem mudou (fingerprint novo): idempotência por linha, sem duplicar nada.
        try f.put("docker-connection.json", ["schemaVersion": 2])
        let third = try await imp.run(dryRun: false)
        #expect(!third.alreadyImported)
        #expect(third.count("sessions.new") == 0 && third.count("sessions.alreadyPresent") == 3)
        #expect(third.count("agentRuns.new") == 0 && third.count("agentRuns.alreadyPresent") == 3)
        #expect(third.count("profiles.alreadyPresent") == 1 && third.count("secrets.alreadyPresent") == 3 && third.count("settings.alreadyPresent") == 2)
        let after = try await store.snapshot()
        #expect(after.sessions.count == 3 && after.terminals.count == 3 && after.tabs.count == 2)
        try await store.close()
    }

    @Test func secretsAreReadFromTheOldKeychainOnlyPerConfirmationAndNeverLeak() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        let store = try await f.openStore()
        let v = vault(store)
        let asked = AskedNames()
        let imp = importer(f, store: store, vault: v, confirm: { name in await asked.add(name); return name != "GITHUB_TOKEN" })
        let report = try await imp.run(dryRun: false)

        #expect(await asked.names.sorted() == ["GITHUB_TOKEN", "GONE_FROM_KEYCHAIN", "ZYTE_API_KEY"], "uma pergunta por segredo")
        #expect(report.count("secrets.new") == 1, "só o confirmado e legível")
        #expect(report.count("secrets.skipped.unconfirmed") == 1, "recusado: nunca lido")
        #expect(report.count("secrets.skipped.unreadable") == 1, "confirmado mas ausente do Keychain antigo")
        let imported = try #require(try await store.secret(named: "ZYTE_API_KEY"))
        #expect(try await v.reveal(id: imported.id).text == "zyte-VALUE-1")
        #expect(imported.importedFrom == "racky:secret-references.json" && imported.defaultEnvName == "ZYTE_API_KEY")
        #expect(try await store.secret(named: "GITHUB_TOKEN") == nil)

        // Há pendências: a mesma origem pode ser reexecutada depois (agora confirmando).
        #expect(try await store.importRuns().last?.status == "completed_pending_secrets")
        let retry = importer(f, store: store, vault: v, confirm: { _ in true })
        let second = try await retry.run(dryRun: false)
        #expect(!second.alreadyImported && second.count("secrets.new") == 1 && second.count("secrets.alreadyPresent") == 1 && second.count("secrets.skipped.unreadable") == 1)
        #expect(second.count("sessions.alreadyPresent") == 3)

        // Nenhum valor em relatório nem em resumo gravado.
        let dump = String(decoding: try JSONEncoder().encode(report), as: UTF8.self) + (try await store.importRuns().map(\.summaryJSON).joined())
        #expect(!dump.contains("VALUE") && !dump.contains("ZYTE_API_KEY") && !dump.contains("GITHUB_TOKEN"))
        try await store.close()
    }

    @Test func withoutAVaultOrReaderNoSecretIsImported() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        let store = try await f.openStore()
        let report = try await LegacyJSONImporter(store: store, sourceDirectory: f.source, home: f.home).run(dryRun: false)
        #expect(report.count("secrets.skipped.noVault") == 3 && report.count("secrets.new") == 0)
        #expect(try await store.secrets().isEmpty)
        try await store.close()
    }

    @Test func tolerantParseMarksCorruptFilesUnreadableAndKeepsGoing() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        try Data("{not json".utf8).write(to: f.source.appendingPathComponent("library.json"))
        try Data("[]".utf8).write(to: f.source.appendingPathComponent("AgentRuns.json"))
        let store = try await f.openStore()
        let report = try await importer(f, store: store).run(dryRun: true)
        #expect(report.files.first { $0.name == "library.json" }?.outcome == .unreadable)
        #expect(report.files.first { $0.name == "AgentRuns.json" }?.outcome == .unreadable)
        #expect(report.count("sessions.new") == 3, "o resto continua")
        try await store.close()
    }

    @Test func emptyOrMissingSourceYieldsAnEmptyReport() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        let empty = f.base.appendingPathComponent("nothing", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let store = try await f.openStore()
        let report = try await LegacyJSONImporter(store: store, sourceDirectory: empty, home: f.home).run(dryRun: false)
        #expect(report.counts.isEmpty && report.files.allSatisfy { $0.outcome == .absent } && report.legacyCopyPath == nil)
        try await store.close()
    }

    @Test func invalidLayoutFallsBackToASinglePane() async throws {
        let f = try LegacyFixture(); defer { f.remove() }
        try f.put("workspace.json", ["sessions": [["id": f.s1.uuidString, "title": "x", "createdAt": 1.0,
                                                    "terminals": [["id": f.t1.uuidString, "title": "t", "provider": "weird", "cwd": f.plainDir.path, "arguments": [], "createdAt": 1.0]]]],
                                     "layouts": [["sessionID": f.s1.uuidString, "root": ["terminal": ["_0": UUID().uuidString]]]]])
        let store = try await f.openStore()
        _ = try await importer(f, store: store).run(dryRun: false)
        let snap = try await store.snapshot()
        #expect(snap.tabs.first?.layout.terminalIDs == [f.t1], "layout apontando para terminal inexistente vira um pane")
        #expect(snap.terminals.first?.provider == .custom, "provider desconhecido vira custom")
        try await store.close()
    }
}

actor AskedNames {
    private(set) var names: [String] = []
    func add(_ n: String) { names.append(n) }
}
