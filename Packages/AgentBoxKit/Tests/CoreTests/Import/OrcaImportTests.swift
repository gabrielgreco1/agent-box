import AgentBoxProtocol
import AgentBoxStore
import CryptoKit
import Foundation
import SQLite3
import Testing
@testable import AgentBoxCore

// Fixture 100% sintética: SQLite com o schema real do Orca (tabelas `profile_state_*`, descoberto na máquina do dono,
// sem nenhum dado do usuário), repositórios Git temporários e JSON legado gerado aqui.

struct OrcaFixture {
    let sandbox: GitSandbox
    let support: URL
    let profileDir: URL
    let tempRoot: URL

    init() throws {
        sandbox = try GitSandbox()
        support = try sandbox.dir("orca-support")
        profileDir = support.appendingPathComponent("profiles/local-default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        tempRoot = try sandbox.dir("tmp")
    }

    var profile: OrcaProfile { OrcaProfile(id: "local-default", directory: profileDir) }

    struct Repo { var id: String; var path: String; var name: String; var kind = "git"; var gitUsername = "gabrielgreco1" }
    struct Meta { var repoID: String; var path: String; var name: String?; var comment: String?; var sortOrder: Int64; var last: Int64 }

    static let schema = [
        "CREATE TABLE profile_state_meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)",
        """
        CREATE TABLE profile_state_documents (
            domain TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL,
            domain_version INTEGER NOT NULL, revision INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, content_hash TEXT NOT NULL)
        """,
        """
        CREATE TABLE profile_state_automation_runs_meta (
            domain TEXT PRIMARY KEY NOT NULL, presence TEXT NOT NULL, domain_version INTEGER NOT NULL,
            revision INTEGER NOT NULL, updated_at INTEGER NOT NULL, content_hash TEXT NOT NULL)
        """,
        """
        CREATE TABLE profile_state_automation_runs (
            run_id TEXT PRIMARY KEY NOT NULL, ordinal INTEGER NOT NULL, payload TEXT NOT NULL,
            content_hash TEXT NOT NULL, revision INTEGER NOT NULL, updated_at INTEGER NOT NULL)
        """,
    ]

    func settingsJSON(args: [String: String] = ["claude": "--dangerously-skip-permissions", "codex": "--dangerously-bypass-approvals-and-sandbox"],
                      env: [String: [String: String]] = [:], extra: [String: Any] = [:]) -> [String: Any] {
        var s: [String: Any] = [
            "workspaceDir": sandbox.root.appendingPathComponent("orca-workspaces").path, "branchPrefix": "git-username",
            "branchPrefixCustom": "", "defaultTuiAgent": "codex", "terminalDefaultShell": "", "agentDefaultArgs": args,
            "agentDefaultEnv": env, "agentCmdOverrides": [String: String](), "theme": "dark", "someFutureField": 42,
        ]
        for (k, v) in extra { s[k] = v }
        return s
    }

    func domains(repos: [Repo], metas: [Meta], settings: [String: Any], openTabs: [String] = []) -> [String: Any] {
        let repoItems = repos.map { r -> [String: Any] in
            ["id": r.id, "path": r.path, "displayName": r.name, "badgeColor": "#ff00aa", "kind": r.kind,
             "gitUsername": r.gitUsername, "addedAt": 1, "unknownRepoField": true]
        }
        var meta: [String: Any] = [:]
        for m in metas {
            var v: [String: Any] = ["instanceId": "i", "sortOrder": m.sortOrder, "lastActivityAt": m.last, "isUnread": false]
            if let n = m.name { v["displayName"] = n }
            if let c = m.comment { v["comment"] = c }
            meta["\(m.repoID)::\(m.path)"] = v
        }
        var tabs: [String: Any] = [:]
        for key in openTabs { tabs[key] = [["id": "t1"]] }
        return ["repos": repoItems, "folderWorkspaces": [Any](), "worktreeMeta": meta, "settings": settings,
                "workspaceSession": ["tabsByWorktree": tabs, "activeTabId": "x"]]
    }

    /// Cria `profile-state.db` (modo WAL, como o Orca) com os domínios dados.
    func writeSQLite(_ domains: [String: Any], versions: [String: Int] = [:]) throws {
        let url = profileDir.appendingPathComponent("profile-state.db")
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        func exec(_ sql: String) { #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)") }
        exec("PRAGMA journal_mode=WAL")
        for sql in Self.schema { exec(sql) }
        exec("INSERT INTO profile_state_meta VALUES ('profile_id','local-default'),('revision','1')")
        for (domain, value) in domains {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            let payload = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "'", with: "''")
            exec("INSERT INTO profile_state_documents VALUES ('\(domain)','\(payload)',\(versions[domain] ?? 1),1,1,'h-\(domain)')")
        }
    }

    func writeJSON(_ domains: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: domains).write(to: profileDir.appendingPathComponent("orca-data.json"))
    }

    /// SHA-256 de todos os arquivos sob a pasta de dados do Orca (AC-108).
    func treeHash() throws -> [String: String] {
        var result: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(at: support, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            result[url.path] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    func addWorktree(_ repo: URL, _ name: String) async throws -> String {
        let dir = sandbox.root.appendingPathComponent("wt-\(repo.lastPathComponent)-\(name)")
        try await sandbox.git(["worktree", "add", "-q", "-b", "feat/\(name)", dir.path], in: repo)
        return dir.canonicalPath.path
    }
}

struct OrcaHarness {
    let fx: OrcaFixture
    let store: AgentBoxStore
    let repoA: URL
    let repoB: URL
    let wtA1: String
    let wtA2: String
    let wtB1: String
    let importer: OrcaImporter

    init(args: [String: String] = ["claude": "--dangerously-skip-permissions", "codex": "--dangerously-bypass-approvals-and-sandbox"],
         env: [String: [String: String]] = [:]) async throws {
        fx = try OrcaFixture()
        let home = try fx.sandbox.dir("agentbox-home")
        store = try await AgentBoxStore.open(paths: StorePaths(root: home))
        repoA = try await fx.sandbox.makeRepo("alpha")
        repoB = try await fx.sandbox.makeRepo("beta")
        wtA1 = try await fx.addWorktree(repoA, "one")
        wtA2 = try await fx.addWorktree(repoA, "two")
        wtB1 = try await fx.addWorktree(repoB, "three")
        // wtA2 não tem meta no Orca de propósito; um terceiro caminho de meta não existe em disco.
        let repos = [
            OrcaFixture.Repo(id: "r-alpha", path: repoA.path, name: "Alpha"),
            OrcaFixture.Repo(id: "r-beta", path: repoB.path, name: "Beta"),
            OrcaFixture.Repo(id: "r-gone", path: fx.sandbox.root.appendingPathComponent("vanished").path, name: "Gone"),
        ]
        let metas = [
            OrcaFixture.Meta(repoID: "r-alpha", path: repoA.path, name: "main", comment: nil, sortOrder: 10, last: 1_000),
            OrcaFixture.Meta(repoID: "r-alpha", path: wtA1, name: "Feature One", comment: "waiting on review", sortOrder: 50, last: 5_000),
            OrcaFixture.Meta(repoID: "r-alpha", path: fx.sandbox.root.appendingPathComponent("deleted-wt").path, name: "Ghost", comment: nil, sortOrder: 5, last: 1),
            OrcaFixture.Meta(repoID: "r-beta", path: wtB1, name: nil, comment: nil, sortOrder: 30, last: 3_000),
        ]
        try fx.writeSQLite(fx.domains(repos: repos, metas: metas, settings: fx.settingsJSON(args: args, env: env),
                                      openTabs: ["r-alpha::\(wtA1)"]))
        importer = OrcaImporter(store: store, git: fx.sandbox.service, locator: OrcaLocator(supportDirectory: fx.support),
                                tempRoot: fx.tempRoot, worktreeBase: fx.sandbox.root.appendingPathComponent("wt-base"),
                                clock: { Date(timeIntervalSince1970: 1_800_000_000) })
    }
}

@Suite struct OrcaImportTests {
    @Test func locatorFindsProfileAndDetectCountsWithoutTouchingTheGit() async throws {
        let h = try await OrcaHarness()
        #expect(h.importer.profiles().map(\.id) == ["local-default"])
        let detection = try h.importer.detect(profile: h.fx.profile)
        #expect(detection.source == .sqlite && detection.repositories == 3 && detection.worktreeEntries == 4)
        #expect(detection.agentsWithDefaultArgs == ["claude", "codex"])
    }

    @Test func dryRunReportsCountsAndNamesAndWritesNothing() async throws {
        let h = try await OrcaHarness()
        let before = try h.fx.treeHash()
        let report = try await h.importer.dryRun(profile: h.fx.profile)

        #expect(report.dryRun)
        #expect(report.projects.filter { $0.outcome == .imported }.map(\.name) == ["Alpha", "Beta"])
        #expect(report.projects.first { $0.name == "Gone" }?.outcome == .skipped)
        #expect(report.sessions.filter { $0.outcome == .imported }.map(\.name).sorted() == ["Feature One", "main", "feat/three"].sorted())
        #expect(report.sessions.contains { $0.name == "Ghost" && $0.outcome == .skipped })
        #expect(report.worktreesWithoutMeta == 2)
        #expect(report.profiles.map(\.name) == ["Claude · Skip permissions", "Codex · Bypass approvals"])
        #expect(try await h.store.projects(includeArchived: true).isEmpty)
        #expect(try await h.store.sessions(includeArchived: true).isEmpty)
        #expect(try await h.store.profiles().isEmpty)
        #expect(try await h.store.importRuns(source: .orca).isEmpty)
        #expect(try h.fx.treeHash() == before)
    }

    @Test func realImportMapsProjectsWorktreesAndLeavesSessionsNotStarted() async throws {
        let h = try await OrcaHarness()
        let before = try h.fx.treeHash()
        let report = try await h.importer.run(profile: h.fx.profile)
        #expect(!report.dryRun && report.projectsImported == 2 && report.sessionsImported == 3)

        let projects = try await h.store.projects()
        #expect(projects.map(\.name) == ["Alpha", "Beta"])
        let alpha = try #require(projects.first { $0.name == "Alpha" })
        #expect(alpha.source == .orcaImport && alpha.importSourceID == "orca:r-alpha" && alpha.color == "#ff00aa")
        #expect(alpha.rootPath == h.repoA.canonicalPath.path && alpha.kind == .git)
        #expect(alpha.branchPrefix == "gabrielgreco1")
        #expect(alpha.worktreeRoot == h.fx.sandbox.root.appendingPathComponent("orca-workspaces/alpha").path)

        let sessions = try await h.store.sessions().filter { $0.projectID == alpha.id }
        #expect(sessions.count == 2)
        let feature = try #require(sessions.first { $0.title == "Feature One" })
        #expect(feature.kind == .worktree && feature.folderPath == h.wtA1 && feature.lifecycle == .active)
        #expect(feature.statusNote?.text == "waiting on review" && feature.statusNote?.author == "orca")
        #expect(feature.lastActiveAt == Date(timeIntervalSince1970: 5))
        let main = try #require(sessions.first { $0.title == "main" })
        #expect(main.kind == .checkout)
        #expect(feature.sortIndex < main.sortIndex, "sortOrder mais alto vem primeiro")
        // Sem processo: nenhuma tab e nenhum terminal (P15, AC-109).
        for s in try await h.store.sessions() { #expect(try await h.store.tabs(sessionID: s.id, includeClosed: true).isEmpty) }
        let worktrees = try await h.store.worktrees(projectID: alpha.id)
        #expect(worktrees.allSatisfy { $0.source == .orcaImport && !$0.createdByApp })
        // Beta: sem displayName, usa o branch.
        #expect(try await h.store.sessions().contains { $0.title == "feat/three" })
        #expect(try h.fx.treeHash() == before, "nada sob a pasta de dados do Orca mudou")
        let runs = try await h.store.importRuns(source: .orca)
        #expect(runs.count == 1 && runs[0].status == "completed" && runs[0].sourceFingerprint?.count == 64 && !runs[0].dryRun)
    }

    @Test func importIsIdempotentAndPicksUpNewWorktreesByPath() async throws {
        let h = try await OrcaHarness()
        _ = try await h.importer.run(profile: h.fx.profile)
        let projectsBefore = try await h.store.projects()
        let sessionsBefore = try await h.store.sessions().count
        let wtBefore = try await h.store.worktrees(projectID: projectsBefore[0].id).count

        let again = try await h.importer.run(profile: h.fx.profile)
        #expect(again.projectsImported == 0 && again.sessionsImported == 0 && again.profilesImported == 0)
        #expect(try await h.store.projects().map(\.id) == projectsBefore.map(\.id))
        #expect(try await h.store.sessions().count == sessionsBefore)
        #expect(try await h.store.worktrees(projectID: projectsBefore[0].id).count == wtBefore)
        #expect(try await h.store.profiles().count == 2)

        // Worktree novo no Orca (e no git): entra; os antigos são reconhecidos.
        let newPath = try await h.fx.addWorktree(h.repoB, "four")
        var repos = [OrcaFixture.Repo(id: "r-alpha", path: h.repoA.path, name: "Alpha"), OrcaFixture.Repo(id: "r-beta", path: h.repoB.path, name: "Beta")]
        repos.append(OrcaFixture.Repo(id: "r-gone", path: h.fx.sandbox.root.appendingPathComponent("vanished").path, name: "Gone"))
        let metas = [
            OrcaFixture.Meta(repoID: "r-alpha", path: h.repoA.path, name: "main", comment: nil, sortOrder: 10, last: 1_000),
            OrcaFixture.Meta(repoID: "r-alpha", path: h.wtA1, name: "Feature One", comment: "waiting on review", sortOrder: 50, last: 5_000),
            OrcaFixture.Meta(repoID: "r-beta", path: h.wtB1, name: nil, comment: nil, sortOrder: 30, last: 3_000),
            OrcaFixture.Meta(repoID: "r-beta", path: newPath, name: "Fourth", comment: nil, sortOrder: 60, last: 6_000),
        ]
        try h.fx.writeSQLite(h.fx.domains(repos: repos, metas: metas, settings: h.fx.settingsJSON()))
        let third = try await h.importer.run(profile: h.fx.profile)
        #expect(third.sessions.filter { $0.outcome == .imported }.map(\.name) == ["Fourth"])
        #expect(try await h.store.sessions().count == sessionsBefore + 1)
    }

    @Test func reimportKeepsLocalEditsUnlessOverwriteIsChosen() async throws {
        let h = try await OrcaHarness()
        _ = try await h.importer.run(profile: h.fx.profile)
        var session = try #require(try await h.store.sessions().first { $0.title == "Feature One" })
        session.title = "My rename"
        try await h.store.save(session)
        var project = try #require(try await h.store.projects().first { $0.name == "Alpha" })
        project.name = "My Alpha"
        try await h.store.save(project)

        _ = try await h.importer.run(profile: h.fx.profile)
        #expect(try await h.store.session(id: session.id)?.title == "My rename")
        #expect(try await h.store.project(id: project.id)?.name == "My Alpha")

        let overwrite = try await h.importer.run(profile: h.fx.profile, options: OrcaImportOptions(overwriteLocalEdits: true))
        #expect(overwrite.sessions.contains { $0.outcome == .updated })
        #expect(try await h.store.session(id: session.id)?.title == "Feature One")
        #expect(try await h.store.project(id: project.id)?.name == "Alpha")
        #expect(try await h.store.sessions().count == 3, "continua sem duplicar")
    }

    @Test func archivedProjectIsNotResurrectedWithoutOverwrite() async throws {
        let h = try await OrcaHarness()
        _ = try await h.importer.run(profile: h.fx.profile)
        let alpha = try #require(try await h.store.projects().first { $0.name == "Alpha" })
        try await h.store.archiveProject(id: alpha.id)
        let report = try await h.importer.run(profile: h.fx.profile)
        #expect(report.conflicts.count == 1 && report.projects.contains { $0.name == "Alpha" && $0.outcome == .skipped })
        #expect(try await h.store.projects().map(\.name) == ["Beta"])
    }

    @Test func agentDefaultsBecomeImportedProfilesMarkedAsBypass() async throws {
        let h = try await OrcaHarness(
            args: ["claude": "--dangerously-skip-permissions --append-system-prompt \"be brief\"",
                   "codex": "--dangerously-bypass-approvals-and-sandbox", "gemini": "--yolo", "droid": ""],
            env: ["claude": ["ANTHROPIC_API_KEY": "sk-secret-value"]])
        let report = try await h.importer.run(profile: h.fx.profile)
        #expect(report.ignoredAgents == ["gemini"])
        #expect(report.envKeys["claude"] == ["ANTHROPIC_API_KEY"])
        #expect(!((try? JSONEncoder().encode(report)).map { String(decoding: $0, as: UTF8.self) } ?? "").contains("sk-secret-value"))

        let profiles = try await h.store.profiles()
        let claude = try #require(profiles.first { $0.provider == .claude })
        #expect(claude.id == BuiltinProfiles.claudeSkipPermissions.id && claude.name == "Claude · Skip permissions")
        #expect(claude.permissionMode == "bypassPermissions" && claude.source == .orcaImport && claude.isDefault)
        #expect(claude.extraArgs == ["--append-system-prompt", "be brief"])
        #expect(claude.env.isEmpty, "valores de env só com confirmação")
        let codex = try #require(profiles.first { $0.provider == .codex })
        #expect(codex.name == "Codex · Bypass approvals" && codex.permissionMode == "bypass" && codex.isDefault && codex.extraArgs.isEmpty)

        // O catálogo resolve o perfil importado como padrão (AC-110).
        let catalog = ProfileCatalog(userProfiles: profiles)
        #expect(catalog.resolve(provider: .claude, explicitID: nil, projectID: nil)?.source == .orcaImport)
        #expect(catalog.resolve(provider: .codex, explicitID: nil, projectID: nil)?.name == "Codex · Bypass approvals")

        let settings = try #require(try await h.store.setting(AppSettings.storeKey, as: AppSettings.self))
        #expect(settings.agents.defaultAgent == .codex)
        #expect(settings.general.worktreeFolder == h.fx.sandbox.root.appendingPathComponent("orca-workspaces").path)
        #expect(settings.general.branchPrefix == .gitUser)
    }

    @Test func envValuesAreImportedOnlyWhenConfirmed() async throws {
        let h = try await OrcaHarness(env: ["codex": ["FOO": "bar"]])
        _ = try await h.importer.run(profile: h.fx.profile, options: OrcaImportOptions(importEnvValues: true))
        #expect(try await h.store.profiles().first { $0.provider == .codex }?.env == ["FOO": "bar"])
    }

    @Test func existingManualDefaultIsNotReplaced() async throws {
        let h = try await OrcaHarness()
        try await h.store.save(LaunchProfile(name: "Mine", provider: .claude, scope: .global, isDefault: true))
        let report = try await h.importer.run(profile: h.fx.profile)
        #expect(try await h.store.profiles().first { $0.id == BuiltinProfiles.claudeSkipPermissions.id }?.isDefault == false)
        #expect(report.profiles.first { $0.name == "Claude · Skip permissions" }?.reason?.contains("already have a default") == true)
    }

    @Test func togglesLimitWhatIsImported() async throws {
        let h = try await OrcaHarness()
        let report = try await h.importer.run(profile: h.fx.profile, options: OrcaImportOptions(selection: .agentDefaults))
        #expect(report.projects.isEmpty && report.sessions.isEmpty && report.profilesImported == 2)
        #expect(try await h.store.projects().isEmpty)
        let settings = try #require(try await h.store.setting(AppSettings.storeKey, as: AppSettings.self))
        #expect(settings.general.worktreeFolder == "~/orca/workspaces", "worktreeSettings desligado: padrão intacto")
    }

    @Test func legacyJSONIsUsedWhenSQLiteIsMissingOrBroken() async throws {
        let h = try await OrcaHarness()
        let repos = [OrcaFixture.Repo(id: "r-alpha", path: h.repoA.path, name: "Alpha Legacy")]
        let metas = [OrcaFixture.Meta(repoID: "r-alpha", path: h.wtA1, name: "Old Name", comment: nil, sortOrder: 1, last: 1)]
        try h.fx.writeJSON(h.fx.domains(repos: repos, metas: metas, settings: h.fx.settingsJSON()))
        try Data("not a database".utf8).write(to: h.fx.profileDir.appendingPathComponent("profile-state.db"))
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: h.fx.profileDir.appendingPathComponent("profile-state.db").path + suffix) }

        let report = try await h.importer.dryRun(profile: h.fx.profile)
        #expect(report.source == .legacyJSON)
        #expect(report.notes.contains { $0.contains("may be outdated") })
        #expect(report.projects.map(\.name) == ["Alpha Legacy"] && report.sessions.map(\.name) == ["Old Name"])

        try FileManager.default.removeItem(at: h.fx.profileDir.appendingPathComponent("profile-state.db"))
        #expect(try await h.importer.dryRun(profile: h.fx.profile).source == .legacyJSON)
    }

    @Test func unknownDomainVersionIsSkippedWithANote() async throws {
        let h = try await OrcaHarness()
        let repos = [OrcaFixture.Repo(id: "r-alpha", path: h.repoA.path, name: "Alpha")]
        try h.fx.writeSQLite(h.fx.domains(repos: repos, metas: [], settings: h.fx.settingsJSON()), versions: ["worktreeMeta": 9])
        let report = try await h.importer.dryRun(profile: h.fx.profile)
        #expect(report.notes.contains { $0.contains("worktreeMeta") && $0.contains("domain_version 9") })
        #expect(report.projectsImported == 1 && report.sessions.isEmpty)
    }

    @Test func noOrcaFilesMeansNoProfiles() throws {
        let sandbox = try GitSandbox()
        let empty = try sandbox.dir("nothing-here")
        #expect(OrcaLocator(supportDirectory: empty).profiles().isEmpty)
        #expect(OrcaLocator(supportDirectory: empty.appendingPathComponent("missing")).profiles().isEmpty)
    }

    @Test func readerOnlyTouchesATemporaryCopyAndCleansUp() async throws {
        let h = try await OrcaHarness()
        // Sem -wal/-shm no disco depois do fechamento: o leitor tem que funcionar mesmo assim, e deixar tempRoot vazio.
        let before = try h.fx.treeHash()
        _ = try OrcaReader(tempRoot: h.fx.tempRoot).read(h.fx.profile)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.fx.tempRoot.path).isEmpty)
        #expect(try h.fx.treeHash() == before)
    }

    @Test func orcaDefaultArgsTokenizeLikeAShell() throws {
        #expect(try ShellWords.split("--allow \"*\"") == ["--allow", "*"])
        #expect(try ShellWords.split("--approval-mode yolo") == ["--approval-mode", "yolo"])
    }
}

@Suite struct OrcaCoexistenceTests {
    @Test func warnsWhenOrcaStillListsTheWorktree() async throws {
        let h = try await OrcaHarness()
        let coexistence = OrcaCoexistence.refresh(locator: OrcaLocator(supportDirectory: h.fx.support), tempRoot: h.fx.tempRoot,
                                                  isOrcaRunning: { _ in false })
        let listed = coexistence.status(forWorktreePath: h.wtA1)
        #expect(listed.listedInOrca && listed.openTabsInOrca && !listed.orcaRunning)
        #expect(listed.warning == "This worktree is also open in Orca.")
        let notOpen = coexistence.status(forWorktreePath: h.wtB1)
        #expect(notOpen.listedInOrca && !notOpen.openTabsInOrca)
        #expect(coexistence.status(forWorktreePath: h.wtA2).warning == nil, "worktree que o Orca não registra: sem aviso")
    }

    @Test func runningOrcaChangesTheVariant() async throws {
        let h = try await OrcaHarness()
        let coexistence = OrcaCoexistence.refresh(locator: OrcaLocator(supportDirectory: h.fx.support), tempRoot: h.fx.tempRoot,
                                                  isOrcaRunning: { _ in true })
        #expect(coexistence.status(forWorktreePath: h.wtA1).warning == "Orca is open.")
        #expect(coexistence.status(forWorktreePath: h.wtA2).warning == nil)
    }

    @Test func missingOrcaMeansNoWarning() throws {
        let sandbox = try GitSandbox()
        let coexistence = OrcaCoexistence.refresh(locator: OrcaLocator(supportDirectory: sandbox.root.appendingPathComponent("none")),
                                                  tempRoot: sandbox.root)
        #expect(coexistence.status(forWorktreePath: "/tmp/whatever").warning == nil)
    }

    @Test func defaultProbeReadsSingletonLockAndRejectsStalePid() throws {
        let sandbox = try GitSandbox()
        let dir = try sandbox.dir("orca-data")
        #expect(!OrcaCoexistence.defaultRunningProbe(dir), "sem SingletonLock")
        // Pid vivo mas que não é o Orca (o próprio teste) e pid inexistente: ambos falso.
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("SingletonLock").path,
                                                   withDestinationPath: "host-\(getpid())")
        #expect(!OrcaCoexistence.defaultRunningProbe(dir))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("SingletonLock"))
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("SingletonLock").path,
                                                   withDestinationPath: "host-999999")
        #expect(!OrcaCoexistence.defaultRunningProbe(dir))
    }
}
