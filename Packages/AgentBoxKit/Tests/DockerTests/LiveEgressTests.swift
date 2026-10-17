import AgentBoxProtocol
import Foundation
import Testing

@testable import AgentBoxDocker

/// T3-02 com o Docker real (`AGENTBOX_TEST_DOCKER=1`): rede interna + egress, `work` sem rota para fora, reqlog, SSRF e
/// encadeamento para proxies upstream HTTP (Basic) e SOCKS5 (usuário/senha). Só toca em recursos `agentbox.test=1` + `test_run`.
@Suite("T3-02 - egress sidecar com Docker real", .serialized, .enabled(if: Live.enabled), .tags(.integration), .timeLimit(.minutes(10)))
struct LiveEgressTests {
    static let file = "slice3/T3-02/live-egress.json"

    static var repoRoot: URL {
        var root = URL(fileURLWithPath: #filePath)
        while root.path != "/", !FileManager.default.fileExists(atPath: root.appendingPathComponent("runtime/egress/Dockerfile").path) {
            root.deleteLastPathComponent()
        }
        return root
    }

    struct Fixture {
        var env: LiveEnv
        var images: ImageManager
        var egressImage: String
        var upstreamImage: String
        var bridgeName: String
        var bridgeSubnet: String
        var secrets: BoxSecretFiles
        var home: URL
        var originID: String
        var upstreamHTTPID: String
        var upstreamSocksID: String
    }

    static func computerLabels(_ env: LiveEnv, name: String) -> ComputerLabels {
        ComputerLabels(owner: "test-\(env.runID)", computerID: UUID().uuidString.lowercased(), computerName: name, ephemeral: true, isTest: true)
    }

    /// Servidor SOCKS5 de teste (RFC 1928/1929, só CONNECT) com usuário `sockuser` e senha `sock-pass-secret`.
    static let socks5Server = """
    import asyncio
    async def pipe(r, w):
        try:
            while d := await r.read(65536):
                w.write(d); await w.drain()
        except Exception: pass
        finally: w.close()
    async def handle(r, w):
        try:
            _, n = await r.readexactly(2); m = await r.readexactly(n)
            if 2 not in m: w.write(b"\\x05\\xff"); w.close(); return
            w.write(b"\\x05\\x02")
            _, ul = await r.readexactly(2); u = await r.readexactly(ul); pl = (await r.readexactly(1))[0]; p = await r.readexactly(pl)
            if u != b"sockuser" or p != b"sock-pass-secret": w.write(b"\\x01\\x01"); w.close(); return
            w.write(b"\\x01\\x00")
            _, c, _, a = await r.readexactly(4)
            if a == 3: h = (await r.readexactly((await r.readexactly(1))[0])).decode()
            elif a == 1: h = ".".join(str(b) for b in await r.readexactly(4))
            else: w.close(); return
            port = int.from_bytes(await r.readexactly(2), "big")
            ur, uw = await asyncio.open_connection(h, port)
            w.write(b"\\x05\\x00\\x00\\x01\\x00\\x00\\x00\\x00\\x00\\x00"); await w.drain()
            await asyncio.gather(pipe(r, uw), pipe(ur, w))
        except Exception: w.close()
    async def main():
        s = await asyncio.start_server(handle, "0.0.0.0", 1080)
        async with s: await s.serve_forever()
    asyncio.run(main())
    """

    func makeFixture(_ env: LiveEnv) async throws -> Fixture {
        let images = ImageManager(client: env.client)
        let testLabels = [AgentBoxLabel.test: "1", "agentbox.test_run": env.runID]

        // imagem do egress (contexto REAL runtime/egress) e imagem do upstream de teste (tinyproxy)
        let egressSource = ImageSource(repository: "agentbox-egress-test-\(env.runID)", contextDirectory: Self.repoRoot.appendingPathComponent("runtime/egress"), extraLabels: testLabels)
        let egress = try await images.ensure(egressSource)
        let upstreamDir = FileManager.default.temporaryDirectory.appendingPathComponent("abx-upstream-\(env.runID)", isDirectory: true)
        try FileManager.default.createDirectory(at: upstreamDir, withIntermediateDirectories: true)
        try Data("FROM \(Live.alpine)\nRUN apk add --no-cache tinyproxy busybox-extras\n".utf8).write(to: upstreamDir.appendingPathComponent("Dockerfile"))
        let upstream = try await images.ensure(ImageSource(repository: "agentbox-upstream-test-\(env.runID)", contextDirectory: upstreamDir, extraLabels: testLabels))
        try? FileManager.default.removeItem(at: upstreamDir)

        // bridge de saída de teste e os alvos nela
        let bridge = env.name("bridge")
        let bridgeID = try await env.client.createNetwork(name: bridge, isInternal: false, labels: env.baseLabels)
        let subnet = try #require(try await env.client.inspectNetwork(bridgeID).subnets.first)

        var origin = env.spec("origin", command: ["sh", "-c", """
            mkdir -p /tmp/www
            printf '<html>hello from origin %s</html>' "$$" > /tmp/www/index.html
            printf '{"ok":true,"token":"sk-ant-api03-LEAKYORIGINTOKEN123456","user":"alice"}' > /tmp/www/api.json
            exec httpd -f -vv -p 8080 -h /tmp/www
            """])
        origin.image = upstream.tag  // busybox-extras traz o `httpd`
        origin.user = "65534"
        origin.network = ContainerNetworkAttachment(network: bridge, aliases: ["origin"])
        let originID = try await env.run(origin)

        var tiny = env.spec("tinyproxy", command: ["sh", "-c", """
            printf 'Port 8888\\nListen 0.0.0.0\\nTimeout 30\\nBasicAuth upuser up-pass-secret\\nConnectPort 8080\\nPidFile "/tmp/tp.pid"\\nLogLevel Info\\n' > /tmp/tp.conf
            exec tinyproxy -d -c /tmp/tp.conf
            """])
        tiny.image = upstream.tag
        tiny.user = "65534"
        tiny.network = ContainerNetworkAttachment(network: bridge, aliases: ["upstream-http"])
        let tinyID = try await env.run(tiny)

        var socks = env.spec("socks")
        socks.command = nil
        socks.entrypoint = ["python", "-c", Self.socks5Server]
        socks.image = egress.tag  // imagem do egress só como runtime de Python para o servidor SOCKS5 de teste
        socks.user = "65534"
        socks.network = ContainerNetworkAttachment(network: bridge, aliases: ["upstream-socks"])
        let socksID = try await env.run(socks)

        let home = FileManager.default.temporaryDirectory.appendingPathComponent("abx-home-\(env.runID)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(1500))
        return Fixture(env: env, images: images, egressImage: egress.tag, upstreamImage: upstream.tag, bridgeName: bridge, bridgeSubnet: subnet,
                       secrets: BoxSecretFiles(root: home), home: home, originID: originID, upstreamHTTPID: tinyID, upstreamSocksID: socksID)
    }

    struct Box {
        var labels: ComputerLabels
        var provisioned: ProvisionedEgress
        var admin: EgressAdminClient
        var token: String
        var logs: URL
        var workID: String
    }

    func provision(_ fx: Fixture, name: String, config: EgressConfigFile) async throws -> Box {
        let labels = Self.computerLabels(fx.env, name: name)
        let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        let logs = fx.home.appendingPathComponent("runs/\(name)/logs", isDirectory: true)
        let request = EgressProvisionRequest(
            labels: labels, image: fx.egressImage, token: token, config: config, secrets: fx.secrets, logsDirectory: logs,
            bridgeNetwork: fx.bridgeName, extraLabels: ["agentbox.test_run": fx.env.runID])
        let provisioned = try await EgressOrchestrator(client: fx.env.client).provision(request)
        let admin = EgressAdminClient(port: provisioned.adminPort, token: token)
        try await admin.waitUntilHealthy()

        // work: só na rede interna, com as variáveis de proxy (CS-112)
        var work = fx.env.spec("work-\(name)", role: .work)
        work.labels.merge(labels.labels(role: .work)) { $1 }
        work.labels[AgentBoxLabel.test] = "1"
        work.labels["agentbox.test_run"] = fx.env.runID
        work.network = ContainerNetworkAttachment(network: labels.networkName, aliases: ["work"])
        work.environment = EgressOrchestrator.workEnvironment()
        work.user = "10002"
        let workID = try await fx.env.run(work)
        return Box(labels: labels, provisioned: provisioned, admin: admin, token: token, logs: logs, workID: workID)
    }

    func sh(_ fx: Fixture, _ box: Box, _ script: String) async throws -> (code: Int, out: String) {
        let result = try await fx.env.client.run(in: box.workID, command: ["sh", "-c", script], timeout: .seconds(40))
        return (result.exitCode, result.stdoutString + result.stderrString)
    }

    @Test func egressIsolationReqlogSSRFAndUpstreamChaining() async throws {
        try await Live.with { env in
            let fx = try await makeFixture(env)
            defer { try? FileManager.default.removeItem(at: fx.home) }
            let e = Evidence.shared
            let file = Self.file
            await e.record(file, "runtime", "\(env.runtime.runtime.kind.rawValue): Engine \(env.runtime.version.version), \(env.runtime.info.architecture)")
            await e.record(file, "egress_image", "\(fx.egressImage) (base python:3.13-alpine fixada por digest)")

            // ---------------------------------------------------------------- A) direto, com exceção só para a bridge de teste
            let direct = try await provision(fx, name: "direct", config: EgressConfigFile.make(profile: nil, secret: nil, allowCIDRs: [fx.bridgeSubnet]))
            let client = env.client

            // A1. topologia: rede internal, só o egress publica porta, em 127.0.0.1
            let net = try await client.inspectNetwork(direct.provisioned.networkID)
            #expect(net.isInternal)
            let egressInspect = try await client.inspectContainer(direct.provisioned.egressContainerID)
            let workInspect = try await client.inspectContainer(direct.workID)
            #expect(workInspect.ports.isEmpty)
            #expect(egressInspect.ports.values.flatMap { $0 }.allSatisfy { $0.hostIP == "127.0.0.1" } && direct.provisioned.adminPort > 0)
            #expect(egressInspect.networks.keys.contains(direct.labels.networkName) && egressInspect.networks.keys.contains(fx.bridgeName))
            #expect(workInspect.networks.keys.sorted() == [direct.labels.networkName])
            #expect(egressInspect.readonlyRootfs && egressInspect.capDrop == ["ALL"] && egressInspect.user == "10003")
            await e.record(file, "topology", "rede \(net.name) internal=\(net.isInternal); work sem portas; egress publica 127.0.0.1:\(direct.provisioned.adminPort)->8790; work só na rede interna")

            // A2. segredos: nada em env/inspect; arquivos 0400 em diretório 0700, montados ro
            let inspectJSON = String(describing: egressInspect)
            #expect(!inspectJSON.contains(direct.token))
            #expect(egressInspect.env.allSatisfy { !$0.contains(direct.token) })
            #expect(try fx.secrets.permissionViolations(computerID: direct.labels.computerID).isEmpty)
            let mounts = try await client.run(in: direct.provisioned.egressContainerID, command: ["sh", "-c", "grep ' /run/agentbox ' /proc/mounts; ls -l /run/agentbox; touch /run/agentbox/x 2>&1; id -u"])
            #expect(mounts.stdoutString.contains(" ro,") && mounts.stdoutString.contains("token") && mounts.stdoutString.contains("egress.json"), "\(mounts.stdoutString)")
            await e.record(file, "secrets_mount", mounts.stdoutString.replacingOccurrences(of: "\n", with: " | "))
            let workSecrets = try await sh(fx, direct, "ls /run/agentbox 2>&1; env | grep -i -E 'token|pass|secret|key' | grep -v NO_PROXY; echo done")
            #expect(!workSecrets.out.contains(direct.token))
            await e.record(file, "work_has_no_secrets", workSecrets.out.replacingOccurrences(of: "\n", with: " | "))

            // A3. work sem rota para fora: por IP e sem proxy falha; pelo proxy chega
            let norouteScript = "env -u http_proxy -u HTTP_PROXY -u all_proxy -u ALL_PROXY wget -T3 -qO- http://1.1.1.1/ >/dev/null 2>&1; echo wget_noproxy=$?; ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; echo ping=$?; ip route | head -3"
            let noroute = try await sh(fx, direct, norouteScript)
            #expect(noroute.out.contains("wget_noproxy=1") && !noroute.out.contains("ping=0"), "\(noroute.out)")
            await e.record(file, "work_no_route_out", noroute.out.replacingOccurrences(of: "\n", with: " | "))
            let toOtherBox = try await sh(fx, direct, "env -u http_proxy -u HTTP_PROXY wget -T3 -qO- http://origin:8080/ >/dev/null 2>&1; echo direct_to_origin=$?")
            #expect(toOtherBox.out.contains("direct_to_origin=1"), "o work não resolve nem alcança a bridge: \(toOtherBox.out)")

            // A4. request pelo egress aparece no reqlog (HTTP simples, com corpo redigido)
            let page = try await sh(fx, direct, "wget -T5 -qO- 'http://origin:8080/index.html?api_key=SHOULDNOTAPPEAR&q=1'")
            #expect(page.code == 0 && page.out.contains("hello from origin"), "\(page.out)")
            let api = try await sh(fx, direct, "wget -T5 -qO- http://origin:8080/api.json")
            #expect(api.out.contains("LEAKYORIGINTOKEN123456"), "o agente recebe a resposta intacta: \(api.out)")
            // CONNECT (túnel TCP sem descriptografar): GET dentro do túnel
            let tunnel = try await sh(fx, direct, "printf 'CONNECT origin:8080 HTTP/1.1\\r\\n\\r\\nGET /index.html HTTP/1.1\\r\\nHost: o\\r\\nConnection: close\\r\\n\\r\\n' | nc -w 3 egress 3128")
            #expect(tunnel.out.contains("200 Connection Established") && tunnel.out.contains("hello from origin"), "\(tunnel.out)")
            try await Task.sleep(for: .milliseconds(800))
            let records = try await direct.admin.reqlog()
            let pageRecord = try #require(records.first { $0.url?.contains("index.html") == true && $0.kind == "http" }, "reqlog: \(records.map { $0.url ?? "?" })")
            #expect(pageRecord.status == 200 && pageRecord.via == "direct" && !(pageRecord.url ?? "").contains("SHOULDNOTAPPEAR"))
            let apiRecord = try #require(records.first { $0.url?.hasSuffix("/api.json") == true })
            let apiBody = try await direct.admin.responseBody(id: apiRecord.id)
            #expect(apiBody.contains("alice") && !apiBody.contains("LEAKYORIGINTOKEN123456"), "corpo no log, segredo redigido: \(apiBody)")
            let tunnelRecord = try #require(records.first { $0.kind == "tunnel" && $0.host == "origin" })
            #expect(tunnelRecord.bytesUp > 0 && tunnelRecord.bytesDown > 0)
            await e.record(file, "reqlog_http", "GET index.html status=\(pageRecord.status ?? 0) via=\(pageRecord.via ?? "?"); url no log: \(pageRecord.url ?? "")")
            await e.record(file, "reqlog_body_redacted", apiBody)
            await e.record(file, "reqlog_tunnel", "CONNECT origin:8080 up=\(tunnelRecord.bytesUp) down=\(tunnelRecord.bytesDown)")

            // A5. destinos proibidos bloqueados (403) e registrados
            var blockedSummary: [String] = []
            for target in ["http://169.254.169.254/latest/meta-data/", "http://127.0.0.1:8790/v1/usage", "http://10.0.0.1/", "http://192.168.0.1/", "http://100.64.0.1/",
                           "http://host.docker.internal:8080/", "http://gateway.docker.internal/", "http://2130706433/", "http://[::1]/", "http://localhost/",
                           "http://\(egressInspect.networks[direct.labels.networkName]?.ipAddress ?? "172.30.0.2"):8790/v1/health", "http://93.184.216.34@127.0.0.1/"] {
                let r = try await sh(fx, direct, "wget -T5 -S -qO- '\(target)' 2>&1 | head -3; echo")
                #expect(r.out.contains("403"), "\(target): \(r.out)")
                blockedSummary.append(target)
            }
            let connectBlocked = try await sh(fx, direct, "printf 'CONNECT 169.254.169.254:443 HTTP/1.1\\r\\n\\r\\n' | nc -w 3 egress 3128 | head -1")
            #expect(connectBlocked.out.contains("403"))
            try await Task.sleep(for: .milliseconds(500))
            let after = try await direct.admin.reqlog(limit: 500)
            let blocked = after.filter(\.blocked)
            #expect(blocked.count >= blockedSummary.count + 1, "bloqueios no log: \(blocked.count)")
            #expect(Set(blocked.compactMap(\.blockedReason)).isSuperset(of: ["link-local", "loopback", "private"]))
            await e.record(file, "ssrf_blocked", "\(blocked.count) bloqueios no reqlog; motivos: \(Set(blocked.compactMap(\.blockedReason)).sorted().joined(separator: ", ")); alvos: \(blockedSummary.joined(separator: " "))")

            // A6. contadores e integridade (o log fica no host; a cadeia confere)
            let usage = try await direct.admin.usage()
            #expect(usage.requests >= 3 && usage.blocked >= blockedSummary.count && usage.tunnels >= 1, "\(usage)")
            await e.record(file, "usage_direct", "requests=\(usage.requests) tunnels=\(usage.tunnels) blocked=\(usage.blocked) up=\(usage.bytesUp) down=\(usage.bytesDown)")
            let integrity = try ReqlogIntegrity.verify(file: direct.logs.appendingPathComponent("requests.jsonl"))
            guard case .ok(let lines) = integrity else { Issue.record("integridade: \(integrity.message)"); return }
            #expect(lines >= 10)
            await e.record(file, "log_integrity", "\(integrity.message) (\(lines) linhas, escritas pelo egress no bind rw do host)")
            // adulteração é detectada
            let copy = fx.home.appendingPathComponent("tampered.jsonl")
            var text = try String(contentsOf: direct.logs.appendingPathComponent("requests.jsonl"), encoding: .utf8)
            text = text.replacingOccurrences(of: "\"status\":200", with: "\"status\":201")
            try text.write(to: copy, atomically: true, encoding: .utf8)
            guard case .tampered(let line) = try ReqlogIntegrity.verify(file: copy) else { Issue.record("adulteração não detectada"); return }
            await e.record(file, "log_tamper_detected", "Tampered at line \(line)")
            let usageFile = try String(contentsOf: direct.logs.appendingPathComponent("usage.json"), encoding: .utf8)
            #expect(usageFile.contains("\"blocked\""))

            // ---------------------------------------------------------------- B) encadeado: HTTP upstream com Basic
            let httpUp = ProxyProfile(name: "test-http", scheme: .http, host: "upstream-http", port: 8888, username: "upuser")
            let httpConfig = EgressConfigFile.make(profile: httpUp, secret: "up-pass-secret", allowCIDRs: [fx.bridgeSubnet])
            let chained = try await provision(fx, name: "chained", config: httpConfig)
            let viaUp = try await sh(fx, chained, "wget -T8 -qO- http://origin:8080/index.html")
            #expect(viaUp.out.contains("hello from origin"), "\(viaUp.out)")
            let tunnelUp = try await sh(fx, chained, "printf 'CONNECT origin:8080 HTTP/1.1\\r\\n\\r\\nGET /index.html HTTP/1.1\\r\\nHost: o\\r\\nConnection: close\\r\\n\\r\\n' | nc -w 4 egress 3128")
            #expect(tunnelUp.out.contains("200") && tunnelUp.out.contains("hello from origin"), "\(tunnelUp.out)")
            try await Task.sleep(for: .milliseconds(600))
            let upRecords = try await chained.admin.reqlog()
            #expect(upRecords.filter { $0.via == "test-http" && $0.status == 200 }.count >= 1)
            #expect(upRecords.contains { $0.kind == "tunnel" && $0.via == "test-http" })
            // o origin viu o request vindo do tinyproxy (IP dele), não do egress
            let tinyIP = try await client.inspectContainer(fx.upstreamHTTPID).networks[fx.bridgeName]?.ipAddress
            let egressIPOnBridge = try await client.inspectContainer(chained.provisioned.egressContainerID).networks[fx.bridgeName]?.ipAddress
            let originLogs = try await client.collectedLogs(fx.originID)
            let originLog = originLogs.stdout + originLogs.stderr
            #expect(originLog.contains(tinyIP ?? "?"), "origin deveria ter visto o IP do tinyproxy \(tinyIP ?? "?"): \(originLog.suffix(600))")
            await e.record(file, "chained_http_upstream", "origin viu \(tinyIP ?? "?") (tinyproxy), egress=\(egressIPOnBridge ?? "?"); reqlog via=test-http; túnel CONNECT encadeado com Proxy-Authorization")
            // credenciais do upstream só no egress: nem no inspect, nem no log do host, nem no work
            let chainedInspect = try await client.inspectContainer(chained.provisioned.egressContainerID)
            #expect(!String(describing: chainedInspect).contains("up-pass-secret"))
            let reqlogText = try String(contentsOf: chained.logs.appendingPathComponent("requests.jsonl"), encoding: .utf8)
            #expect(!reqlogText.contains("up-pass-secret") && !reqlogText.contains("dXB1c2VyOnVwLXBhc3Mtc2VjcmV0"))
            let workEnv = try await sh(fx, chained, "env; cat /run/agentbox/egress.json 2>&1")
            #expect(!workEnv.out.contains("up-pass-secret"))
            let dockerLogs = try await client.collectedLogs(chained.provisioned.egressContainerID)
            #expect(!(dockerLogs.stdout + dockerLogs.stderr).contains("up-pass-secret"))
            await e.record(file, "upstream_credentials_confined", "senha do upstream ausente de: inspect do egress, env/arquivos do work, docker logs, reqlog no host")

            // senha errada -> proxy_error com o status do upstream (407); nada de troca automática (CS-163)
            let wrong = EgressConfigFile.make(profile: httpUp, secret: "WRONG-password-1", allowCIDRs: [fx.bridgeSubnet])
            let wrongBox = try await provision(fx, name: "wrongpw", config: wrong)
            let w = try await sh(fx, wrongBox, "printf 'CONNECT origin:8080 HTTP/1.1\\r\\n\\r\\n' | nc -w 4 egress 3128 | head -1")
            #expect(w.out.contains("502"), "\(w.out)")
            try await Task.sleep(for: .milliseconds(500))
            let wrongRecords = try await wrongBox.admin.reqlog()
            let err = try #require(wrongRecords.first { $0.error == "proxy_error" }, "\(wrongRecords)")
            #expect([401, 407].contains(err.upstreamStatus ?? 0) && err.via == "test-http", "o tinyproxy recusa credencial errada com 401 ou 407: \(err.upstreamStatus ?? 0)")
            await e.record(file, "proxy_error_upstream_auth", "senha errada: 502 ao agente, reqlog error=proxy_error upstream_status=\(err.upstreamStatus ?? 0) via=\(err.via ?? "?")")

            // ---------------------------------------------------------------- C) encadeado: SOCKS5 com usuário e senha
            let socksProfile = ProxyProfile(name: "test-socks", scheme: .socks5, host: "upstream-socks", port: 1080, username: "sockuser")
            let socksBox = try await provision(fx, name: "socks", config: EgressConfigFile.make(profile: socksProfile, secret: "sock-pass-secret", allowCIDRs: [fx.bridgeSubnet]))
            let viaSocks = try await sh(fx, socksBox, "wget -T8 -qO- http://origin:8080/index.html")
            #expect(viaSocks.out.contains("hello from origin"), "\(viaSocks.out)")
            let socksIP = try await client.inspectContainer(fx.upstreamSocksID).networks[fx.bridgeName]?.ipAddress
            let originLogs2 = try await client.collectedLogs(fx.originID)
            #expect((originLogs2.stdout + originLogs2.stderr).contains(socksIP ?? "?"), "origin deveria ter visto \(socksIP ?? "?") (servidor SOCKS5 de teste)")
            try await Task.sleep(for: .milliseconds(500))
            let socksRecords = try await socksBox.admin.reqlog()
            #expect(socksRecords.contains { $0.via == "test-socks" && $0.status == 200 })
            let badSocks = try await provision(fx, name: "socksbad", config: EgressConfigFile.make(profile: socksProfile, secret: "nope-wrong", allowCIDRs: [fx.bridgeSubnet]))
            let bs = try await sh(fx, badSocks, "wget -T8 -S -qO- http://origin:8080/index.html 2>&1 | head -2")
            #expect(bs.out.contains("502"), "\(bs.out)")
            await e.record(file, "chained_socks5_upstream", "origin viu \(socksIP ?? "?") (servidor SOCKS5 de teste); reqlog via=test-socks; senha errada -> 502 proxy_error")

            // ---------------------------------------------------------------- D) troca de proxy derruba túneis abertos (CS-141 base)
            // túnel longo aberto no work (nc segura a conexão), depois reload com outra config
            _ = try await sh(fx, chained, "(printf 'CONNECT origin:8080 HTTP/1.1\\r\\n\\r\\n'; sleep 20) | nc egress 3128 >/tmp/tun.out 2>&1 &\nsleep 1; echo started")
            try await Task.sleep(for: .milliseconds(800))
            let open = try await chained.admin.usage().openTunnels
            #expect(open >= 1)
            try EgressOrchestrator(client: client).rewriteConfig(EgressConfigFile.make(profile: nil, secret: nil, allowCIDRs: [fx.bridgeSubnet], internalSubnet: chained.provisioned.internalSubnet), proxyCA: nil, secrets: fx.secrets, computerID: chained.labels.computerID)
            let closed = try await chained.admin.reloadProxy()
            #expect(closed >= 1)
            let afterSwitch = try await chained.admin.usage()
            #expect(afterSwitch.via == "direct" && afterSwitch.openTunnels == 0)
            let direct2 = try await sh(fx, chained, "wget -T5 -qO- http://origin:8080/index.html")
            #expect(direct2.out.contains("hello from origin"))
            let switchedRecords = try await chained.admin.reqlog(limit: 500)
            #expect(switchedRecords.contains { $0.raw["closed_by"]?.string == "proxy_switch" })
            #expect(switchedRecords.last { $0.kind == "http" }?.via == "direct")
            await e.record(file, "proxy_switch", "reload: \(closed) túnel(is) aberto(s) derrubado(s); via agora \(afterSwitch.via); novo request sai com via=direct")

            // ---------------------------------------------------------------- E) sem exceção de LAN: a própria bridge de teste é bloqueada
            let strict = try await provision(fx, name: "strict", config: EgressConfigFile.make(profile: nil, secret: nil))
            let s = try await sh(fx, strict, "wget -T5 -S -qO- http://origin:8080/index.html 2>&1 | head -3")
            #expect(s.out.contains("403"), "sem allow_cidrs, destino em faixa privada (a bridge) é recusado: \(s.out)")
            await e.record(file, "no_exception_blocks_private_bridge", "sem allow_cidrs o egress recusa origin (IP privado da bridge): 403")

            // ---------------------------------------------------------------- F) internet real (informativo)
            let internet = try await sh(fx, strict, "wget -T8 -qO- http://example.com/ | head -c 120; echo; echo rc=$?")
            await e.record(file, "internet_via_egress_informational", internet.out.replacingOccurrences(of: "\n", with: " | "))

            // ---------------------------------------------------------------- limpeza pelo orquestrador (rede, container e segredos)
            for box in [direct, chained, wrongBox, socksBox, badSocks, strict] {
                _ = try? await client.removeContainer(box.workID, force: true)
                let failures = try await EgressOrchestrator(client: client).teardown(computerID: box.labels.computerID, secrets: fx.secrets)
                #expect(failures.isEmpty, "\(failures)")
                #expect(!FileManager.default.fileExists(atPath: (try fx.secrets.computerDirectory(box.labels.computerID)).path), "segredos removidos")
            }
            await e.record(file, "teardown", "egress + rede + pasta de segredos removidos por computador (CS-180)")
        }
    }
}
