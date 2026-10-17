import Foundation

extension ComputerDisplay {
    /// Limite de memória e CPU do `runtime` (07 §2.4).
    var runtimeMemory: Int64 { self == .desktop ? 3 << 30 : 2 << 30 }
    var runtimeCPUs: Double { self == .desktop ? 2 : 1 }
}

public enum ComputerProvisionerError: Error, Sendable, Equatable {
    case runtimeNotReady(String)
}

/// Pedido para montar um computador completo: rede interna + egress + `runtime` (se o display não é `http`) + `work`
/// (07 §2.2, CS-110..116).
public struct ComputerProvisionRequest: Sendable {
    public var labels: ComputerLabels
    /// Tag de `agentbox-box` (papéis `runtime` e `work`).
    public var boxImage: String
    public var egressImage: String
    public var display: ComputerDisplay
    /// Token do computador: arquivo 0400 no egress e no runtime. Nunca env, nunca no `work`.
    public var token: String
    public var config: EgressConfigFile
    public var proxyCA: String?
    public var secrets: BoxSecretFiles
    /// `.../runs/<session>/<computer>/`: `work/` vira bind rw em `/work`; `logs/` só o egress escreve (CS-149, CS-233).
    public var runDirectory: URL
    public var bridgeNetwork: String
    public var extraLabels: [String: String]
    /// Volume do perfil do Chromium. `nil` = efêmero `ab-prof-<computerId>` (CS-170).
    public var profileVolume: String?

    public init(labels: ComputerLabels, boxImage: String, egressImage: String, display: ComputerDisplay, token: String,
                config: EgressConfigFile, proxyCA: String? = nil, secrets: BoxSecretFiles, runDirectory: URL,
                bridgeNetwork: String = EgressOrchestrator.sharedBridgeName, extraLabels: [String: String] = [:],
                profileVolume: String? = nil) {
        self.labels = labels; self.boxImage = boxImage; self.egressImage = egressImage; self.display = display; self.token = token
        self.config = config; self.proxyCA = proxyCA; self.secrets = secrets; self.runDirectory = runDirectory
        self.bridgeNetwork = bridgeNetwork; self.extraLabels = extraLabels; self.profileVolume = profileVolume
    }
}

public struct ProvisionedComputer: Sendable {
    public var labels: ComputerLabels
    public var display: ComputerDisplay
    public var egress: ProvisionedEgress
    public var runtimeContainerID: String?
    public var workContainerID: String
    public var profileVolume: String?
    public var workDirectory: URL
    public var logsDirectory: URL
    public var admin: EgressAdminClient
}

/// Cria e destrói computadores. Só usa recursos com os labels do computador (GC por label, nunca varredura geral).
public struct ComputerProvisioner: Sendable {
    public let client: DockerClient

    public init(client: DockerClient) { self.client = client }

    public func provision(_ request: ComputerProvisionRequest) async throws -> ProvisionedComputer {
        let labels = request.labels
        let computerID = labels.computerID
        let work = request.runDirectory.appendingPathComponent("work", isDirectory: true)
        let logs = request.runDirectory.appendingPathComponent("logs", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)

        let egress = try await EgressOrchestrator(client: client).provision(EgressProvisionRequest(
            labels: labels, image: request.egressImage, token: request.token, config: request.config, proxyCA: request.proxyCA,
            secrets: request.secrets, logsDirectory: logs, bridgeNetwork: request.bridgeNetwork, extraLabels: request.extraLabels))
        let admin = EgressAdminClient(port: egress.adminPort, token: request.token)
        var profileName: String?
        do {
            try await admin.waitUntilHealthy()
            var runtimeID: String?
            if request.display != .http {
                try request.secrets.write(Data(request.token.utf8), named: "token", computerID: computerID, role: .runtime)
                let secretsDirectory = try request.secrets.roleDirectory(computerID, role: .runtime)
                let volume = request.profileVolume ?? "ab-prof-\(computerID)"
                profileName = volume
                var volumeLabels = labels.labels(role: .runtime)
                volumeLabels.merge(request.extraLabels) { $1 }
                _ = try await client.createVolume(name: volume, labels: volumeLabels)
                runtimeID = try await startRuntime(request, secretsDirectory: secretsDirectory, volume: volume)
            }
            let workID = try await startWork(request, work: work)
            if runtimeID != nil { try await waitRuntimeReady(admin) }
            return ProvisionedComputer(
                labels: labels, display: request.display, egress: egress, runtimeContainerID: runtimeID, workContainerID: workID,
                profileVolume: profileName, workDirectory: work, logsDirectory: logs, admin: admin)
        } catch {
            _ = try? await GarbageCollector(client: client).removeComputer(id: computerID)
            try? request.secrets.removeAll(computerID: computerID)
            throw error
        }
    }

    private func startRuntime(_ request: ComputerProvisionRequest, secretsDirectory: URL, volume: String) async throws -> String {
        let labels = request.labels
        var spec = ContainerSpec(name: labels.containerName(.runtime), image: request.boxImage)
        spec.labels = labels.labels(role: .runtime).merging(request.extraLabels) { $1 }
        spec.user = "10001"
        spec.hostname = "runtime"
        spec.environment = ["AGENTBOX_ROLE=runtime", "DISPLAY=:99", "HOME=/home/runtime"]
        spec.resources = ContainerResources(memoryBytes: request.display.runtimeMemory, cpus: request.display.runtimeCPUs, pidsLimit: 1024)
        spec.tmpfs = ["/tmp": "rw,nosuid,size=512m,uid=10001", "/home/runtime": "rw,nosuid,size=256m,uid=10001"]
        spec.binds = ["\(secretsDirectory.path):/run/agentbox:ro"]
        spec.named = ["\(volume):/profile"]
        spec.network = ContainerNetworkAttachment(network: labels.networkName, aliases: ["runtime"])
        spec.stopTimeoutSeconds = 5
        let id = try await client.createContainer(spec)
        try await client.startContainer(id)
        return id
    }

    private func startWork(_ request: ComputerProvisionRequest, work: URL) async throws -> String {
        let labels = request.labels
        var spec = ContainerSpec(name: labels.containerName(.work), image: request.boxImage)
        spec.labels = labels.labels(role: .work).merging(request.extraLabels) { $1 }
        spec.user = "10002"
        spec.hostname = "work"
        spec.workingDirectory = "/work"
        spec.environment = ["AGENTBOX_ROLE=work", "HOME=/tmp"] + EgressOrchestrator.workEnvironment(proxyPort: request.config.proxyPort)
        spec.resources = ContainerResources(memoryBytes: 1 << 30, cpus: 0.5, pidsLimit: 512)
        spec.tmpfs = ["/tmp": "rw,nosuid,size=1g,uid=10002"]
        spec.binds = ["\(work.path):/work"]
        spec.network = ContainerNetworkAttachment(network: labels.networkName, aliases: ["work"])
        spec.stopTimeoutSeconds = 3
        let id = try await client.createContainer(spec)
        try await client.startContainer(id)
        return id
    }

    /// Espera o Chromium headed do runtime ficar pronto (o Playwright demora alguns segundos para subir).
    func waitRuntimeReady(_ admin: EgressAdminClient, timeout: Duration = .seconds(90)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await admin.runtimeReady() { return }
            try await Task.sleep(for: .milliseconds(400))
        }
        throw ComputerProvisionerError.runtimeNotReady("o browser do runtime não ficou pronto em \(timeout)")
    }

    /// Fim do run (07 CS-180): containers, rede, volume de perfil efêmero e segredos. A pasta do run no host fica.
    public func teardown(_ computer: ProvisionedComputer, secrets: BoxSecretFiles) async throws -> [(ManagedResource, DockerError)] {
        let failures = try await GarbageCollector(client: client).removeComputer(id: computer.labels.computerID)
        try secrets.removeAll(computerID: computer.labels.computerID)
        return failures
    }
}
