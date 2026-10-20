import XCTest
@testable import RackyCore

final class ProcessesProbeTests: XCTestCase {
    func testProbeFindsInterpreterBesideNVMStyleExecutable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("probe-helper")
        let cli = directory.appendingPathComponent("mock-codex")
        try "#!/bin/sh\nprintf 'Logged in using test account\\n'\n".write(to: helper, atomically: true, encoding: .utf8)
        try "#!/usr/bin/env probe-helper\n".write(to: cli, atomically: true, encoding: .utf8)
        for path in [helper, cli] { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path) }
        let result = await CLICommandProbe.run(executable: cli.path, arguments: ["login", "status"], timeout: 2)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(CLIAuthStatus.interpret(result, provider: .codex), .authenticated)
    }

    func testAuthStatusShapesDoNotExposeOutput() {
        let notLoggedIn = CLICommandResult(exitCode: 0, output: "Not logged in", timedOut: false)
        XCTAssertEqual(CLIAuthStatus.interpret(notLoggedIn, provider: .codex), .unauthenticated)
        let claude = CLICommandResult(exitCode: 0, output: "{\"loggedIn\":false,\"email\":\"ignored@example.invalid\"}", timedOut: false)
        XCTAssertEqual(CLIAuthStatus.interpret(claude, provider: .claude), .unauthenticated)
        let timedOut = CLICommandResult(exitCode: nil, output: "", timedOut: true)
        XCTAssertEqual(CLIAuthStatus.interpret(timedOut, provider: .codex), .unavailable)
    }
}
