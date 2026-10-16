import AppKit
import SwiftUI
import AgentBoxCore

@MainActor public enum WorkspaceServices {
    public static let terminalRuntime = TerminalRuntimeManager()
}

private enum WorkspaceChrome {
    static let sidebar = Color(red: 40.0 / 255, green: 40.0 / 255, blue: 40.0 / 255)
    static let tabBar = Color(red: 25.0 / 255, green: 25.0 / 255, blue: 25.0 / 255)
    static let canvas = Color(red: 39.0 / 255, green: 43.0 / 255, blue: 51.0 / 255)
    static let paneHeader = Color(red: 35.0 / 255, green: 39.0 / 255, blue: 46.0 / 255)
    static let secondary = Color(red: 0.67, green: 0.68, blue: 0.69)
    static let selection = Color(red: 0.20, green: 0.20, blue: 0.20)
}

private enum GitObservation: Equatable, Sendable {
    case loading
    case plainFolder
    case checkout(GitCheckout)
    case failed(String)
}

private struct AgentBoxMark: View {
    var body: some View {
        Group {
            if let url = AppResources.brandURL("agentbox"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "square.split.2x2")
                    .resizable().scaledToFit()
            }
        }
        .frame(width: 17, height: 17)
        .accessibilityLabel("Agent Box")
    }
}

private struct ProviderMark: View {
    let provider: CLIProvider
    let size: CGFloat

    var body: some View {
        Group {
            if provider == .shell {
                Image(systemName: "terminal").font(.system(size: size - 1))
            } else if let url = AppResources.brandURL(provider.rawValue),
                      let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * (provider == .codex ? 0.82 : 1), height: size * (provider == .codex ? 0.82 : 1))
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "terminal").font(.system(size: size - 1))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(provider.displayName)
    }
}

private enum WorkspaceSheet: Identifiable {
    case session
    case terminal(UUID)
    case renameSession(UUID)
    case renameTerminal(UUID)
    case library
    case requests
    case launch(UUID)
    case scrapingLaunch(ScrapingLaunchTarget)
    case settings
    case computer(UUID)
    case worktree(sessionID: UUID, terminalID: UUID)
    case nativeAgent(UUID)

    var id: String {
        switch self {
        case .session: return "session"
        case .terminal(let id): return "terminal-\(id)"
        case .renameSession(let id): return "rename-session-\(id)"
        case .renameTerminal(let id): return "rename-terminal-\(id)"
        case .library: return "library"
        case .requests: return "requests"
        case .launch(let id): return "launch-\(id)"
        case .scrapingLaunch(let target): return "scraping-\(target.assignment.computerID)"
        case .settings: return "settings"
        case .computer(let id): return "computer-\(id)"
        case .worktree(let sessionID, let terminalID): return "worktree-\(sessionID)-\(terminalID)"
        case .nativeAgent(let id): return "native-agent-\(id)"
        }
    }
}

public struct WorkspaceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var runtime = WorkspaceServices.terminalRuntime
    @StateObject private var humanRequests = HumanRequestCenter.shared
    @StateObject private var nativeAgents = NativeAgentMonitor.shared
    @State private var snapshot: WorkspaceSnapshot
    @State private var loadError: String?
    @State private var showLoadError = false
    @State private var saveError: String?
    @State private var sheet: WorkspaceSheet?
    @State private var pendingLaunchAgentID: UUID?
    @State private var pendingScrapingLaunch: ScrapingLaunchTarget?
    @State private var pendingRun: AgentUsageRecord?
    @State private var pendingRequestTarget: HumanRequestTarget?
    @State private var launchBindings: [UUID: AgentLaunchBinding]
    @State private var bindingLoadError: String?
    @State private var bindingsAvailable: Bool
    @State private var collapsedSessions = Set<UUID>()
    @State private var collapsedTerminals = Set<UUID>()
    @State private var sidebarDragStart: Double?
    @State private var splitDragStarts: [UUID: Double] = [:]
    @State private var stopRequested = Set<UUID>()
    @State private var startingTerminalIDs = Set<UUID>()
    @State private var forceStopTerminalID: UUID?
    @State private var search = ""
    @State private var gitObservations: [UUID: GitObservation] = [:]
    @State private var gitRefreshIDs: [UUID: UUID] = [:]
    @State private var showGitDetails = false
    @FocusState private var searchFocused: Bool
    private let repository = WorkspaceRepository()
    private let bindingStore = AgentLaunchBindingStore()

    public init() {
        do {
            _launchBindings = State(initialValue: try AgentLaunchBindingStore().load())
            _bindingLoadError = State(initialValue: nil)
            _bindingsAvailable = State(initialValue: true)
        } catch {
            _launchBindings = State(initialValue: [:])
            _bindingLoadError = State(initialValue: "Os vínculos de lançamento não puderam ser lidos: \(error.localizedDescription). O arquivo foi preservado; agentes salvos não podem ser reiniciados até ser corrigido.")
            _bindingsAvailable = State(initialValue: false)
        }
        do {
            _snapshot = State(initialValue: try WorkspaceRepository().load())
            _loadError = State(initialValue: nil)
            _showLoadError = State(initialValue: false)
        } catch {
            _snapshot = State(initialValue: WorkspaceSnapshot())
            _loadError = State(initialValue: "Não foi possível ler as sessões salvas: \(error.localizedDescription)")
            _showLoadError = State(initialValue: true)
        }
    }

    private var selectedSession: WorkspaceSession? {
        snapshot.sessions.first { $0.id == snapshot.selectedSessionID }
    }

    private var selectedLayout: WorkspaceLayout? {
        guard let selectedSession else { return nil }
        return snapshot.layouts.first { $0.sessionID == selectedSession.id }
    }

    private var focusedTerminal: TerminalRecord? {
        guard let selectedSession, let id = selectedLayout?.focusedTerminalID else { return nil }
        return selectedSession.terminals.first { $0.id == id }
    }

    public var body: some View {
        HStack(spacing: 0) {
            if !snapshot.sidebarCollapsed {
                sidebar
                    .frame(width: CGFloat(snapshot.sidebarWidth))
                sidebarDivider
            }
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WorkspaceChrome.canvas)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: snapshot.sidebarCollapsed)
        .foregroundStyle(.white)
        .font(.system(size: 13))
        .disabled(loadError != nil)
        .frame(minWidth: 1000, minHeight: 650)
        .onAppear {
            RuntimeLifecycle.shared.attach(runtime)
            refreshMissingGit()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if let selectedSession { selectedSession.terminals.forEach(refreshGit) }
        }
        .onChange(of: snapshot.sessions) { _, _ in refreshMissingGit() }
        .onChange(of: snapshot) { _, value in
            guard loadError == nil else { return }
            do { try repository.save(value); saveError = nil }
            catch { saveError = error.localizedDescription }
        }
        .onChange(of: runtime.processStates) { _, states in
            stopRequested = Set(stopRequested.filter { id in
                if case .running? = states[id] { return true }
                return false
            })
        }
        .sheet(item: $sheet, onDismiss: handleSheetDismissal) { route in
            switch route {
            case .session:
                SessionEditor { title in createSession(title: title) }
            case .terminal(let sessionID):
                TerminalEditor(defaultDirectory: snapshot.sessions.first(where: { $0.id == sessionID })?.terminals.last?.cwd ?? NSHomeDirectory()) { title, provider, cwd in
                    createTerminal(in: sessionID, title: title, provider: provider, cwd: cwd)
                }
            case .renameSession(let id):
                RenameEditor(title: "Renomear sessão", current: snapshot.sessions.first(where: { $0.id == id })?.title ?? "") { name in
                    guard let index = snapshot.sessions.firstIndex(where: { $0.id == id }) else { return }
                    snapshot.sessions[index].title = name
                }
            case .renameTerminal(let id):
                RenameEditor(title: "Renomear terminal", current: snapshot.sessions.flatMap(\.terminals).first(where: { $0.id == id })?.title ?? "") { name in
                    for sessionIndex in snapshot.sessions.indices {
                        if let terminalIndex = snapshot.sessions[sessionIndex].terminals.firstIndex(where: { $0.id == id }) {
                            snapshot.sessions[sessionIndex].terminals[terminalIndex].title = name
                            break
                        }
                    }
                }
            case .library:
                LibraryView(onLaunch: { pendingLaunchAgentID = $0; sheet = nil },
                            onOpenRun: { run in
                                guard let sessionID = run.sessionID,
                                      snapshot.sessions.contains(where: { $0.id == sessionID && $0.terminals.contains(where: { $0.id == run.terminalID }) }) else { return false }
                                pendingRun = run
                                sheet = nil
                                return true
                            })
            case .requests:
                HumanRequestsView(onOpenTarget: { target in
                    guard snapshot.sessions.contains(where: {
                        $0.id == target.sessionID && $0.terminals.contains(where: { $0.id == target.terminalID })
                    }) else { return false }
                    pendingRequestTarget = target
                    sheet = nil
                    return true
                })
            case .launch(let agentID):
                AgentLaunchView(agentID: agentID, sessions: snapshot.sessions,
                                selectedSessionID: snapshot.selectedSessionID,
                                onLaunch: launchSavedAgent)
            case .scrapingLaunch(let target):
                AgentLaunchView(agentID: target.assignment.defaultAgentDefinitionID, sessions: snapshot.sessions,
                                selectedSessionID: target.sessionID, scrapingTarget: target,
                                onLaunch: launchSavedAgent)
            case .settings:
                AppSettingsView()
            case .computer(let id):
                if let session = snapshot.sessions.first(where: { $0.terminals.contains(where: { $0.id == id }) }),
                   let terminal = session.terminals.first(where: { $0.id == id }) {
                    ComputerPanel(terminalID: id, context: computerPolicyContext(for: terminal, in: session.id),
                                  onReviewAgent: { assignment in
                                      snapshot.selectedSessionID = session.id
                                      pendingScrapingLaunch = ScrapingLaunchTarget(assignment: assignment, sessionID: session.id, terminal: terminal)
                                      sheet = nil
                                  })
                } else {
                    Text("O terminal não está mais disponível.").padding(20)
                }
            case .worktree(let sessionID, let terminalID):
                if let terminal = snapshot.sessions.first(where: { $0.id == sessionID })?.terminals.first(where: { $0.id == terminalID }),
                   let observedCheckout = checkout(for: terminalID) {
                    WorktreeEditor(checkout: observedCheckout) { reference, branch, destination in
                        try await createWorktree(from: terminal, in: sessionID, checkout: observedCheckout,
                                                 reference: reference, branch: branch, destination: destination)
                    }
                } else {
                    Text("O checkout não está mais disponível.").padding(20)
                }
            case .nativeAgent(let id):
                nativeAgentDetails(id)
            }
        }
        .alert("Erro no workspace", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .alert("Arquivo de sessões indisponível", isPresented: $showLoadError) {
            Button("OK") { }
        } message: { Text((loadError ?? "") + " O arquivo foi preservado; corrija-o e reabra o aplicativo.") }
        .alert("Vínculos de lançamento indisponíveis", isPresented: Binding(
            get: { bindingLoadError != nil }, set: { if !$0 { bindingLoadError = nil } }
        )) { Button("OK") { bindingLoadError = nil } }
        message: { Text(bindingLoadError ?? "") }
        .confirmationDialog("Forçar encerramento deste terminal?", isPresented: Binding(
            get: { forceStopTerminalID != nil }, set: { if !$0 { forceStopTerminalID = nil } }
        )) {
            Button("Forçar encerramento", role: .destructive) {
                if let id = forceStopTerminalID {
                    AgentComputerAccess.shared.stop(terminalID: id)
                    runtime.forceStop(id)
                }
                forceStopTerminalID = nil
            }
            Button("Cancelar", role: .cancel) { forceStopTerminalID = nil }
        } message: {
            Text("O processo deste terminal e seus filhos receberão encerramento forçado.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AgentBoxMark()
                Text("Agent Box").font(.system(size: 13, weight: .medium))
                Spacer()
                Button { sheet = .session } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("Nova sessão")
                    .accessibilityLabel("Nova sessão")
            }
            .padding(.horizontal, 12)
            .frame(height: 42)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(WorkspaceChrome.secondary)
                TextField("Buscar sessões", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(WorkspaceChrome.selection)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(snapshot.sessions.filter(matchesSearch)) { session in
                        sessionRow(session)
                        if !collapsedSessions.contains(session.id) {
                            ForEach(session.terminals) { terminal in
                                terminalRow(terminal, sessionID: session.id)
                                if !collapsedTerminals.contains(terminal.id) {
                                    ForEach(nativeChildren(for: terminal.id)) { child in
                                        nativeChildRow(child)
                                    }
                                }
                            }
                            Button { sheet = .terminal(session.id) } label: {
                                Label("Novo terminal", systemImage: "plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WorkspaceChrome.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 38)
                                    .frame(height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if snapshot.sessions.isEmpty {
                        Text("Nenhuma sessão")
                            .foregroundStyle(WorkspaceChrome.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 6)
            }

            if let errorText = nativeAgents.errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            HStack {
                Button { sheet = .library } label: { Label("Biblioteca", systemImage: "books.vertical") }
                Spacer()
                Button { sheet = .requests } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bell")
                        if humanRequests.pendingCount > 0 { HumanRequestBadge() }
                    }
                }
                .help("Pedidos aguardando você")
                .accessibilityLabel("Pedidos aguardando você")
                Button { sheet = .settings } label: { Image(systemName: "gearshape") }
                    .help("Configurações")
                    .accessibilityLabel("Configurações")
                    .keyboardShortcut(",", modifiers: .command)
            }
            .buttonStyle(.plain)
            .foregroundStyle(WorkspaceChrome.secondary)
            .padding(.horizontal, 12)
            .frame(height: 40)
        }
        .background(WorkspaceChrome.sidebar)
    }

    private func matchesSearch(_ session: WorkspaceSession) -> Bool {
        search.isEmpty || session.title.localizedCaseInsensitiveContains(search) ||
        session.terminals.contains { terminal in
            terminal.title.localizedCaseInsensitiveContains(search) || nativeChildren(for: terminal.id).contains {
                ($0.nativeAgentType ?? "").localizedCaseInsensitiveContains(search) ||
                ($0.nativeAgentID ?? "").localizedCaseInsensitiveContains(search)
            }
        }
    }

    private func sessionRow(_ session: WorkspaceSession) -> some View {
        HStack(spacing: 4) {
            Button {
                if collapsedSessions.contains(session.id) { collapsedSessions.remove(session.id) }
                else { collapsedSessions.insert(session.id) }
            } label: {
                Image(systemName: collapsedSessions.contains(session.id) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 16, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapsedSessions.contains(session.id) ? "Expandir \(session.title)" : "Recolher \(session.title)")
            Button {
                snapshot.selectedSessionID = session.id
            } label: {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.system(size: 13, weight: snapshot.selectedSessionID == session.id ? .medium : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let summary = sessionBranchSummary(session) {
                        Text(summary)
                            .font(.system(size: 10))
                            .foregroundStyle(WorkspaceChrome.secondary)
                            .lineLimit(1)
                    }
                    HumanRequestBadge(sessionID: session.id)
                }
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Renomear") { sheet = .renameSession(session.id) }
                Button("Novo terminal") { sheet = .terminal(session.id) }
            }
        }
        .padding(.horizontal, 6)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .contain)
    }

    private func terminalRow(_ terminal: TerminalRecord, sessionID: UUID) -> some View {
        let focused = snapshot.selectedSessionID == sessionID && selectedLayout?.focusedTerminalID == terminal.id
        let hasChildren = !nativeChildren(for: terminal.id).isEmpty
        return HStack(spacing: 0) {
            if hasChildren {
                Button {
                    if collapsedTerminals.contains(terminal.id) { collapsedTerminals.remove(terminal.id) }
                    else { collapsedTerminals.insert(terminal.id) }
                } label: {
                    Image(systemName: collapsedTerminals.contains(terminal.id) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 16, height: 28)
                }
                .accessibilityLabel(collapsedTerminals.contains(terminal.id) ?
                    "Expandir subagentes de \(terminal.title)" : "Recolher subagentes de \(terminal.title)")
            } else {
                Color.clear.frame(width: 16, height: 28)
            }
            Button {
                selectTerminal(terminal.id, in: sessionID)
            } label: {
                HStack(spacing: 8) {
                    ProviderMark(provider: terminal.provider, size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(terminal.title).lineLimit(1)
                            Spacer(minLength: 0)
                            HumanRequestBadge(terminalID: terminal.id)
                            statusIcon(for: terminal.id)
                        }
                        if let checkout = checkout(for: terminal.id) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                Text(gitBranchLabel(checkout)).lineLimit(1)
                                if checkout.isDirty {
                                    Text("• Alterações").foregroundStyle(Color.orange)
                                }
                                if let remote = checkout.remote {
                                    Text("· \(remote.displayName)").lineLimit(1)
                                }
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(WorkspaceChrome.secondary)
                        }
                    }
                }
                .padding(.trailing, 7)
                .frame(height: checkout(for: terminal.id) == nil ? 30 : 42)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 11)
        .buttonStyle(.plain)
        .background(focused ? WorkspaceChrome.selection : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contextMenu {
            Button("Renomear") { sheet = .renameTerminal(terminal.id) }
            Button("Mostrar em pane") {
                selectTerminal(terminal.id, in: sessionID)
            }
            Button("Dividir à direita") { split(terminal.id, axis: .horizontal, sessionID: sessionID) }
            Button("Dividir abaixo") { split(terminal.id, axis: .vertical, sessionID: sessionID) }
            Button("Atualizar Git") { refreshGit(for: terminal) }
            Button("Reautorizar pasta…") { reauthorizeDirectory(for: terminal) }
            if checkout(for: terminal.id) != nil {
                Button("Criar worktree…") { sheet = .worktree(sessionID: sessionID, terminalID: terminal.id) }
            }
            Divider()
            Button("Encerrar processo") { requestStop(terminal.id) }
            if stopRequested.contains(terminal.id) {
                Button("Forçar encerramento…") { forceStopTerminalID = terminal.id }
            }
        }
    }

    private func nativeChildren(for terminalID: UUID) -> [AgentRunRecord] {
        nativeAgents.runs.filter { $0.kind == .nativeSubagent && $0.parentTerminalID == terminalID }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func nativeChildStatus(_ child: AgentRunRecord) -> String {
        if child.status == .finished { return "Concluído" }
        guard let parentID = child.parentRunID,
              let parent = nativeAgents.runs.first(where: { $0.id == parentID && $0.kind == .terminal }),
              parent.status == .running,
              case .running(let pid) = runtime.state(for: child.terminalID),
              parent.processID == pid else { return "Último evento: iniciado" }
        return "Em execução"
    }

    private func nativeChildRow(_ child: AgentRunRecord) -> some View {
        Button { sheet = .nativeAgent(child.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 10))
                Text(child.nativeAgentType ?? "Subagente Claude").lineLimit(1)
                Text(String((child.nativeAgentID ?? "").prefix(8)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(WorkspaceChrome.secondary)
                Spacer(minLength: 0)
                Text(nativeChildStatus(child))
                    .font(.system(size: 10)).foregroundStyle(WorkspaceChrome.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 43)
            .padding(.trailing, 7)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Subagente nativo \(child.nativeAgentType ?? "Claude"), \(nativeChildStatus(child))")
    }

    private func nativeAgentDetails(_ id: UUID) -> some View {
        Group {
            if let child = nativeAgents.runs.first(where: { $0.id == id && $0.kind == .nativeSubagent }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Subagente nativo").font(.system(size: 16, weight: .medium))
                    LabeledContent("Tipo", value: child.nativeAgentType ?? "Desconhecido")
                    LabeledContent("ID nativo", value: child.nativeAgentID ?? "Indisponível")
                    LabeledContent("Estado observado", value: nativeChildStatus(child))
                    LabeledContent("Origem", value: child.nativeHookSource?.rawValue ?? "Indisponível")
                    LabeledContent("Iniciado", value: child.startedAt.formatted(date: .abbreviated, time: .standard))
                    if let endedAt = child.endedAt {
                        LabeledContent("Último fim observado", value: endedAt.formatted(date: .abbreviated, time: .standard))
                    }
                    Text("Este é um registro de eventos nativos do CLI. O subagente compartilha o terminal pai e não possui PTY independente.")
                        .font(.system(size: 11)).foregroundStyle(WorkspaceChrome.secondary)
                    HStack {
                        Spacer()
                        Button("Mostrar terminal pai") {
                            if let session = snapshot.sessions.first(where: { $0.terminals.contains(where: { $0.id == child.terminalID }) }) {
                                selectTerminal(child.terminalID, in: session.id)
                            }
                            sheet = nil
                        }
                    }
                }
                .font(.system(size: 13))
                .padding(20)
                .frame(width: 480)
            } else {
                Text("Este registro de subagente não está mais disponível.").padding(20)
            }
        }
    }

    @ViewBuilder private func statusIcon(for id: UUID) -> some View {
        switch runtime.state(for: id) {
        case .running:
            Circle().fill(Color.green).frame(width: 6, height: 6).accessibilityLabel("Em execução")
        case .starting:
            ProgressView().controlSize(.mini).accessibilityLabel("Iniciando")
        case .failed:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.red).accessibilityLabel("Falhou")
        case .exited:
            Image(systemName: "checkmark.circle").foregroundStyle(WorkspaceChrome.secondary).accessibilityLabel("Encerrado")
        case .idle:
            EmptyView()
        }
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(WorkspaceChrome.sidebar)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hover in if hover { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if sidebarDragStart == nil { sidebarDragStart = snapshot.sidebarWidth }
                    snapshot.sidebarWidth = min(480, max(224, (sidebarDragStart ?? 288) + Double(value.translation.width)))
                }
                .onEnded { _ in sidebarDragStart = nil })
            .onTapGesture(count: 2) { snapshot.sidebarWidth = 288 }
            .accessibilityLabel("Largura da barra lateral")
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            toolbar
            if let selectedSession {
                sessionTabs(selectedSession)
                if selectedSession.terminals.isEmpty {
                    emptySession(selectedSession)
                } else if let node = selectedLayout?.root {
                    GeometryReader { geometry in
                        if geometry.size.width < CGFloat(node.terminalIDs.count) * 260,
                           let focusedID = selectedLayout?.focusedTerminalID,
                           let focusedTerminal = selectedSession.terminals.first(where: { $0.id == focusedID }) {
                            terminalPane(focusedTerminal, sessionID: selectedSession.id, showHeader: false)
                        } else {
                            paneNode(node, in: selectedSession, showPaneHeaders: node.terminalIDs.count > 1)
                        }
                    }
                } else {
                    emptyPane(selectedSession)
                }
            } else {
                emptyWorkspace
            }
        }
        .background(WorkspaceChrome.canvas)
    }


    private func sessionTabs(_ session: WorkspaceSession) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(session.terminals) { terminal in
                    let focused = selectedLayout?.focusedTerminalID == terminal.id
                    Button {
                        selectTerminal(terminal.id, in: session.id)
                    } label: {
                        HStack(spacing: 6) {
                            ProviderMark(provider: terminal.provider, size: 14)
                            Text(terminal.title).lineLimit(1)
                        }
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(focused ? Color.white : WorkspaceChrome.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 35)
                        .background(focused ? WorkspaceChrome.canvas : WorkspaceChrome.tabBar)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 35)
        .background(WorkspaceChrome.tabBar)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { snapshot.sidebarCollapsed.toggle() } label: {
                Image(systemName: "sidebar.left").frame(width: 20)
            }
            .help(snapshot.sidebarCollapsed ? "Mostrar barra lateral" : "Recolher barra lateral")
            .accessibilityLabel(snapshot.sidebarCollapsed ? "Mostrar barra lateral" : "Recolher barra lateral")
            .keyboardShortcut("b", modifiers: .command)
            .buttonStyle(.plain)

            if let selectedSession {
                Text(selectedSession.title).font(.system(size: 13, weight: .regular)).lineLimit(1)
                Spacer()
                if let terminal = focusedTerminal {
                    Text(statusText(for: terminal.id))
                        .font(.system(size: 11))
                        .foregroundStyle(WorkspaceChrome.secondary)
                        .lineLimit(1)
                    gitStatusButton(for: terminal, sessionID: selectedSession.id)
                    runtimeButton(for: terminal)
                    Button { sheet = .computer(terminal.id) } label: { Image(systemName: "desktopcomputer") }
                        .help("Computador deste terminal")
                        .accessibilityLabel("Computador de \(terminal.title)")
                }
                if let focus = selectedLayout?.focusedTerminalID {
                    Button { split(focus, axis: .horizontal, sessionID: selectedSession.id) } label: { Image(systemName: "rectangle.split.2x1") }
                        .help("Dividir à direita")
                        .accessibilityLabel("Dividir à direita")
                        .keyboardShortcut("d", modifiers: .command)
                    Button { split(focus, axis: .vertical, sessionID: selectedSession.id) } label: { Image(systemName: "rectangle.split.1x2") }
                        .help("Dividir abaixo")
                        .accessibilityLabel("Dividir abaixo")
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                }
                Button { sheet = .terminal(selectedSession.id) } label: { Image(systemName: "plus") }
                    .help("Novo terminal")
                    .accessibilityLabel("Novo terminal")
                    .keyboardShortcut("t", modifiers: .command)
            } else {
                Text("Sessões").foregroundStyle(WorkspaceChrome.secondary)
                Spacer()
                Button { sheet = .session } label: { Image(systemName: "plus") }
                    .help("Nova sessão")
                    .accessibilityLabel("Nova sessão")
            }
            Menu {
                Button("Nova sessão") { sheet = .session }
                    .keyboardShortcut("n", modifiers: .command)
                if let selectedSession, let focusedTerminal {
                    Button("Fechar pane focado") {
                        snapshot.updateLayout(for: selectedSession.id) { $0.closePane(focusedTerminal.id) }
                    }
                }
                Button("Biblioteca") { sheet = .library }
                Button("Pedidos aguardando você") { sheet = .requests }
                Button("Configurações") { sheet = .settings }
                Divider()
                Button("Buscar sessões") {
                    if snapshot.sidebarCollapsed { snapshot.sidebarCollapsed = false }
                    searchFocused = true
                }
                Button("Estreitar barra lateral") { snapshot.sidebarWidth = max(224, snapshot.sidebarWidth - 24) }
                    .keyboardShortcut("[", modifiers: [.command, .option])
                Button("Alargar barra lateral") { snapshot.sidebarWidth = min(480, snapshot.sidebarWidth + 24) }
                    .keyboardShortcut("]", modifiers: [.command, .option])
            } label: { Image(systemName: "ellipsis") }
                .help("Mais opções")
                .accessibilityLabel("Mais opções")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(WorkspaceChrome.tabBar)
    }

    @ViewBuilder private func runtimeButton(for terminal: TerminalRecord) -> some View {
        switch runtime.state(for: terminal.id) {
        case .idle, .exited, .failed:
            Button {
                startTerminal(terminal)
            } label: { Image(systemName: "play.fill") }
                .help("Iniciar \(terminal.provider.displayName)")
                .accessibilityLabel("Iniciar \(terminal.title)")
        case .starting, .running:
            if stopRequested.contains(terminal.id) {
                Button { forceStopTerminalID = terminal.id } label: { Image(systemName: "xmark.octagon") }
                    .help("Forçar encerramento")
                    .accessibilityLabel("Forçar encerramento de \(terminal.title)")
            } else {
                Button { requestStop(terminal.id) } label: { Image(systemName: "stop.fill") }
                    .help("Encerrar processo")
                    .accessibilityLabel("Encerrar processo de \(terminal.title)")
            }
        }
    }

    private func gitStatusButton(for terminal: TerminalRecord, sessionID: UUID) -> some View {
        Button { showGitDetails.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: checkout(for: terminal.id) == nil ? "folder" : "arrow.triangle.branch")
                if let checkout = checkout(for: terminal.id) {
                    Text(gitBranchLabel(checkout)).lineLimit(1).frame(maxWidth: 94)
                    if checkout.isDirty { Circle().fill(Color.orange).frame(width: 5, height: 5) }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(WorkspaceChrome.secondary)
        }
        .help("Git e pasta de \(terminal.title)")
        .accessibilityLabel("Git e pasta de \(terminal.title)")
        .popover(isPresented: $showGitDetails, arrowEdge: .bottom) {
            gitDetails(for: terminal, sessionID: sessionID)
        }
    }

    private func gitDetails(for terminal: TerminalRecord, sessionID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Git e pasta").font(.system(size: 13, weight: .medium))
            Text(terminal.cwd).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled)
            switch gitObservations[terminal.id] {
            case .none, .some(.loading):
                Text("Verificando Git…").foregroundStyle(.secondary)
            case .some(.plainFolder):
                Text("Pasta comum · sem repositório Git").foregroundStyle(.secondary)
            case .some(.failed(let detail)):
                Text(detail).foregroundStyle(.red)
            case .some(.checkout(let checkout)):
                Text("Branch: \(gitBranchLabel(checkout))")
                Text(checkout.isDirty ? "Alterações locais presentes" : "Checkout limpo")
                    .foregroundStyle(checkout.isDirty ? Color.orange : WorkspaceChrome.secondary)
                if let remote = checkout.remote {
                    Text("Remote: \(remote.displayName)").textSelection(.enabled)
                    if let webURL = remote.webURL {
                        Link("Abrir repositório", destination: webURL)
                    }
                } else {
                    Text("Nenhum remote configurado").foregroundStyle(.secondary)
                }
                Button("Criar worktree…") {
                    showGitDetails = false
                    sheet = .worktree(sessionID: sessionID, terminalID: terminal.id)
                }
            }
            HStack {
                Spacer()
                Button("Atualizar") { refreshGit(for: terminal) }
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 310, alignment: .leading)
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.split.2x2").font(.system(size: 28, weight: .ultraLight))
            Text("Nenhuma sessão aberta").font(.system(size: 15, weight: .medium))
            Text("Crie uma sessão para organizar terminais Claude Code, Codex, OpenCode ou shell.")
                .foregroundStyle(WorkspaceChrome.secondary)
                .multilineTextAlignment(.center)
            Button("Nova sessão") { sheet = .session }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptySession(_ session: WorkspaceSession) -> some View {
        VStack(spacing: 10) {
            Text("Esta sessão ainda não tem terminais").font(.system(size: 15, weight: .medium))
            Text("Escolha um CLI ou shell e a pasta de trabalho.").foregroundStyle(WorkspaceChrome.secondary)
            Button("Novo terminal") { sheet = .terminal(session.id) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyPane(_ session: WorkspaceSession) -> some View {
        VStack(spacing: 10) {
            Text("Selecione um terminal na barra lateral").foregroundStyle(WorkspaceChrome.secondary)
            if let first = session.terminals.first {
                Button("Abrir \(first.title)") { selectTerminal(first.id, in: session.id) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paneNode(_ node: WorkspaceNode, in session: WorkspaceSession, showPaneHeaders: Bool) -> AnyView {
        switch node {
        case .terminal(let id):
            guard let terminal = session.terminals.first(where: { $0.id == id }) else { return AnyView(EmptyView()) }
            return AnyView(terminalPane(terminal, sessionID: session.id, showHeader: showPaneHeaders))
        case .split(let id, let axis, let fraction, let first, let second):
            return AnyView(GeometryReader { geometry in
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        paneNode(first, in: session, showPaneHeaders: showPaneHeaders).frame(width: max(0, geometry.size.width * CGFloat(fraction) - 2))
                        splitDivider(id: id, axis: axis, extent: geometry.size.width, fraction: fraction, sessionID: session.id)
                        paneNode(second, in: session, showPaneHeaders: showPaneHeaders).frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        paneNode(first, in: session, showPaneHeaders: showPaneHeaders).frame(height: max(0, geometry.size.height * CGFloat(fraction) - 2))
                        splitDivider(id: id, axis: axis, extent: geometry.size.height, fraction: fraction, sessionID: session.id)
                        paneNode(second, in: session, showPaneHeaders: showPaneHeaders).frame(maxHeight: .infinity)
                    }
                }
            })
        }
    }

    private func splitDivider(id: UUID, axis: SplitAxis, extent: CGFloat, fraction: Double, sessionID: UUID) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: axis == .horizontal ? 4 : nil, height: axis == .vertical ? 4 : nil)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard extent > 0 else { return }
                if splitDragStarts[id] == nil { splitDragStarts[id] = fraction }
                let delta = axis == .horizontal ? value.translation.width : value.translation.height
                snapshot.updateLayout(for: sessionID) { layout in
                    layout.root = layout.root?.settingFraction((splitDragStarts[id] ?? fraction) + Double(delta / extent), for: id)
                }
            }.onEnded { _ in splitDragStarts[id] = nil })
            .onTapGesture(count: 2) {
                snapshot.updateLayout(for: sessionID) { $0.root = $0.root?.settingFraction(0.5, for: id) }
            }
    }

    private func terminalPane(_ terminal: TerminalRecord, sessionID: UUID, showHeader: Bool) -> some View {
        let focused = selectedLayout?.focusedTerminalID == terminal.id
        return VStack(spacing: 0) {
            if showHeader {
                HStack(spacing: 7) {
                    ProviderMark(provider: terminal.provider, size: 14)
                    Text(terminal.title).font(.system(size: 13, weight: .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                    statusIcon(for: terminal.id)
                    Button {
                        snapshot.updateLayout(for: sessionID) { $0.closePane(terminal.id) }
                    } label: { Image(systemName: "xmark") }
                        .help("Fechar pane")
                        .accessibilityLabel("Fechar pane de \(terminal.title)")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(focused ? WorkspaceChrome.paneHeader : WorkspaceChrome.canvas)
            }
            Group {
                switch runtime.state(for: terminal.id) {
                case .idle:
                    VStack(spacing: 8) {
                        Text("Pronto para iniciar \(terminal.provider.displayName)")
                        Text(terminal.cwd).font(.system(size: 11, design: .monospaced)).foregroundStyle(WorkspaceChrome.secondary).lineLimit(2)
                        Text("Sessões restauradas aguardam início manual.")
                            .font(.system(size: 11)).foregroundStyle(WorkspaceChrome.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    VStack(spacing: 8) {
                        Text("Não foi possível iniciar o terminal")
                        Text(message).foregroundStyle(WorkspaceChrome.secondary).multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    TerminalSurface(terminal: terminal, runtime: runtime, isFocused: focused)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WorkspaceChrome.canvas)
        .contentShape(Rectangle())
        .onTapGesture {
            snapshot.updateLayout(for: sessionID) { $0.focusedTerminalID = terminal.id }
            runtime.focus(terminal.id)
        }
    }

    private func statusText(for id: UUID) -> String {
        switch runtime.state(for: id) {
        case .idle: return "Parado"
        case .starting: return "Iniciando"
        case .running(let pid): return "PID \(pid)"
        case .exited(let code): return code.map { "Saiu · \($0)" } ?? "Encerrado"
        case .failed: return "Falhou"
        }
    }

    private func refreshMissingGit() {
        for terminal in snapshot.sessions.flatMap(\.terminals) where gitObservations[terminal.id] == nil {
            refreshGit(for: terminal)
        }
    }

    private func refreshGit(for terminal: TerminalRecord) {
        gitObservations[terminal.id] = .loading
        let terminalID = terminal.id
        let refreshID = UUID()
        gitRefreshIDs[terminalID] = refreshID
        let directory = URL(fileURLWithPath: terminal.cwd, isDirectory: true)
        do { try WorkspaceDirectoryAccess.shared.activate(terminal.cwd) }
        catch {
            gitObservations[terminal.id] = .failed(error.localizedDescription)
            return
        }
        Task {
            let observation = await Task.detached(priority: .utility) { () -> GitObservation in
                do {
                    if let checkout = try GitWorkspaceInspector<GitProcessRunner>().inspect(at: directory) {
                        return .checkout(checkout)
                    }
                    return .plainFolder
                } catch {
                    return .failed(error.localizedDescription)
                }
            }.value
            guard snapshot.sessions.contains(where: { $0.terminals.contains(where: { $0.id == terminalID }) }) else { return }
            guard gitRefreshIDs[terminalID] == refreshID else { return }
            gitObservations[terminalID] = observation
        }
    }

    private func gitBranchLabel(_ checkout: GitCheckout) -> String {
        checkout.branch ?? "HEAD destacado"
    }

    private func checkout(for terminalID: UUID) -> GitCheckout? {
        guard case .checkout(let checkout)? = gitObservations[terminalID] else { return nil }
        return checkout
    }

    private func computerPolicyContext(for terminal: TerminalRecord, in sessionID: UUID) -> ComputerPolicyContext {
        let directory = checkout(for: terminal.id)?.rootURL ?? URL(fileURLWithPath: terminal.cwd, isDirectory: true)
        let projectID = directory.resolvingSymlinksInPath().standardizedFileURL.path
        return ComputerPolicyContext(terminalID: terminal.id, projectID: projectID,
                                     sessionID: sessionID, agentID: terminal.agentDefinitionID)
    }

    private func sessionBranchSummary(_ session: WorkspaceSession) -> String? {
        guard !session.terminals.isEmpty,
              session.terminals.allSatisfy({ gitObservations[$0.id] != nil }),
              !session.terminals.contains(where: {
                  if case .loading? = gitObservations[$0.id] { return true }
                  if case .failed(_)? = gitObservations[$0.id] { return true }
                  return false
              }) else { return nil }
        let branches = Set(session.terminals.compactMap { terminal -> String? in
            guard let observedCheckout = checkout(for: terminal.id) else { return nil }
            return gitBranchLabel(observedCheckout)
        })
        if branches.count > 1 { return "Várias branches" }
        return branches.first
    }

    private func createWorktree(from terminal: TerminalRecord, in sessionID: UUID,
                                checkout: GitCheckout, reference: String, branch: String,
                                destination: URL) async throws {
        try WorkspaceDirectoryAccess.shared.activate(checkout.rootURL.path)
        try WorkspaceDirectoryAccess.shared.activate(destination.deletingLastPathComponent().path)
        let repositoryURL = checkout.rootURL
        let created = try await Task.detached(priority: .userInitiated) {
            try GitWorktreeManager<GitProcessRunner>().createWorktree(
                repositoryURL: repositoryURL, reference: reference,
                newBranch: branch, destinationURL: destination)
        }.value
        createTerminal(in: sessionID, title: branch, provider: terminal.provider, cwd: created.rootURL.path)
        if let newest = snapshot.sessions.first(where: { $0.id == sessionID })?.terminals.last {
            gitObservations[newest.id] = .checkout(created)
        }
        refreshGit(for: terminal)
    }

    private func createSession(title: String) {
        let session = WorkspaceSession(title: title)
        snapshot.sessions.append(session)
        snapshot.selectedSessionID = session.id
        snapshot.layouts.append(WorkspaceLayout(sessionID: session.id))
    }

    private func selectTerminal(_ id: UUID, in sessionID: UUID) {
        showGitDetails = false
        snapshot.selectedSessionID = sessionID
        snapshot.updateLayout(for: sessionID) { $0.show(id) }
        runtime.focus(id)
        if let terminal = snapshot.sessions.first(where: { $0.id == sessionID })?.terminals.first(where: { $0.id == id }) {
            refreshGit(for: terminal)
        }
    }

    private func handleSheetDismissal() {
        if let target = pendingRequestTarget {
            pendingRequestTarget = nil
            selectTerminal(target.terminalID, in: target.sessionID)
        } else if let run = pendingRun, let sessionID = run.sessionID {
            pendingRun = nil
            selectTerminal(run.terminalID, in: sessionID)
        } else if let target = pendingScrapingLaunch {
            pendingScrapingLaunch = nil
            sheet = .scrapingLaunch(target)
        } else if let agentID = pendingLaunchAgentID {
            pendingLaunchAgentID = nil
            sheet = .launch(agentID)
        }
    }

    private func launchSavedAgent(_ request: AgentLaunchRequest) async throws {
        guard bindingsAvailable else { throw AgentLaunchError.invalidBinding }
        guard let terminal = request.materialized.terminal,
              let binding = request.materialized.binding,
              terminal.id == binding.terminalID,
              terminal.agentDefinitionID == request.prepared.agentID else {
            throw AgentLaunchError.contextNotActive
        }
        guard startingTerminalIDs.insert(terminal.id).inserted else {
            throw LibraryError.invalid("Este terminal já está iniciando. Aguarde a tentativa atual.")
        }
        defer { startingTerminalIDs.remove(terminal.id) }
        if let target = request.scrapingTarget {
            // Docker discovery performs no token read and does not start a container.
            let computer = try await Task.detached(priority: .utility) {
                try BrowserComputerService(runner: DockerProcessRunner(), tokens: KeychainBrowserComputerTokenStore())
                    .computer(for: target.terminal.id)
            }.value
            guard computer?.id == target.assignment.computerID,
                  request.sessionID == target.sessionID, request.newSessionTitle == nil else {
                throw LibraryError.invalid("A box não pertence mais ao terminal revisado.")
            }
            let current = snapshot.sessions.first(where: { $0.id == target.sessionID })?.terminals.first(where: { $0.id == target.terminal.id })
            try target.validate(currentTerminal: current,
                currentAssignment: ScrapingBoxAssignmentStore().load()[target.assignment.computerID],
                agentID: request.prepared.agentID, skillIDs: request.prepared.selectedSkills.map(\.id))
            switch runtime.state(for: terminal.id) {
            case .running, .starting: throw LibraryError.invalid("Pare o processo atual antes de iniciar o agente neste terminal.")
            default: break
            }
        } else {
            guard !snapshot.sessions.flatMap(\.terminals).contains(where: { $0.id == terminal.id }),
                  launchBindings[terminal.id] == nil else { throw AgentLaunchError.alreadyMaterialized }
        }
        try WorkspaceDirectoryAccess.shared.activate(terminal.cwd)

        var nextWorkspace = snapshot
        if let newTitle = request.newSessionTitle {
            guard !newTitle.isEmpty, !nextWorkspace.sessions.contains(where: { $0.id == request.sessionID }) else {
                throw LibraryError.invalid("A sessão escolhida mudou. Prepare o lançamento novamente.")
            }
            nextWorkspace.sessions.append(WorkspaceSession(id: request.sessionID, title: newTitle))
            nextWorkspace.layouts.append(WorkspaceLayout(sessionID: request.sessionID))
        }
        guard let sessionIndex = nextWorkspace.sessions.firstIndex(where: { $0.id == request.sessionID }) else {
            throw LibraryError.invalid("A sessão escolhida não está mais disponível.")
        }
        if let target = request.scrapingTarget {
            nextWorkspace = try target.replacingTerminal(in: nextWorkspace, with: terminal)
        } else {
            nextWorkspace.sessions[sessionIndex].terminals.append(terminal)
            nextWorkspace.selectedSessionID = request.sessionID
            nextWorkspace.updateLayout(for: request.sessionID) { layout in
                if layout.root == nil { layout.show(terminal.id) }
                else if let focus = layout.focusedTerminalID, layout.visibleTerminalIDs.count < 5 {
                    layout.split(terminal.id, beside: focus, axis: .horizontal)
                } else { layout.show(terminal.id) }
            }
        }

        var library = try LibraryRepository().load()
        let existingHistoryCount = library.history.count
        try LibraryMutations.recordRun(prepared: request.prepared, terminalID: terminal.id,
                                       sessionID: request.sessionID, in: &library,
                                       taskSummary: request.taskSummary)
        // `recordRun` above is only a dry candidate until a process is observed running.
        guard library.history.count == existingHistoryCount + 1 else { throw LibraryError.invalid("Histórico inválido.") }
        var nextBindings = launchBindings
        nextBindings[terminal.id] = binding
        // Make both durable before starting a process. UI state and run history remain unpublished.
        do {
            try bindingStore.save(nextBindings)
            try repository.save(nextWorkspace)
        } catch {
            if let rollbackError = rollbackLaunchMetadata() {
                bindingsAvailable = false
                throw LibraryError.invalid("Metadados de lançamento falharam e a restauração também falhou: \(rollbackError). Nenhum processo foi iniciado.")
            }
            throw error
        }
        var registeredComputerMCP = false
        do {
            if let mcp = request.materialized.computerMCP {
                let endpoint = try await verifiedComputerEndpoint(for: terminal, in: request.sessionID, mcp: mcp)
                try await AgentComputerAccess.shared.register(
                    launch: request.materialized, sessionID: request.sessionID,
                    policyContext: computerPolicyContext(for: terminal, in: request.sessionID), endpoint: endpoint)
                registeredComputerMCP = true
                try validateComputerAssignment(for: terminal, in: request.sessionID, mcp: mcp)
            }
            try runtime.start(request.materialized)
            guard runtime.isRunning(request.materialized) else {
                throw LibraryError.invalid("O CLI não iniciou; nenhuma execução foi registrada.")
            }
            try LibraryRepository().save(library)
            if registeredComputerMCP { AgentComputerAccess.shared.activate(terminalID: terminal.id) }
        } catch {
            if registeredComputerMCP { AgentComputerAccess.shared.stop(terminalID: terminal.id) }
            if runtime.isRunning(request.materialized) { runtime.stop(terminal.id) }
            if let rollbackError = rollbackLaunchMetadata() {
                bindingsAvailable = false
                throw LibraryError.invalid("Lançamento falhou e os metadados não puderam ser restaurados: \(rollbackError). O processo recebeu pedido de encerramento.")
            }
            throw error
        }
        launchBindings = nextBindings
        snapshot = nextWorkspace
        runtime.focus(terminal.id)
        refreshGit(for: terminal)
    }

    private func rollbackLaunchMetadata() -> String? {
        do {
            try repository.save(snapshot)
            try bindingStore.save(launchBindings)
            return nil
        } catch { return error.localizedDescription }
    }

    private func requestStop(_ id: UUID) {
        stopRequested.insert(id)
        AgentComputerAccess.shared.stop(terminalID: id)
        runtime.stop(id)
    }

    private func startTerminal(_ terminal: TerminalRecord) {
        guard !startingTerminalIDs.contains(terminal.id) else { return }
        switch runtime.state(for: terminal.id) {
        case .running, .starting: runtime.focus(terminal.id); return
        default: break
        }
        startingTerminalIDs.insert(terminal.id)
        Task {
            defer { startingTerminalIDs.remove(terminal.id) }
            await startTerminalValidated(terminal)
        }
    }

    private func startTerminalValidated(_ terminal: TerminalRecord) async {
        stopRequested.remove(terminal.id)
        do { try WorkspaceDirectoryAccess.shared.activate(terminal.cwd) }
        catch { saveError = error.localizedDescription; return }
        guard let agentID = terminal.agentDefinitionID else {
            runtime.start(terminal)
            runtime.focus(terminal.id)
            return
        }
        guard bindingsAvailable, let binding = launchBindings[terminal.id],
              binding.agentDefinitionID == agentID else {
            saveError = "O snapshot revisado deste agente não está disponível. O terminal não será iniciado."
            return
        }
        var registeredComputerMCP = false
        do {
            let restored = try AgentLaunchPlanner().restore(binding, terminal: terminal)
            if let mcp = restored.computerMCP {
                guard let session = snapshot.sessions.first(where: { $0.terminals.contains(where: { $0.id == terminal.id }) }) else {
                    throw LibraryError.invalid("A sessão do terminal não está disponível.")
                }
                let endpoint = try await verifiedComputerEndpoint(for: terminal, in: session.id, mcp: mcp)
                try await AgentComputerAccess.shared.register(
                    launch: restored, sessionID: session.id,
                    policyContext: computerPolicyContext(for: terminal, in: session.id), endpoint: endpoint)
                registeredComputerMCP = true
                try validateComputerAssignment(for: terminal, in: session.id, mcp: mcp)
            }
            try runtime.start(restored)
            guard runtime.isRunning(restored) else {
                throw LibraryError.invalid("O CLI não iniciou; o controle do computador permanece inativo.")
            }
            if restored.computerMCP != nil { AgentComputerAccess.shared.activate(terminalID: terminal.id) }
            runtime.focus(terminal.id)
        } catch {
            if registeredComputerMCP { AgentComputerAccess.shared.stop(terminalID: terminal.id) }
            saveError = error.localizedDescription
        }
    }

    private func verifiedComputerEndpoint(for terminal: TerminalRecord, in sessionID: UUID,
                                          mcp: ComputerMCPConfiguration) async throws -> BrowserRuntimeEndpoint {
        try validateComputerAssignment(for: terminal, in: sessionID, mcp: mcp)
        let endpoint = try await Task.detached(priority: .utility) {
            let service = BrowserComputerService(runner: DockerProcessRunner(), tokens: KeychainBrowserComputerTokenStore())
            guard try service.computer(for: terminal.id)?.id == mcp.computerID else {
                throw LibraryError.invalid("O computador não pertence mais a este terminal.")
            }
            return try await service.reconnectEndpoint(computerID: mcp.computerID)
        }.value
        try validateComputerAssignment(for: terminal, in: sessionID, mcp: mcp)
        return endpoint
    }

    private func validateComputerAssignment(for terminal: TerminalRecord, in sessionID: UUID,
                                            mcp: ComputerMCPConfiguration) throws {
        guard terminal.provider == .claude,
              terminal.agentDefinitionID != nil,
              snapshot.sessions.contains(where: { $0.id == sessionID && $0.terminals.contains(where: {
                  $0.id == terminal.id && $0.cwd == terminal.cwd
              }) }),
              let assignment = try ScrapingBoxAssignmentStore().load()[mcp.computerID],
              assignment.computerID == mcp.computerID,
              assignment.terminalID == terminal.id,
              assignment.defaultAgentDefinitionID == terminal.agentDefinitionID else {
            throw LibraryError.invalid("A atribuição atual do box não corresponde ao lançamento revisado.")
        }
    }

    private func reauthorizeDirectory(for terminal: TerminalRecord) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: terminal.cwd, isDirectory: true)
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        let expected = URL(fileURLWithPath: terminal.cwd, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
        let actual = selected.resolvingSymlinksInPath().standardizedFileURL.path
        guard expected == actual else {
            saveError = "Escolha exatamente a pasta deste terminal. A pasta não foi alterada."
            return
        }
        do {
            try WorkspaceDirectoryAccess.shared.remember(selected)
            refreshGit(for: terminal)
        } catch { saveError = error.localizedDescription }
    }

    private func createTerminal(in sessionID: UUID, title: String, provider: CLIProvider, cwd: String) {
        guard let sessionIndex = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let terminal = TerminalRecord(title: title, provider: provider, cwd: cwd)
        snapshot.sessions[sessionIndex].terminals.append(terminal)
        snapshot.selectedSessionID = sessionID
        snapshot.updateLayout(for: sessionID) { layout in
            if layout.root == nil { layout.show(terminal.id) }
            else if let focus = layout.focusedTerminalID, layout.visibleTerminalIDs.count < 5 {
                layout.split(terminal.id, beside: focus, axis: .horizontal)
            }
        }
    }

    private func split(_ terminalID: UUID, axis: SplitAxis, sessionID: UUID) {
        guard let session = snapshot.sessions.first(where: { $0.id == sessionID }) else { return }
        let layout = snapshot.layouts.first(where: { $0.sessionID == sessionID })
        let visible = layout?.visibleTerminalIDs ?? []
        guard visible.count < 5 else { return }
        snapshot.selectedSessionID = sessionID
        if !visible.contains(terminalID) {
            if let target = layout?.focusedTerminalID ?? visible.first {
                snapshot.updateLayout(for: sessionID) { $0.split(terminalID, beside: target, axis: axis) }
            } else {
                snapshot.updateLayout(for: sessionID) { $0.show(terminalID) }
            }
            return
        }
        guard let candidate = session.terminals.first(where: { !visible.contains($0.id) }) else {
            snapshot.updateLayout(for: sessionID) { $0.focusedTerminalID = terminalID }
            sheet = .terminal(sessionID)
            return
        }
        snapshot.updateLayout(for: sessionID) { $0.split(candidate.id, beside: terminalID, axis: axis) }
    }
}

private struct SessionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nova sessão").font(.system(size: 16, weight: .semibold))
            TextField("Nome da sessão", text: $title)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Criar") { onSave(title.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct RenameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    let heading: String
    let onSave: (String) -> Void

    init(title: String, current: String, onSave: @escaping (String) -> Void) {
        self.heading = title
        self._title = State(initialValue: current)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading).font(.system(size: 16, weight: .semibold))
            TextField("Nome", text: $title)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Salvar") { onSave(title.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct TerminalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var provider: CLIProvider = .shell
    @State private var cwd: String
    @State private var authorizationError: String?
    let onSave: (String, CLIProvider, String) -> Void

    init(defaultDirectory: String, onSave: @escaping (String, CLIProvider, String) -> Void) {
        self._cwd = State(initialValue: defaultDirectory)
        self.onSave = onSave
    }

    private var directoryIsValid: Bool {
        (try? WorkspaceDirectory.resolve(cwd)) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Novo terminal").font(.system(size: 16, weight: .semibold))
            Picker("Cliente", selection: $provider) {
                ForEach(CLIProvider.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            TextField("Título (opcional)", text: $title)
            HStack {
                TextField("Pasta de trabalho", text: $cwd)
                    .onChange(of: cwd) { _, _ in authorizationError = nil }
                Button("Escolher…") { chooseDirectory() }
            }
            if !directoryIsValid {
                Text("Escolha uma pasta existente.").font(.system(size: 11)).foregroundStyle(.red)
            }
            if let authorizationError {
                Text(authorizationError).font(.system(size: 11)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Criar") {
                    guard let directory = try? WorkspaceDirectory.resolve(cwd) else { return }
                    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(name.isEmpty ? provider.displayName : name, provider, directory)
                    dismiss()
                }
                .disabled(!directoryIsValid || authorizationError != nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            do {
                cwd = try WorkspaceDirectoryAccess.shared.remember(url)
                authorizationError = nil
            } catch { authorizationError = error.localizedDescription }
        }
    }
}

private struct WorktreeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reference = "HEAD"
    @State private var branch = ""
    @State private var destination = ""
    @State private var isCreating = false
    @State private var errorText: String?

    let checkout: GitCheckout
    let onCreate: (String, String, URL) async throws -> Void

    private var trimmedReference: String { reference.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBranch: String { branch.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var expandedDestination: String {
        (destination.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    private var canCreate: Bool {
        guard !trimmedReference.isEmpty, !trimmedBranch.isEmpty, !expandedDestination.isEmpty else { return false }
        let url = URL(fileURLWithPath: expandedDestination).standardizedFileURL
        let parent = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Criar worktree").font(.system(size: 16, weight: .semibold))
            Text("Repositório: \(checkout.rootURL.path)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            TextField("Referência de origem", text: $reference)
                .help("Branch, tag ou commit local; HEAD usa o commit atual.")
            TextField("Nova branch", text: $branch)
            HStack(spacing: 8) {
                TextField("Destino do worktree", text: $destination)
                Button("Escolher pasta pai…") { chooseParent() }
            }
            Text("O destino deve estar fora do checkout e vazio ou inexistente. Nenhum stash, reset ou remoção do checkout atual será feito.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let errorText {
                Text(errorText).font(.system(size: 11)).foregroundStyle(.red)
            }
            HStack {
                if isCreating { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancelar") { dismiss() }.disabled(isCreating)
                Button("Criar worktree") { create() }
                    .disabled(!canCreate || isCreating)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = checkout.rootURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do { try WorkspaceDirectoryAccess.shared.remember(parent) }
        catch { errorText = error.localizedDescription; return }
        let leaf = trimmedBranch.isEmpty ? "new-worktree" : trimmedBranch.replacingOccurrences(of: "/", with: "-")
        destination = parent.appendingPathComponent(leaf, isDirectory: true).path
    }

    private func create() {
        guard canCreate else { return }
        let requestedReference = trimmedReference
        let requestedBranch = trimmedBranch
        let destinationURL = URL(fileURLWithPath: expandedDestination, isDirectory: true).standardizedFileURL
        errorText = nil
        isCreating = true
        Task {
            do {
                try await onCreate(requestedReference, requestedBranch, destinationURL)
                dismiss()
            } catch {
                errorText = error.localizedDescription
                isCreating = false
            }
        }
    }
}
