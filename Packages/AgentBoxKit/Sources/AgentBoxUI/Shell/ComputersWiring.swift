import AgentBoxCore
import AgentBoxDocker
import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxStore
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
    /// Cria o orquestrador depois que o Store abriu. Sem o helper `agentbox` (nem bundle nem `AGENTBOX_HELPER`) não há como o Claude
    /// falar com o app, então nada é injetado e "Subagent computers" fica inerte.
    func startOrchestrator(store: AgentBoxStore) async {
        guard flags.isEnabled(.slice3), orchestratorHolder.value == nil, let helper = Self.helperPath(environmentVariables) else { return }
        let root = StorePaths.default(environment: environmentVariables).root
        var config = AppComputerProvisioning.Config(
            runtimeRoot: RuntimeContextLocator.root(environment: environmentVariables, bundleURL: Bundle.main.bundleURL),
            secretsRoot: root.appendingPathComponent("computers", isDirectory: true), owner: "agent-box")
        // Testes e evidência (AGENTBOX_TEST_RUN): tudo leva `agentbox.test=1` + `agentbox.test_run=<id>` e sai com o cleanup do teste.
        if let run = environmentVariables["AGENTBOX_TEST_RUN"], !run.isEmpty {
            config.isTest = true
            config.owner = "test-\(run)"
            config.repositorySuffix = "-test-\(run)"
            config.extraLabels = [AgentBoxLabel.test: "1", "agentbox.test_run": run]
            if let bridge = environmentVariables["AGENTBOX_COMPUTER_BRIDGE"], !bridge.isEmpty { config.bridgeNetwork = bridge }
            config.allowCIDRs = (environmentVariables["AGENTBOX_ALLOW_CIDRS"] ?? "").split(separator: ",").map { String($0) }
        }
        let provisioning = AppComputerProvisioning(config: config)
        let wait = environmentVariables["AGENTBOX_ASK_WAIT_S"].flatMap(TimeInterval.init) ?? 45
        let orchestrator = ComputerOrchestrator(
            helperPath: helper, store: store, provisioning: provisioning, runsRoot: root.appendingPathComponent("computers/runs", isDirectory: true),
            waitSeconds: wait)
        orchestratorHolder.set(orchestrator)
        let toasts = toasts
        let settings = settings
        await orchestrator.start()
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
                Task { @MainActor in
                    settings.dockerStatus = DockerStatusInfo(text: problem.localizedDescription, stopped: true)
                    toasts.show(
                        kind: .error, title: String(localized: "Docker isn't running", bundle: .module),
                        detail: String(localized: "Subagent computers need Docker. Open it and ask Claude again.", bundle: .module),
                        action: ToastAction(.dockerStart, title: String(localized: "Open Docker", bundle: .module)))
                }
            })
        await computers.useOrchestrator(orchestrator)
        computers.startRefreshing()
        computerSweeper?.cancel()
        computerSweeper = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                _ = await orchestrator.scheduler.sweep()
            }
        }
    }
}
