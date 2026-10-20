import SwiftUI
import RackyCore

public struct DockerSettingsView: View {
    @State private var policy = ComputerPolicy()
    @State private var availability: DockerAvailability?
    @State private var errorText: String?
    @State private var saved = false
    @State private var readable = false
    @State private var busy = false
    @State private var scopeEditor: ComputerPolicyOverride?
    @State private var dockerContext = ""
    @State private var contexts:[String] = []
    private let store = ComputerPolicyStore()
    public init() {}
    public var body: some View {
        Form {
            Section("Docker") {
                Picker("Conexão",selection:$dockerContext) {
                    Text("Padrão do CLI").tag("")
                    ForEach(contexts,id:\.self){Text($0).tag($0)}
                }
                Button("Usar esta conexão") {do{try DockerConnectionStore().save(.init(contextName:dockerContext.isEmpty ? nil:dockerContext));refresh()}catch{errorText=error.localizedDescription}}
                Text("A seleção vale só para o Racky; não muda o contexto global do Docker.").font(.caption).foregroundStyle(.secondary)
                statusView
                Button("Verificar novamente") { refresh() }.disabled(busy)
            }
            Section("Permissões globais") {
                Picker("Criar computadores", selection: $policy.creation) {
                    Text("Desativado").tag(ComputerCreationPermission.disabled)
                    Text("Manual").tag(ComputerCreationPermission.manual)
                    Text("Orquestrador · integração pendente").tag(ComputerCreationPermission.automatic).disabled(true)
                }
                Picker("Modo", selection: $policy.modePreference) {
                    Text("Tentar HTTP / headless primeiro").tag(ComputerModePreference.adaptive)
                    Text("Sempre gráfico").tag(ComputerModePreference.alwaysGraphical)
                }
                Text("O computador pode usar HTTP, navegador headless ou desktop. O runtime de navegador requer pelo menos 2048 MiB por box.").font(.caption).foregroundStyle(.secondary)
                Toggle("Rede nas novas boxes", isOn: $policy.networkAllowed)
                resourceFields
            }.disabled(!readable)
            Section("Restrições por escopo") {
                ForEach(policy.overrides) { item in
                    HStack {
                        Button { scopeEditor=item } label: {
                            VStack(alignment:.leading) { Text(item.scope.rawValue);Text(item.scopeID).font(.caption).lineLimit(1).truncationMode(.middle) }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button {policy.overrides.removeAll{$0.id==item.id}} label:{Image(systemName:"trash")}.help("Remover restrição")
                    }
                }
                Button("Adicionar restrição…") {scopeEditor=ComputerPolicyOverride(scope:.terminal,scopeID:"")}
                Text("Projeto → sessão → terminal → agente. Cada nível pode restringir o pai; nunca ampliar sua permissão ou seus limites. IDs de projeto usam o caminho canônico do checkout.").font(.caption).foregroundStyle(.secondary)
            }.disabled(!readable)
            Section {
                Text("Permissão de criação: vale na próxima solicitação. CPU, memória e rede: novas boxes. Teto: novas criações/inícios. Processos e boxes em execução não são interrompidos ao salvar. Estas regras não isolam um CLI executado no Mac.").font(.caption).foregroundStyle(.secondary)
                HStack {Button("Salvar configurações") {save()}.disabled(!readable);if saved {Text("Salvo").foregroundStyle(.secondary)}}
                if let errorText {Text(errorText).foregroundStyle(.red).textSelection(.enabled)}
            }
        }.formStyle(.grouped)
        .task {load();refresh()}
        .sheet(item:$scopeEditor) { item in
            ComputerScopeEditor(item:item) { changed in
                policy.overrides.removeAll{$0.id==item.id || $0.id==changed.id}
                policy.overrides.append(changed);saved=false
            }
        }
    }
    private var resourceFields: some View {
        Group {
            Stepper("CPU por box: \(policy.limits.cpus, specifier:"%.2g")",value:$policy.limits.cpus,in:0.25...32,step:0.25)
            Stepper("Memória por box: \(policy.limits.memoryMiB) MiB",value:$policy.limits.memoryMiB,in:128...65536,step:128)
            Stepper("Computadores ativos: \(policy.limits.maxComputers)",value:$policy.limits.maxComputers,in:1...64)
        }
    }
    @ViewBuilder private var statusView: some View {
        switch availability {
        case .none: Text("Verificando runtime…")
        case .cliMissing: Label("Docker CLI não encontrado",systemImage:"xmark.circle")
        case .daemonUnavailable(let message): Text("Daemon indisponível: \(message)").font(.caption)
        case .ready(let version):Label("Daemon disponível · \(version)",systemImage:"checkmark.circle")
        }
    }
    private func load() { do {policy=try store.load();dockerContext=try DockerConnectionStore().load().contextName ?? "";readable=true;errorText=nil} catch {readable=false;errorText=error.localizedDescription} }
    private func save() { do {try store.save(policy);errorText=nil;saved=true} catch {saved=false;errorText=error.localizedDescription} }
    private func refresh() {
        busy=true
        Task.detached {
            let runner=DockerProcessRunner()
            let discovered=try? runner.run(["context","ls","--format","{{.Name}}"],timeout:5)
            let names=discovered?.exitCode == 0 ? discovered!.stdout.split(whereSeparator:\.isNewline).map(String.init) : []
            let status=DockerComputerService(runner:runner).availability()
            await MainActor.run{contexts=names;availability=status;busy=false}
        }
    }
}

private struct ComputerScopeEditor:View {
    @Environment(\.dismiss) private var dismiss
    @State var item:ComputerPolicyOverride
    let onSave:(ComputerPolicyOverride)->Void
    @State private var error:String?
    var body:some View {
        Form {
            Picker("Escopo",selection:$item.scope){ForEach(ComputerPolicyScope.allCases,id:\.self){Text($0.rawValue).tag($0)}}
            TextField("ID / caminho do projeto",text:$item.scopeID)
            Picker("Criação",selection:$item.creation) {
                Text("Herdar").tag(ComputerCreationPermission?.none)
                Text("Desativar").tag(ComputerCreationPermission?.some(.disabled))
                Text("Somente manual").tag(ComputerCreationPermission?.some(.manual))
            }
            Toggle("Exigir desktop",isOn:Binding(get:{item.modePreference == .alwaysGraphical},set:{item.modePreference=$0 ? .alwaysGraphical:nil}))
            Toggle("Bloquear rede",isOn:Binding(get:{item.networkAllowed == false},set:{item.networkAllowed=$0 ? false:nil}))
            Toggle("Restringir recursos",isOn:Binding(get:{item.limits != nil},set:{item.limits=$0 ? ComputerResourceLimits():nil}))
            if item.limits != nil {
                Stepper("CPU: \((item.limits?.cpus ?? 1),specifier:"%.2g")",value:Binding(get:{(item.limits?.cpus ?? 1)},set:{item.limits?.cpus=$0}),in:0.25...32,step:0.25)
                Stepper("Memória: \((item.limits?.memoryMiB ?? 768)) MiB",value:Binding(get:{(item.limits?.memoryMiB ?? 768)},set:{item.limits?.memoryMiB=$0}),in:128...65536,step:128)
                Stepper("Teto ativo: \((item.limits?.maxComputers ?? 2))",value:Binding(get:{(item.limits?.maxComputers ?? 2)},set:{item.limits?.maxComputers=$0}),in:1...64)
            }
            if let error {Text(error).foregroundStyle(.red)}
            HStack {Button("Cancelar"){dismiss()};Spacer();Button("Aplicar"){do{item.scopeID=item.scopeID.trimmingCharacters(in:.whitespacesAndNewlines);try ComputerPolicy(overrides:[item]).validate();onSave(item);dismiss()}catch{self.error=error.localizedDescription}}}
        }.padding(20).frame(width:520,height:440)
    }
}

public struct ComputerPanel: View {
    public let terminalID: UUID
    public let context: ComputerPolicyContext
    public let onReviewAgent: (ScrapingBoxAssignment) -> Void
    @State private var policy = ComputerPolicy()
    @State private var availability: DockerAvailability?
    @State private var computer: ManagedComputer?
    @State private var errorText: String?
    @State private var busy = false
    private let store = ComputerPolicyStore()

    public init(terminalID: UUID, context: ComputerPolicyContext? = nil,
                onReviewAgent: @escaping (ScrapingBoxAssignment) -> Void = { _ in }) {
        self.terminalID = terminalID
        self.context = context ?? ComputerPolicyContext(terminalID:terminalID)
        self.onReviewAgent = onReviewAgent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Computador").font(.headline)
            BrowserComputerPanel(terminalID:terminalID,context:context,onReviewAgent:onReviewAgent)
            Text("Container HTTP básico").font(.caption).foregroundStyle(.secondary)
            Text("Terminal \(terminalID.uuidString)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let availability {
                switch availability {
                case .cliMissing: Text("Docker CLI não encontrado")
                case .daemonUnavailable(let detail): Text("Daemon indisponível: \(detail)")
                case .ready(let version): Text("Docker disponível · \(version)")
                }
            } else { ProgressView("Verificando Docker…") }
            if let computer {
                Label(computer.running ? "Container HTTP em execução" : "Container HTTP parado",
                      systemImage: computer.running ? "checkmark.circle" : "pause.circle")
                Text(computer.name).font(.caption.monospaced()).textSelection(.enabled)
                if computer.running {
                    Button("Parar computador") { performStop() }.disabled(busy)
                } else {
                    Button("Iniciar computador") { performCreate() }.disabled(busy || effective?.creation == .disabled || effective == nil)
                }
            } else {
                Text("Sem computador para este terminal").foregroundStyle(.secondary)
                Button("Criar computador HTTP") { performCreate() }
                    .disabled(busy || effective?.creation == .disabled || effective == nil || !dockerReady)
            }
            if effective?.creation == .disabled {
                Text("Criação desativada em Configurações › Docker.").font(.caption).foregroundStyle(.secondary)
            }
            if let effective {Text("Política: \(effective.sources.joined(separator:" → "))").font(.caption2).foregroundStyle(.secondary)}
            Text("Este container básico oferece Python e rede para HTTP. Para navegador e streaming, use o computador acima. A atribuição automática a subagentes ainda está em implementação.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorText { Text(errorText).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
            Button("Atualizar estado") { refresh() }.disabled(busy)
            Spacer(minLength: 0)
        }
        .padding()
        .task { refresh() }
    }

    private var effective: EffectiveComputerPolicy? {try? policy.effective(for:context)}
    private var dockerReady: Bool { if case .ready = availability { return true }; return false }
    private func refresh() {
        busy = true
        Task.detached {
            let service = DockerComputerService(runner: DockerProcessRunner())
            let availability = service.availability()
            let result = Result { try (ComputerPolicyStore().load(), service.computer(for: terminalID)) }
            await MainActor.run {
                self.availability = availability
                switch result {
                case .success(let (policy, computer)):
                    self.policy = policy; self.computer = computer; self.errorText = nil
                case .failure(let error): self.errorText = error.localizedDescription
                }
                self.busy = false
            }
        }
    }
    private func performCreate() {
        busy = true; errorText = nil
        Task.detached {
            let result = Result { try DockerComputerService(runner: DockerProcessRunner()).createAndStart(for: terminalID, context: context) }
            await MainActor.run {
                switch result {
                case .success(let computer): self.computer = computer
                case .failure(let error): self.errorText = error.localizedDescription
                }
                self.busy = false
            }
        }
    }
    private func performStop() {
        busy = true; errorText = nil
        Task.detached {
            let service = DockerComputerService(runner: DockerProcessRunner())
            let result = Result { try service.stop(for: terminalID); return try service.computer(for: terminalID) }
            await MainActor.run {
                switch result {
                case .success(let computer): self.computer = computer
                case .failure(let error): self.errorText = error.localizedDescription
                }
                self.busy = false
            }
        }
    }
}
