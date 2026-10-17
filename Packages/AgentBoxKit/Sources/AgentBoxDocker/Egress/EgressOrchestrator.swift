import Foundation

public enum EgressOrchestratorError: Error, Sendable, Equatable {
    case noSubnet(network: String)
    case noPublishedPort
    case notInternal(network: String)
}

/// Pedido para criar a rede interna de um computador e o egress dele (07 §2.2, CS-110..112, CS-145, CS-602).
public struct EgressProvisionRequest: Sendable {
    public var labels: ComputerLabels
    /// Tag da imagem `agentbox-egress` (`ImageManager.ensure`).
    public var image: String
    /// Token do computador (admin API). Vai para arquivo 0400, nunca para env.
    public var token: String
    /// Config completa do egress menos `internalSubnet` (preenchida aqui com a sub-rede da rede criada).
    public var config: EgressConfigFile
    public var proxyCA: String?
    public var secrets: BoxSecretFiles
    /// Pasta do host com `requests.jsonl`, `bodies/`, `usage.json`; montada rw SÓ no egress (CS-149).
    public var logsDirectory: URL
    /// Bridge compartilhada de saída (`agentbox-egress`).
    public var bridgeNetwork: String
    /// Labels extras nos recursos (testes: `agentbox.test_run`).
    public var extraLabels: [String: String]
    public var memoryBytes: Int64

    public init(labels: ComputerLabels, image: String, token: String, config: EgressConfigFile, proxyCA: String? = nil, secrets: BoxSecretFiles,
                logsDirectory: URL, bridgeNetwork: String = EgressOrchestrator.sharedBridgeName, extraLabels: [String: String] = [:],
                memoryBytes: Int64 = 128 << 20) {
        self.labels = labels; self.image = image; self.token = token; self.config = config; self.proxyCA = proxyCA; self.secrets = secrets
        self.logsDirectory = logsDirectory; self.bridgeNetwork = bridgeNetwork; self.extraLabels = extraLabels; self.memoryBytes = memoryBytes
    }
}

public struct ProvisionedEgress: Sendable, Equatable {
    public var networkName: String
    public var networkID: String
    public var internalSubnet: String
    public var bridgeNetwork: String
    public var egressContainerID: String
    public var egressContainerName: String
    /// Porta efêmera em `127.0.0.1` (admin API). É a ÚNICA porta publicada do computador.
    public var adminPort: Int
    /// Pasta (host) montada somente leitura em `/run/agentbox` no egress.
    public var secretsDirectory: URL
    public var logsDirectory: URL
}

/// Rede interna + egress + publicação só do egress em `127.0.0.1` (CS-110, CS-111). `work`/`runtime` entram na T3-03 e só se
/// conectam à rede interna devolvida aqui.
public struct EgressOrchestrator: Sendable {
    public static let sharedBridgeName = "agentbox-egress"
    /// Porta do proxy dentro da rede interna (`http://egress:3128`).
    public static let proxyAlias = "egress"

    public let client: DockerClient

    public init(client: DockerClient) { self.client = client }

    /// Variáveis de proxy do `work` (CS-112). Sem rota para fora: o que ignora o proxy falha.
    public static func workEnvironment(proxyPort: Int = EgressConfigFile.defaultProxyPort) -> [String] {
        let url = "http://\(proxyAlias):\(proxyPort)"
        let noProxy = "\(proxyAlias),localhost,127.0.0.1"
        return ["HTTP_PROXY=\(url)", "HTTPS_PROXY=\(url)", "ALL_PROXY=\(url)", "http_proxy=\(url)", "https_proxy=\(url)", "all_proxy=\(url)",
                "NO_PROXY=\(noProxy)", "no_proxy=\(noProxy)"]
    }

    /// Cria a bridge compartilhada se não existir. Idempotente.
    @discardableResult
    public func ensureBridge(name: String, labels: [String: String]) async throws -> String {
        if let existing = try await client.listNetworks(filters: ["name": [name]]).first(where: { $0.name == name }) { return existing.id }
        return try await client.createNetwork(name: name, isInternal: false, labels: labels)
    }

    public func provision(_ request: EgressProvisionRequest) async throws -> ProvisionedEgress {
        let labels = request.labels
        var resourceLabels = labels.labels(role: nil)
        resourceLabels.merge(request.extraLabels) { $1 }
        let computerID = labels.computerID

        // 1. rede interna do computador (sem rota para fora) e bridge compartilhada de saída
        let networkID = try await client.createNetwork(name: labels.networkName, isInternal: true, labels: resourceLabels)
        do {
            let network = try await client.inspectNetwork(networkID)
            guard network.isInternal else { throw EgressOrchestratorError.notInternal(network: network.name) }
            guard let subnet = network.subnets.first else { throw EgressOrchestratorError.noSubnet(network: network.name) }
            try await ensureBridge(name: request.bridgeNetwork, labels: request.extraLabels)

            // 2. segredos em arquivo 0400 (só o egress os recebe)
            var config = request.config
            config.internalSubnet = subnet
            var upstream = config.upstream
            let caPath = "/run/agentbox/proxy-ca.pem"
            if let ca = request.proxyCA, upstream != nil {
                try request.secrets.write(Data(ca.utf8), named: "proxy-ca.pem", computerID: computerID, role: .egress)
                upstream?.caFile = caPath
            }
            config.upstream = upstream
            try request.secrets.write(try config.jsonData(), named: "egress.json", computerID: computerID, role: .egress)
            try request.secrets.write(Data(request.token.utf8), named: "token", computerID: computerID, role: .egress)
            let secretsDirectory = try request.secrets.roleDirectory(computerID, role: .egress)
            try FileManager.default.createDirectory(at: request.logsDirectory, withIntermediateDirectories: true)

            // 3. egress: rede interna (alias `egress`), conectado à bridge antes do start, porta admin só em 127.0.0.1
            var spec = ContainerSpec(name: labels.containerName(.egress), image: request.image)
            spec.labels = labels.labels(role: .egress).merging(request.extraLabels) { $1 }
            spec.user = "10003"
            spec.hostname = "egress"
            spec.resources = ContainerResources(memoryBytes: request.memoryBytes, cpus: 0.25, pidsLimit: 256)
            spec.tmpfs = ["/tmp": "rw,noexec,nosuid,size=16m,uid=10003"]
            spec.binds = ["\(secretsDirectory.path):/run/agentbox:ro", "\(request.logsDirectory.path):/logs"]
            spec.network = ContainerNetworkAttachment(network: labels.networkName, aliases: [Self.proxyAlias])
            spec.publishedPorts = [PublishedPort(containerPort: "\(config.adminPort)/tcp", hostIP: "127.0.0.1", hostPort: "")]
            spec.stopTimeoutSeconds = 5
            let containerID = try await client.createContainer(spec)
            try await client.connectNetwork(request.bridgeNetwork, container: containerID)
            try await client.startContainer(containerID)

            let inspect = try await client.inspectContainer(containerID)
            guard let port = inspect.publishedHostPort(for: "\(config.adminPort)/tcp") else { throw EgressOrchestratorError.noPublishedPort }
            return ProvisionedEgress(
                networkName: labels.networkName, networkID: networkID, internalSubnet: subnet, bridgeNetwork: request.bridgeNetwork,
                egressContainerID: containerID, egressContainerName: spec.name, adminPort: port, secretsDirectory: secretsDirectory,
                logsDirectory: request.logsDirectory)
        } catch {
            // não deixa rede, container nem segredo órfãos
            _ = try? await GarbageCollector(client: client).removeComputer(id: computerID)
            try? request.secrets.removeAll(computerID: computerID)
            throw error
        }
    }

    /// Escreve a nova config (troca de proxy) de forma atômica; quem chama pede o `reload` pela admin API (CS-141).
    public func rewriteConfig(_ config: EgressConfigFile, proxyCA: String?, secrets: BoxSecretFiles, computerID: String) throws {
        var config = config
        if let ca = proxyCA, config.upstream != nil {
            try secrets.write(Data(ca.utf8), named: "proxy-ca.pem", computerID: computerID, role: .egress)
            config.upstream?.caFile = "/run/agentbox/proxy-ca.pem"
        }
        try secrets.write(try config.jsonData(), named: "egress.json", computerID: computerID, role: .egress)
    }

    /// Remove egress, rede e segredos do computador (CS-180). A pasta de logs do host é do app e não é apagada aqui.
    public func teardown(computerID: String, secrets: BoxSecretFiles) async throws -> [(ManagedResource, DockerError)] {
        let failures = try await GarbageCollector(client: client).removeComputer(id: computerID)
        try secrets.removeAll(computerID: computerID)
        return failures
    }
}
