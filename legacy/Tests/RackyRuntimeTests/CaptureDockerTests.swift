import RackyCore
import Foundation
import XCTest
@testable import Racky

/// Opt-in real Chromium/listener smoke. All Docker state is isolated to one
/// labeled box on the dedicated test context; no public site or user profile.
final class CaptureDockerTests: XCTestCase {
    func testRealBrowserCaptureFiltersIdleRequestsAndExportsEvidence() async throws {
        guard ProcessInfo.processInfo.environment["RACKY_TEST_CAPTURE_DOCKER"] == "1" else {
            throw XCTSkip("Set RACKY_TEST_CAPTURE_DOCKER=1 for the isolated capture Docker smoke")
        }
        let smokeDeadline = Date().addingTimeInterval(90)
        let docker = DockerProcessRunner(executableURL: try XCTUnwrap(DockerProcessRunner.findExecutable()),
                                         contextName: "colima-racky-dev")
        let suffix = UUID().uuidString.lowercased()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("racky-capture-smoke-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let terminalID = UUID(), sessionID = UUID(), runID = UUID()
        let runner = CaptureTrackingRunner(docker: docker)
        defer { cleanup(docker: docker, computerIDs: runner.createdComputerIDs, terminalID: terminalID) }
        let policy = ComputerPolicyStore(fileURL: root.appendingPathComponent("policy.json"))
        try policy.save(ComputerPolicy(creation: .manual,
            limits: .init(cpus: 1, memoryMiB: 2048, maxComputers: 64)))
        let service = BrowserComputerService(runner: runner, tokens: CaptureMemoryTokens(),
            policyStore: policy, metadataStore: BrowserComputerMetadataStore(url: root.appendingPathComponent("metadata.json")))
        let box = try service.createAndStart(for: terminalID)
        let marker = "CAPTURE_\(suffix.replacingOccurrences(of: "-", with: ""))"
        try fixture(docker: docker, containerID: box.containerID, marker: marker, seed: true)
        let endpoint = try await service.reconnectEndpoint(computerID: box.id)
        let client = BrowserRuntimeClient(endpoint: endpoint)
        let initial = try await client.capture()
        XCTAssertFalse(initial.enabled)
        XCTAssertTrue(initial.events.isEmpty)
        XCTAssertEqual(UUID(uuidString: initial.computerID), box.id)
        let broker = try ControlBroker(url: root.appendingPathComponent("broker.json"))
        let bridge = ComputerControlBridge(broker: broker, transport: client)
        var ticket = try await bridge.assumeAgent(runID: runID, paths: Set(ControlWritePath.allCases))
        _ = try await bridge.changeMode(.headless, ticket: ticket)
        let headlessTicket = await bridge.ticket()
        ticket = try XCTUnwrap(headlessTicket)
        let redirectURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8766/redirect?token=HIDDEN"))
        _ = try await bridge.navigate(to: redirectURL, ticket: ticket)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let disabledObservation = try await client.capture()
        XCTAssertTrue(disabledObservation.events.isEmpty,
                      "Listener must remain disabled until host configuration")

        let denied = CaptureConfiguration(enabled: true, hosts: ["example.invalid"],
            pathPrefixes: ["/api/late.json", "/redirect", "/popup.html"])
        _ = try await client.configureCapture(denied)
        _ = try await bridge.navigate(to: redirectURL, ticket: ticket)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let deniedObservation = try await client.capture()
        XCTAssertTrue(deniedObservation.events.isEmpty,
                      "A host not on the allowlist must not be retained")

        let allowed = CaptureConfiguration(enabled: true, hosts: ["127.0.0.1"],
            pathPrefixes: ["/api/late.json", "/redirect", "/popup.html"],
            maxEvents: 64, retentionSeconds: 3_600)
        let enabled = try await client.configureCapture(allowed)
        XCTAssertTrue(enabled.enabled)
        XCTAssertNotEqual(enabled.captureID, initial.captureID)
        _ = try await bridge.navigate(to: redirectURL, ticket: ticket)
        let deadline = min(Date().addingTimeInterval(15), smokeDeadline)
        let browserBatch = try await waitForCapture(client, after: 0, deadline: deadline) { batch in
            let events = batch.events.filter { $0.source == "browser" }
            return events.contains { $0.status == 301 } &&
                events.contains { $0.url == "http://127.0.0.1:8766/api/late.json" }
        }
        XCTAssertEqual(browserBatch.captureID, enabled.captureID)
        XCTAssertTrue(browserBatch.events.allSatisfy { $0.url.hasPrefix("http://127.0.0.1:8766") })
        XCTAssertFalse(browserBatch.events.contains { $0.url.contains("HIDDEN") || $0.url.contains("?") })
        XCTAssertTrue(browserBatch.gaps.contains("browser_response_bodies"))
        XCTAssertTrue(browserBatch.gaps.contains("websocket_frames"))
        let delayed = try XCTUnwrap(browserBatch.events.first { $0.url.hasSuffix("/api/late.json") })
        XCTAssertEqual(delayed.status, 200)
        XCTAssertEqual(delayed.omission, "browser_body_not_captured")
        XCTAssertNil(delayed.bodyJSON)

        let hostStore = try CaptureStore(directory: root.appendingPathComponent("captures"))
        let identity = CaptureIdentity(sessionID: sessionID, terminalID: terminalID,
                                       computerID: box.id)
        let appended = try await hostStore.append(batch: browserBatch, identity: identity, configuration: allowed)
        XCTAssertGreaterThan(appended.inserted, 0)
        let records = try await hostStore.records(computerID: box.id)
        XCTAssertEqual(records.count, appended.inserted)
        let datasetStore = try DatasetStore(directory: root.appendingPathComponent("results"))
        let dataset = try await datasetStore.create(name: "Fixture metadata", columns: ["value"], from: records)
        XCTAssertEqual(dataset.rows.count, records.count)
        XCTAssertTrue(dataset.rows.allSatisfy { $0.missingReasons["value"] == "body_not_captured" })
        let export = try await datasetStore.export(datasetID: dataset.id, format: .json, to: root)
        XCTAssertEqual(export.rowCount, records.count)
        let exported = try String(contentsOf: export.dataURL, encoding: .utf8)
        XCTAssertFalse(exported.contains("HIDDEN"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.manifestURL.path))

        // The next page load may only read the persisted profile. It must not
        // silently recreate the marker if Chromium started with a fresh one.
        try fixture(docker: docker, containerID: box.containerID, marker: marker,
                    seed: false, startServer: false)
        _ = try await bridge.changeMode(.desktop, ticket: ticket)
        let desktopTicket = await bridge.ticket()
        ticket = try XCTUnwrap(desktopTicket)
        let desktopClient = try client.refreshed(generation: await bridge.currentGeneration())
        let promotedPage = try await desktopClient.page()
        XCTAssertTrue(promotedPage.text.contains(marker),
                      "The same Chromium profile must survive headless-to-desktop promotion")
        let beforePopup = try await client.capture()
        try await bridge.input(.key("ctrl+t"), ticket: ticket)
        try await bridge.input(.text("http://127.0.0.1:8766/popup.html?token=HIDDEN"), ticket: ticket)
        try await bridge.input(.key("Return"), ticket: ticket)
        let popupBatch = try await waitForCapture(client, after: beforePopup.nextCursor,
                                                   deadline: min(Date().addingTimeInterval(15), smokeDeadline)) { batch in
            batch.events.contains { $0.source == "browser" &&
                $0.url == "http://127.0.0.1:8766/popup.html" && $0.status == 200 }
        }
        XCTAssertEqual(popupBatch.captureID, enabled.captureID)
        XCTAssertFalse(popupBatch.events.contains { $0.url.contains("HIDDEN") })

        let cleared = try await client.clearCaptures()
        XCTAssertTrue(cleared.enabled)
        XCTAssertTrue(cleared.events.isEmpty)
        XCTAssertEqual(cleared.nextCursor, 0)
        XCTAssertNotEqual(cleared.captureID, popupBatch.captureID)
        let disabled = try await client.configureCapture(CaptureConfiguration())
        XCTAssertFalse(disabled.enabled)
        XCTAssertTrue(disabled.events.isEmpty)
        try await bridge.releaseAgent(ticket)
        try service.stop(computerID: box.id)
        _ = try service.start(computerID: box.id)
        try fixture(docker: docker, containerID: box.containerID, marker: marker, seed: false)
        let restartedEndpoint = try await service.reconnectEndpoint(computerID: box.id)
        let restartedClient = BrowserRuntimeClient(endpoint: restartedEndpoint)
        let restartedCapture = try await restartedClient.capture()
        XCTAssertFalse(restartedCapture.enabled)
        XCTAssertNotEqual(restartedCapture.captureID, disabled.captureID)
        let restartedBridge = ComputerControlBridge(broker: broker, transport: restartedClient)
        var resumed = try await restartedBridge.assumeAgent(runID: runID, paths: Set(ControlWritePath.allCases))
        _ = try await restartedBridge.changeMode(.headless, ticket: resumed)
        let restartedTicket = await restartedBridge.ticket()
        resumed = try XCTUnwrap(restartedTicket)
        let restored = try restartedClient.refreshed(generation: await restartedBridge.currentGeneration())
        let restoredPage = try await restored.page()
        XCTAssertTrue(restoredPage.text.contains(marker),
                      "The profile marker must persist through box restart")
        try await restartedBridge.releaseAgent(resumed)
        XCTAssertLessThan(Date(), smokeDeadline, "The opt-in capture smoke must finish within 90 seconds")
        print("AB046_CAPTURE_SMOKE browser_events=\(browserBatch.events.count) popup_observed=true origin_sanitized=true capture_rotated=true profile_persisted=true")
    }

    private func waitForCapture(_ client: BrowserRuntimeClient, after: Int, deadline: Date,
                                condition: (CaptureBatch) -> Bool) async throws -> CaptureBatch {
        while Date() < deadline {
            let batch = try await client.capture(after: after)
            if condition(batch) { return batch }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw BrowserComputerError.notReady
    }

    private func fixture(docker: DockerProcessRunner, containerID: String, marker: String,
                         seed: Bool, startServer: Bool = true) throws {
        let seedScript = seed ? "if (!localStorage.getItem('capture-owner')) localStorage.setItem('capture-owner', '\(marker)');" : ""
        let html = """
        <!doctype html><html><head><title>Capture fixture</title></head><body>
        <div id="marker"></div><script>
        \(seedScript)
        document.getElementById('marker').textContent = localStorage.getItem('capture-owner');
        setTimeout(() => fetch('/api/late.json?token=HIDDEN'), 900);
        </script></body></html>
        """
        let script = """
        from pathlib import Path
        import sys
        root = Path('/data/workspace')
        (root / 'redirect').mkdir(exist_ok=True)
        (root / 'api').mkdir(exist_ok=True)
        (root / 'redirect' / 'index.html').write_text(sys.argv[1])
        (root / 'popup.html').write_text('<!doctype html><title>Popup fixture</title><p>new tab</p>')
        (root / 'api' / 'late.json').write_text('{"value":"public-fixture"}')
        """
        _ = try checked(docker, ["exec", containerID, "python", "-c", script, html])
        if !startServer { return }
        _ = try checked(docker, ["exec", "-d", containerID, "python", "-m", "http.server", "8766",
                                 "--bind", "127.0.0.1", "--directory", "/data/workspace"])
        for _ in 0..<30 {
            let probe = try docker.run(["exec", containerID, "python", "-c",
                "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8766/redirect/',timeout=1).read()"], timeout: 3)
            if probe.exitCode == 0 { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw BrowserComputerError.notReady
    }

    private func checked(_ docker: DockerProcessRunner, _ arguments: [String]) throws -> String {
        let result = try docker.run(arguments, timeout: 30)
        guard result.exitCode == 0 else {
            throw BrowserComputerError.commandFailed("Capture Docker fixture command failed")
        }
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

private final class CaptureMemoryTokens: BrowserComputerTokenStoring {
    private var values: [UUID: String] = [:]
    func put(computerID: UUID, value: String) throws { values[computerID] = value }
    func read(computerID: UUID) throws -> String {
        guard let value = values[computerID] else { throw BrowserComputerError.missingToken }
        return value
    }
    func delete(computerID: UUID) throws { values.removeValue(forKey: computerID) }
}

private final class CaptureTrackingRunner: DockerCommandRunning {
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
