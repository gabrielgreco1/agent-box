import XCTest
@testable import AgentBoxCore

final class ProcessesResolverTests: XCTestCase {
    func testFinderStylePathStillFindsSystemShell() throws {
        let resolver = CLIExecutableResolver(environment: ["PATH": "/empty"], homeDirectory: "/empty")
        XCTAssertEqual(try resolver.resolve(.shell), "/bin/zsh")
    }

    func testExplicitOverrideIsValidatedAndPreferred() throws {
        let resolver = CLIExecutableResolver(overrides: [.shell: "/bin/sh"], environment: ["PATH": "/empty"])
        XCTAssertEqual(try resolver.resolve(.shell), "/bin/sh")
        let invalid = CLIExecutableResolver(overrides: [.shell: "/no/such/executable"])
        XCTAssertThrowsError(try invalid.resolve(.shell)) { error in
            XCTAssertEqual(error as? CLIResolutionError, .notExecutable("/no/such/executable"))
        }
    }

    func testWorkingDirectoryValidation() throws {
        let resolver = CLIExecutableResolver()
        XCTAssertEqual(try resolver.validateWorkingDirectory("/tmp"), "/tmp")
        XCTAssertThrowsError(try resolver.validateWorkingDirectory("/no/such/directory"))
    }

    func testNVMDiscoveryChoosesNewestInstalledNodeVersion() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        for version in ["v20.1.0", "v25.9.0"] {
            let directory = home.appendingPathComponent(".nvm/versions/node/\(version)/bin", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let executable = directory.appendingPathComponent("codex")
            try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        let resolver = CLIExecutableResolver(environment: ["PATH": "/empty"], homeDirectory: home.path)
        XCTAssertTrue(try resolver.resolve(.codex).contains("v25.9.0/bin/codex"))
    }

    func testProbeDrainsOversizedOutputAndTimesOutAnIgnoringChild() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loud = directory.appendingPathComponent("loud")
        try "#!/bin/sh\ni=0; while [ $i -lt 20000 ]; do printf x; i=$((i+1)); done\n".write(to: loud, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: loud.path)
        let output = await CLICommandProbe.run(executable: loud.path, arguments: [], timeout: 3)
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertFalse(output.timedOut)
        XCTAssertEqual(output.output.count, 16_384)

        let hanging = directory.appendingPathComponent("hanging")
        try "#!/bin/sh\ntrap '' TERM\nwhile :; do :; done\n".write(to: hanging, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hanging.path)
        let timeout = await CLICommandProbe.run(executable: hanging.path, arguments: [], timeout: 0.2)
        XCTAssertTrue(timeout.timedOut)
        XCTAssertNil(timeout.exitCode)
    }
}
