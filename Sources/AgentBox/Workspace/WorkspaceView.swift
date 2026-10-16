import AppKit
import SwiftUI
import AgentBoxCore

@MainActor public enum WorkspaceServices {
    public static let terminalRuntime = TerminalRuntimeManager()
}

private enum WorkspaceChrome {
    static let sidebar = Color(red: 0.145, green: 0.149, blue: 0.153)
    static let canvas = Color(red: 0.095, green: 0.099, blue: 0.106)
    static let line = Color(red: 0.23, green: 0.235, blue: 0.243)
    static let secondary = Color(red: 0.67, green: 0.68, blue: 0.69)
    static let selection = Color(red: 0.205, green: 0.21, blue: 0.218)
}

private struct ProviderMark: View {
    let provider: CLIProvider
    let size: CGFloat

    var body: some View {
        Group {
            if provider == .shell {
                Image(systemName: "terminal").font(.system(size: size - 1))
            } else if let url = Bundle.module.url(forResource: provider.rawValue, withExtension: "png", subdirectory: "Brands"),
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
    case settings
    case computer(UUID)

    var id: String {
        switch self {
        case .session: return "session"
        case .terminal(let id): return "terminal-\(id)"
        case .renameSession(let id): return "rename-session-\(id)"
        case .renameTerminal(let id): return "rename-terminal-\(id)"
        case .library: return "library"
        case .settings: return "settings"
        case .computer(let id): return "computer-\(id)"
        }
    }
}

public struct WorkspaceView: View {
    @StateObject private var runtime = WorkspaceServices.terminalRuntime
    @State private var snapshot: WorkspaceSnapshot
    @State private var loadError: String?
    @State private var showLoadError = false
    @State private var saveError: String?
    @State private var sheet: WorkspaceSheet?
    @State private var collapsedSessions = Set<UUID>()
    @State private var sidebarDragStart: Double?
    @State private var splitDragStarts: [UUID: Double] = [:]
    @State private var stopRequested = Set<UUID>()
    @State private var forceStopTerminalID: UUID?
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    private let repository = WorkspaceRepository()

    public init() {
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
        .foregroundStyle(.white)
        .font(.system(size: 13))
        .disabled(loadError != nil)
        .frame(minWidth: 1000, minHeight: 650)
        .onAppear { RuntimeLifecycle.shared.attach(runtime) }
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
        .sheet(item: $sheet) { route in
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
                LibraryView()
            case .settings:
                AppSettingsView()
            case .computer(let id):
                ComputerPanel(terminalID: id)
            }
        }
        .alert("Erro ao salvar sessões", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .alert("Arquivo de sessões indisponível", isPresented: $showLoadError) {
            Button("OK") { }
        } message: { Text((loadError ?? "") + " O arquivo foi preservado; corrija-o e reabra o aplicativo.") }
        .confirmationDialog("Forçar encerramento deste terminal?", isPresented: Binding(
            get: { forceStopTerminalID != nil }, set: { if !$0 { forceStopTerminalID = nil } }
        )) {
            Button("Forçar encerramento", role: .destructive) {
                if let id = forceStopTerminalID { runtime.forceStop(id) }
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
                Image(systemName: "square.split.2x2")
                    .font(.system(size: 14, weight: .medium))
                Text("Agent Box").font(.system(size: 13, weight: .semibold))
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

            Divider().overlay(WorkspaceChrome.line)
            HStack {
                Button { sheet = .library } label: { Label("Biblioteca", systemImage: "books.vertical") }
                Spacer()
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
        session.terminals.contains { $0.title.localizedCaseInsensitiveContains(search) }
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
                Text(session.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Renomear") { sheet = .renameSession(session.id) }
                Button("Novo terminal") { sheet = .terminal(session.id) }
            }
        }
        .padding(.horizontal, 6)
        .background(snapshot.selectedSessionID == session.id ? WorkspaceChrome.selection : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .contain)
    }

    private func terminalRow(_ terminal: TerminalRecord, sessionID: UUID) -> some View {
        let focused = snapshot.selectedSessionID == sessionID && selectedLayout?.focusedTerminalID == terminal.id
        return Button {
            snapshot.selectedSessionID = sessionID
            snapshot.updateLayout(for: sessionID) { $0.show(terminal.id) }
        } label: {
            HStack(spacing: 8) {
                ProviderMark(provider: terminal.provider, size: 16)
                Text(terminal.title).lineLimit(1)
                Spacer(minLength: 0)
                statusIcon(for: terminal.id)
            }
            .padding(.leading, 27)
            .padding(.trailing, 7)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(focused ? WorkspaceChrome.selection : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contextMenu {
            Button("Renomear") { sheet = .renameTerminal(terminal.id) }
            Button("Mostrar em pane") {
                snapshot.selectedSessionID = sessionID
                snapshot.updateLayout(for: sessionID) { $0.show(terminal.id) }
            }
            Button("Dividir à direita") { split(terminal.id, axis: .horizontal, sessionID: sessionID) }
            Button("Dividir abaixo") { split(terminal.id, axis: .vertical, sessionID: sessionID) }
            Divider()
            Button("Encerrar processo") { requestStop(terminal.id) }
            if stopRequested.contains(terminal.id) {
                Button("Forçar encerramento…") { forceStopTerminalID = terminal.id }
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
            .fill(WorkspaceChrome.line)
            .frame(width: 5)
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
            Rectangle().fill(WorkspaceChrome.line).frame(height: 1)
            if let selectedSession {
                sessionTabs(selectedSession)
                if selectedSession.terminals.isEmpty {
                    emptySession(selectedSession)
                } else if let node = selectedLayout?.root {
                    GeometryReader { geometry in
                        if geometry.size.width < CGFloat(node.terminalIDs.count) * 260,
                           let focusedID = selectedLayout?.focusedTerminalID,
                           let focusedTerminal = selectedSession.terminals.first(where: { $0.id == focusedID }) {
                            terminalPane(focusedTerminal, sessionID: selectedSession.id)
                        } else {
                            paneNode(node, in: selectedSession)
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
                        snapshot.updateLayout(for: session.id) { $0.show(terminal.id) }
                    } label: {
                        HStack(spacing: 6) {
                            ProviderMark(provider: terminal.provider, size: 14)
                            Text(terminal.title).lineLimit(1)
                        }
                        .font(.system(size: 11, weight: focused ? .medium : .regular))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(focused ? WorkspaceChrome.selection : .clear)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(WorkspaceChrome.line).frame(width: 1, height: 18)
                }
            }
        }
        .frame(height: 34)
        .background(WorkspaceChrome.sidebar)
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
                Text(selectedSession.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
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
                Button("Biblioteca") { sheet = .library }
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
        .frame(height: 42)
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
                Button("Abrir \(first.title)") { snapshot.updateLayout(for: session.id) { $0.show(first.id) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paneNode(_ node: WorkspaceNode, in session: WorkspaceSession) -> AnyView {
        switch node {
        case .terminal(let id):
            guard let terminal = session.terminals.first(where: { $0.id == id }) else { return AnyView(EmptyView()) }
            return AnyView(terminalPane(terminal, sessionID: session.id))
        case .split(let id, let axis, let fraction, let first, let second):
            return AnyView(GeometryReader { geometry in
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        paneNode(first, in: session).frame(width: max(0, geometry.size.width * CGFloat(fraction) - 2))
                        splitDivider(id: id, axis: axis, extent: geometry.size.width, fraction: fraction, sessionID: session.id)
                        paneNode(second, in: session).frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        paneNode(first, in: session).frame(height: max(0, geometry.size.height * CGFloat(fraction) - 2))
                        splitDivider(id: id, axis: axis, extent: geometry.size.height, fraction: fraction, sessionID: session.id)
                        paneNode(second, in: session).frame(maxHeight: .infinity)
                    }
                }
            })
        }
    }

    private func splitDivider(id: UUID, axis: SplitAxis, extent: CGFloat, fraction: Double, sessionID: UUID) -> some View {
        Rectangle()
            .fill(WorkspaceChrome.line)
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

    private func terminalPane(_ terminal: TerminalRecord, sessionID: UUID) -> some View {
        let focused = selectedLayout?.focusedTerminalID == terminal.id
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
                ProviderMark(provider: terminal.provider, size: 16)
                Text(terminal.title).font(.system(size: 12, weight: focused ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                Text(statusText(for: terminal.id))
                    .foregroundStyle(WorkspaceChrome.secondary)
                    .font(.system(size: 11))
                    .lineLimit(1)
                switch runtime.state(for: terminal.id) {
                case .idle, .exited, .failed:
                    Button("Iniciar") { stopRequested.remove(terminal.id); runtime.start(terminal) }.help("Iniciar \(terminal.provider.displayName)")
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
                Button { sheet = .computer(terminal.id) } label: { Image(systemName: "desktopcomputer") }
                    .help("Computador deste terminal")
                    .accessibilityLabel("Computador de \(terminal.title)")
                Button {
                    snapshot.updateLayout(for: sessionID) { $0.closePane(terminal.id) }
                } label: { Image(systemName: "xmark") }
                    .help("Fechar pane")
                    .accessibilityLabel("Fechar pane de \(terminal.title)")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 9)
            .frame(height: 35)
            .background(WorkspaceChrome.sidebar)
            Rectangle().fill(WorkspaceChrome.line).frame(height: 1)
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
                    TerminalSurface(terminal: terminal, runtime: runtime)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WorkspaceChrome.canvas)
        .overlay(Rectangle().stroke(focused ? Color.white.opacity(0.65) : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { snapshot.updateLayout(for: sessionID) { $0.focusedTerminalID = terminal.id } }
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

    private func createSession(title: String) {
        let session = WorkspaceSession(title: title)
        snapshot.sessions.append(session)
        snapshot.selectedSessionID = session.id
        snapshot.layouts.append(WorkspaceLayout(sessionID: session.id))
    }

    private func requestStop(_ id: UUID) {
        stopRequested.insert(id)
        runtime.stop(id)
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
                Button("Escolher…") { chooseDirectory() }
            }
            if !directoryIsValid {
                Text("Escolha uma pasta existente.").font(.system(size: 11)).foregroundStyle(.red)
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
                .disabled(!directoryIsValid)
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
        if panel.runModal() == .OK, let url = panel.url { cwd = url.path }
    }
}
