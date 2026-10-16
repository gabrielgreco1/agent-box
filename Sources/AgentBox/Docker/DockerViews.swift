import SwiftUI
import AgentBoxCore

public struct DockerSettingsView: View {
    @State private var policy = ComputerPolicy()
    @State private var availability: DockerAvailability?
    @State private var errorText: String?
    @State private var busy = false
    private let store = ComputerPolicyStore()

    public init() {}

    public var body: some View {
        Form {
            Section("Docker") {
                statusView
                Button("Verificar novamente") { refresh() }
                    .disabled(busy)
            }
            Section("Criação de computadores") {
                Picker("Permissão", selection: $policy.creation) {
                    Text("Desativada").tag(ComputerCreationPermission.disabled)
                    Text("Manual, por terminal").tag(ComputerCreationPermission.manual)
                }
                .onChange(of: policy.creation) { _, _ in save() }
                Text("Um computador só é criado quando você usa Criar no painel do terminal. Esta opção não altera as permissões dos CLIs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preferência de modo") {
                Picker("Modo", selection: $policy.modePreference) {
                    Text("Adaptativo").tag(ComputerModePreference.adaptive)
                    Text("Sempre gráfico").tag(ComputerModePreference.alwaysGraphical)
                }
                .onChange(of: policy.modePreference) { _, _ in save() }
                Text("Esta preferência está salva para uma versão futura. Atualmente só há container HTTP; navegador, desktop e streaming ainda não são suportados.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .task { load(); refresh() }
    }

    @ViewBuilder private var statusView: some View {
        switch availability {
        case .none: Text("Verificando runtime…")
        case .cliMissing: Label("Docker CLI não encontrado", systemImage: "xmark.circle")
        case .daemonUnavailable(let message):
            VStack(alignment: .leading) {
                Label("Daemon indisponível", systemImage: "exclamationmark.triangle")
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        case .ready(let version): Label("Daemon disponível · \(version)", systemImage: "checkmark.circle")
        }
    }

    private func load() {
        do { policy = try store.load(); errorText = nil }
        catch { errorText = "Não foi possível ler a política: \(error.localizedDescription)" }
    }
    private func save() {
        do { try store.save(policy); errorText = nil }
        catch { errorText = "Não foi possível salvar a política: \(error.localizedDescription)" }
    }
    private func refresh() {
        busy = true
        Task.detached {
            let status = DockerComputerService(runner: DockerProcessRunner()).availability()
            await MainActor.run { availability = status; busy = false }
        }
    }
}

public struct ComputerPanel: View {
    public let terminalID: UUID
    @State private var policy = ComputerPolicy()
    @State private var availability: DockerAvailability?
    @State private var computer: ManagedComputer?
    @State private var errorText: String?
    @State private var busy = false
    private let store = ComputerPolicyStore()

    public init(terminalID: UUID) { self.terminalID = terminalID }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Computador").font(.headline)
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
                    Button("Iniciar computador") { performCreate() }.disabled(busy || policy.creation != .manual)
                }
            } else {
                Text("Sem computador para este terminal").foregroundStyle(.secondary)
                Button("Criar computador HTTP") { performCreate() }
                    .disabled(busy || policy.creation != .manual || !dockerReady)
            }
            if policy.creation == .disabled {
                Text("Criação desativada em Configurações › Docker.").font(.caption).foregroundStyle(.secondary)
            }
            Text("A box oferece um processo Linux com Python e rede para trabalho HTTP. A associação a subagentes nativos, o navegador, o desktop e o streaming ainda não são suportados.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorText { Text(errorText).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
            Button("Atualizar estado") { refresh() }.disabled(busy)
            Spacer(minLength: 0)
        }
        .padding()
        .task { refresh() }
    }

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
            let result = Result { try DockerComputerService(runner: DockerProcessRunner()).createAndStart(for: terminalID) }
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
