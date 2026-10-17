import AgentBoxProtocol
import Foundation
import Testing
@testable import AgentBoxCore

/// Regras do composer (03 §6, 06 §5.2) sem UI: nomes derivados do prompt, branch com prefixo, caminho, resumo, validação e pedido.
@Suite struct ComposerDraftTests {
    static let project = Project(name: "rti-platform", kind: .git, rootPath: "/Users/me/code/rti-platform", defaultBranch: "main")
    static let main = Worktree(projectID: project.id, path: "/Users/me/code/rti-platform", branch: "main", isMain: true)
    static let feature = Worktree(projectID: project.id, path: "/Users/me/orca/workspaces/rti-platform/feat", branch: "me/feat")

    func context(
        project: Project? = ComposerDraftTests.project, prefix: String? = "gabrielgreco1", lookup: GitBranchLookup? = nil,
        users: [UUID: String] = [:]
    ) -> ComposerContext {
        ComposerContext(
            project: project, defaultBranch: "main", branchPrefix: prefix, worktreeRoot: "/Users/me/orca/workspaces",
            cleanSessionRoot: "/Users/me/AgentBox/sessions", createFromLookup: lookup, worktrees: [Self.main, Self.feature],
            worktreeUsers: users, home: "/Users/me")
    }

    func draft(_ prompt: String = "", where choice: ComposerWhere = .newWorktree) -> ComposerDraft {
        var d = ComposerDraft(projectID: Self.project.id, whereChoice: choice, automaticName: "quiet-harbor")
        d.prompt = prompt
        return d
    }

    // MARK: Nomes

    @Test func sessionNameComesFromTheFirstWordsOfThePromptAsTyped() {
        let d = draft("Fix the ArcGIS pagination: the last page is dropped when resultOffset lands")
        #expect(d.sessionTitle == "Fix the ArcGIS pagination: the")
        #expect(d.slug == "fix-the-arcgis-pagination-the")
    }

    @Test func emptyPromptFallsBackToTheAutomaticAdjectiveNoun() {
        let d = draft("   ")
        #expect(d.sessionTitle == "quiet-harbor")
        #expect(d.slug == "quiet-harbor")
    }

    @Test func typedSessionNameWinsAndBlankTerminalIgnoresThePrompt() {
        var d = draft("fix arcgis pagination")
        d.sessionName = "  My Name  "
        #expect(d.sessionTitle == "My Name" && d.slug == "my-name")
        var shell = draft("fix arcgis pagination")
        shell.provider = .shell
        #expect(shell.effectivePrompt.isEmpty)
        #expect(shell.sessionTitle == "quiet-harbor")
        #expect(shell.spec().initialPrompt == nil)
    }

    @Test func branchHasTheUserPrefixAndALongPromptIsCapped() {
        let d = draft("fix arcgis pagination")
        #expect(d.defaultBranchName(context()) == "gabrielgreco1/fix-arcgis-pagination")
        #expect(d.defaultBranchName(context(prefix: nil)) == "fix-arcgis-pagination")
        var typed = d
        typed.branchName = "custom/name"
        #expect(typed.shownBranchName(context()) == "custom/name")
        #expect(draft(String(repeating: "supercalifragilistic ", count: 10)).slug.count <= 40)
    }

    @Test func automaticNamesAreAdjectiveNounAndFolderNamesNeverReuseAnExistingOne() throws {
        let name = SessionNaming.automaticName()
        let parts = name.split(separator: "-")
        #expect(parts.count == 2 && parts.allSatisfy { $0.allSatisfy(\.isLowercase) })
        var rng = SystemRandomNumberGenerator()
        #expect(SessionNaming.automaticName(using: &rng).contains("-"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("abnaming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("quiet-harbor"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(SessionNaming.uniqueFolderName("quiet-harbor", in: root) == "quiet-harbor-2")
        #expect(SessionNaming.uniqueFolderName("calm-otter", in: root) == "calm-otter")
    }

    // MARK: Caminhos e Where

    @Test func locationAndPathFollowTheWhereChoice() {
        let ctx = context()
        var d = draft("fix arcgis pagination")
        #expect(d.worktreeLocation(ctx) == "/Users/me/orca/workspaces/rti-platform/fix-arcgis-pagination")
        d.locationRoot = "/tmp/wt"
        #expect(d.worktreeLocation(ctx) == "/tmp/wt/rti-platform/fix-arcgis-pagination")
        d.whereChoice = .mainCheckout
        #expect(d.targetPath(ctx) == "/Users/me/code/rti-platform")
        d.whereChoice = .existingWorktree
        d.worktreeID = Self.feature.id
        #expect(d.targetPath(ctx) == Self.feature.path)
        var clean = ComposerDraft(automaticName: "quiet-harbor")
        #expect(clean.whereChoice == .newFolder)
        #expect(clean.targetPath(context(project: nil)) == "/Users/me/AgentBox/sessions/quiet-harbor")
        clean.prompt = "write the docs"
        #expect(clean.targetPath(context(project: nil)) == "/Users/me/AgentBox/sessions/write-the-docs")
    }

    @Test func availableWheresDependOnTheProject() {
        #expect(ComposerDraft.availableWheres(hasProject: true, kind: .git) == [.newWorktree, .existingWorktree, .mainCheckout])
        #expect(ComposerDraft.availableWheres(hasProject: false, kind: .git) == [.newFolder, .chooseFolder])
        #expect(ComposerDraft.availableWheres(hasProject: true, kind: .folder) == [.mainCheckout])
        #expect(ComposerDraft.defaultWhere(hasProject: true, kind: .git) == .newWorktree)
        #expect(ComposerDraft.defaultWhere(hasProject: false, kind: .git) == .newFolder)
    }

    // MARK: Validação

    @Test func onlyMissingProjectOrFolderBlocksTheButton() {
        var d = draft("x")
        #expect(d.canSubmit(context()))
        #expect(!d.canSubmit(context(project: nil)))
        d.whereChoice = .chooseFolder
        #expect(!d.canSubmit(context(project: nil)) && d.issues(context(project: nil)).first?.field == .folder)
        d.folderPath = "/tmp"
        #expect(d.canSubmit(context(project: nil)))
        d.whereChoice = .existingWorktree
        #expect(d.issues(context()).first?.field == .worktree)
        d.worktreeID = Self.feature.id
        #expect(d.canSubmit(context()))
    }

    @Test func createFromAcceptsOnlyExistingBranchNamesInSliceOne() {
        var d = draft("x")
        d.createFrom = "#412"
        #expect(d.issues(context()).first?.field == .createFrom)
        d.createFrom = "https://github.com/o/r/pull/9"
        #expect(d.createFromIsReference)
        d.createFrom = "nope"
        #expect(d.issues(context(lookup: GitBranchLookup.none)).first?.message.contains("No branch named") == true)
        #expect(d.issues(context(lookup: nil)).isEmpty, "consulta ainda em andamento não bloqueia")
        #expect(d.issues(context(lookup: .local)).isEmpty)
        d.branchName = "has space"
        #expect(d.issues(context(lookup: .local)).first?.field == .branch)
    }

    @Test func usedWorktreeWarnsWithoutBlocking() {
        var d = draft("x", where: .existingWorktree)
        d.worktreeID = Self.feature.id
        let ctx = context(users: [Self.feature.id: "other session"])
        #expect(d.warning(ctx) == "Another session already uses this worktree.")
        #expect(d.canSubmit(ctx))
        #expect(d.warning(context()) == nil)
    }

    // MARK: Resumo

    @Test func summaryShowsTheCommandThePromptAndTheAbbreviatedPath() {
        var d = draft("Fix the ArcGIS pagination: the last page is dropped when resultOffset lands")
        d.profileID = BuiltinProfiles.claudeSkipPermissions.id
        let text = d.summary(context())
        #expect(text.hasPrefix("claude --dangerously-skip-permissions \"Fix the ArcGIS pagination: the last"))
        #expect(text.contains("…\""))
        #expect(text.hasSuffix(" in ~/orca/workspaces/rti-platform/fix-the-arcgis-pagination-the"))
        d.profileID = BuiltinProfiles.claudePlan.id
        #expect(d.summary(context()).hasPrefix("claude --permission-mode plan "))
        d.provider = .shell
        #expect(d.summary(context()).hasPrefix("zsh -l in "))
    }

    // MARK: Pedido

    @Test func newWorktreeRequestUsesSlugPrefixAndBase() throws {
        let d = draft("fix arcgis pagination")
        let request = try #require(d.request(context()))
        guard case .newWorktree(let spec) = request.target else { Issue.record("not a new worktree"); return }
        #expect(spec.projectID == Self.project.id && spec.fetch == .fetchFirst)
        #expect(spec.source == .newBranch(slug: "fix-arcgis-pagination", prefix: .custom("gabrielgreco1"), baseRef: nil))
        #expect(request.title == "fix arcgis pagination")
        #expect(request.spec.initialPrompt == "fix arcgis pagination")
        let skipFetch = try #require(d.request(context(), fetch: .skipFetch))
        if case .newWorktree(let s) = skipFetch.target { #expect(s.fetch == .skipFetch) }
    }

    @Test func typedBranchBecomesExactAndCreateFromReusesOrBranchesOff() throws {
        var d = draft("x")
        d.branchName = "me/exact"
        if case .newWorktree(let s) = try #require(d.request(context())).target { #expect(s.source == .newBranchExact(name: "me/exact", baseRef: nil)) }
        d.branchName = ""
        d.createFrom = "release"
        if case .newWorktree(let s) = try #require(d.request(context(lookup: .remote))).target { #expect(s.source == .existingBranch("release")) }
        d.reuseBranch = false
        if case .newWorktree(let s) = try #require(d.request(context(lookup: .remote))).target {
            #expect(s.source == .newBranch(slug: "x", prefix: .custom("gabrielgreco1"), baseRef: "release"))
        }
        d.reuseBranch = true
        if case .newWorktree(let s) = try #require(d.request(context(lookup: .remote), forceExistingBranch: "forced")).target {
            #expect(s.source == .existingBranch("forced"))
        }
    }

    @Test func otherTargetsMapToPlacements() throws {
        var d = draft("x", where: .mainCheckout)
        #expect(try #require(d.request(context())).target == .existingCheckout(worktreeID: Self.main.id))
        d.whereChoice = .existingWorktree
        d.worktreeID = Self.feature.id
        #expect(try #require(d.request(context())).target == .existingCheckout(worktreeID: Self.feature.id))
        var clean = ComposerDraft(automaticName: "quiet-harbor")
        #expect(try #require(clean.request(context(project: nil))).target == .cleanFolder(path: "/Users/me/AgentBox/sessions/quiet-harbor", managed: true))
        clean.whereChoice = .chooseFolder
        clean.folderPath = "/tmp/mine"
        #expect(try #require(clean.request(context(project: nil))).target == .cleanFolder(path: "/tmp/mine", managed: false))
        let folderProject = Project(name: "notes", kind: .folder, rootPath: "/tmp/notes")
        var f = ComposerDraft(projectID: folderProject.id, whereChoice: .mainCheckout, automaticName: "a-b")
        f.prompt = "x"
        #expect(try #require(f.request(context(project: folderProject))).target == .projectFolder(projectID: folderProject.id))
    }

    @Test func createMoreKeepsProjectWhereAgentAndProfile() {
        var d = draft("fix it")
        d.provider = .codex
        d.profileID = BuiltinProfiles.codexDefault.id
        d.createFrom = "x"
        d.sessionName = "n"
        d.resetForNext(automaticName: "calm-otter")
        #expect(d.prompt.isEmpty && d.createFrom.isEmpty && d.sessionName.isEmpty && d.automaticName == "calm-otter")
        #expect(d.projectID == Self.project.id && d.whereChoice == .newWorktree && d.provider == .codex && d.profileID == BuiltinProfiles.codexDefault.id)
    }
}
