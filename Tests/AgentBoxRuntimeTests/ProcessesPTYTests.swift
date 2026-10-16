import AppKit
import Darwin
import XCTest
import AgentBoxCore
@testable import AgentBox

final class ProcessesPTYTests: XCTestCase {
    @MainActor
    func testRealTTYResizeRemountAndControlC() async throws {
        let manager = TerminalRuntimeManager()
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
        let manager = TerminalRuntimeManager()
        defer { manager.shutdown() }
        let record = TerminalRecord(title: "exit", provider: .shell, cwd: "/tmp", arguments: ["-c", "exit 7"])
        manager.start(record)
        let firstExit = await waitUntil { manager.state(for: record.id) == .exited(code: 7) }
        XCTAssertTrue(firstExit)
        let oldRenderer = manager.renderer(for: record.id)
        manager.start(record)
        XCTAssertFalse(manager.renderer(for: record.id) === oldRenderer)
        let secondExit = await waitUntil { manager.state(for: record.id) == .exited(code: 7) }
        XCTAssertTrue(secondExit)
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
}
