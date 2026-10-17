import AgentBoxDocker
import Foundation

/// `proxy_set`: devolve a config do egress (política e upstream) e a CA extra do proxy escolhido (`"direct"` = sem upstream).
/// O app monta a partir do `ProxyService` (T3-02); o egress é o único que recebe as credenciais, por arquivo 0400.
public typealias ProxyConfigResolver = @Sendable (_ proxy: String, _ country: String?) async throws -> (config: EgressConfigFile, caPEM: String?)

/// Backend real: Engine API para o `work`, reverse proxy do egress para o runtime, ingest e render no egress.
public struct DockerComputerBackend: ComputerBackend {
    public let client: DockerClient
    public let computer: ProvisionedComputer
    public let secrets: BoxSecretFiles
    public let baseConfig: EgressConfigFile
    private let resolver: ProxyConfigResolver?
    private let jobs = ExecJobs()

    public init(client: DockerClient, computer: ProvisionedComputer, secrets: BoxSecretFiles, baseConfig: EgressConfigFile, resolver: ProxyConfigResolver? = nil) {
        self.client = client
        self.computer = computer
        self.secrets = secrets
        self.baseConfig = baseConfig
        self.resolver = resolver
    }

    // MARK: Runtime (browser)

    public func runtime(_ operation: String, _ args: JSON, timeout: TimeInterval) async throws -> JSON {
        let status: Int, body: Data
        do {
            (status, body) = try await computer.admin.runtimeCall(operation, body: args.data(), timeout: timeout)
        } catch let error as URLError where error.code == .timedOut {
            throw ToolError(.timeout, "the runtime did not answer in time")
        } catch let error as EgressAdminError {
            throw ToolError(.boxRestarted, "the computer's egress is not reachable (\(error))", retryAfterS: 5)
        } catch is URLError {
            throw ToolError(.boxRestarted, "the computer's runtime is not reachable", retryAfterS: 5)
        }
        let json = (try? JSON.parse(body)) ?? .null
        guard status == 200 else { throw RuntimeErrorMapper.map(status: status, body: json) }
        return json
    }

    // MARK: Exec no `work`

    static func command(for request: BackendExec) -> [String] {
        let base: [String] = request.shell.map { ["bash", "-lc", $0] } ?? request.argv ?? []
        guard !request.secretEnv.isEmpty else { return base }
        // O valor do segredo vem de arquivo montado só leitura dentro do `work` e só existe neste processo (§3.3).
        let script = "names=\"$1\"; shift; for n in $names; do f=\"/run/agentbox/secrets/$n\"; "
            + "[ -r \"$f\" ] || { echo \"secret $n is not available\" >&2; exit 126; }; export \"$n=$(cat \"$f\")\"; done; exec \"$@\""
        return ["/bin/sh", "-c", script, "sh", request.secretEnv.joined(separator: " ")] + base
    }

    func spec(_ request: BackendExec) -> ExecSpec {
        var spec = ExecSpec(command: Self.command(for: request), attachStdin: request.stdin != nil, killableGroup: true)
        spec.user = "10002"
        spec.workingDirectory = request.cwd
        spec.environment = request.env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return spec
    }

    private func start(_ request: BackendExec) async throws -> String {
        let session = try await client.startExec(in: computer.workContainerID, spec: spec(request))
        if let stdin = request.stdin {
            try await session.writeStdin(stdin)
            session.closeStdin()
        }
        return await jobs.add(session)
    }

    public func execRun(_ request: BackendExec, timeout: Duration) async throws -> BackendExecOutcome {
        let id = try await start(request)
        var outcome = await jobs.poll(id, wait: timeout)
        if outcome.running {
            // Passou do prazo: SIGTERM no grupo e, 2 s depois, SIGKILL. A saída parcial volta com `timedOut`.
            outcome = await jobs.cancel(id, grace: .seconds(2))
            outcome.timedOut = true
        }
        await jobs.forget(id)
        return outcome
    }

    public func execStart(_ request: BackendExec) async throws -> String { try await start(request) }

    public func execPoll(jobID: String, wait: Duration) async throws -> BackendExecOutcome {
        guard await jobs.contains(jobID) else { throw ToolError(.notFound, "no job \(jobID)") }
        return await jobs.poll(jobID, wait: wait)
    }

    public func execCancel(jobID: String) async throws -> BackendExecOutcome {
        guard await jobs.contains(jobID) else { throw ToolError(.notFound, "no job \(jobID)") }
        return await jobs.cancel(jobID, grace: .seconds(5))
    }

    // MARK: Egress

    public func ingest(_ payload: JSON) async throws -> String {
        do { return try await computer.admin.ingest(payload.data()) } catch {
            throw ToolError(.boxRestarted, "could not record the request in the egress log: \(error)", retryAfterS: 5)
        }
    }

    public func switchProxy(to proxy: String, country: String?) async throws -> Int {
        guard let resolver else { throw ToolError(.notSupported, "this app build has no proxy resolver") }
        let resolved = try await resolver(proxy, country)
        var config = resolved.config
        config.internalSubnet = computer.egress.internalSubnet
        config.proxyPort = baseConfig.proxyPort
        config.adminPort = baseConfig.adminPort
        config.allowCIDRs = baseConfig.allowCIDRs
        config.allowHosts = baseConfig.allowHosts
        try EgressOrchestrator(client: client).rewriteConfig(config, proxyCA: resolved.caPEM, secrets: secrets, computerID: computer.labels.computerID)
        do { return try await computer.admin.reloadProxy() } catch {
            throw ToolError(.proxyError, "the egress did not confirm the proxy switch: \(error)")
        }
    }

    public func proxyInfo() async throws -> JSON { try JSON.parse(try await computer.admin.get("/v1/proxy")) }

    public func usage() async throws -> JSON {
        let body = try JSON.parse(try await computer.admin.get("/v1/usage"))
        let total = body["total"] ?? [:]
        func n(_ key: String) -> Int { total[key]?.int ?? 0 }
        return ["requests": .int(n("requests")), "tunnels": .int(n("tunnels")), "bytes": .int(n("bytes_up") + n("bytes_down")), "renders": .int(n("renders"))]
    }

    public func render(_ payload: JSON) async throws -> JSON {
        let (status, body) = try await computer.admin.render(payload.data())
        let json = (try? JSON.parse(body)) ?? .null
        if status == 200 { return json }
        throw RuntimeErrorMapper.map(status: status, body: json)
    }
}

/// Jobs de exec em andamento: consome a saída de cada `ExecSession` e guarda stdout, stderr e código de saída.
actor ExecJobs {
    private struct Job {
        var session: ExecSession
        var stdout = Data()
        var stderr = Data()
        var exitCode: Int?
        var finished = false
        var started = ContinuousClock.now
        var duration: Duration = .zero
    }

    private var jobs: [String: Job] = [:]

    func contains(_ id: String) -> Bool { jobs[id] != nil }
    func forget(_ id: String) { jobs[id] = nil }

    func add(_ session: ExecSession) -> String {
        let id = ULID.generate()
        jobs[id] = Job(session: session)
        Task { [weak self] in await self?.consume(id, session) }
        return id
    }

    private func consume(_ id: String, _ session: ExecSession) async {
        do {
            for try await frame in session.output {
                if frame.kind == .stderr { jobs[id]?.stderr.append(frame.data) } else { jobs[id]?.stdout.append(frame.data) }
            }
            jobs[id]?.exitCode = try? await session.exitCode()
        } catch {
            jobs[id]?.exitCode = nil
        }
        jobs[id]?.finished = true
        if let started = jobs[id]?.started { jobs[id]?.duration = started.duration(to: .now) }
    }

    private func outcome(_ id: String) -> BackendExecOutcome {
        guard let job = jobs[id] else { return BackendExecOutcome() }
        let elapsed = job.finished ? job.duration : job.started.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        return BackendExecOutcome(running: !job.finished, exitCode: job.exitCode, stdout: job.stdout, stderr: job.stderr, durationMs: ms)
    }

    func poll(_ id: String, wait: Duration) async -> BackendExecOutcome {
        let deadline = ContinuousClock.now + wait
        while jobs[id]?.finished == false, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return outcome(id)
    }

    func cancel(_ id: String, grace: Duration) async -> BackendExecOutcome {
        guard let job = jobs[id], !job.finished else { return outcome(id) }
        try? await job.session.terminate(grace: grace)
        return await poll(id, wait: .seconds(5))
    }
}
