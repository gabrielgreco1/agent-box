import XCTest
@testable import RackyCore

private final class FakeDockerRunner: DockerCommandRunning {
    var commands: [[String]] = []
    var responses: [DockerCommandResult] = []
    func run(_ arguments: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        commands.append(arguments)
        guard !responses.isEmpty else { XCTFail("Unexpected Docker invocation: \(arguments)"); return .init(exitCode: 1) }
        return responses.removeFirst()
    }
}

final class DockerComputerTests: XCTestCase {
    private func policyStore() -> ComputerPolicyStore {
        ComputerPolicyStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("policy.json"))
    }
    private func inspection(_ terminalID: UUID, owner: String = "true", running: Bool = true) -> String {
        let dictionary: [String: Any] = [
            "Id": "container-123", "Name": "/racky-\(terminalID.uuidString.lowercased())",
            "Config": ["Labels": ["com.racky.managed": owner,
                                  "com.racky.terminal-id": terminalID.uuidString.lowercased()]],
            "State": ["Running": running]
        ]
        let data = try! JSONSerialization.data(withJSONObject: dictionary)
        return String(decoding: data, as: UTF8.self)
    }

    func testPolicyDefaultsDisabledAndPersists() throws {
        let store = policyStore()
        XCTAssertEqual(try store.load().creation, .disabled)
        try store.save(ComputerPolicy(creation: .manual, modePreference: .alwaysGraphical))
        XCTAssertEqual(try store.load().creation, .manual)
        XCTAssertEqual(try store.load().modePreference, .alwaysGraphical)
    }

    func testCreationIsBlockedByDefaultWithoutDockerInvocation() throws {
        let runner = FakeDockerRunner()
        let service = DockerComputerService(runner: runner, policyStore: policyStore())
        XCTAssertThrowsError(try service.createAndStart(for: UUID()))
        XCTAssertTrue(runner.commands.isEmpty)
    }

    func testExplicitCreationUsesTerminalLabelsAndConstrainedContainer() throws {
        let id = UUID(), runner = FakeDockerRunner(), store = policyStore()
        try store.save(ComputerPolicy(creation: .manual))
        runner.responses = [
            .init(exitCode: 0), // No existing container.
            .init(exitCode: 0), // Legacy capacity available.
            .init(exitCode: 0), // Browser capacity available.
            .init(exitCode: 0, stdout: "container-123\n"), // docker create
            .init(exitCode: 0, stdout: "container-123\n"), // list
            .init(exitCode: 0, stdout: inspection(id, running: false)), // inspect
            .init(exitCode: 0, stdout: inspection(id, running: false)), // pre-start ownership check
            .init(exitCode: 0), // start
            .init(exitCode: 0, stdout: "container-123\n"), // list
            .init(exitCode: 0, stdout: inspection(id)) // inspect running
        ]
        let service = DockerComputerService(runner: runner, policyStore: store)
        let computer = try service.createAndStart(for: id)
        XCTAssertTrue(computer.running)
        let create = runner.commands[3]
        XCTAssertEqual(create.first, "create")
        XCTAssertTrue(create.contains("com.racky.terminal-id=\(id.uuidString.lowercased())"))
        for option in ["--cpus", "--memory", "--pids-limit", "--read-only", "--cap-drop", "--user"] {
            XCTAssertTrue(create.contains(option), option)
        }
        for forbidden in ["--privileged", "--volume", "-v", "--mount", "--publish", "-p"] {
            XCTAssertFalse(create.contains(forbidden), forbidden)
        }
        XCTAssertEqual(runner.commands[7], ["start", "container-123"])
    }

    func testUnownedContainerCannotBeStopped() throws {
        let id = UUID(), runner = FakeDockerRunner()
        runner.responses = [.init(exitCode: 0, stdout: "container-123\n"),
                            .init(exitCode: 0, stdout: inspection(id, owner: "false"))]
        let service = DockerComputerService(runner: runner, policyStore: policyStore())
        XCTAssertThrowsError(try service.stop(for: id))
        XCTAssertFalse(runner.commands.contains { $0.first == "stop" })
    }

    func testRealProcessRunnerUsesArgvAndTimesOut() throws {
        let echo = DockerProcessRunner(executableURL: URL(fileURLWithPath: "/bin/echo"))
        let result = try echo.run(["literal;$(touch /tmp/racky-should-not-exist)"], timeout: 2)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "literal;$(touch /tmp/racky-should-not-exist)")
        let sleep = DockerProcessRunner(executableURL: URL(fileURLWithPath: "/bin/sleep"))
        XCTAssertThrowsError(try sleep.run(["5"], timeout: 0.1)) { error in
            XCTAssertEqual(error as? DockerCommandError, .timedOut)
        }
    }

    func testDaemonProbeReportsActualFailure() {
        let runner = FakeDockerRunner()
        runner.responses = [.init(exitCode: 1, stderr: "Cannot connect to the Docker daemon")]
        XCTAssertEqual(DockerComputerService(runner: runner).availability(),
                       .daemonUnavailable("Cannot connect to the Docker daemon"))
    }
}
