import SwiftUI
import AgentBoxCore

private struct DesktopPresentation: Identifiable {
    let id: UUID
    let endpoint: BrowserRuntimeEndpoint
    let actions: BrokerDesktopActions
}

struct BrowserComputerPanel: View {
    let terminalID: UUID
    let owner: BrowserComputerOwner
    let context: ComputerPolicyContext
    let onReviewAgent: (ScrapingBoxAssignment) -> Void
    @StateObject private var store = BrowserComputerStore()
    @ObservedObject private var runtime = WorkspaceServices.terminalRuntime
    @ObservedObject private var nativeAgents = NativeAgentMonitor.shared
    @State private var launchBinding: AgentLaunchBinding?
    @State private var error: String?
    @State private var busy = false
    @State private var presentation: DesktopPresentation?
    @State private var currentMode: BrowserRuntimeMode?

    init(terminalID: UUID, context: ComputerPolicyContext,
         owner: BrowserComputerOwner? = nil,
         onReviewAgent: @escaping (ScrapingBoxAssignment) -> Void = { _ in }) {
        self.terminalID = terminalID
        self.owner = owner ?? .terminal(terminalID)
        self.context = context
        self.onReviewAgent = onReviewAgent
    }

    private var computer: BrowserManagedComputer? { store.computer(for: owner) }
    private var nativeChildCurrent: Bool {
        guard case .nativeChild(let parentTerminalID, let runID) = owner else { return true }
        return nativeAgents.isCurrentNativeChild(runID: runID,
            parentTerminalID: parentTerminalID, runtime: runtime)
    }
    private var isBusy: Bool {
        busy || store.busyComputerIDs.contains(terminalID) ||
            (computer.map { store.busyComputerIDs.contains($0.id) } ?? false)
    }
    private var recoveryBlocksActions: Bool {
        store.pendingImageUpdate != nil || store.imageUpdateRecoveryBlocked
    }
    private var terminalActive: Bool {
        switch runtime.state(for: terminalID) {
        case .running, .starting: return true
        default: return false
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Text(owner.agentRunID == nil ? "Navegador e desktop" : "Computador do subagente")
                .font(.system(size:13,weight:.medium))
            if let runID = owner.agentRunID {
                Text("Run observado \(runID.uuidString.prefix(8)) · terminal pai compartilhado")
                    .font(.caption).foregroundStyle(.secondary)
                Text(nativeChildCurrent
                     ? "Box próprio do subagente. O acesso nativo às ferramentas ainda não está disponível."
                     : "Subagente não ativo; esta box pode ser consultada ou parada, sem iniciar nova execução.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let computer {
                Label(computer.running ? "Em execução" : "Parado",systemImage:computer.running ? "circle.fill":"pause.circle")
                    .font(.caption).foregroundStyle(.secondary)
                if let currentMode {Text(modeLabel(currentMode)).font(.caption).foregroundStyle(.secondary)}
                if computer.running && store.tokenAuthorizationRequired.contains(computer.id) {
                    Button("Autorizar acesso ao token") {
                        perform {
                            let endpoint = try await store.authorizeReconnect(computerID: computer.id)
                            currentMode = try await BrowserRuntimeClient(endpoint: endpoint).health().mode
                        }
                    }.disabled(isBusy || recoveryBlocksActions)
                    Text("A autorização pode abrir uma janela do macOS. O box e seus dados são preservados se você recusar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if owner.agentRunID == nil,
                   let assignment = store.scrapingAssignment(for: computer.id),
                   assignment.terminalID == terminalID {
                    Text(skillIncluded(assignment) ? "Web scraping · skill incluída no lançamento" : "Web scraping · lançamento pendente")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Inicie o agente de scraping neste terminal, mantendo esta box e seu perfil. O processo atual deve estar parado.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Revisar e iniciar agente") {
                        onReviewAgent(assignment)
                    }.disabled(isBusy || recoveryBlocksActions)
                } else if owner.agentRunID == nil {
                    Button("Definir agente de scraping padrão") {
                        perform { try store.assignDefault(to: computer) }
                    }.disabled(isBusy || recoveryBlocksActions)
                }
                HStack {
                    if computer.running {
                        Button("Abrir desktop") {openDesktop(computer.id, allowModeChange: nativeChildCurrent)}
                            .disabled(isBusy || recoveryBlocksActions || (!nativeChildCurrent && currentMode != .desktop))
                        Button("Parar") {perform {try await store.stop(computerID:computer.id,owner:owner);currentMode=nil}}
                            .disabled(isBusy)
                    } else {
                        Button("Iniciar") {perform {_ = try await store.start(computerID:computer.id,owner:owner,context:context);try await applyPreferredMode(computer.id)}}
                            .disabled(isBusy || recoveryBlocksActions || !nativeChildCurrent)
                    }
                }
                if !computer.running,
                   let imageStatus = store.imageUpdateStatuses[computer.id], imageStatus.updateAvailable {
                    Text("Atualização disponível")
                        .font(.system(size: 12))
                    Text("Nova imagem local. Perfil e arquivos permanecem; pare o terminal antes de atualizar.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button(store.imageUpdateAuthorizationRequired.contains(computer.id)
                           ? "Autorizar e atualizar" : "Atualizar computador") {
                        perform {
                            presentation = nil
                            _ = try await store.updateStoppedImage(computerID: computer.id, owner: owner, context: context,
                                interactiveAuthorization: store.imageUpdateAuthorizationRequired.contains(computer.id))
                            currentMode = nil
                        }
                    }
                    .disabled(isBusy || terminalActive || recoveryBlocksActions)
                    if store.imageUpdateAuthorizationRequired.contains(computer.id) {
                        Text("A autorização pode abrir uma janela do macOS. Se for recusada, o computador e seus dados serão preservados.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if terminalActive {
                        Text("Encerre o processo deste terminal para atualizar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if computer.running {
                    Menu("Modo") {
                        Button("HTTP · sem navegador") {changeMode(.http,computerID:computer.id)}
                        Button("Navegador headless") {changeMode(.headless,computerID:computer.id)}
                        Button("Desktop") {openDesktop(computer.id)}
                    }.disabled(isBusy || recoveryBlocksActions || !nativeChildCurrent)
                    Text("Trocar de modo reinicia o navegador. Perfil e arquivos são mantidos; formulários em andamento podem ser perdidos.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("Criar computador") {
                    perform {
                        let created: BrowserManagedComputer
                        if owner.agentRunID == nil {
                            created = try await store.createAndStart(terminalID: terminalID, context: context)
                        } else {
                            created = try await store.createAndStart(owner: owner, context: context)
                        }
                        try await applyPreferredMode(created.id)
                    }
                }.disabled(isBusy || recoveryBlocksActions || !nativeChildCurrent)
                Text("Perfil e arquivos persistem entre reinícios. Requer imagem do runtime e teto de memória de pelo menos 2048 MiB.").font(.caption).foregroundStyle(.secondary)
            }
            if let pending = store.pendingImageUpdate {
                Text("Recuperação de atualização pendente")
                    .font(.system(size: 12))
                Text("O computador \(pending.computerID.uuidString.prefix(8)) precisa concluir ou desfazer uma atualização interrompida. Perfil e arquivos serão mantidos.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Recuperar atualização") {
                    perform {
                        presentation = nil
                        try await store.recoverStoppedImageUpdate()
                        currentMode = nil
                    }
                }.disabled(isBusy || store.computers.contains(where: { $0.id == pending.computerID && $0.running }))
                if store.computers.contains(where: { $0.id == pending.computerID && $0.running }) {
                    Text("Pare o computador antes de recuperar a atualização.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if store.imageUpdateRecoveryBlocked {
                Text("O registro de recuperação não pôde ser verificado. A atualização automática está bloqueada; confira o erro abaixo antes de alterar este computador.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isBusy {ProgressView().controlSize(.small)}
            if let issue=error ?? store.errorText {Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
            Button("Atualizar") {perform {await store.refresh();try await refreshMode()}}.disabled(isBusy)
        }
        .task {
            launchBinding = try? AgentLaunchBindingStore().load()[terminalID]
            await store.refresh();try? await refreshMode()
        }
        .sheet(item:$presentation) { item in
            VStack(spacing:0) {
                HStack {Text("Computador");Spacer();Button("Fechar"){presentation=nil}}.padding(10)
                RemoteDesktopView(endpoint:item.endpoint,control:item.actions.actions())
            }.frame(minWidth:800,minHeight:560).frame(idealWidth:1100,idealHeight:760)
        }
    }
    private func skillIncluded(_ assignment: ScrapingBoxAssignment) -> Bool {
        guard let binding = launchBinding else { return false }
        return binding.terminalID == terminalID && binding.agentDefinitionID == assignment.defaultAgentDefinitionID &&
            binding.skillReferences.contains(where: { $0.id == assignment.skillID }) &&
            runtime.runningPlanID(for: terminalID) == binding.planID
    }
    private func modeLabel(_ mode:BrowserRuntimeMode)->String {
        switch mode {case .http:return "HTTP · navegador desligado";case .headless:return "Navegador headless";case .desktop:return "Desktop Linux"}
    }
    private func perform(_ operation:@escaping @MainActor () async throws -> Void) {
        guard !isBusy else{return};busy=true;error=nil
        Task {do{try await operation()}catch{self.error=error.localizedDescription};busy=false}
    }
    private func refreshMode() async throws {
        guard let computer, computer.running, !recoveryBlocksActions else {currentMode=nil;return}
        let endpoint=try await store.reconnect(computerID:computer.id)
        currentMode=try await BrowserRuntimeClient(endpoint:endpoint).health().mode
    }
    private func applyPreferredMode(_ id:UUID) async throws {
        let policy=try ComputerPolicyStore().load().effective(for:context)
        if policy.modePreference == .alwaysGraphical {_ = try await setMode(.desktop,computerID:id)}
        try await refreshMode()
    }
    private func setMode(_ mode:BrowserRuntimeMode,computerID:UUID) async throws -> BrowserRuntimeEndpoint {
        let policy=try ComputerPolicyStore().load().effective(for:context)
        if policy.modePreference == .alwaysGraphical && mode != .desktop {throw ComputerPolicyError.graphicalUnavailable}
        let endpoint=try await store.reconnect(computerID:computerID)
        let health=try await BrowserRuntimeClient(endpoint:endpoint).health()
        if health.mode == mode {currentMode=mode;return endpoint}
        let actions=await BrokerDesktopActions(endpoint:endpoint,broker:try DesktopBrokerService.result.get())
        var assumedGrant: ControlGrant?
        do {
            let grant = try await actions.actions().assume()
            assumedGrant = grant
            _ = try await actions.changeMode(mode)
            try await actions.actions().release(grant)
        } catch {
            if let assumedGrant { await actions.actions().streamDisconnected(assumedGrant) }
            throw error
        }
        currentMode=mode
        return try await store.reconnect(computerID:computerID)
    }
    private func changeMode(_ mode:BrowserRuntimeMode,computerID:UUID) {
        perform {_ = try await setMode(mode,computerID:computerID)}
    }
    private func openDesktop(_ id:UUID, allowModeChange: Bool = true) {
        perform {
            let endpoint: BrowserRuntimeEndpoint
            if allowModeChange {
                endpoint = try await setMode(.desktop, computerID: id)
            } else {
                endpoint = try await store.reconnect(computerID: id)
            }
            let health=try await BrowserRuntimeClient(endpoint:endpoint).health()
            guard health.isFullDesktopReady else {throw BrowserComputerError.notReady}
            presentation=DesktopPresentation(id:id,endpoint:endpoint,actions:await BrokerDesktopActions(endpoint:endpoint,broker:try DesktopBrokerService.result.get()))
        }
    }
}
