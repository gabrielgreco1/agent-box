import AgentBoxCore
import Foundation
import SwiftUI

/// Observes terminal processes and authenticated native hooks. PTY text is never parsed as identity.
@MainActor
public final class NativeAgentMonitor: ObservableObject {
    public static let shared = NativeAgentMonitor()

    @Published public private(set) var runs: [AgentRunRecord] = []
    @Published public private(set) var errorText: String?

    private struct Observation {
        let runID: UUID
        var exitRequested = false
        var task: Task<Void, Never>?
    }

    private let registry: AgentRunRegistry?
    private let pollIntervalNanoseconds: UInt64
    private var bootstrapTask: Task<Void, Never>?
    private var observations: [UUID: Observation] = [:]
    private var refreshRevision = 0

    public init(registry: AgentRunRegistry? = try? AgentRunRegistry(),
                pollIntervalNanoseconds: UInt64 = 300_000_000) {
        self.registry = registry
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        if registry == nil { errorText = "Não foi possível abrir o histórico de agentes." }
        bootstrapTask = Task { [weak self] in await self?.reconcilePreviousRuns() }
    }

    /// The caller reports only a process that SwiftTerm has observed running with a real PID.
    public func didStart(terminalID: UUID, provider: CLIProvider, processID: Int32,
                         runID: UUID, hook: ClaudeHookInboxConfiguration?) {
        guard observations[terminalID] == nil || observations[terminalID]?.exitRequested == true else {
            errorText = "Já existe uma observação ativa para este terminal."
            return
        }
        let previousTask = observations[terminalID]?.task
        observations[terminalID] = Observation(runID: runID)
        let task = Task { [weak self] in
            await previousTask?.value
            await self?.observe(terminalID: terminalID, provider: provider,
                                processID: processID, runID: runID, hook: hook)
        }
        observations[terminalID]?.task = task
    }

    /// May arrive before asynchronous registry admission; observe() serializes admission first.
    public func didExit(terminalID: UUID, runID: UUID) {
        guard var observation = observations[terminalID], observation.runID == runID else { return }
        observation.exitRequested = true
        observation.task?.cancel()
        observations[terminalID] = observation
    }

    public func stopAll() {
        for (terminalID, observation) in observations { didExit(terminalID: terminalID, runID: observation.runID) }
    }

    private func reconcilePreviousRuns() async {
        guard let registry else { return }
        do {
            // A new app process owns none of these PTYs. The parent is no longer observed;
            // native children retain their last hook state because their completion is unknown.
            for run in await registry.allRuns() where run.kind == .terminal && run.status == .running {
                try await registry.finishTerminalRun(run.id)
            }
            await refresh(registry)
        } catch {
            errorText = "Não foi possível reconciliar execuções anteriores."
        }
    }

    private func observe(terminalID: UUID, provider: CLIProvider, processID: Int32,
                         runID: UUID, hook: ClaudeHookInboxConfiguration?) async {
        await bootstrapTask?.value
        guard let registry else {
            if observations[terminalID]?.runID == runID { observations[terminalID] = nil }
            return
        }
        do {
            _ = try await registry.recordTerminalStart(terminalID: terminalID, provider: provider,
                                                       processID: processID, runID: runID)
            await refresh(registry)
        } catch {
            errorText = "Não foi possível registrar a execução do terminal."
            if observations[terminalID]?.runID == runID { observations[terminalID] = nil }
            return
        }

        let inbox = hook.map { ClaudeHookInbox(configuration: $0, registry: registry) }
        while observations[terminalID]?.runID == runID,
              observations[terminalID]?.exitRequested == false,
              !Task.isCancelled {
            if let inbox { await drain(inbox, registry: registry) }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        // A hook can write immediately before PTY exit. Drain while the parent is still
        // recorded as running, then close the parent. This never marks children complete.
        if let inbox { await drain(inbox, registry: registry) }
        do {
            try await registry.finishTerminalRun(runID)
            await refresh(registry)
        } catch {
            errorText = "Não foi possível encerrar o registro da execução."
        }
        if observations[terminalID]?.runID == runID { observations[terminalID] = nil }
    }

    private func drain(_ inbox: ClaudeHookInbox, registry: AgentRunRegistry) async {
        do {
            if try await inbox.drain() > 0 { await refresh(registry) }
        } catch {
            errorText = "O evento de agente nativo foi rejeitado ou não pôde ser lido."
        }
    }

    private func refresh(_ registry: AgentRunRegistry) async {
        refreshRevision += 1
        let revision = refreshRevision
        let latest = await registry.allRuns()
        if revision == refreshRevision { runs = latest }
    }
}
