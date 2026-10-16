import AppKit
import SwiftUI
import AgentBoxCore

struct AgentLaunchRequest {
    let materialized: MaterializedAgentLaunch
    let prepared: PreparedAgentContext
    let sessionID: UUID
    let newSessionTitle: String?
    let taskSummary: String?
}

/// Review is an explicit boundary: changing any input discards the prepared plan.
struct AgentLaunchView: View {
    @Environment(\.dismiss) private var dismiss
    let agentID: UUID
    let sessions: [WorkspaceSession]
    let onLaunch: (AgentLaunchRequest) throws -> Void

    @State private var document = LibraryDocument()
    @State private var errorText: String?
    @State private var sessionID: UUID
    @State private var newSessionID = UUID()
    @State private var newSessionTitle = ""
    @State private var directory: String
    @State private var directoryAuthorizationError: String?
    @State private var projectKey = ""
    @State private var taskKey = ""
    @State private var profileKey = ""
    @State private var taskSummary = ""
    @State private var memoryIDs: Set<UUID> = []
    @State private var skillIDs: Set<UUID> = []
    @State private var plan: AgentLaunchPlan?
    @State private var prepared: PreparedAgentContext?
    @State private var reviewed = false
    @State private var stoppingTerminalID: UUID?
    @State private var confirmForceStop = false

    init(agentID: UUID, sessions: [WorkspaceSession], selectedSessionID: UUID?,
         onLaunch: @escaping (AgentLaunchRequest) throws -> Void) {
        self.agentID = agentID
        self.sessions = sessions
        self.onLaunch = onLaunch
        let freshSessionID = UUID()
        _sessionID = State(initialValue: selectedSessionID ?? sessions.first?.id ?? freshSessionID)
        _newSessionID = State(initialValue: freshSessionID)
        let folder = sessions.first(where: { $0.id == selectedSessionID })?.terminals.last?.cwd ?? NSHomeDirectory()
        _directory = State(initialValue: folder)
    }

    private var agent: SavedAgent? { document.agents.first { $0.id == agentID } }
    private var newSession: Bool { !sessions.contains(where: { $0.id == sessionID }) }
    private var validDirectory: Bool { (try? WorkspaceDirectory.resolve(directory)) != nil }
    private var canPrepare: Bool {
        validDirectory && directoryAuthorizationError == nil &&
        (!newSession || !newSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Usar agente salvo").font(.system(size: 16, weight: .medium))
                Spacer()
                if let agent { Text("\(agent.provider.displayName) · r\(agent.revision)").foregroundStyle(.secondary) }
            }
            if let agent {
                Text(agent.name).font(.system(size: 13, weight: .medium))
                if plan == nil { inputs(agent) } else { review }
            } else {
                Text("Este agente não está mais disponível.").foregroundStyle(.secondary)
            }
            if let errorText { Text(errorText).foregroundStyle(.red).font(.system(size: 12)) }
            if stoppingTerminalID != nil {
                HStack {
                    Text("Aguardando o processo encerrar antes de outra tentativa.")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                    Spacer()
                    Button("Forçar encerramento…") { confirmForceStop = true }
                }
            }
            HStack {
                Button("Cancelar") { dismiss() }.disabled(stoppingTerminalID != nil)
                Spacer()
                if plan == nil {
                    Button("Preparar revisão") { prepare() }.disabled(!canPrepare || agent == nil || stoppingTerminalID != nil)
                } else {
                    Button("Alterar seleção") { invalidate() }
                    if let plan, case .exportOnly = plan.activation {
                        Button("Copiar contexto") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(plan.review.contextText, forType: .string) }
                        Button("Exportar…") { export(plan.review.contextText) }
                    } else {
                        Button("Iniciar agente") { launch() }.disabled(!reviewed)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .font(.system(size: 13))
        .padding(20)
        .frame(width: 690, height: 640)
        .onAppear(perform: load)
        .onReceive(WorkspaceServices.terminalRuntime.$processStates) { states in
            if let id = stoppingTerminalID {
                if case .running? = states[id] { return }
                stoppingTerminalID = nil
            }
        }
        .confirmationDialog("Forçar encerramento deste processo?", isPresented: $confirmForceStop) {
            Button("Forçar encerramento", role: .destructive) {
                if let id = stoppingTerminalID { WorkspaceServices.terminalRuntime.forceStop(id) }
            }
            Button("Cancelar", role: .cancel) { }
        }
    }

    private func inputs(_ agent: SavedAgent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Sessão", selection: $sessionID) {
                    ForEach(sessions) { session in Text(session.title).tag(session.id) }
                    Text("Nova sessão").tag(newSessionID)
                }
                if newSession { TextField("Nome da nova sessão", text: $newSessionTitle) }
                HStack {
                    TextField("Pasta de trabalho", text: $directory)
                        .onChange(of: directory) { _, _ in directoryAuthorizationError = nil }
                    Button("Escolher…") { chooseDirectory() }
                }
                if !validDirectory { Text("Escolha uma pasta existente.").foregroundStyle(.red) }
                if let directoryAuthorizationError { Text(directoryAuthorizationError).foregroundStyle(.red) }
                TextField("ID do projeto (opcional)", text: $projectKey)
                TextField("ID da tarefa (opcional)", text: $taskKey)
                TextField("ID do perfil (opcional)", text: $profileKey)
                TextField("Resumo da tarefa (opcional)", text: $taskSummary)
                Text("Memórias incluídas").fontWeight(.medium)
                if agent.memoryIDs.isEmpty { Text("Nenhuma memória selecionada.").foregroundStyle(.secondary) }
                ForEach(document.memories.filter { agent.memoryIDs.contains($0.id) }) { memory in
                    Toggle("\(memory.title) · r\(memory.revision) · \(memory.scope.label)",
                           isOn: setBinding(memory.id, in: $memoryIDs)).toggleStyle(.checkbox)
                }
                Text("Skills incluídas").fontWeight(.medium)
                if agent.skillIDs.isEmpty { Text("Nenhuma skill selecionada.").foregroundStyle(.secondary) }
                ForEach(document.skills.filter { agent.skillIDs.contains($0.id) }) { skill in
                    Toggle("\(skill.name) · \(skill.sha256.prefix(12))",
                           isOn: setBinding(skill.id, in: $skillIDs)).toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let plan {
                let details = plan.review
                Text("Revisão do lançamento").fontWeight(.medium)
                Text("Sessão: \(newSession ? newSessionTitle : sessions.first(where: { $0.id == sessionID })?.title ?? "")")
                Text("Executável: \(details.executablePath)")
                Text("Argumentos: \(details.arguments.joined(separator: " "))")
                Text("Pasta: \(details.workingDirectory)")
                Text("Snapshot: \(details.contextFilePath)")
                Text("SHA-256: \(details.contextSHA256)")
                Text("Memórias: \(details.selectedMemories.map { "\($0.title) r\($0.revision)" }.joined(separator: ", ").ifEmpty("nenhuma"))")
                Text("Skills: \(details.selectedSkills.map { "\($0.name) \($0.sha256.prefix(12))" }.joined(separator: ", ").ifEmpty("nenhuma"))")
                if case .exportOnly(let reason) = details.activation {
                    Text("Somente exportação: \(reason)").foregroundStyle(.orange)
                }
                ScrollView {
                    Text(details.contextText).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .padding(8)
                .background(Color.black.opacity(0.15))
                if details.activation.contextIsActiveAtLaunch {
                    Toggle("Revisei o contexto completo e autorizo iniciar este snapshot", isOn: $reviewed)
                        .toggleStyle(.checkbox)
                }
            }
        }
        .font(.system(size: 11))
        .textSelection(.enabled)
    }

    private func setBinding(_ id: UUID, in selection: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(get: { selection.wrappedValue.contains(id) }, set: { selected in
            var values = selection.wrappedValue
            if selected { values.insert(id) } else { values.remove(id) }
            selection.wrappedValue = values
        })
    }

    private func load() {
        do {
            document = try LibraryRepository().load()
            guard let agent, !agent.archived else { throw LibraryError.invalid("Agente indisponível.") }
            memoryIDs = Set(agent.memoryIDs)
            skillIDs = Set(agent.skillIDs)
        } catch { errorText = error.localizedDescription }
    }

    private func prepare() {
        do {
            let fresh = try LibraryRepository().load()
            let memorySelection = agent?.memoryIDs.filter(memoryIDs.contains) ?? []
            let skillSelection = agent?.skillIDs.filter(skillIDs.contains) ?? []
            let project = projectKey.isEmpty ? nil : projectKey
            let task = taskKey.isEmpty ? nil : taskKey
            let profile = profileKey.isEmpty ? nil : profileKey
            let preparedContext = try LibraryContext.prepare(agentID: agentID, in: fresh,
                projectKey: project, taskKey: task, profileKey: profile,
                selectedMemoryIDs: memorySelection, selectedSkillIDs: skillSelection)
            let candidate = try AgentLaunchPlanner().prepare(agentID: agentID, in: fresh,
                workingDirectory: directory, projectKey: project, taskKey: task, profileKey: profile,
                selectedMemoryIDs: memorySelection, selectedSkillIDs: skillSelection)
            guard candidate.review.contextText == preparedContext.text,
                  candidate.agentRevision == preparedContext.agentRevision else {
                throw AgentLaunchError.contextChanged
            }
            prepared = preparedContext
            plan = candidate
            errorText = nil
            reviewed = false
        } catch { errorText = error.localizedDescription }
    }

    private func invalidate() { plan = nil; prepared = nil; reviewed = false; errorText = nil }

    private func launch() {
        guard reviewed, let plan, let prepared else { return }
        var materialized: MaterializedAgentLaunch?
        do {
            let created = try AgentLaunchPlanner().materialize(plan, reviewedDigest: plan.review.contextSHA256)
            materialized = created
            try onLaunch(AgentLaunchRequest(materialized: created, prepared: prepared,
                sessionID: sessionID, newSessionTitle: newSession ? newSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                taskSummary: taskSummary.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty))
            dismiss()
        } catch {
            if let materialized,
               let terminal = materialized.terminal,
               case .running = WorkspaceServices.terminalRuntime.state(for: terminal.id) {
                // The process may still be reading the protected file while SIGTERM completes.
                stoppingTerminalID = terminal.id
            } else if let materialized {
                try? AgentLaunchPlanner().removeContextFile(for: materialized)
            }
            invalidate()
            errorText = error.localizedDescription + " Prepare uma nova revisão antes de tentar novamente."
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            do { directory = try WorkspaceDirectoryAccess.shared.remember(url); directoryAuthorizationError = nil; errorText = nil }
            catch { directoryAuthorizationError = error.localizedDescription }
        }
    }

    private func export(_ text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "agent-context.md"
        if panel.runModal() == .OK, let url = panel.url {
            do { try text.write(to: url, atomically: true, encoding: .utf8); errorText = nil }
            catch { errorText = error.localizedDescription }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
    var nonEmpty: String? { isEmpty ? nil : self }
}
