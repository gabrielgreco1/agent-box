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
        let inbox: ClaudeHookInbox?
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
        let inbox = hook.flatMap { config in registry.map { ClaudeHookInbox(configuration: config, registry: $0) } }
        observations[terminalID] = Observation(runID: runID, inbox: inbox)
        let task = Task { [weak self] in
            await previousTask?.value
            await self?.observe(terminalID: terminalID, provider: provider,
                                processID: processID, runID: runID)
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

    /// A PreToolUse route is valid only after the authenticated SessionStart
    /// event has linked this Claude process to the native session in the registry.
    func verifiedParentSession(terminalID: UUID, runID: UUID, sessionID: String) async -> Bool {
        guard !sessionID.isEmpty, let registry else { return false }
        await bootstrapTask?.value
        for attempt in 0..<6 {
            guard let observation = observations[terminalID],
                  observation.runID == runID, !observation.exitRequested,
                  let inbox = observation.inbox else { return false }
            let before = await registry.allRuns()
            if let admitted = before.first(where: { $0.id == runID && $0.kind == .terminal }) {
                guard admitted.terminalID == terminalID, admitted.provider == .claude,
                      admitted.status == .running else { return false }
                do { if try await inbox.drain() > 0 { await refresh(registry) } }
                catch { return false }
                let records = await registry.allRuns()
                guard let parent = records.first(where: { $0.id == runID && $0.kind == .terminal }),
                      parent.status == .running else { return false }
                if let observed = parent.nativeSessionID {
                    return parent.nativeHookSource == .claude && observed == sessionID
                }
            }
            if attempt < 5 { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        return false
    }

    /// A child can request a new box only while its observed parent PTY and
    /// native hook run are still current. Historical hook state is not liveness.
    public func isCurrentNativeChild(runID: UUID, parentTerminalID: UUID,
                                     runtime: TerminalRuntimeManager) -> Bool {
        guard let child = runs.first(where: { $0.id == runID && $0.kind == .nativeSubagent }),
              child.parentTerminalID == parentTerminalID, child.terminalID == parentTerminalID,
              child.status == .running, let parentRunID = child.parentRunID,
              let parent = runs.first(where: { $0.id == parentRunID && $0.kind == .terminal }),
              parent.terminalID == parentTerminalID, parent.status == .running,
              let observation = observations[parentTerminalID],
              observation.runID == parentRunID, !observation.exitRequested,
              case .running(let pid) = runtime.state(for: parentTerminalID),
              parent.processID == pid else { return false }
        return true
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
                         runID: UUID) async {
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

        let inbox = observations[terminalID]?.runID == runID ? observations[terminalID]?.inbox : nil
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
