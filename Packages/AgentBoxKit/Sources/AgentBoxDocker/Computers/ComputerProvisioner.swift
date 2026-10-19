import Foundation

extension ComputerDisplay {
    /// Limite de memória do container único (P24): Chromium headed + utilitários de trabalho + proxy. Antes eram três containers
    /// (runtime 2 GiB, work 1 GiB, egress 128 MiB); o uso real somado era ~0,75 GiB, então o teto único é menor que a soma.
    var computerMemory: Int64 {
        switch self {
        case .http: 1 << 30
        case .desktop: 7 << 29  // 3,5 GiB
        default: 5 << 29  // 2,5 GiB
        }
    }
    var computerCPUs: Double {
        switch self {
        case .http: 0.75
        case .desktop: 2.75
        default: 1.75
        }
    }
}

public enum ComputerProvisionerError: Error, Sendable, Equatable {
    case runtimeNotReady(String)
    case noPublishedPort
    case provisioningFailed(String)
}

/// Pedido para montar um computador: UM container (P24) com navegador, terminal de trabalho e proxy/egress.
public struct ComputerProvisionRequest: Sendable {
    public var labels: ComputerLabels
    /// Tag de `agentbox-computer` (`ImageManager.ensure`).
    public var image: String
    public var display: ComputerDisplay
    /// Token do computador: entregue por `docker exec` ao tmpfs 0700 do usuário `egress`. Nunca env, nunca disco do host.
    public var token: String
    public var config: EgressConfigFile
    public var proxyCA: String?
    /// Só para os segredos de TAREFA (§3.3): arquivos 0400 numa pasta só leitura que o agente lê em `/run/abx-secrets`.
    public var secrets: BoxSecretFiles
    /// `.../runs/<session>/<computer>/`: `work/` vira bind rw em `/work`; `logs/` fica atrás de `/run/agentbox` (CS-149, CS-233).
    public var runDirectory: URL
    /// Rede em que o container entra. Padrão: a `bridge` do Docker (sem rede por computador; o isolamento é por uid no iptables).
    public var network: String
    public var extraLabels: [String: String]
    /// Volume do perfil do Chromium. `nil` = efêmero `ab-prof-<computerId>` (CS-170).
    public var profileVolume: String?

    public init(labels: ComputerLabels, image: String, display: ComputerDisplay, token: String, config: EgressConfigFile, proxyCA: String? = nil,
                secrets: BoxSecretFiles, runDirectory: URL, network: String = ComputerProvisioner.defaultNetwork,
                extraLabels: [String: String] = [:], profileVolume: String? = nil) {
        self.labels = labels; self.image = image; self.display = display; self.token = token; self.config = config; self.proxyCA = proxyCA
        self.secrets = secrets; self.runDirectory = runDirectory; self.network = network; self.extraLabels = extraLabels
        self.profileVolume = profileVolume
    }
}

public struct ProvisionedComputer: Sendable {
    public var labels: ComputerLabels
    public var display: ComputerDisplay
    /// O único container do computador (P24).
    public var containerID: String
    public var containerName: String
    /// Porta efêmera em `127.0.0.1`: a ÚNICA publicada (admin API, reverse proxy do runtime e túnel VNC).
    public var adminPort: Int
    public var profileVolume: String?
    public var workDirectory: URL
    public var logsDirectory: URL
    public var admin: EgressAdminClient
}

/// Cria e destrói computadores. Só usa recursos com os labels do computador (GC por label, nunca varredura geral).
public struct ComputerProvisioner: Sendable {
    public static let defaultNetwork = "bridge"
    /// Usuários da imagem: o agente (comandos do exec, Chromium) e o dono do proxy, dos segredos e do reqlog.
    public static let agentUser = "agent"
    public static let egressUser = "egress"
    static let agentUID = 10001
    static let egressUID = 10003

    public let client: DockerClient

    public init(client: DockerClient) { self.client = client }

    /// Variáveis de proxy dos comandos do agente (CS-112). O iptables por uid garante que ignorá-las não adianta: falha, não vaza.
    public static func agentEnvironment(proxyPort: Int = EgressConfigFile.defaultProxyPort) -> [String] {
        let url = "http://127.0.0.1:\(proxyPort)"
        let noProxy = "localhost,127.0.0.1,::1"
        return ["HTTP_PROXY=\(url)", "HTTPS_PROXY=\(url)", "ALL_PROXY=\(url)", "http_proxy=\(url)", "https_proxy=\(url)", "all_proxy=\(url)",
                "NO_PROXY=\(noProxy)", "no_proxy=\(noProxy)"]
    }

    /// Especificação do container único (pública para os testes conferirem o hardening sem subir nada).
    public static func containerSpec(_ request: ComputerProvisionRequest, work: URL, logs: URL, taskSecrets: URL, volume: String?) -> ContainerSpec {
        let labels = request.labels
        var spec = ContainerSpec(name: labels.containerName, image: request.image)
        spec.labels = labels.labels(role: .computer).merging(request.extraLabels) { $1 }
        spec.hostname = "computer"
        spec.workingDirectory = "/work"
        spec.environment = ["AGENTBOX_DISPLAY=\(request.display == .http ? "http" : "browser")", "HOME=/home/agent", "DISPLAY=:99"]
            + agentEnvironment(proxyPort: request.config.proxyPort)
        spec.resources = ContainerResources(memoryBytes: request.display.computerMemory, cpus: request.display.computerCPUs, pidsLimit: 1536)
        spec.tmpfs = [
            "/tmp": "rw,nosuid,size=1g,mode=1777",
            "/home/agent": "rw,nosuid,size=256m,uid=\(agentUID),gid=\(agentUID),mode=0755",
            // Segredos, token, config do proxy e reqlog: do usuário `egress`, 0700, fora do alcance do `agent`.
            "/run/agentbox": "rw,nosuid,noexec,size=64m,uid=\(egressUID),gid=\(egressUID),mode=0700",
        ]
        spec.binds = ["\(work.path):/work", "\(taskSecrets.path):/run/abx-secrets:ro", "\(logs.path):/run/agentbox/logs"]
        if let volume { spec.named = ["\(volume):/profile"] }
        spec.network = ContainerNetworkAttachment(network: request.network)
        spec.publishedPorts = [PublishedPort(containerPort: "\(request.config.adminPort)/tcp", hostIP: "127.0.0.1", hostPort: "")]
        // `CapDrop ALL` + só o que o supervisor usa e os serviços largam por `setpriv`: NET_ADMIN (iptables por uid), SETUID/SETGID
        // (largar o privilégio), SETPCAP (reduzir o conjunto de capacidades) e KILL (encerrar serviços e o grupo do exec).
        // Os comandos do agente (`docker exec -u agent`) rodam sem capacidade efetiva e com no-new-privileges.
        spec.capAdd = ["NET_ADMIN", "SETUID", "SETGID", "SETPCAP", "KILL"]
        spec.stopTimeoutSeconds = 5
        return spec
    }

    public func provision(_ request: ComputerProvisionRequest) async throws -> ProvisionedComputer {
        let labels = request.labels
        let computerID = labels.computerID
        let work = request.runDirectory.appendingPathComponent("work", isDirectory: true)
        let logs = request.runDirectory.appendingPathComponent("logs", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        do {
            // Segredos de tarefa (§3.3): arquivos 0400 numa pasta só leitura; o valor nunca vai por env nem argv.
            let taskSecrets = try request.secrets.ensureRoleDirectory(computerID, role: .work)
            var profileName: String?
            if request.display != .http {
                let volume = request.profileVolume ?? "ab-prof-\(computerID)"
                profileName = volume
                var volumeLabels = labels.labels(role: .computer)
                volumeLabels.merge(request.extraLabels) { $1 }
                _ = try await client.createVolume(name: volume, labels: volumeLabels)
            }
            let spec = Self.containerSpec(request, work: work, logs: logs, taskSecrets: taskSecrets, volume: profileName)
            let id = try await client.createContainer(spec)
            try await client.startContainer(id)
            let inspect = try await client.inspectContainer(id)
            guard let port = inspect.publishedHostPort(for: "\(request.config.adminPort)/tcp") else { throw ComputerProvisionerError.noPublishedPort }
            let computer = ProvisionedComputer(
                labels: labels, display: request.display, containerID: id, containerName: spec.name, adminPort: port, profileVolume: profileName,
                workDirectory: work, logsDirectory: logs, admin: EgressAdminClient(port: port, token: request.token))
            try await deliver(config: request.config, proxyCA: request.proxyCA, token: request.token, to: id)
            try await computer.admin.waitUntilHealthy()
            if request.display != .http { try await waitRuntimeReady(computer.admin) }
            return computer
        } catch {
            _ = try? await GarbageCollector(client: client).removeComputer(id: computerID)
            try? request.secrets.removeAll(computerID: computerID)
            throw error
        }
    }

    /// Entrega token, `egress.json` e CA ao tmpfs `/run/agentbox` por `docker exec -i -u egress abx-provision` (stdin). O valor
    /// nunca aparece em env, argv, `inspect` nem no disco do host. Serve também à troca de proxy (reescrita atômica).
    func deliver(config: EgressConfigFile, proxyCA: String?, token: String?, to container: String) async throws {
        var config = config
        var files: [String: String] = [:]
        if let ca = proxyCA, config.upstream != nil {
            files["proxy-ca.pem"] = ca
            config.upstream?.caFile = "/run/agentbox/proxy-ca.pem"
        }
        // O token entra por último: o egress só sobe com token + config.
        files["egress.json"] = String(decoding: try config.jsonData(), as: UTF8.self)
        if let token { files["token"] = token }
        let payload = try JSONSerialization.data(withJSONObject: ["files": files])
        let result = try await client.run(in: container, command: ["abx-provision"], stdin: payload, user: Self.egressUser, killableGroup: false)
        guard result.exitCode == 0 else {
            throw ComputerProvisionerError.provisioningFailed("abx-provision saiu com \(result.exitCode): \(result.stderrString.prefix(200))")
        }
    }

    /// Troca de proxy (CS-141): reescreve `egress.json` dentro do container; quem chama pede o `reload` pela admin API.
    public func rewriteConfig(_ config: EgressConfigFile, proxyCA: String?, computer: ProvisionedComputer) async throws {
        try await deliver(config: config, proxyCA: proxyCA, token: nil, to: computer.containerID)
    }

    /// Espera o Chromium headed ficar pronto (o Playwright demora alguns segundos para subir).
    func waitRuntimeReady(_ admin: EgressAdminClient, timeout: Duration = .seconds(90)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await admin.runtimeReady() { return }
            try await Task.sleep(for: .milliseconds(400))
        }
        throw ComputerProvisionerError.runtimeNotReady("o browser do runtime não ficou pronto em \(timeout)")
    }

    /// Fim do run (07 CS-180): o container, o volume de perfil efêmero e os segredos de tarefa. A pasta do run no host fica.
    public func teardown(_ computer: ProvisionedComputer, secrets: BoxSecretFiles) async throws -> [(ManagedResource, DockerError)] {
        let failures = try await GarbageCollector(client: client).removeComputer(id: computer.labels.computerID)
        try secrets.removeAll(computerID: computer.labels.computerID)
        return failures
    }
}
