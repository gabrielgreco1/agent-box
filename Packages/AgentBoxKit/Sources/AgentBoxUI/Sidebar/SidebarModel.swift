import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxStore
import Foundation
import Observation

/// Parte do estado da sidebar que sobrevive ao reinício (`ui_state`, 08 §3): projetos recolhidos, `Show more`,
/// ordenação, filtros, projetos escondidos, sessões recolhidas e a sessão selecionada (03 §2.5, §2.4).
nonisolated struct SidebarPersistedState: Codable, Equatable, Sendable {
    var collapsedProjects: [UUID] = []
    var showMoreOpen: [UUID] = []
    var hiddenProjects: [UUID] = []
    var collapsedSessions: [UUID] = []
    var expandedSummaries: [UUID] = []
    var sort: SidebarSort = .recent
    var filters = SidebarFilters()
    var selectedSession: UUID?
}

/// Modelo observável da sidebar. Só a UI muda estas propriedades (no MainActor); a persistência vai ao Store por tarefas
/// separadas e o Store é a fonte de verdade dos dados (a sidebar observa `snapshots()`, nunca grava a lista).
@MainActor
@Observable
final class SidebarModel {
    static let uiStateKey = "sidebar"

    private(set) var snapshot = StoreSnapshot()
    var query = ""
    private(set) var sort: SidebarSort = .recent
    private(set) var filters = SidebarFilters()
    private(set) var collapsedProjects: Set<UUID> = []
    private(set) var showMoreOpen: Set<UUID> = []
    private(set) var hiddenProjects: Set<UUID> = []
    private(set) var collapsedSessions: Set<UUID> = []
    private(set) var expandedSummaries: Set<UUID> = []
    private(set) var selectedSession: UUID? {
        didSet { if oldValue != selectedSession { onSelectionChange?(selectedSession) } }
    }
    /// Avisa quem mostra o conteúdo da sessão (tabs e panes, T1-14) quando a seleção muda.
    @ObservationIgnored var onSelectionChange: ((UUID?) -> Void)?
    /// Avisa a cada snapshot novo do Store (o workspace carrega a sessão selecionada quando ela chega).
    @ObservationIgnored var onSnapshot: ((StoreSnapshot) -> Void)?
    private(set) var pending: [PendingLaunch] = []
    /// Sessão em edição inline (03 §2.11): no máximo uma.
    private(set) var renamingSession: UUID?
    /// Projeto em edição inline (T1-19): no máximo um, e nunca junto com uma sessão em edição.
    private(set) var renamingProject: UUID?
    /// Último status Git visto por worktree (caminho canônico), alimentado pelo refresh em segundo plano (T1-19).
    private(set) var gitStatus: [String: GitStatus] = [:]
    /// Item com o anel do teclado (`nil` = a lista não tem foco de teclado).
    var keyboardFocus: SidebarItemID?
    /// `true` enquanto o popover Sort and Filter está aberto.
    var filterMenuOpen = false
    /// Incrementa para pedir foco da lista (`⇧⌘0`) ou do campo de busca (`⌘F`).
    private(set) var focusListRequest = 0
    private(set) var focusSearchRequest = 0
    /// Pedido de rolagem até o card ativo (M-211): `nonce` muda a cada pedido, mesmo para o mesmo alvo.
    private(set) var reveal: (id: UUID, nonce: Int)?
    /// Ligada ao Store real em `attach`; nos testes de projeção fica nula.
    private var store: AgentBoxStore?
    private var observation: Task<Void, Never>?
    var clock: () -> Date = { Date() }
    private let log = LogFacade(.app, category: "sidebar")

    /// Chamada quando o usuário cancela uma sessão em criação (o orquestrador de lançamento aborta o trabalho).
    var onCancelPending: (UUID) -> Void = { _ in }
    /// `session.cancelLaunch` com o ID de um terminal em ignição (Cancel do pane): `true` se alguém cuidou.
    @ObservationIgnored var cancelLaunchFallback: (UUID) -> Bool = { _ in false }

    init() {}

    // MARK: Projeção

    var input: SidebarInput {
        SidebarInput(
            snapshot: snapshot, query: query, sort: sort, filters: filters, collapsedProjects: collapsedProjects,
            showMoreOpen: showMoreOpen, hiddenProjects: hiddenProjects, collapsedSessions: collapsedSessions,
            expandedSummaries: expandedSummaries, selectedSession: selectedSession, pending: pending, now: clock())
    }

    var projection: SidebarProjection { SidebarProjector.build(input) }

    func session(_ id: UUID) -> Session? { snapshot.sessions.first { $0.id == id } }
    func project(_ id: UUID) -> Project? { snapshot.projects.first { $0.id == id } }
    func worktree(of session: Session) -> Worktree? { session.worktreeID.flatMap { id in snapshot.worktrees.first { $0.id == id } } }

    // MARK: Store

    /// Liga ao Store: carrega o estado salvo e passa a observar os snapshots (T1-05).
    func attach(store: AgentBoxStore) async {
        self.store = store
        if let saved = try? await store.uiState(Self.uiStateKey, as: SidebarPersistedState.self) { apply(saved) }
        observation?.cancel()
        observation = Task { [weak self] in
            do {
                for try await snap in store.snapshots() { self?.apply(snap) }
            } catch {
                self?.log.error("sidebar observation ended: \(error)")
            }
        }
    }

    func detach() {
        observation?.cancel()
        observation = nil
    }

    /// Aplica um snapshot novo. Mantém a seleção válida: se a sessão selecionada sumiu, a seleção é limpa.
    func apply(_ snap: StoreSnapshot) {
        snapshot = snap
        onSnapshot?(snap)
        if let s = selectedSession, !snap.sessions.contains(where: { $0.id == s }) { selectedSession = nil }
        if let r = renamingSession, !snap.sessions.contains(where: { $0.id == r }) { renamingSession = nil }
        if let r = renamingProject, !snap.projects.contains(where: { $0.id == r }) { renamingProject = nil }
    }

    private func apply(_ saved: SidebarPersistedState) {
        collapsedProjects = Set(saved.collapsedProjects)
        showMoreOpen = Set(saved.showMoreOpen)
        hiddenProjects = Set(saved.hiddenProjects)
        collapsedSessions = Set(saved.collapsedSessions)
        expandedSummaries = Set(saved.expandedSummaries)
        sort = saved.sort
        filters = saved.filters
        selectedSession = saved.selectedSession
    }

    private func persist() {
        guard let store else { return }
        let state = SidebarPersistedState(
            collapsedProjects: Array(collapsedProjects), showMoreOpen: Array(showMoreOpen), hiddenProjects: Array(hiddenProjects),
            collapsedSessions: Array(collapsedSessions), expandedSummaries: Array(expandedSummaries), sort: sort, filters: filters,
            selectedSession: selectedSession)
        Task { try? await store.scheduleUIState(Self.uiStateKey, state) }
    }

    // MARK: Seleção

    /// Seleciona a sessão e a marca como vista. Devolve `false` se ela não existe.
    @discardableResult
    func select(_ id: UUID) -> Bool {
        guard let session = session(id) else { return false }
        selectedSession = id
        keyboardFocus = nil
        focusListRequest += 1
        if session.unread, let store {
            Task { try? await store.markSessionViewed(id: id, at: clock()) }
        }
        persist()
        return true
    }

    /// Sai da sessão que acabou de ser arquivada ou apagada: vai para a vizinha visível (a seguinte, senão a anterior) ou, sem
    /// nenhuma, deixa a seleção vazia (a landing volta).
    func leave(session id: UUID) {
        guard selectedSession == id else { return }
        let order = projection.sessionOrder
        if let i = order.firstIndex(of: id), let next = order.indices.contains(i + 1) ? order[i + 1] : (i > 0 ? order[i - 1] : nil) {
            select(next)
        } else {
            selectedSession = nil
            persist()
        }
    }

    /// Sessão vizinha na ordem visível (⇧⌘↑/↓); sem seleção, o primeiro/último.
    @discardableResult
    func selectNeighbor(_ delta: Int) -> UUID? {
        let order = projection.sessionOrder
        guard !order.isEmpty else { return nil }
        let current = selectedSession.flatMap { order.firstIndex(of: $0) }
        let next: Int
        if let current { next = min(max(current + delta, 0), order.count - 1) } else { next = delta > 0 ? 0 : order.count - 1 }
        select(order[next])
        return order[next]
    }

    /// ⌘1…⌘9: sessão N na ordem visível.
    @discardableResult
    func selectNth(_ n: Int) -> UUID? {
        let order = projection.sessionOrder
        guard order.indices.contains(n - 1) else { return nil }
        select(order[n - 1])
        return order[n - 1]
    }

    // MARK: Projetos

    func toggleProject(_ id: UUID) {
        if collapsedProjects.contains(id) { collapsedProjects.remove(id) } else { collapsedProjects.insert(id) }
        persist()
    }

    func setProject(_ id: UUID, collapsed: Bool) {
        if collapsed { collapsedProjects.insert(id) } else { collapsedProjects.remove(id) }
        persist()
    }

    func showMore(_ projectID: UUID, open: Bool = true) {
        if open { showMoreOpen.insert(projectID) } else { showMoreOpen.remove(projectID) }
        persist()
    }

    func collapseAllSessions(in projectID: UUID) {
        let ids = snapshot.sessions.filter { $0.projectID == projectID }.map(\.id)
        collapsedSessions.formUnion(ids)
        persist()
    }

    func setSession(_ id: UUID, agentsCollapsed: Bool) {
        if agentsCollapsed { collapsedSessions.insert(id) } else { collapsedSessions.remove(id) }
        persist()
    }

    func toggleSummary(_ id: UUID) {
        if expandedSummaries.contains(id) { expandedSummaries.remove(id) } else { expandedSummaries.insert(id) }
        persist()
    }

    func hideProject(_ id: UUID) {
        hiddenProjects.insert(id)
        persist()
    }

    // MARK: Ordenação e filtros

    func setSort(_ value: SidebarSort) {
        sort = value
        persist()
    }

    func setFilter(_ key: String, on: Bool) {
        switch key {
        case "idleOverWeek": filters.idleOverWeek = on
        case "archived": filters.archived = on
        case "hiddenProjects": filters.hiddenProjects = on
        case "mainCheckouts": filters.mainCheckouts = on
        default: return
        }
        persist()
    }

    func resetFilters() {
        sort = .recent
        filters = SidebarFilters()
        persist()
    }

    func clearFilters() {
        filters = SidebarFilters()
        persist()
    }

    // MARK: Renomear (03 §2.11)

    func beginRename(_ id: UUID) -> Bool {
        guard session(id) != nil else { return false }
        renamingProject = nil
        renamingSession = id
        return true
    }

    func cancelRename() { renamingSession = nil }

    /// Confirma o nome. Vazio volta ao nome automático: a pasta (ou a branch) da sessão. Não renomeia pasta nem branch.
    func commitRename(_ text: String) async throws {
        guard let id = renamingSession, var s = session(id) else { return }
        renamingSession = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? automaticName(for: s) : trimmed
        guard name != s.title, let store else { return }
        s.title = name
        // Reflete já; o snapshot do Store confirma em seguida.
        snapshot.sessions = snapshot.sessions.map { $0.id == id ? s : $0 }
        try await store.save(s)
    }

    private func automaticName(for s: Session) -> String {
        if let wt = worktree(of: s), !wt.branch.isEmpty { return wt.branch }
        return URL(fileURLWithPath: s.folderPath).lastPathComponent
    }

    // MARK: Renomear projeto (T1-19)

    func beginRenameProject(_ id: UUID) -> Bool {
        guard project(id) != nil else { return false }
        renamingSession = nil
        renamingProject = id
        return true
    }

    func cancelRenameProject() { renamingProject = nil }

    /// Fecha a edição e devolve o que gravar; reflete o nome já na tela (o snapshot do Store confirma em seguida).
    /// Vazio devolve nome vazio: o `ProjectService` o troca pelo nome da pasta.
    func finishRenameProject(_ text: String) -> (id: UUID, name: String)? {
        guard let id = renamingProject, let p = project(id) else {
            renamingProject = nil
            return nil
        }
        renamingProject = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = trimmed.isEmpty ? URL(fileURLWithPath: p.rootPath).lastPathComponent : trimmed
        snapshot.projects = snapshot.projects.map { $0.id == id ? { var c = $0; c.name = shown; return c }($0) : $0 }
        return (id, trimmed)
    }

    func setGitStatus(_ status: GitStatus, at path: String) { gitStatus[path] = status }

    // MARK: Linhas pendentes (03 §2.9)

    func beginPending(_ launch: PendingLaunch) { pending.append(launch) }

    func advance(pending id: UUID, to phase: PendingLaunch.Phase) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[i].phase = phase
        pending[i].failure = nil
    }

    func fail(pending id: UUID, message: String) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[i].failure = message
    }

    func finish(pending id: UUID) { pending.removeAll { $0.id == id } }

    /// `Cancel` da linha pendente: remove e avisa o orquestrador para abortar. `false` se já terminou.
    @discardableResult
    func cancel(pending id: UUID) -> Bool {
        guard pending.contains(where: { $0.id == id }) else { return false }
        pending.removeAll { $0.id == id }
        onCancelPending(id)
        return true
    }

    // MARK: Foco e rolagem

    func requestListFocus() {
        if keyboardFocus == nil { keyboardFocus = selectedSession.map(SidebarItemID.session) ?? projection.items.first }
        focusListRequest += 1
    }

    func requestSearchFocus() { focusSearchRequest += 1 }

    @discardableResult
    func revealCurrent() -> Bool {
        guard let id = selectedSession else { return false }
        // Se o projeto da sessão está recolhido, expande para o card existir (M-211).
        if let pid = session(id)?.projectID {
            if collapsedProjects.contains(pid) { setProject(pid, collapsed: false) }
            if !projection.projects.contains(where: { $0.id == pid && $0.sessions.contains { $0.id == id } }) { showMore(pid) }
        }
        reveal = (id, (reveal?.nonce ?? 0) + 1)
        return true
    }
}
