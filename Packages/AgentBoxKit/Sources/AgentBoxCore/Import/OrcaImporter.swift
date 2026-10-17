import AgentBoxProtocol
import AgentBoxStore
import Foundation

// Importador do Orca (T2-08; 06 §6; 08 AR-340). Dry-run e importação real passam pelo MESMO caminho de planejamento
// (`perform(commit:)`), então o relatório do dry-run é exatamente o que a importação real fará. Nada é escrito no Orca:
// a leitura é por cópia temporária (`OrcaReader`); só o Store do Agent Box recebe gravações, e só na importação real.

public struct OrcaImportSelection: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Repos viram projetos e worktrees viram sessões não iniciadas.
    public static let projectsAndWorktrees = OrcaImportSelection(rawValue: 1)
    /// `agentDefaultArgs`/`agentDefaultEnv` viram perfis de lançamento; `defaultTuiAgent` vira o agente padrão.
    public static let agentDefaults = OrcaImportSelection(rawValue: 2)
    /// Raiz de worktrees e prefixo de branch.
    public static let worktreeSettings = OrcaImportSelection(rawValue: 4)
    public static let all: OrcaImportSelection = [.projectsAndWorktrees, .agentDefaults, .worktreeSettings]
}

public struct OrcaImportOptions: Sendable {
    public var selection: OrcaImportSelection = .all
    /// "Overwrite my changes" (06 §6.3): reimportar volta a aplicar nome, nota, perfil e ajustes do Orca.
    public var overwriteLocalEdits = false
    /// Valores de `agentDefaultEnv` podem ser segredos: só entram com confirmação explícita. Sem ela, só as chaves
    /// aparecem no relatório e o perfil importado fica sem `env`.
    public var importEnvValues = false

    public init(selection: OrcaImportSelection = .all, overwriteLocalEdits: Bool = false, importEnvValues: Bool = false) {
        self.selection = selection; self.overwriteLocalEdits = overwriteLocalEdits; self.importEnvValues = importEnvValues
    }
}

public struct OrcaImportReport: Sendable, Equatable, Codable {
    public enum Outcome: String, Sendable, Codable {
        /// Criado (ou, no dry-run, será criado).
        case imported
        /// Já existia e foi atualizado por "Overwrite my changes".
        case updated
        /// Já existia: nada muda (edições locais preservadas).
        case unchanged
        case skipped
    }

    public struct Line: Sendable, Equatable, Codable {
        public var name: String
        /// Projeto da sessão, caminho do projeto, ou valor do ajuste.
        public var detail: String?
        public var outcome: Outcome
        public var reason: String?
    }

    public var dryRun: Bool
    public var profileID: String
    public var source: OrcaStateSource
    public var projects: [Line] = []
    public var sessions: [Line] = []
    public var profiles: [Line] = []
    public var settings: [Line] = []
    /// Chaves (nunca valores) de `agentDefaultEnv` dos agentes suportados.
    public var envKeys: [String: [String]] = [:]
    /// Worktrees listados pelo git sem meta no Orca (não viram sessão; o sync do ProjectService os adota depois).
    public var worktreesWithoutMeta = 0
    /// Agentes com args padrão no Orca que o Agent Box não importa (gemini, amp…).
    public var ignoredAgents: [String] = []
    public var notes: [String] = []
    public var conflicts: [String] = []

    public func count(_ outcome: Outcome, in lines: KeyPath<OrcaImportReport, [Line]>) -> Int {
        self[keyPath: lines].filter { $0.outcome == outcome }.count
    }
    public var projectsImported: Int { count(.imported, in: \.projects) }
    public var sessionsImported: Int { count(.imported, in: \.sessions) }
    public var profilesImported: Int { count(.imported, in: \.profiles) }
}

/// "Found Orca: 7 repositories, N worktrees on disk, default args for Claude and Codex." (06 §6.3 passo 1)
public struct OrcaDetection: Sendable, Equatable {
    public let profileID: String
    public let source: OrcaStateSource
    public let repositories: Int
    public let worktreeEntries: Int
    public let agentsWithDefaultArgs: [String]
}

public enum OrcaImportError: Error, Sendable, Equatable {
    case noOrcaFound
    case read(OrcaReadError)
}

public struct OrcaImporter: Sendable {
    /// IDs fixos dos perfis importados; o de OpenCode não existe entre os prontos (`BuiltinProfiles`).
    public static let openCodeImportedProfileID = UUID(uuidString: "A0000000-0000-4000-8000-000000000008")!

    private let store: AgentBoxStore
    private let git: GitService
    private let locator: OrcaLocator
    private let reader: OrcaReader
    private let worktreeBase: URL
    private let clock: @Sendable () -> Date

    public init(store: AgentBoxStore, git: GitService = GitService(), locator: OrcaLocator = OrcaLocator(),
                tempRoot: URL = FileManager.default.temporaryDirectory,
                worktreeBase: URL = GitNaming.defaultWorktreeRoot(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store; self.git = git; self.locator = locator; self.reader = OrcaReader(tempRoot: tempRoot)
        self.worktreeBase = worktreeBase; self.clock = clock
    }

    // MARK: - API

    public func profiles() -> [OrcaProfile] { locator.profiles() }

    /// Contagens para o onboarding. Lê só a cópia temporária; não consulta o git nem grava nada.
    public func detect(profile: OrcaProfile) throws -> OrcaDetection {
        let snap = try readSnapshot(profile)
        return OrcaDetection(
            profileID: profile.id, source: snap.source, repositories: snap.repos.count, worktreeEntries: snap.worktreeMeta.count,
            agentsWithDefaultArgs: snap.settings.agentDefaultArgs.keys.filter(Self.supportedAgents.contains).sorted())
    }

    /// Relatório do que a importação faria. Não grava nada (nem no Store).
    public func dryRun(profile: OrcaProfile, options: OrcaImportOptions = OrcaImportOptions()) async throws -> OrcaImportReport {
        try await perform(profile: profile, options: options, commit: false)
    }

    /// Importação real, idempotente: reimportar atualiza por caminho real, adiciona o que é novo e não sobrescreve o que
    /// foi editado no Agent Box (a menos que `overwriteLocalEdits`).
    public func run(profile: OrcaProfile, options: OrcaImportOptions = OrcaImportOptions()) async throws -> OrcaImportReport {
        try await perform(profile: profile, options: options, commit: true)
    }

    // MARK: - Planejamento + gravação

    static let supportedAgents: Set<String> = ["claude", "codex", "opencode"]

    private func readSnapshot(_ profile: OrcaProfile) throws -> OrcaSnapshot {
        do { return try reader.read(profile) } catch let error as OrcaReadError { throw OrcaImportError.read(error) }
    }

    private func perform(profile: OrcaProfile, options: OrcaImportOptions, commit: Bool) async throws -> OrcaImportReport {
        let started = clock()
        let snap = try readSnapshot(profile)
        var report = OrcaImportReport(dryRun: !commit, profileID: profile.id, source: snap.source)
        report.notes = snap.notes
        let firstImport = try await store.importRuns(source: .orca).filter { !$0.dryRun && $0.status == "completed" }.isEmpty

        if options.selection.contains(.projectsAndWorktrees) {
            try await importProjects(snap, options: options, commit: commit, report: &report)
        }
        if options.selection.contains(.agentDefaults) {
            try await importProfiles(snap, options: options, commit: commit, report: &report)
        }
        if !options.selection.isDisjoint(with: [.agentDefaults, .worktreeSettings]) {
            try await importSettings(snap, options: options, firstImport: firstImport, commit: commit, report: &report)
        }
        if !snap.settings.terminalDefaultShell.isNilOrEmpty {
            report.notes.append("Default shell is not imported in this version")
        }
        if !snap.settings.agentCmdOverrides.isEmpty {
            report.notes.append("Executable overrides (\(snap.settings.agentCmdOverrides.keys.sorted().joined(separator: ", "))) are not imported")
        }

        if commit {
            let summary = (try? JSONEncoder().encode(report)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            try await store.record(ImportRun(
                source: .orca, sourcePath: profile.directory.path, sourceFingerprint: snap.fingerprint, dryRun: false,
                status: "completed", summaryJSON: summary, startedAt: started, finishedAt: clock()))
        }
        return report
    }

    // MARK: Projetos e worktrees

    private func importProjects(_ snap: OrcaSnapshot, options: OrcaImportOptions, commit: Bool,
                                report: inout OrcaImportReport) async throws {
        let now = clock()
        var projects = try await store.projects(includeArchived: true)
        var nextProjectSort = (projects.map(\.sortIndex).max() ?? -1) + 1
        var sessions = try await store.sessions(includeArchived: true)
        let applyWorktreeSettings = options.selection.contains(.worktreeSettings)

        // Meta por repo e caminho canônico (o Orca guarda o caminho como o usuário o abriu).
        var metaByRepo: [String: [String: OrcaWorktreeMeta]] = [:]
        for meta in snap.worktreeMeta {
            metaByRepo[meta.repoID, default: [:]][Self.canonical(meta.path)] = meta
        }

        for repo in snap.repos {
            let rootPath = Self.canonical(repo.path)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDir), isDir.boolValue else {
                report.projects.append(.init(name: repo.displayName, detail: rootPath, outcome: .skipped, reason: "Folder not found"))
                continue
            }
            let kind: ProjectKind = repo.isFolder ? .folder : .git

            var project: Project
            if let index = projects.firstIndex(where: { $0.rootPath == rootPath }) {
                project = projects[index]
                if project.archivedAt != nil && !options.overwriteLocalEdits {
                    report.projects.append(.init(name: project.name, detail: rootPath, outcome: .skipped,
                                                 reason: "Removed from Agent Box; skipped"))
                    report.conflicts.append("\(project.name) was removed from Agent Box; use Overwrite my changes to bring it back")
                    continue
                }
                var changed = false
                if project.importSourceID == nil { project.importSourceID = "orca:\(repo.id)"; changed = true }
                if project.archivedAt != nil { project.archivedAt = nil; changed = true }
                if options.overwriteLocalEdits {
                    if project.name != repo.displayName { project.name = repo.displayName; changed = true }
                    if let color = repo.badgeColor, project.color != color { project.color = color; changed = true }
                }
                report.projects.append(.init(name: project.name, detail: rootPath, outcome: changed && options.overwriteLocalEdits ? .updated : .unchanged,
                                             reason: changed && options.overwriteLocalEdits ? nil : "Already in Agent Box"))
                if changed && commit { try await store.save(project); projects[index] = project }
            } else {
                var remote: String?, defaultBranch: String?, prefix: String?
                if kind == .git {
                    let url = URL(fileURLWithPath: rootPath, isDirectory: true)
                    remote = (try? await git.remoteURL(in: url)) ?? nil
                    defaultBranch = try? await git.defaultBranch(in: url)
                    prefix = await branchPrefix(for: repo, snap: snap, applyOrcaSettings: applyWorktreeSettings, url: url)
                }
                let folderName = URL(fileURLWithPath: rootPath).lastPathComponent
                let root = (applyWorktreeSettings ? snap.settings.workspaceDir.map { URL(fileURLWithPath: $0, isDirectory: true) } : nil)
                    ?? worktreeBase
                project = Project(
                    name: repo.displayName, kind: kind, rootPath: rootPath, gitRemoteURL: remote, defaultBranch: defaultBranch,
                    worktreeRoot: kind == .git ? root.appendingPathComponent(folderName, isDirectory: true).path : nil,
                    branchPrefix: prefix, color: repo.badgeColor, source: .orcaImport, importSourceID: "orca:\(repo.id)",
                    sortIndex: nextProjectSort, createdAt: now)
                nextProjectSort += 1
                report.projects.append(.init(name: project.name, detail: rootPath, outcome: .imported))
                if commit { try await store.save(project) }
                projects.append(project)
            }

            guard kind == .git else { continue }
            let listed: [GitWorktreeInfo]
            do { listed = try await git.listWorktrees(in: URL(fileURLWithPath: rootPath, isDirectory: true)) }
            catch {
                report.notes.append("Could not list worktrees of \(project.name): \(error)")
                continue
            }
            // Verdade dos worktrees = `git worktree list`; a lista do Orca só fornece nome, nota e ordem.
            let live = listed.filter { !$0.isBare && !$0.isPrunable }
            let existingWorktrees = try await store.worktrees(projectID: project.id)
            let metas = metaByRepo[repo.id] ?? [:]
            for orphan in metas.values where !live.contains(where: { Self.canonical($0.path) == Self.canonical(orphan.path) }) {
                report.sessions.append(.init(name: orphan.displayName ?? URL(fileURLWithPath: orphan.path).lastPathComponent,
                                             detail: project.name, outcome: .skipped, reason: "Worktree not found on disk"))
            }

            var candidates: [(info: GitWorktreeInfo, path: String, meta: OrcaWorktreeMeta)] = []
            for info in live {
                let path = Self.canonical(info.path)
                guard let meta = metas[path] else { report.worktreesWithoutMeta += 1; continue }
                candidates.append((info, path, meta))
            }
            // Mais recente primeiro (`sortOrder` do Orca; empate por última atividade).
            candidates.sort { lhs, rhs in
                let l: Int64 = lhs.meta.sortOrder ?? lhs.meta.lastActivityAt ?? 0
                let r: Int64 = rhs.meta.sortOrder ?? rhs.meta.lastActivityAt ?? 0
                if l != r { return l > r }
                return (lhs.meta.lastActivityAt ?? 0) > (rhs.meta.lastActivityAt ?? 0)
            }

            var nextSort = (sessions.filter { $0.projectID == project.id }.map(\.sortIndex).max() ?? -1) + 1
            for candidate in candidates {
                let title = Self.title(for: candidate.meta, info: candidate.info, path: candidate.path)
                let label = OrcaImportReport.Line(name: title, detail: project.name, outcome: .imported)
                if var wt = existingWorktrees.first(where: { $0.path == candidate.path }) {
                    if var session = sessions.first(where: { $0.worktreeID == wt.id }) {
                        guard options.overwriteLocalEdits, session.archivedAt == nil else {
                            var line = label; line.outcome = .unchanged
                            line.reason = session.archivedAt == nil ? "Already in Agent Box" : "Archived in Agent Box"
                            report.sessions.append(line)
                            continue
                        }
                        session.title = title
                        session.statusNote = Self.note(candidate.meta, fallback: now)
                        session.lastActiveAt = candidate.meta.lastActivityAt.map(Self.date) ?? session.lastActiveAt
                        var line = label; line.outcome = .updated
                        report.sessions.append(line)
                        if commit { try await store.save(session) }
                        if let i = sessions.firstIndex(where: { $0.id == session.id }) { sessions[i] = session }
                        continue
                    }
                    // Worktree conhecido sem sessão (ex.: sync do ProjectService antes): só cria a sessão.
                    wt.lastSeenAt = now
                    let session = makeSession(project: project, wt: wt, candidate: candidate, title: title, sort: nextSort, now: now)
                    nextSort += 1
                    report.sessions.append(label)
                    if commit { try await store.save(session) }
                    sessions.append(session)
                    continue
                }
                let wt = Worktree(projectID: project.id, path: candidate.path, branch: candidate.info.branch ?? "",
                                  isMain: candidate.info.isMain, createdByApp: false, source: .orcaImport,
                                  createdAt: now, lastSeenAt: now)
                let session = makeSession(project: project, wt: wt, candidate: candidate, title: title, sort: nextSort, now: now)
                nextSort += 1
                report.sessions.append(label)
                if commit {
                    try await store.save(wt)
                    try await store.save(session)
                }
                sessions.append(session)
            }
        }
    }

    private func makeSession(project: Project, wt: Worktree, candidate: (info: GitWorktreeInfo, path: String, meta: OrcaWorktreeMeta),
                             title: String, sort: Int, now: Date) -> Session {
        // Sessão importada nasce SEM tabs nem terminais (P15): nenhum processo de agente é iniciado.
        Session(kind: candidate.info.isMain ? .checkout : .worktree, projectID: project.id, worktreeID: wt.id,
                folderPath: candidate.path, managedFolder: false, title: title, statusNote: Self.note(candidate.meta, fallback: now),
                lifecycle: .active, sortIndex: sort, createdAt: now,
                lastActiveAt: candidate.meta.lastActivityAt.map(Self.date))
    }

    private func branchPrefix(for repo: OrcaRepo, snap: OrcaSnapshot, applyOrcaSettings: Bool, url: URL) async -> String? {
        if applyOrcaSettings {
            switch snap.settings.branchPrefix {
            case "custom": return GitBranchPrefix.custom(snap.settings.branchPrefixCustom ?? "").value
            case "none": return nil
            default:
                if let user = repo.gitUsername { return GitBranchPrefix.gitUsername(user).value }
            }
        }
        return (try? await git.gitUsernamePrefix(in: url))?.value
    }

    static func title(for meta: OrcaWorktreeMeta, info: GitWorktreeInfo, path: String) -> String {
        if let name = meta.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let branch = info.branch, !branch.isEmpty { return branch }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    static func note(_ meta: OrcaWorktreeMeta, fallback: Date) -> StatusNote? {
        guard let text = meta.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return StatusNote(text: text, author: "orca", at: meta.lastActivityAt.map(date) ?? fallback)
    }

    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    static func canonical(_ path: String) -> String { URL(fileURLWithPath: path, isDirectory: true).canonicalPath.path }

    // MARK: Perfis

    private func importProfiles(_ snap: OrcaSnapshot, options: OrcaImportOptions, commit: Bool,
                                report: inout OrcaImportReport) async throws {
        let now = clock()
        let stored = try await store.profiles()
        report.ignoredAgents = snap.settings.agentDefaultArgs.keys.filter { !Self.supportedAgents.contains($0) }.sorted()

        let plans: [(agent: String, provider: TerminalProvider, id: UUID, name: String, bypass: Set<String>, mode: String?)] = [
            ("claude", .claude, BuiltinProfiles.claudeSkipPermissions.id, BuiltinProfiles.claudeSkipPermissions.name,
             ["--dangerously-skip-permissions"], "bypassPermissions"),
            ("codex", .codex, BuiltinProfiles.codexBypassApprovals.id, BuiltinProfiles.codexBypassApprovals.name,
             ["--dangerously-bypass-approvals-and-sandbox"], "bypass"),
            ("opencode", .opencode, Self.openCodeImportedProfileID, "OpenCode · Orca defaults", [], nil),
        ]
        for plan in plans {
            if let keys = snap.settings.agentDefaultEnv[plan.agent]?.keys.sorted() { report.envKeys[plan.agent] = keys }
            guard let argsText = snap.settings.agentDefaultArgs[plan.agent] else { continue }
            let tokens: [String]
            do { tokens = try ShellWords.split(argsText) }
            catch {
                report.profiles.append(.init(name: plan.name, outcome: .skipped, reason: "Default args could not be parsed (unbalanced quote)"))
                continue
            }
            // Marca de bypass: o flag vira `permissionMode` (o adapter o reemite e o indicador de permissões puladas aparece).
            let bypassed = tokens.contains(where: plan.bypass.contains)
            let extra = tokens.filter { !plan.bypass.contains($0) }
            var env: [String: String] = [:]
            if options.importEnvValues { env = snap.settings.agentDefaultEnv[plan.agent] ?? [:] }

            let existing = stored.first { $0.id == plan.id }
            let hasOtherDefault = stored.contains { $0.provider == plan.provider && $0.scope == .global && $0.isDefault
                && $0.id != plan.id && $0.source == .manual }
            let profile = LaunchProfile(
                id: plan.id, name: plan.name, provider: plan.provider, permissionMode: bypassed ? plan.mode : nil,
                extraArgs: extra, env: env, scope: .global, isDefault: existing?.isDefault ?? !hasOtherDefault,
                source: .orcaImport, createdAt: existing?.createdAt ?? now, updatedAt: now)
            let detail = bypassed ? "Skips permission prompts" : nil
            if existing != nil {
                if options.overwriteLocalEdits {
                    report.profiles.append(.init(name: plan.name, detail: detail, outcome: .updated))
                    if commit { try await store.save(profile) }
                } else {
                    report.profiles.append(.init(name: plan.name, detail: detail, outcome: .unchanged, reason: "Already in Agent Box"))
                }
            } else {
                report.profiles.append(.init(name: plan.name, detail: detail, outcome: .imported,
                                             reason: hasOtherDefault ? "Not set as default: you already have a default" : nil))
                if commit { try await store.save(profile) }
            }
        }
    }

    // MARK: Ajustes (AppSettings)

    private func importSettings(_ snap: OrcaSnapshot, options: OrcaImportOptions, firstImport: Bool, commit: Bool,
                                report: inout OrcaImportReport) async throws {
        // Ajustes só entram na primeira importação (ou com "Overwrite my changes"): depois disso o usuário pode tê-los editado.
        guard firstImport || options.overwriteLocalEdits else {
            report.settings.append(.init(name: "Settings", outcome: .unchanged, reason: "Already imported"))
            return
        }
        var settings = (try await store.setting(AppSettings.storeKey, as: AppSettings.self)) ?? AppSettings()
        var changed = false
        if options.selection.contains(.worktreeSettings) {
            if let dir = snap.settings.workspaceDir {
                let value = Self.tildePath(dir)
                settings.general.worktreeFolder = value
                report.settings.append(.init(name: "Worktree folder", detail: value, outcome: .imported)); changed = true
            }
            switch snap.settings.branchPrefix {
            case "git-username": settings.general.branchPrefix = .gitUser
            case "custom": settings.general.branchPrefix = .custom; settings.general.branchPrefixCustom = snap.settings.branchPrefixCustom ?? ""
            case "none": settings.general.branchPrefix = .none
            default: break
            }
            if let mode = snap.settings.branchPrefix, ["git-username", "custom", "none"].contains(mode) {
                report.settings.append(.init(name: "Branch prefix", detail: mode, outcome: .imported)); changed = true
            }
        }
        if options.selection.contains(.agentDefaults), let name = snap.settings.defaultTuiAgent,
           let provider = TerminalProvider(rawValue: name), provider.isAgent {
            settings.agents.defaultAgent = provider
            report.settings.append(.init(name: "Default agent", detail: name, outcome: .imported)); changed = true
        }
        if changed && commit { try await store.setSetting(AppSettings.storeKey, settings) }
    }

    static func tildePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
