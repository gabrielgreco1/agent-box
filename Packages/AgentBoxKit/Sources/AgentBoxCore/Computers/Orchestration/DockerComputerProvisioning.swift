import AgentBoxDocker
import Foundation

/// Fábrica real de computadores para o `ComputerScheduler`: rede interna + egress + runtime + work (T3-03 `ComputerProvisioner`) e o
/// `DockerComputerBackend` que as ferramentas MCP usam. Só toca recursos com os labels do computador.
public struct DockerComputerProvisioning: ComputerProvisioning {
    public let client: DockerClient
    public let boxImage: String
    public let egressImage: String
    public let secrets: BoxSecretFiles
    public let owner: String
    public var bridgeNetwork: String
    /// Exceção explícita ao filtro SSRF (rede de teste); vazio em produção.
    public var allowCIDRs: [String]
    public var extraLabels: [String: String]
    public var isTest: Bool
    public var resolver: ProxyConfigResolver?

    public init(
        client: DockerClient, boxImage: String, egressImage: String, secrets: BoxSecretFiles, owner: String,
        bridgeNetwork: String = EgressOrchestrator.sharedBridgeName, allowCIDRs: [String] = [], extraLabels: [String: String] = [:],
        isTest: Bool = false, resolver: ProxyConfigResolver? = nil
    ) {
        self.client = client; self.boxImage = boxImage; self.egressImage = egressImage; self.secrets = secrets; self.owner = owner
        self.bridgeNetwork = bridgeNetwork; self.allowCIDRs = allowCIDRs; self.extraLabels = extraLabels; self.isTest = isTest; self.resolver = resolver
    }

    public func preflight() async throws { try await client.ping() }

    /// `M` da VM e CPUs, lidos de `/info` (a admissão usa isto).
    public func vmCapacity() async -> VMCapacity {
        if let info = try? await client.info() { return VMCapacity(memTotalBytes: info.memTotal, cpuCount: info.cpuCount) }
        return VMCapacity(memTotalBytes: 8 << 30, cpuCount: 4)
    }

    public func provision(_ spec: ComputerSpec) async throws -> ProvisionedHandle {
        let computerID = UUID().uuidString.lowercased()
        let labels = ComputerLabels(owner: owner, computerID: computerID, computerName: spec.name, batch: spec.batch, ephemeral: true, isTest: isTest)
        let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        var config = EgressConfigFile.make(profile: nil, secret: nil, allowCIDRs: allowCIDRs, allowHosts: spec.allowHosts)
        var proxyCA: String?
        if spec.proxy != "direct", let resolver {
            let resolved = try await resolver(spec.proxy, nil)
            var merged = resolved.config
            merged.allowCIDRs = config.allowCIDRs
            merged.allowHosts = config.allowHosts
            config = merged
            proxyCA = resolved.caPEM
        }
        let provisioner = ComputerProvisioner(client: client)
        let provisioned = try await provisioner.provision(ComputerProvisionRequest(
            labels: labels, boxImage: boxImage, egressImage: egressImage, display: spec.display, token: token, config: config, proxyCA: proxyCA,
            secrets: secrets, runDirectory: spec.run.root, bridgeNetwork: bridgeNetwork, extraLabels: extraLabels))
        let backend = DockerComputerBackend(client: client, computer: provisioned, secrets: secrets, baseConfig: config, resolver: resolver)
        let secrets = secrets
        return ProvisionedHandle(backend: backend) { _ = try? await provisioner.teardown(provisioned, secrets: secrets) }
    }
}
