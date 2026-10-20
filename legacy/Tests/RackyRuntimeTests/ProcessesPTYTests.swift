import AppKit
import Darwin
import XCTest
import RackyCore
@testable import Racky

final class ProcessesPTYTests: XCTestCase {
    @MainActor
    func testRealTTYResizeRemountAndControlC() async throws {
        let manager = TerminalRuntimeManager(nativeAgentMonitor: try makeMonitor())
        defer { manager.shutdown() }
        let record = TerminalRecord(title: "PTY smoke", provider: .shell, cwd: "/tmp",
                                    arguments: ["-c", "echo PTY_READY; tty; stty size; exec sleep 30"])
        manager.start(record)
        guard case .running(let pid) = manager.state(for: record.id),
              let renderer = manager.renderer(for: record.id), let process = renderer.process else {
            XCTFail("A real PTY shell did not start: \(manager.state(for: record.id))")
            return
        }
        XCTAssertGreaterThan(pid, 0)
        let background = try XCTUnwrap(renderer.nativeBackgroundColor.usingColorSpace(.sRGB))
        let foreground = try XCTUnwrap(renderer.nativeForegroundColor.usingColorSpace(.sRGB))
        XCTAssertEqual(background.redComponent, 39.0 / 255, accuracy: 0.001)
        XCTAssertEqual(background.greenComponent, 43.0 / 255, accuracy: 0.001)
        XCTAssertEqual(background.blueComponent, 51.0 / 255, accuracy: 0.001)
        XCTAssertEqual(foreground.redComponent, 218.0 / 255, accuracy: 0.001)
        XCTAssertEqual(foreground.greenComponent, 220.0 / 255, accuracy: 0.001)
        XCTAssertEqual(foreground.blueComponent, 226.0 / 255, accuracy: 0.001)
        let sawTTY = await waitUntil {
            let text = String(data: renderer.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
            return text.contains("PTY_READY") && text.contains("/dev/tty")
        }
        XCTAssertTrue(sawTTY, "The shell should observe a real controlling TTY")

        renderer.resize(cols: 100, rows: 30)
        var size = winsize()
        XCTAssertEqual(ioctl(process.childfd, TIOCGWINSZ, &size), 0)
        XCTAssertEqual(size.ws_col, 100)
        XCTAssertEqual(size.ws_row, 30)

        let hostA = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        let hostB = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        manager.attach(record.id, to: hostA)
        manager.attach(record.id, to: hostB)
        XCTAssertTrue(manager.renderer(for: record.id) === renderer)
        XCTAssertEqual(manager.state(for: record.id), .running(pid: pid))

        process.send(data: [UInt8(3)][...])
        let interrupted = await waitUntil {
            if case .exited = manager.state(for: record.id) { return true }
            return false
        }
        XCTAssertTrue(interrupted, "Ctrl-C should interrupt the foreground process")
        XCTAssertFalse(manager.hasRunningProcesses)
    }

    @MainActor
    func testNormalExitAndExplicitRestart() async throws {
        let monitor = try makeMonitor()
        let manager = TerminalRuntimeManager(nativeAgentMonitor: monitor)
        defer { manager.shutdown() }
        let record = TerminalRecord(title: "exit", provider: .shell, cwd: "/tmp", arguments: ["-c", "exit 7"])
        manager.start(record)
        let firstExit = await waitUntil { manager.state(for: record.id) == .exited(code: 7) }
        XCTAssertTrue(firstExit)
        let firstRecorded = await waitUntil {
            monitor.runs.filter { $0.terminalID == record.id && $0.status == .finished }.count == 1
        }
        XCTAssertTrue(firstRecorded)
        let oldRenderer = manager.renderer(for: record.id)
        manager.start(record)
        XCTAssertFalse(manager.renderer(for: record.id) === oldRenderer)
        let secondExit = await waitUntil { manager.state(for: record.id) == .exited(code: 7) }
        XCTAssertTrue(secondExit)
        let secondRecorded = await waitUntil {
            monitor.runs.filter { $0.terminalID == record.id && $0.status == .finished }.count == 2
        }
        XCTAssertTrue(secondRecorded)
        XCTAssertEqual(Set(monitor.runs.filter { $0.terminalID == record.id }.map(\.id)).count, 2)
    }

    @MainActor
    func testReviewedLaunchCannotReuseLiveProcessAndCanReplaceStoppedTerminal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("local-cli-fixture")
        try "#!/bin/sh\necho SNAPSHOT_PROCESS\nexec sleep 30\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
            resolver: CLIExecutableResolver(overrides: [.claude: executable.path]))
        let agent = SavedAgent(name: "Fixture", instructions: "Local fixture only", provider: .claude)
        let document = LibraryDocument(agents: [agent])
        let manager = TerminalRuntimeManager(nativeAgentMonitor: try makeMonitor())
        defer { manager.shutdown() }
        let terminal = TerminalRecord(title: "Existing", provider: .shell, cwd: "/tmp", arguments: ["-c", "exec sleep 30"])
        manager.start(terminal)
        let original = manager.state(for: terminal.id)
        let first = try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp")
        let launch = try planner.materialize(first, reviewedDigest: first.review.contextSHA256, terminalID: terminal.id)
        XCTAssertThrowsError(try manager.start(launch))
        XCTAssertEqual(manager.state(for: terminal.id), original)
        XCTAssertFalse(manager.isRunning(launch))
        XCTAssertThrowsError(try manager.beginComputerMaintenance(terminalID: terminal.id))
        manager.stop(terminal.id)
        let stopped = await waitUntil { if case .exited = manager.state(for: terminal.id) { return true }; return false }
        XCTAssertTrue(stopped)
        let maintenance = try manager.beginComputerMaintenance(terminalID: terminal.id)
        XCTAssertThrowsError(try manager.beginComputerMaintenance(terminalID: terminal.id))
        XCTAssertThrowsError(try manager.start(launch))
        manager.start(terminal)
        guard case .failed = manager.state(for: terminal.id) else {
            return XCTFail("Maintenance must block a plain terminal start too")
        }
        manager.endComputerMaintenance(terminalID: terminal.id, ticket: UUID())
        XCTAssertThrowsError(try manager.start(launch), "An old or foreign ticket must not release maintenance")
        manager.endComputerMaintenance(terminalID: terminal.id, ticket: maintenance)
        try manager.start(launch)
        XCTAssertTrue(manager.isRunning(launch))
        XCTAssertEqual(manager.runningPlanID(for: terminal.id), first.id)
        let second = try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp")
        let replacement = try planner.materialize(second, reviewedDigest: second.review.contextSHA256, terminalID: terminal.id)
        XCTAssertThrowsError(try manager.start(replacement))
        XCTAssertFalse(manager.isRunning(replacement))
        XCTAssertTrue(manager.isRunning(launch))
        manager.stop(terminal.id)
        let stoppedAgain = await waitUntil { if case .exited = manager.state(for: terminal.id) { return true }; return false }
        XCTAssertTrue(stoppedAgain)
        try manager.start(replacement)
        XCTAssertTrue(manager.isRunning(replacement))
        XCTAssertFalse(manager.isRunning(launch))
    }

    @MainActor
    func testReviewedClaudeHookGetsFreshInvocationForEachPTYRun() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hook-runtime-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("claude-fixture")
        let script = """
        #!/bin/sh
        [ -n "$RACKY_HOOK_RUN_ID" ] || exit 41
        [ -n "$RACKY_HOOK_TOKEN" ] || exit 42
        [ -f "$RACKY_HOOK_INBOX" ] || exit 43
        case " $* " in *" --settings "*) ;; *) exit 44 ;; esac
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let hookScript = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("runtime/hooks/claude_event.py")
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
            resolver: CLIExecutableResolver(overrides: [.claude: executable.path]))
        let agent = SavedAgent(name: "Hook fixture", instructions: "Local test", provider: .claude)
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent]),
                                       workingDirectory: root.path, hookScriptURL: hookScript)
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        let monitor = try makeMonitor()
        let manager = TerminalRuntimeManager(nativeAgentMonitor: monitor)
        defer { manager.shutdown() }
        let terminalID = try XCTUnwrap(launch.terminal?.id)

        try manager.start(launch)
        let firstExited = await waitUntil { manager.state(for: terminalID) == .exited(code: 0) }
        XCTAssertTrue(firstExited)
        let firstRecorded = await waitUntil {
            monitor.runs.filter { $0.terminalID == terminalID && $0.status == .finished }.count == 1
        }
        XCTAssertTrue(firstRecorded)
        try manager.start(launch)
        let secondExited = await waitUntil { manager.state(for: terminalID) == .exited(code: 0) }
        XCTAssertTrue(secondExited)
        let secondRecorded = await waitUntil {
            monitor.runs.filter { $0.terminalID == terminalID && $0.status == .finished }.count == 2
        }
        XCTAssertTrue(secondRecorded)
        XCTAssertEqual(Set(monitor.runs.filter { $0.terminalID == terminalID }.map(\.id)).count, 2)
        XCTAssertNil(monitor.errorText)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    @MainActor
    private func makeMonitor() throws -> NativeAgentMonitor {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-runs-\(UUID())")
        return NativeAgentMonitor(registry: try AgentRunRegistry(url: root.appendingPathComponent("runs.json")),
                                  pollIntervalNanoseconds: 20_000_000)
    }
}
