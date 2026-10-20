import RackyCore
import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import Racky

/// Opt-in paid/native integration. It uses the reviewed launch, real PTY, native
/// Claude hooks, packaged MCP helper, app dispatcher and two owned Docker boxes.
final class NativeChildFlowDockerTests: XCTestCase {
    @MainActor
    func testNativeClaudeChildRoutesToItsOwnRealComputer() async throws {
        guard ProcessInfo.processInfo.environment["RACKY_TEST_NATIVE_CHILD_FLOW"] == "1" else {
            throw XCTSkip("Set RACKY_TEST_NATIVE_CHILD_FLOW=1 for the bounded native child flow")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("racky-native-flow-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let docker = DockerProcessRunner(executableURL: try XCTUnwrap(DockerProcessRunner.findExecutable()),
                                         contextName: "colima-racky-dev")
        let runner = NativeFlowTrackingRunner(docker: docker)
        let terminalID = UUID(), sessionID = UUID()
        defer { cleanup(docker: docker, computerIDs: runner.createdComputerIDs, terminalID: terminalID) }
        let tokens = NativeFlowTokens()
        let policyStore = ComputerPolicyStore(fileURL: root.appendingPathComponent("policy.json"))
        try policyStore.save(ComputerPolicy(creation: .automatic,
            limits: .init(cpus: 1, memoryMiB: 2048, maxComputers: 64)))
        let service = BrowserComputerService(runner: runner, tokens: tokens, policyStore: policyStore,
            metadataStore: BrowserComputerMetadataStore(url: root.appendingPathComponent("metadata.json")))
        let parentBox = try service.createAndStart(for: terminalID)
        let marker = "NATIVE_CHILD_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        try startPageFixture(docker: docker, containerID: parentBox.containerID, marker: marker)
        let parentAddress = try containerIPv4(docker: docker, containerID: parentBox.containerID)
        let fixtureURL = try XCTUnwrap(URL(string: "http://\(parentAddress):8766/fixture.html"))
        let parentEndpoint = try await service.reconnectEndpoint(computerID: parentBox.id)
        let initialParentHealth = try await BrowserRuntimeClient(endpoint: parentEndpoint).health()
        XCTAssertEqual(initialParentHealth.mode, .http)

        let helper = try helperExecutable()
        let claude = try CLIExecutableResolver().resolve(.claude)
        let output = root.appendingPathComponent("result.json")
        let stderr = root.appendingPathComponent("claude.stderr")
        let agents = root.appendingPathComponent("agents.json")
        let childTools = ["mcp__racky__computer_acquire", "mcp__racky__computer_navigate",
                          "mcp__racky__computer_page", "mcp__racky__computer_request_help",
                          "mcp__racky__computer_status"]
        let childDefinition: [String: Any] = ["marker-worker": [
            "description": "Use only the assigned computer to read one synthetic local page.",
            "prompt": "Use only your assigned computer. Acquire headless, navigate to the requested URL and read computer_page. Then call computer_request_help exactly once. Wait for the test human to take and release control; check computer_status until awaiting_user=false. Navigate to the same URL again and read computer_page again. Return the exact NATIVE_CHILD marker and the final visits count from the page. Do not infer or invent either value.",
            "tools": childTools, "model": "haiku"]]
        try JSONSerialization.data(withJSONObject: childDefinition, options: [.sortedKeys]).write(to: agents, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: agents.path)
        let prompt = "Launch one marker-worker native child. It must use its own computer: acquire headless, navigate to \(fixtureURL.absoluteString), read computer_page, request human help once, wait for human release and check status, then navigate and read the page again. Do not use computer tools in the parent. Relay the child's final marker and visits count, then stop."
        let wrapper = root.appendingPathComponent("claude-flow-wrapper")
        let permitted = (["Agent"] + childTools).joined(separator: ",")
        let script = """
        #!/bin/sh
        umask 077
        exec \(shellQuote(claude)) -p --output-format json --model haiku --max-budget-usd 0.25 \
          --no-session-persistence --setting-sources '' --strict-mcp-config --no-chrome \
          --tools \(shellQuote(permitted)) --allowedTools \(shellQuote(permitted)) \
          --permission-mode dontAsk --permission-prompts none --agents \(shellQuote(agents.path)) \
          "$@" \(shellQuote(prompt)) > \(shellQuote(output.path)) 2> \(shellQuote(stderr.path))
        """
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let source = root.appendingPathComponent("synthetic-skill/SKILL.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        let skillContent = "---\nname: webscraping-expert\ndescription: Synthetic integration fixture\n---\nUse only the assigned computer for the synthetic page.\n"
        try skillContent.write(to: source, atomically: true, encoding: .utf8)
        let skillHash = SHA256.hash(data: Data(skillContent.utf8)).map { String(format: "%02x", $0) }.joined()
        let skill = SkillEntry(name: "webscraping-expert", summary: "Synthetic fixture",
                               sourcePath: source.path, content: skillContent, sha256: skillHash)
        let agent = SavedAgent(name: "Native flow fixture", instructions: "Use only the test page.",
                               provider: .claude, skillIDs: [skill.id])
        let hook = repositoryRoot().appendingPathComponent("runtime/hooks/claude_event.py")
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
            resolver: CLIExecutableResolver(overrides: [.claude: wrapper.path]))
        let plan = try planner.prepare(agentID: agent.id,
            in: LibraryDocument(agents: [agent], skills: [skill]), workingDirectory: root.path,
            computerID: parentBox.id, mcpHelper: helper, hookScriptURL: hook)
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256,
                                              terminalID: terminalID)
        let monitor = NativeAgentMonitor(registry: try AgentRunRegistry(url: root.appendingPathComponent("runs.json")),
                                         pollIntervalNanoseconds: 50_000_000)
        let runtime = TerminalRuntimeManager(nativeAgentMonitor: monitor)
        let broker = try ControlBroker(url: root.appendingPathComponent("broker.json"))
        let capture = NativeFlowStopCapture()
        let human = NativeFlowHumanHarness(broker: broker,
            endpoint: { id in try await service.reconnectEndpoint(computerID: id) })
        let resources = AgentComputerResources(
            lookup: { owner in try await Task.detached { try service.computer(for: owner) }.value },
            acquire: { owner, context in try await Task.detached {
                try service.createAndStart(for: owner, context: context, automaticRequest: true)
            }.value },
            endpoint: { id in try await service.reconnectEndpoint(computerID: id) },
            stop: { id in
                if let endpoint = try? await service.reconnectEndpoint(computerID: id),
                   let page = try? await BrowserRuntimeClient(endpoint: endpoint).page() {
                    await capture.record(computerID: id, url: page.url, text: page.text)
                }
                try await Task.detached { try service.stop(computerID: id) }.value
            })
        let access = AgentComputerAccess(resources: resources, runtime: runtime, broker: broker,
            policyProvider: { context in try policyStore.load().effective(for: context) },
            notifyUser: { request in human.notify(request) },
            completeRequest: { id in human.complete(id) })
        human.access = access
        defer { access.stop(terminalID: terminalID); runtime.shutdown() }
        let context = ComputerPolicyContext(terminalID: terminalID, sessionID: sessionID, agentID: agent.id)
        try await access.register(launch: launch, sessionID: sessionID,
                                  policyContext: context, endpoint: parentEndpoint)
        try runtime.start(launch)
        try access.activate(terminalID: terminalID)
        let watchdog = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 150_000_000_000); runtime.forceStop(terminalID) }
            catch {}
        }
        defer { watchdog.cancel() }

        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline {
            if case .exited = runtime.state(for: terminalID) { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard case .exited(let code) = runtime.state(for: terminalID) else {
            runtime.forceStop(terminalID)
            return XCTFail("Native Claude flow exceeded the 150-second deadline")
        }
        guard code == 0 else {
            let starts = monitor.runs.filter { $0.kind == .nativeSubagent }.count
            XCTFail("Native Claude exit=\(code.map { String($0) } ?? "unknown"); native_children=\(starts); \(sanitizedCLIError(at: stderr))")
            return
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            XCTFail("Native Claude produced no JSON result; \(sanitizedCLIError(at: stderr))")
            return
        }
        let raw = try Data(contentsOf: output)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(result["is_error"] as? Bool, false)
        let cost = result["total_cost_usd"] as? Double ?? 1
        XCTAssertLessThanOrEqual(cost, 0.25)
        let resultHasMarker = (result["result"] as? String ?? "").contains(marker)
        XCTAssertTrue(resultHasMarker,
                      "Only the local fixture page contains the required marker")

        var child: AgentRunRecord?
        var childBox: BrowserManagedComputer?
        var captured: NativeFlowStopCapture.Page?
        while Date() < deadline {
            child = monitor.runs.first(where: { $0.kind == .nativeSubagent && $0.parentTerminalID == terminalID })
            if let child {
                childBox = try service.computer(for: .nativeChild(parentTerminalID: terminalID, agentRunID: child.id))
                captured = await capture.page(for: childBox?.id)
            }
            if child?.status == .finished, childBox?.running == false, captured != nil { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let observedChild = try XCTUnwrap(child)
        let observedBox = try XCTUnwrap(childBox)
        let observedPage = try XCTUnwrap(captured)
        XCTAssertEqual(observedChild.nativeHookSource, .claude)
        XCTAssertNotNil(observedChild.nativeAgentID)
        XCTAssertEqual(observedChild.status, .finished)
        XCTAssertEqual(human.requests.count, 1, "Native child must request human help exactly once")
        XCTAssertEqual(human.requests.first?.target.sessionID, sessionID)
        XCTAssertEqual(human.requests.first?.target.terminalID, terminalID)
        XCTAssertEqual(human.requests.first?.target.runID, observedChild.id)
        XCTAssertEqual(human.requests.first?.target.computerID, observedBox.id)
        XCTAssertTrue(human.takeoverSucceeded, "Test human must acquire and release the shared child bridge")
        XCTAssertEqual(human.completedRequestIDs, human.requests.map(\.id))
        XCTAssertEqual(human.visitsAtTakeover, 1,
                       "The first page visit must precede the human takeover")
        XCTAssertEqual(observedBox.agentRunID, observedChild.id)
        XCTAssertEqual(observedBox.terminalID, terminalID)
        XCTAssertNotEqual(observedBox.id, parentBox.id)
        XCTAssertFalse(observedBox.running, "Automatic cleanup must stop the child box")
        XCTAssertEqual(observedPage.url, fixtureURL.absoluteString)
        XCTAssertTrue(observedPage.text.contains(marker))
        let visitSuffix = observedPage.text.components(separatedBy: "visits=").last ?? ""
        let finalVisits = Int(String(visitSuffix.prefix(while: { $0.isNumber }))) ?? 0
        XCTAssertGreaterThan(finalVisits, human.visitsAtTakeover ?? 0,
                             "Child must navigate again after human release")
        let parentAfter = try XCTUnwrap(service.computer(for: terminalID))
        XCTAssertEqual(parentAfter.id, parentBox.id)
        XCTAssertTrue(parentAfter.running)
        let parentHealth = try await BrowserRuntimeClient(endpoint: parentEndpoint).health()
        XCTAssertEqual(parentHealth.mode, .http, "The child's browser must not be the parent's browser")
        print("AB044_NATIVE_FLOW cost_usd=\(cost) native_child_count=\(monitor.runs.filter { $0.kind == .nativeSubagent }.count) marker_present=\(resultHasMarker && observedPage.text.contains(marker)) human_takeover=\(human.takeoverSucceeded) visits=\(finalVisits)")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func helperExecutable() throws -> URL {
        let starts = [Bundle(for: Self.self).bundleURL, Bundle.main.executableURL,
                      URL(fileURLWithPath: CommandLine.arguments[0])].compactMap { $0 }
        for start in starts {
            var directory = start.resolvingSymlinksInPath().deletingLastPathComponent()
            for _ in 0..<8 {
                let candidate = directory.appendingPathComponent("RackyMCP")
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
                directory.deleteLastPathComponent()
            }
        }
        throw XCTSkip("Build RackyMCP beside the test bundle before running native flow")
    }

    private func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func sanitizedCLIError(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return "cli_stderr=empty" }
        let text = String(decoding: data.prefix(8192), as: UTF8.self).lowercased()
        if text.contains("unknown option") || text.contains("unknown argument") {
            return "cli_stderr=option_rejected"
        }
        if text.contains("not logged in") || text.contains("authentication") || text.contains("unauthorized") {
            return "cli_stderr=authentication"
        }
        if text.contains("budget") { return "cli_stderr=budget" }
        if text.contains("permission") { return "cli_stderr=permission" }
        if text.contains("mcp") { return "cli_stderr=mcp" }
        return "cli_stderr=present"
    }

    private func containerIPv4(docker: DockerProcessRunner, containerID: String) throws -> String {
        let raw = try checked(docker, ["inspect", "--format",
            "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", containerID]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.allSatisfy({ $0.isNumber || $0 == "." }),
              raw.split(separator: ".").count == 4 else { throw BrowserComputerError.invalidDockerResponse }
        return raw
    }

    private func startPageFixture(docker: DockerProcessRunner, containerID: String, marker: String) throws {
        let html = """
        <!doctype html><html><head><title>Native child flow</title></head><body>
        <div id="marker"></div><script>
        const visits = Number(localStorage.getItem('visits') || '0') + 1;
        localStorage.setItem('visits', String(visits));
        document.getElementById('marker').textContent = '\(marker) visits=' + visits;
        </script>
        </body></html>
        """
        _ = try checked(docker, ["exec", containerID, "python", "-c",
            "from pathlib import Path; import sys; Path('/data/workspace/fixture.html').write_text(sys.argv[1])", html])
        _ = try checked(docker, ["exec", "-d", containerID, "python", "-m", "http.server", "8766",
                                 "--bind", "0.0.0.0", "--directory", "/data/workspace"])
        for _ in 0..<30 {
            let probe = try docker.run(["exec", containerID, "python", "-c",
                "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8766/fixture.html',timeout=1).read()"], timeout: 3)
            if probe.exitCode == 0 { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw BrowserComputerError.notReady
    }

    private func checked(_ docker: DockerProcessRunner, _ arguments: [String]) throws -> String {
        let result = try docker.run(arguments, timeout: 30)
        guard result.exitCode == 0 else { throw BrowserComputerError.commandFailed("Native flow fixture Docker command failed") }
        return result.stdout
    }

    private func cleanup(docker: DockerProcessRunner, computerIDs: Set<UUID>, terminalID: UUID) {
        for computerID in computerIDs {
            let lower = computerID.uuidString.lowercased()
            let listed = try? docker.run(["ps", "-a", "-q", "--no-trunc", "--filter",
                                          "label=com.racky.browser-computer-id=\(lower)"], timeout: 8)
            for id in (listed?.stdout ?? "").split(whereSeparator: \.isNewline).map(String.init) {
                guard let result = try? docker.run(["inspect", "--format", "{{json .Config.Labels}}", id], timeout: 8),
                      result.exitCode == 0, let data = result.stdout.data(using: .utf8),
                      let labels = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      labels["com.racky.browser-managed"] == "true",
                      labels["com.racky.browser-computer-id"] == lower,
                      labels["com.racky.browser-terminal-id"] == terminalID.uuidString.lowercased() else { continue }
                _ = try? docker.run(["rm", "--force", id], timeout: 20)
            }
            let volume = "racky-browser-data-\(lower)"
            guard let result = try? docker.run(["volume", "inspect", "--format", "{{json .Labels}}", volume], timeout: 8),
                  result.exitCode == 0, let data = result.stdout.data(using: .utf8),
                  let labels = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  labels["com.racky.browser-managed"] == "true",
                  labels["com.racky.browser-computer-id"] == lower else { continue }
            _ = try? docker.run(["volume", "rm", volume], timeout: 20)
        }
    }
}

private final class NativeFlowTokens: BrowserComputerTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [UUID: String] = [:]
    func put(computerID: UUID, value: String) throws {
        lock.lock(); tokens[computerID] = value; lock.unlock()
    }
    func read(computerID: UUID) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let token = tokens[computerID] else { throw BrowserComputerError.missingToken }
        return token
    }
    func delete(computerID: UUID) throws {
        lock.lock(); tokens.removeValue(forKey: computerID); lock.unlock()
    }
}

private final class NativeFlowTrackingRunner: DockerCommandRunning, @unchecked Sendable {
    let docker: DockerProcessRunner
    private let lock = NSLock()
    private var IDs: Set<UUID> = []
    var createdComputerIDs: Set<UUID> { lock.lock(); defer { lock.unlock() }; return IDs }
    init(docker: DockerProcessRunner) { self.docker = docker }
    func run(_ arguments: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        if arguments.starts(with: ["volume", "create"]),
           let label = arguments.first(where: { $0.hasPrefix("com.racky.browser-computer-id=") }),
           let id = UUID(uuidString: String(label.dropFirst("com.racky.browser-computer-id=".count))) {
            lock.lock(); IDs.insert(id); lock.unlock()
        }
        return try docker.run(arguments, timeout: timeout)
    }
}

private actor NativeFlowStopCapture {
    struct Page: Sendable { let url: String; let text: String }
    private var pages: [UUID: Page] = [:]
    func record(computerID: UUID, url: String, text: String) { pages[computerID] = Page(url: url, text: text) }
    func page(for computerID: UUID?) -> Page? { computerID.flatMap { pages[$0] } }
}

/// The test's human uses the same broker and cached bridge as MCP calls. It
/// intentionally bypasses HumanRequestCenter so the native flow is isolated.
@MainActor
private final class NativeFlowHumanHarness {
    let broker: ControlBroker
    let endpoint: @Sendable (UUID) async throws -> BrowserRuntimeEndpoint
    weak var access: AgentComputerAccess?
    private(set) var requests: [HumanRequest] = []
    private(set) var completedRequestIDs: [UUID] = []
    private(set) var takeoverSucceeded = false
    private(set) var visitsAtTakeover: Int?

    init(broker: ControlBroker, endpoint: @escaping @Sendable (UUID) async throws -> BrowserRuntimeEndpoint) {
        self.broker = broker
        self.endpoint = endpoint
    }

    func notify(_ request: HumanRequest) {
        requests.append(request)
        guard requests.count == 1 else { return }
        Task { [weak self] in await self?.takeAndRelease(request) }
    }

    func complete(_ id: UUID) { completedRequestIDs.append(id) }

    private func takeAndRelease(_ request: HumanRequest) async {
        do {
            let childEndpoint = try await endpoint(request.target.computerID)
            let bridge = await DesktopBrokerService.bridge(endpoint: childEndpoint, broker: broker)
            let humanTicket = try await bridge.assumeHuman()
            let generation = await bridge.currentGeneration()
            let page = try? await BrowserRuntimeClient(endpoint: childEndpoint)
                .refreshed(generation: generation).page()
            let suffix = page?.text.components(separatedBy: "visits=").last ?? ""
            visitsAtTakeover = Int(String(suffix.prefix(while: { $0.isNumber })))
            try await Task.sleep(nanoseconds: 500_000_000)
            try await bridge.releaseHuman(humanTicket)
            access?.humanReleased(computerID: request.target.computerID)
            takeoverSucceeded = true
        } catch {
            takeoverSucceeded = false
        }
    }
}
