import Foundation

enum ComputerCreationLock { static let lock = NSRecursiveLock() }

public enum DockerAvailability: Equatable {
    case cliMissing
    case daemonUnavailable(String)
    case ready(serverVersion: String)
}

public struct ManagedComputer: Equatable, Identifiable {
    public let terminalID: UUID
    public let containerID: String
    public let name: String
    public let running: Bool
    public var id: String { containerID }
}

public enum DockerComputerError: Error, LocalizedError, Equatable {
    case unmanagedContainer
    case resourceLimit
    case duplicateContainers
    case containerMissing
    case malformedResponse
    case commandFailed(String)
    public var errorDescription: String? {
        switch self {
        case .unmanagedContainer: return "O container existente não pertence ao Agent Box; nenhuma ação foi feita."
        case .resourceLimit: return "O teto de computadores ativos foi atingido. Pare um computador ou ajuste o teto global."
        case .duplicateContainers: return "Mais de um container gerenciado foi encontrado para este terminal. Resolva o conflito no Docker antes de continuar."
        case .containerMissing: return "Nenhum computador foi encontrado para este terminal."
        case .malformedResponse: return "Docker retornou uma resposta inesperada."
        case .commandFailed(let detail): return "Docker: \(detail)"
        }
    }
}

/// A first HTTP-capable box: Python standard-library networking, with no viewer or browser.
/// Its workload receives no Docker socket, host directory mount, published port, or privileged flag.
public struct DockerComputerService<Runner: DockerCommandRunning> {
    public static var image: String { "python:3.12.8-slim-bookworm" }
    public static var ownerLabel: String { "com.agentbox.managed" }
    public static var terminalLabel: String { "com.agentbox.terminal-id" }
    public let runner: Runner
    public let policyStore: ComputerPolicyStore

    public init(runner: Runner, policyStore: ComputerPolicyStore = ComputerPolicyStore()) {
        self.runner = runner; self.policyStore = policyStore
    }

    public func availability() -> DockerAvailability {
        do {
            let result = try runner.run(["version", "--format", "{{.Server.Version}}"], timeout: 5)
            guard result.exitCode == 0 else {
                return .daemonUnavailable(trim(result.stderr.isEmpty ? result.stdout : result.stderr))
            }
            return .ready(serverVersion: trim(result.stdout))
        } catch DockerCommandError.executableMissing { return .cliMissing }
        catch { return .daemonUnavailable(error.localizedDescription) }
    }

    public func listManagedComputers() throws -> [ManagedComputer] {
        let ids = try checked(["ps", "-a", "-q", "--filter", "label=\(Self.ownerLabel)=true"], timeout: 8)
            .stdout.split(whereSeparator: \.isNewline).map(String.init)
        return try ids.compactMap { id in
            let labels = try labelsFor(id)
            guard labels[Self.ownerLabel] == "true",
                  let rawID = labels[Self.terminalLabel], let terminalID = UUID(uuidString: rawID) else { return nil }
            return try inspectOwned(id, terminalID: terminalID)
        }
    }

    private func labelsFor(_ id: String) throws -> [String: String] {
        let response = try checked(["inspect", "--format", "{{json .Config.Labels}}", id], timeout: 8)
        guard let data = response.stdout.data(using: .utf8),
              let labels = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw DockerComputerError.malformedResponse
        }
        return labels
    }

    public func computer(for terminalID: UUID) throws -> ManagedComputer? {
        let ids = try checked(["ps", "-a", "-q", "--filter", "label=\(Self.ownerLabel)=true",
                               "--filter", "label=\(Self.terminalLabel)=\(terminalID.uuidString.lowercased())"], timeout: 8)
            .stdout.split(whereSeparator: \.isNewline).map(String.init)
        let computers = try ids.compactMap { try inspectOwned($0, terminalID: terminalID) }
        if computers.count > 1 { throw DockerComputerError.duplicateContainers }
        return computers.first
    }

    public func createAndStart(for terminalID: UUID, context: ComputerPolicyContext? = nil) throws -> ManagedComputer {
        ComputerCreationLock.lock.lock()
        defer { ComputerCreationLock.lock.unlock() }
        let ancestry = context ?? ComputerPolicyContext(terminalID: terminalID)
        guard ancestry.terminalID == terminalID else { throw ComputerPolicyError.invalidScope }
        let policy = try policyStore.load().effective(for: ancestry)
        guard policy.creation != .disabled else { throw ComputerPolicyError.creationDisabled }
        guard policy.modePreference != .alwaysGraphical else { throw ComputerPolicyError.graphicalUnavailable }
        if let existing = try computer(for: terminalID) {
            if existing.running { return existing }
            try checkCapacity(policy)
            try start(existing)
            return try computer(for: terminalID) ?? existing
        }
        try checkCapacity(policy)
        let name = "agentbox-\(terminalID.uuidString.lowercased())"
        // Docker will reject name conflicts, including unowned containers; never overwrite them.
        _ = try checked(["create", "--name", name,
                         "--label", "\(Self.ownerLabel)=true",
                         "--label", "\(Self.terminalLabel)=\(terminalID.uuidString.lowercased())",
                         "--cpus", String(policy.limits.cpus), "--memory", "\(policy.limits.memoryMiB)m", "--pids-limit", "128",
                         "--read-only", "--tmpfs", "/tmp:rw,nosuid,nodev,size=128m",
                         "--security-opt", "no-new-privileges", "--cap-drop", "ALL",
                         "--user", "65534:65534", "--network", policy.networkAllowed ? "bridge" : "none", "--init",
                         Self.image, "sleep", "infinity"], timeout: 120)
        guard let computer = try computer(for: terminalID) else { throw DockerComputerError.containerMissing }
        try start(computer)
        guard let running = try self.computer(for: terminalID), running.running else {
            throw DockerComputerError.commandFailed("O container foi criado, mas não está em execução.")
        }
        return running
    }

    public func stop(for terminalID: UUID) throws {
        guard let computer = try computer(for: terminalID) else { throw DockerComputerError.containerMissing }
        guard computer.running else { return }
        guard try inspectOwned(computer.containerID, terminalID: terminalID) != nil else {
            throw DockerComputerError.unmanagedContainer
        }
        _ = try checked(["stop", "--time", "10", computer.containerID], timeout: 20)
    }

    private func checkCapacity(_ policy: EffectiveComputerPolicy) throws {
        let active = try checked(["ps", "-q", "--filter", "label=\(Self.ownerLabel)=true"], timeout: 8)
            .stdout.split(whereSeparator: \.isNewline).count
        let browsers = try checked(["ps", "-q", "--filter", "label=com.agentbox.browser-managed=true"], timeout: 8)
            .stdout.split(whereSeparator: \.isNewline).count
        guard active + browsers < policy.limits.maxComputers else { throw DockerComputerError.resourceLimit }
    }

    private func start(_ computer: ManagedComputer) throws {
        // Check ownership again immediately before mutating an existing container.
        guard try inspectOwned(computer.containerID, terminalID: computer.terminalID) != nil else {
            throw DockerComputerError.unmanagedContainer
        }
        _ = try checked(["start", computer.containerID], timeout: 30)
    }

    private func inspectOwned(_ id: String, terminalID: UUID) throws -> ManagedComputer? {
        let result = try checked(["inspect", "--format", "{{json .}}", id], timeout: 8)
        guard let data = result.stdout.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = json["Config"] as? [String: Any],
              let labels = config["Labels"] as? [String: String],
              let state = json["State"] as? [String: Any],
              let running = state["Running"] as? Bool,
              let containerID = json["Id"] as? String,
              let rawName = json["Name"] as? String else { throw DockerComputerError.malformedResponse }
        guard labels[Self.ownerLabel] == "true",
              labels[Self.terminalLabel] == terminalID.uuidString.lowercased() else { return nil }
        return ManagedComputer(terminalID: terminalID, containerID: containerID,
                               name: String(rawName.drop(while: { $0 == "/" })), running: running)
    }

    @discardableResult private func checked(_ args: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        let result = try runner.run(args, timeout: timeout)
        guard result.exitCode == 0 else {
            let detail = trim(result.stderr.isEmpty ? result.stdout : result.stderr)
            throw DockerComputerError.commandFailed(detail.isEmpty ? "Comando falhou (código \(result.exitCode))." : detail)
        }
        return result
    }
    private func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
