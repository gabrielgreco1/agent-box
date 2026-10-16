import SwiftUI
import AgentBoxCore

@MainActor private enum DesktopBrokerService {
    static let result = Result { try ControlBroker() }
}
private struct DesktopPresentation: Identifiable {
    let id: UUID
    let endpoint: BrowserRuntimeEndpoint
    let actions: BrokerDesktopActions
}

struct BrowserComputerPanel: View {
    let terminalID: UUID
    let context: ComputerPolicyContext
    let onReviewAgent: (ScrapingBoxAssignment) -> Void
    @StateObject private var store = BrowserComputerStore()
    @ObservedObject private var runtime = WorkspaceServices.terminalRuntime
    @State private var launchBinding: AgentLaunchBinding?
    @State private var error: String?
    @State private var busy = false
    @State private var presentation: DesktopPresentation?
    @State private var currentMode: BrowserRuntimeMode?

    private var computer: BrowserManagedComputer? {store.computer(for:terminalID)}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Navegador e desktop").font(.system(size:13,weight:.medium))
            if let computer {
                Label(computer.running ? "Em execução" : "Parado",systemImage:computer.running ? "circle.fill":"pause.circle")
                    .font(.caption).foregroundStyle(.secondary)
                if let currentMode {Text(modeLabel(currentMode)).font(.caption).foregroundStyle(.secondary)}
                if store.tokenAuthorizationRequired.contains(computer.id) {
                    Button("Autorizar acesso ao token") {
                        perform {
                            let endpoint = try await store.authorizeReconnect(computerID: computer.id)
                            currentMode = try await BrowserRuntimeClient(endpoint: endpoint).health().mode
                        }
                    }.disabled(busy)
                    Text("A autorização pode abrir uma janela do macOS. O box e seus dados são preservados se você recusar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let assignment = store.scrapingAssignment(for: computer.id),
                   assignment.terminalID == terminalID {
                    Text(skillIncluded(assignment) ? "Web scraping · skill incluída no lançamento" : "Web scraping · lançamento pendente")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Inicie o agente de scraping neste terminal, mantendo esta box e seu perfil. O processo atual deve estar parado.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Revisar e iniciar agente") {
                        onReviewAgent(assignment)
                    }
                } else {
                    Button("Definir agente de scraping padrão") {
                        perform { try store.assignDefault(to: computer) }
                    }.disabled(busy)
                }
                HStack {
                    if computer.running {
                        Button("Abrir desktop") {openDesktop(computer.id)}
                        Button("Parar") {perform {try await store.stop(computerID:computer.id);currentMode=nil}}
                    } else {
                        Button("Iniciar") {perform {_ = try await store.start(computerID:computer.id,context:context);try await applyPreferredMode(computer.id)}}
                    }
                }.disabled(busy)
                if computer.running {
                    Menu("Modo") {
                        Button("HTTP · sem navegador") {changeMode(.http,computerID:computer.id)}
                        Button("Navegador headless") {changeMode(.headless,computerID:computer.id)}
                        Button("Desktop") {openDesktop(computer.id)}
                    }.disabled(busy)
                    Text("Trocar de modo reinicia o navegador. Perfil e arquivos são mantidos; formulários em andamento podem ser perdidos.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("Criar computador") {
                    perform {
                        let created=try await store.createAndStart(terminalID:terminalID,context:context)
                        try await applyPreferredMode(created.id)
                    }
                }.disabled(busy)
                Text("Perfil e arquivos persistem entre reinícios. Requer imagem do runtime e teto de memória de pelo menos 2048 MiB.").font(.caption).foregroundStyle(.secondary)
            }
            if busy {ProgressView().controlSize(.small)}
            if let issue=error ?? store.errorText {Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
            Button("Atualizar") {perform {await store.refresh();try await refreshMode()}}.disabled(busy)
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
        guard !busy else{return};busy=true;error=nil
        Task {do{try await operation()}catch{self.error=error.localizedDescription};busy=false}
    }
    private func refreshMode() async throws {
        guard let computer, computer.running else {currentMode=nil;return}
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
        let actions=BrokerDesktopActions(endpoint:endpoint,broker:try DesktopBrokerService.result.get())
        do {
            _ = try await actions.actions().assume()
            _ = try await actions.changeMode(mode)
            try await actions.actions().release()
        } catch {await actions.actions().streamDisconnected();throw error}
        currentMode=mode
        return try await store.reconnect(computerID:computerID)
    }
    private func changeMode(_ mode:BrowserRuntimeMode,computerID:UUID) {
        perform {_ = try await setMode(mode,computerID:computerID)}
    }
    private func openDesktop(_ id:UUID) {
        perform {
            let endpoint=try await setMode(.desktop,computerID:id)
            let health=try await BrowserRuntimeClient(endpoint:endpoint).health()
            guard health.isFullDesktopReady else {throw BrowserComputerError.notReady}
            presentation=DesktopPresentation(id:id,endpoint:endpoint,actions:BrokerDesktopActions(endpoint:endpoint,broker:try DesktopBrokerService.result.get()))
        }
    }
}
