import RackyCore
import RackyDocker
import RackyPlatform
import RackyProtocol
import RackyStore
import AppKit
import Foundation
import Synchronization

/// Guarda o orquestrador de computadores (F12) para o lançamento do Claude achá-lo: o `TerminalRuntime` nasce antes do Store.
nonisolated final class OrchestratorHolder: Sendable {
    private let box = Mutex<ComputerOrchestrator?>(nil)
    nonisolated var value: ComputerOrchestrator? { box.withLock { $0 } }
    nonisolated func set(_ orchestrator: ComputerOrchestrator) { box.withLock { $0 = orchestrator } }
}

/// F12/F13: a fiação que a T3-04 deixou fora do app. Orquestrador (hub, scheduler, MCP, porta Ask/Full), `app.sock` com o serviço `mcp`,
/// linhas dos computadores na sidebar, progresso das imagens, "Open Docker" e o sweep dos computadores reservados e esquecidos.
extension AppEnvironment {
    /// Cria o orquestrador depois que o Store abriu. Sem o helper `racky` (nem bundle nem `RACKY_HELPER`) não há como o Claude
    /// falar com o app, então nada é injetado e "Subagent computers" fica inerte.
    /// Label `racky.owner` dos containers. Um `RACKY_HOME` isolado (testes, e2e, dev) ganha um owner próprio, derivado do home:
    /// a adoção e o GC de uma instância nunca enxergam os computadores de outra (o app do dono segue com `racky`).
    nonisolated static func computerOwner(_ environment: [String: String]) -> String {
        guard let home = environment["RACKY_HOME"], !home.isEmpty else { return "racky" }
        return "racky-\(BackgroundAgentIdentity.testSuffix(forHome: home))"
    }

    /// Lote concluído: o item vai à fila de atenção do terminal pai (Inbox + notificação do macOS, uma vez); sem atenção ou sem terminal
    /// conhecido, vira um toast com o mesmo texto.
    func batchFinished(_ summary: BatchSummary) {
        Task { if let orchestrator = orchestratorHolder.value { computers.model.setBatches(await orchestrator.batches()) } }
        let contexts = sidebar.attentionContexts()
        let terminal = contexts.filter { $0.value.sessionID == summary.sessionID }.sorted { $0.key.uuidString < $1.key.uuidString }
            .first { $0.value.provider.supportsSubagentComputers }?.key
            ?? contexts.first { $0.value.sessionID == summary.sessionID }?.key
        if let attention, let sessionID = summary.sessionID, let terminal {
            attention.batchFinished(batchID: summary.name, title: summary.notificationTitle, body: summary.notificationBody, sessionID: sessionID, terminalID: terminal)
        } else {
            toasts.show(kind: .success, title: summary.notificationTitle, detail: summary.notificationBody)
        }
    }

    func startOrchestrator(store: RackyStore) async {
        guard flags.isEnabled(.slice3), orchestratorHolder.value == nil, let helper = Self.helperPath(environmentVariables) else { return }
        let root = StorePaths.default(environment: environmentVariables).root
        var config = AppComputerProvisioning.Config(
            runtimeRoot: RuntimeContextLocator.root(environment: environmentVariables, bundleURL: Bundle.main.bundleURL),
            secretsRoot: root.appendingPathComponent("computers", isDirectory: true), owner: Self.computerOwner(environmentVariables))
        // Testes e evidência (RACKY_TEST_RUN): tudo leva `racky.test=1` + `racky.test_run=<id>` e sai com o cleanup do teste.
        if let run = environmentVariables["RACKY_TEST_RUN"], !run.isEmpty {
            config.isTest = true
            config.owner = "test-\(run)"
            config.repositorySuffix = "-test-\(run)"
            config.extraLabels = [RackyLabel.test: "1", "racky.test_run": run]
            if let bridge = environmentVariables["RACKY_COMPUTER_BRIDGE"], !bridge.isEmpty { config.network = bridge }
            config.allowCIDRs = (environmentVariables["RACKY_ALLOW_CIDRS"] ?? "").split(separator: ",").map { String($0) }
        }
        // F29: `boxes_reserve(proxy:)` e `proxy_set` resolvem o nome para o ProxyProfile salvo (segredo no Vault, só para o egress).
        let proxyService = ProxyService(store: store, vault: SecretVault(store: store, keyring: VaultKeyring(backend: SystemKeychainBackend())))
        config.resolver = { name, country in
            guard let profile = try await store.proxy(named: name) else { throw ProxyServiceError.unknownProxy(name) }
            var resolved = try await proxyService.egressConfig(for: profile.id)
            if let country, var upstream = resolved.config.upstream { upstream.geoCountry = country; resolved.config.upstream = upstream }
            return resolved
        }
        let provisioning = AppComputerProvisioning(config: config)
        // BK-12: `runOn == .cloud` nunca cai no Mac. Sem provedor implementado (a AWS ainda é esqueleto) o pedido falha com mensagem clara.
        let settingsForRoute = settings
        await provisioning.setCloudRoute(CloudComputerRoute(
            place: { await MainActor.run { settingsForRoute.settings.computers.runOn == .cloud ? .cloud : .local } },
            provisioning: nil))
        let wait = environmentVariables["RACKY_ASK_WAIT_S"].flatMap(TimeInterval.init) ?? 45
        let orchestrator = ComputerOrchestrator(
            helperPath: helper, store: store, provisioning: provisioning, runsRoot: root.appendingPathComponent("computers/runs", isDirectory: true),
            waitSeconds: wait, proxies: StoreProxyDirectory(store: store))
        // Reinício do app com Claude e subagentes vivos: as identidades MCP voltam antes de qualquer chamada (só lê o Store).
        await orchestrator.restoreIdentities()
        orchestratorHolder.set(orchestrator)
        let toasts = toasts
        let settings = settings
        await orchestrator.start()
        // T3-07: todos os filhos de um lote terminaram: um item no Inbox e uma notificação (CS-326, AC-429).
        await orchestrator.scheduler.setBatchObserver { [weak self] summary in Task { @MainActor in self?.batchFinished(summary) } }
        await provisioning.setObserver(
            state: { state in
                Task { @MainActor in
                    switch state {
                    case .idle: break
                    case .ready: settings.dockerStatus = DockerStatusInfo(text: String(localized: "Running. Computer images are ready.", bundle: .module))
                    case .failed(let text): settings.dockerStatus = DockerStatusInfo(text: text, stopped: text.hasPrefix(ComputerSetupError.dockerNotRunningMessage))
                    default: settings.dockerStatus = DockerStatusInfo(text: state.label ?? "")
                    }
                }
                Task {
                    // Linhas dos computadores que estão subindo mostram o mesmo progresso (a camada Core já cobre o primeiro quadro).
                    for computer in await orchestrator.hub.allComputers where await computer.state == .provisioning { await computer.setDetail(state.label) }
                }
            },
            problem: { problem in
                if problem == .cloudUnavailable {
                    Task { @MainActor in
                        toasts.show(kind: .error, title: String(localized: "Cloud computers aren't available yet", bundle: .module),
                                    detail: String(localized: "Switch to This Mac in Computers.", bundle: .module))
                    }
                    return
                }
                Task { @MainActor in
                    settings.dockerStatus = DockerStatusInfo(text: problem.localizedDescription, stopped: true)
                    toasts.show(
                        kind: .error, title: String(localized: "Docker isn't running", bundle: .module),
                        detail: String(localized: "Subagent computers need Docker. Open it and ask Claude again.", bundle: .module),
                        action: ToastAction(.dockerStart, title: String(localized: "Open Docker", bundle: .module)))
                }
            })
        computers.proxyNames = { await StoreProxyDirectory(store: store).names() }
        await computers.useOrchestrator(orchestrator)
        computers.startRefreshing()
        // Computadores que seguiram vivos no Docker voltam para o hub (a UI já observa); sem Docker de pé não faz nada.
        Task { await orchestrator.adoptRunning() }
        computerSweeper?.cancel()
        computerSweeper = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                _ = await orchestrator.scheduler.sweep()
            }
        }
    }
}

/// Amostras dos computadores desta instância (label `racky.owner` próprio) para o Insights e a status bar. Detecta o Docker a cada
/// leitura avulsa (só sonda o socket; nunca inicia o Docker) e devolve `nil` quando ele não responde.
struct LazyDockerComputerSource: InsightsComputerSource {
    let owner: String

    func computerSamples() async -> [ContainerSample]? {
        guard let detected = try? await RuntimeDetector().detect() else { return nil }
        let client = DockerClient(runtime: detected.runtime, defaultTimeout: .seconds(5))
        return await DockerComputerSource(client: client, owner: owner).computerSamples()
    }
}

extension AppEnvironment {
    nonisolated static func computerSource(environment: [String: String]) -> LazyDockerComputerSource {
        LazyDockerComputerSource(owner: computerOwner(environment))
    }
}
