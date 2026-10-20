import Darwin
import Foundation
import XCTest
@testable import RackyCore

/// Explicit opt-in, isolated two-container integration test. No user metadata,
/// Keychain, global Docker context, public site, or personal browser profile is used.
final class BrowserChildControlDockerTests: XCTestCase {
    func testTwoNativeChildBoxesIsolateControlAndPersistProfiles() async throws {
        guard ProcessInfo.processInfo.environment["RACKY_TEST_CHILD_CONTROL"] == "1" else {
            throw XCTSkip("Set RACKY_TEST_CHILD_CONTROL=1 for the isolated Docker child-control smoke")
        }
        let docker = DockerProcessRunner(executableURL: try XCTUnwrap(DockerProcessRunner.findExecutable()),
                                         contextName: "colima-racky-dev")
        let suffix = UUID().uuidString.lowercased()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("racky-child-control-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let terminalID = UUID(), childRunA = UUID(), childRunB = UUID(), parentRunID = UUID()
        let runner = ChildDockerTrackingRunner(docker: docker)
        defer { cleanup(docker: docker, computerIDs: runner.createdComputerIDs,
                        terminalID: terminalID, childRunIDs: [childRunA, childRunB]) }
        let policy = ComputerPolicyStore(fileURL: root.appendingPathComponent("policy.json"))
        try policy.save(ComputerPolicy(creation: .automatic,
            limits: .init(cpus: 1, memoryMiB: 2048, maxComputers: 64)))
        let metadata = BrowserComputerMetadataStore(url: root.appendingPathComponent("metadata.json"))
        let service = BrowserComputerService(runner: runner, tokens: ChildMemoryTokens(),
                                              policyStore: policy, metadataStore: metadata)
        let ownerA = BrowserComputerOwner.nativeChild(parentTerminalID: terminalID, agentRunID: childRunA)
        let ownerB = BrowserComputerOwner.nativeChild(parentTerminalID: terminalID, agentRunID: childRunB)
        let boxA = try service.createAndStart(for: ownerA, automaticRequest: true)
        let boxB = try service.createAndStart(for: ownerB, automaticRequest: true)
        XCTAssertNotEqual(boxA.id, boxB.id)
        XCTAssertNotEqual(boxA.containerID, boxB.containerID)
        XCTAssertNotEqual(boxA.volumeName, boxB.volumeName)
        XCTAssertEqual(boxA.terminalID, terminalID)
        XCTAssertEqual(boxB.terminalID, terminalID)
        XCTAssertEqual(boxA.agentRunID, childRunA)
        XCTAssertEqual(boxB.agentRunID, childRunB)
        let markerA = "A-\(suffix)", markerB = "B-\(suffix)"
        try startPageFixture(docker: docker, containerID: boxA.containerID, marker: markerA)
        try startPageFixture(docker: docker, containerID: boxB.containerID, marker: markerB)
        let endpointA = try await service.reconnectEndpoint(computerID: boxA.id)
        let endpointB = try await service.reconnectEndpoint(computerID: boxB.id)
        let broker = try ControlBroker(url: root.appendingPathComponent("broker.json"))
        let bridgeA = ComputerControlBridge(broker: broker, transport: BrowserRuntimeClient(endpoint: endpointA))
        let bridgeB = ComputerControlBridge(broker: broker, transport: BrowserRuntimeClient(endpoint: endpointB))
        let paths: Set<ControlWritePath> = [.navigate, .mode]
        var ticketA = try await bridgeA.assumeChild(parentRunID: parentRunID, nativeChildID: "native-A",
            paths: paths, allowedParentPaths: paths)
        var ticketB = try await bridgeB.assumeChild(parentRunID: parentRunID, nativeChildID: "native-B",
            paths: paths, allowedParentPaths: paths)
        _ = try await bridgeA.changeMode(.headless, ticket: ticketA)
        _ = try await bridgeB.changeMode(.headless, ticket: ticketB)
        let currentTicketA = await bridgeA.ticket()
        let currentTicketB = await bridgeB.ticket()
        ticketA = try XCTUnwrap(currentTicketA)
        ticketB = try XCTUnwrap(currentTicketB)
        let pageURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8766/fixture.html"))
        _ = try await bridgeA.navigate(to: pageURL, ticket: ticketA)
        _ = try await bridgeB.navigate(to: pageURL, ticket: ticketB)
        let clientA = try BrowserRuntimeClient(endpoint: endpointA)
            .refreshed(generation: await bridgeA.currentGeneration())
        let clientB = try BrowserRuntimeClient(endpoint: endpointB)
            .refreshed(generation: await bridgeB.currentGeneration())
        let textA = try await clientA.page().text
        let textB = try await clientB.page().text
        XCTAssertTrue(textA.contains(markerA))
        XCTAssertFalse(textA.contains(markerB))
        XCTAssertTrue(textB.contains(markerB))
        XCTAssertFalse(textB.contains(markerA))

        let humanA = try await bridgeA.assumeHuman()
        do {
            _ = try await bridgeA.navigate(to: pageURL, ticket: ticketA)
            XCTFail("A stale native child ticket must fail after human takeover")
        } catch {}
        // Human control of A does not revoke or suspend B's independent child.
        _ = try await bridgeB.navigate(to: pageURL, ticket: ticketB)
        let textBAfterTakeover = try await clientB.page().text
        XCTAssertTrue(textBAfterTakeover.contains(markerB))
        try await bridgeA.releaseHuman(humanA)
        ticketA = try await bridgeA.assumeChild(parentRunID: parentRunID, nativeChildID: "native-A",
            paths: paths, allowedParentPaths: paths)
        _ = try await bridgeA.navigate(to: pageURL, ticket: ticketA)
        let textAAfterResume = try await clientA.page().text
        XCTAssertTrue(textAAfterResume.contains(markerA))

        try await bridgeA.releaseController(ticketA)
        try await bridgeA.performIdleMaintenance {
            try service.stop(computerID: boxA.id)
        }
        XCTAssertFalse(try XCTUnwrap(service.computer(for: ownerA)).running)
        XCTAssertTrue(try XCTUnwrap(service.computer(for: ownerB)).running)
        _ = try await bridgeB.navigate(to: pageURL, ticket: ticketB)
        try await bridgeB.releaseController(ticketB)

        let restarted = try service.start(computerID: boxA.id)
        XCTAssertEqual(restarted.id, boxA.id)
        try startPageFixture(docker: docker, containerID: boxA.containerID, marker: "changed-\(suffix)")
        let restartedEndpoint = try await service.reconnectEndpoint(computerID: boxA.id)
        let restartedBridge = ComputerControlBridge(broker: broker,
            transport: BrowserRuntimeClient(endpoint: restartedEndpoint))
        var resumed = try await restartedBridge.assumeChild(parentRunID: parentRunID,
            nativeChildID: "native-A", paths: paths, allowedParentPaths: paths)
        _ = try await restartedBridge.changeMode(.headless, ticket: resumed)
        let currentResumedTicket = await restartedBridge.ticket()
        resumed = try XCTUnwrap(currentResumedTicket)
        _ = try await restartedBridge.navigate(to: pageURL, ticket: resumed)
        let resumedClient = try BrowserRuntimeClient(endpoint: restartedEndpoint)
            .refreshed(generation: await restartedBridge.currentGeneration())
        let persisted = try await resumedClient.page().text
        XCTAssertTrue(persisted.contains(markerA), "A's Chromium localStorage must survive its own restart")
        XCTAssertFalse(persisted.contains(markerB), "B's profile must remain isolated")
        XCTAssertFalse(persisted.contains("changed-\(suffix)"), "The page must read prior profile state")
        try await restartedBridge.releaseController(resumed)
    }

    private func startPageFixture(docker: DockerProcessRunner, containerID: String, marker: String) throws {
        let html = """
        <!doctype html><html><head><title>Native child fixture</title></head><body>
        <div id="owner"></div><script>
        if (!localStorage.getItem('owner')) localStorage.setItem('owner', '\(marker)');
        document.getElementById('owner').textContent = 'stored:' + localStorage.getItem('owner');
        </script></body></html>
        """
        try checked(docker, ["exec", containerID, "python", "-c",
                             "from pathlib import Path; import sys; Path('/data/workspace/fixture.html').write_text(sys.argv[1])", html])
        try checked(docker, ["exec", "-d", containerID, "python", "-m", "http.server", "8766",
                             "--bind", "127.0.0.1", "--directory", "/data/workspace"])
        for _ in 0..<30 {
            let probe = try docker.run(["exec", containerID, "python", "-c",
                "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8766/fixture.html', timeout=1).read()"], timeout: 3)
            if probe.exitCode == 0 { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw BrowserComputerError.notReady
    }

    private func checked(_ docker: DockerProcessRunner, _ arguments: [String]) throws {
        let result = try docker.run(arguments, timeout: 30)
        guard result.exitCode == 0 else { throw BrowserComputerError.commandFailed("Child Docker fixture command failed") }
    }

    private func cleanup(docker: DockerProcessRunner, computerIDs: Set<UUID>, terminalID: UUID,
                         childRunIDs: Set<UUID>) {
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
                      labels["com.racky.browser-terminal-id"] == terminalID.uuidString.lowercased(),
                      let runText = labels["com.racky.browser-agent-run-id"],
                      let runID = UUID(uuidString: runText), childRunIDs.contains(runID) else { continue }
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

private final class ChildMemoryTokens: BrowserComputerTokenStoring {
    private var values: [UUID: String] = [:]
    func put(computerID: UUID, value: String) throws { values[computerID] = value }
    func read(computerID: UUID) throws -> String {
        guard let token = values[computerID] else { throw BrowserComputerError.missingToken }
        return token
    }
    func delete(computerID: UUID) throws { values.removeValue(forKey: computerID) }
}

private final class ChildDockerTrackingRunner: DockerCommandRunning {
    let docker: DockerProcessRunner
    private(set) var createdComputerIDs: Set<UUID> = []
    init(docker: DockerProcessRunner) { self.docker = docker }
    func run(_ arguments: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        if arguments.starts(with: ["volume", "create"]),
           let label = arguments.first(where: { $0.hasPrefix("com.racky.browser-computer-id=") }),
           let id = UUID(uuidString: String(label.dropFirst("com.racky.browser-computer-id=".count))) {
            createdComputerIDs.insert(id)
        }
        return try docker.run(arguments, timeout: timeout)
    }
}
