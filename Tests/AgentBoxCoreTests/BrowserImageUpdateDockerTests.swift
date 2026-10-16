import Darwin
import Foundation
import XCTest
@testable import AgentBoxCore

/// Explicit opt-in integration test. It never reads the user's metadata or Keychain.
final class BrowserImageUpdateDockerTests: XCTestCase {
    func testStoppedBoxUpdateAndRollbackWithRealDocker() throws {
        guard ProcessInfo.processInfo.environment["AGENTBOX_TEST_DOCKER_UPDATE"] == "1" else {
            throw XCTSkip("Set AGENTBOX_TEST_DOCKER_UPDATE=1 to run the isolated Docker update smoke")
        }
        let context = "colima-agentbox-dev"
        let executable = try XCTUnwrap(DockerProcessRunner.findExecutable(), "Docker CLI is required")
        let docker = DockerProcessRunner(executableURL: executable, contextName: context)
        let terminalID = UUID()
        let suffix = UUID().uuidString.lowercased()
        let fixtureTag = "agentbox-update-smoke:\(suffix)"
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentbox-update-smoke-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let sourceTag = BrowserComputerService<MappedDockerRunner, MemoryBrowserTokens>.image
        let sourceImageID = try dockerOutput(docker, ["image", "inspect", "--format", "{{.Id}}", sourceTag])
        XCTAssertTrue(sourceImageID.hasPrefix("sha256:"))
        let runner = MappedDockerRunner(docker: docker, configuredImageID: sourceImageID)
        defer {
            cleanup(docker: docker, computerID: runner.createdComputerID, terminalID: terminalID,
                    knownContainerIDs: runner.createdContainerIDs, fixtureTag: fixtureTag, smokeID: suffix)
        }
        let targetImageID = try buildDerivedImage(dockerExecutable: executable, context: context,
                                                   sourceImageID: sourceImageID, tag: fixtureTag,
                                                   smokeID: suffix)
        XCTAssertNotEqual(sourceImageID, targetImageID)
        let imageLabel = try dockerOutput(docker, ["image", "inspect", "--format",
                                                  "{{ index .Config.Labels \"com.agentbox.smoke\" }}", fixtureTag])
        XCTAssertEqual(imageLabel, suffix)

        let tokens = MemoryBrowserTokens()
        let policyStore = ComputerPolicyStore(fileURL: temporaryRoot.appendingPathComponent("policy.json"))
        try policyStore.save(ComputerPolicy(creation: .manual,
            limits: .init(cpus: 1, memoryMiB: 2048, maxComputers: 64)))
        let metadataStore = BrowserComputerMetadataStore(url: temporaryRoot.appendingPathComponent("metadata.json"))
        let service = BrowserComputerService(runner: runner, tokens: tokens,
                                             policyStore: policyStore, metadataStore: metadataStore)
        let original = try service.createAndStart(for: terminalID)
        XCTAssertEqual(original.id, runner.createdComputerID)
        XCTAssertTrue(original.running)
        XCTAssertEqual(try dockerOutput(docker, ["inspect", "--format", "{{.Image}}", original.containerID]), sourceImageID)
        let marker = "marker-\(suffix)"
        _ = try dockerOutput(docker, ["exec", original.containerID, "python", "-c",
            "from pathlib import Path; Path('/data/workspace/update-marker').write_text('\(marker)'); Path('/data/profile/update-marker').write_text('\(marker)')"])
        let originalToken = try tokens.read(computerID: original.id)
        let mutationCount = runner.mutationCount
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: original.id)) { error in
            XCTAssertEqual(error as? BrowserComputerError, .computerRunning)
        }
        XCTAssertEqual(runner.mutationCount, mutationCount, "A running box must not be replaced")
        XCTAssertEqual(try service.computer(for: terminalID)?.containerID, original.containerID)
        try service.stop(computerID: original.id)
        XCTAssertFalse(try XCTUnwrap(service.computer(for: terminalID)).running)
        let originalMetadata = try XCTUnwrap(metadataStore.load().first)

        runner.configuredImageID = targetImageID
        let status = try service.imageUpdateStatus(computerID: original.id)
        XCTAssertTrue(status.updateAvailable)
        XCTAssertEqual(status.currentImageID, sourceImageID)
        XCTAssertEqual(status.availableImageID, targetImageID)
        let updated = try service.updateStoppedImage(computerID: original.id)
        XCTAssertFalse(updated.running)
        XCTAssertNotEqual(updated.containerID, original.containerID)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.terminalID, original.terminalID)
        XCTAssertEqual(updated.volumeName, original.volumeName)
        XCTAssertEqual(try dockerOutput(docker, ["inspect", "--format", "{{.Image}}", updated.containerID]), targetImageID)
        let updatedMetadata = try XCTUnwrap(metadataStore.load().first)
        XCTAssertEqual(updatedMetadata.containerID, updated.containerID)
        XCTAssertEqual(updatedMetadata.computerID, originalMetadata.computerID)
        XCTAssertEqual(updatedMetadata.terminalID, originalMetadata.terminalID)
        XCTAssertEqual(updatedMetadata.volumeName, originalMetadata.volumeName)
        XCTAssertEqual(updatedMetadata.createdAt, originalMetadata.createdAt)
        XCTAssertEqual(try tokens.read(computerID: original.id), originalToken)
        XCTAssertEqual(tokens.putCount, 1)
        XCTAssertEqual(tokens.deleteCount, 0)
        _ = try service.start(computerID: updated.id)
        XCTAssertEqual(try dockerOutput(docker, ["exec", updated.containerID, "python", "-c",
            "from pathlib import Path; print(Path('/data/workspace/update-marker').read_text())"]), marker)
        XCTAssertEqual(try dockerOutput(docker, ["exec", updated.containerID, "python", "-c",
            "from pathlib import Path; print(Path('/data/profile/update-marker').read_text())"]), marker)
        try service.stop(computerID: updated.id)

        // Downgrade is only a fault-injection target; the second Docker rename fails
        // after the old container has been moved to its backup name.
        runner.configuredImageID = sourceImageID
        runner.failSecondRenameOnce = true
        let metadataBeforeFailure = try Data(contentsOf: metadataStore.url)
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: updated.id))
        let recovered = try XCTUnwrap(service.computer(for: terminalID))
        XCTAssertEqual(recovered.containerID, updated.containerID)
        XCTAssertFalse(recovered.running)
        XCTAssertEqual(try Data(contentsOf: metadataStore.url), metadataBeforeFailure)
        XCTAssertEqual(try tokens.read(computerID: updated.id), originalToken)
        XCTAssertEqual(tokens.deleteCount, 0)
        let remaining = try dockerOutput(docker, ["ps", "-a", "-q", "--no-trunc", "--filter",
                                                   "label=com.agentbox.browser-computer-id=\(updated.id.uuidString.lowercased())"])
        XCTAssertEqual(Set(remaining.split(whereSeparator: \.isNewline).map(String.init)), Set([updated.containerID]),
                       "Rollback must remove the failed replacement container")
        _ = try service.start(computerID: updated.id)
        XCTAssertEqual(try dockerOutput(docker, ["exec", updated.containerID, "python", "-c",
            "from pathlib import Path; print(Path('/data/workspace/update-marker').read_text())"]), marker)
        try service.stop(computerID: updated.id)
    }

    private func dockerOutput(_ docker: DockerProcessRunner, _ arguments: [String]) throws -> String {
        let result = try docker.run(arguments, timeout: 120)
        guard result.exitCode == 0 else { throw BrowserComputerError.commandFailed("Docker smoke command failed") }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildDerivedImage(dockerExecutable: URL, context: String, sourceImageID: String,
                                   tag: String, smokeID: String) throws -> String {
        let process = Process()
        process.executableURL = dockerExecutable
        process.arguments = ["--context", context, "build", "--quiet", "--network=none", "--pull=false",
                             "--tag", tag, "-"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                if finished.wait(timeout: .now() + 2) != .success {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        let dockerfile = "FROM \(sourceImageID)\nLABEL com.agentbox.smoke=\(smokeID)\n"
        try input.fileHandleForWriting.write(contentsOf: Data(dockerfile.utf8))
        try input.fileHandleForWriting.close()
        guard finished.wait(timeout: .now() + 120) == .success, process.terminationStatus == 0 else {
            throw BrowserComputerError.commandFailed("Derived smoke image build failed")
        }
        let imageID = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard imageID.hasPrefix("sha256:") else { throw BrowserComputerError.invalidDockerResponse }
        return imageID
    }

    private func cleanup(docker: DockerProcessRunner, computerID: UUID?, terminalID: UUID,
                         knownContainerIDs: [String], fixtureTag: String, smokeID: String) {
        defer {
            if let raw = try? dockerOutput(docker, ["image", "inspect", "--format",
                                                    "{{ index .Config.Labels \"com.agentbox.smoke\" }}", fixtureTag]),
               raw == smokeID {
                _ = try? docker.run(["image", "rm", fixtureTag], timeout: 20)
            }
        }
        guard let computerID else { return }
        let label = "com.agentbox.browser-computer-id=\(computerID.uuidString.lowercased())"
        let listed = (try? dockerOutput(docker, ["ps", "-a", "-q", "--no-trunc", "--filter", "label=\(label)"])) ?? ""
        let containerIDs = Set(knownContainerIDs + listed.split(whereSeparator: \.isNewline).map(String.init))
        for id in containerIDs {
            guard let raw = try? dockerOutput(docker, ["inspect", "--format", "{{json .Config.Labels}}", id]),
                  let data = raw.data(using: .utf8),
                  let labels = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  labels["com.agentbox.browser-managed"] == "true",
                  labels["com.agentbox.browser-computer-id"] == computerID.uuidString.lowercased(),
                  labels["com.agentbox.browser-terminal-id"] == terminalID.uuidString.lowercased() else { continue }
            _ = try? docker.run(["rm", "--force", id], timeout: 20)
        }
        let volume = "agentbox-browser-data-\(computerID.uuidString.lowercased())"
        if let raw = try? dockerOutput(docker, ["volume", "inspect", "--format", "{{json .Labels}}", volume]),
           let data = raw.data(using: .utf8),
           let labels = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           labels["com.agentbox.browser-managed"] == "true",
           labels["com.agentbox.browser-computer-id"] == computerID.uuidString.lowercased() {
            _ = try? docker.run(["volume", "rm", volume], timeout: 20)
        }
    }
}

private final class MemoryBrowserTokens: BrowserComputerTokenStoring {
    private var values: [UUID: String] = [:]
    private(set) var putCount = 0
    private(set) var deleteCount = 0
    func put(computerID: UUID, value: String) throws { values[computerID] = value; putCount += 1 }
    func read(computerID: UUID) throws -> String {
        guard let value = values[computerID] else { throw BrowserComputerError.missingToken }
        return value
    }
    func delete(computerID: UUID) throws { values.removeValue(forKey: computerID); deleteCount += 1 }
}

private final class MappedDockerRunner: DockerCommandRunning {
    let docker: DockerProcessRunner
    var configuredImageID: String
    var failSecondRenameOnce = false
    private var renameCount = 0
    private(set) var mutationCount = 0
    private(set) var createdComputerID: UUID?
    private(set) var createdContainerIDs: [String] = []

    init(docker: DockerProcessRunner, configuredImageID: String) {
        self.docker = docker; self.configuredImageID = configuredImageID
    }

    func run(_ arguments: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        if arguments.starts(with: ["volume", "create"]),
           let label = arguments.first(where: { $0.hasPrefix("com.agentbox.browser-computer-id=") }),
           let computerID = UUID(uuidString: String(label.dropFirst("com.agentbox.browser-computer-id=".count))) {
            createdComputerID = computerID
        }
        if ["create", "start", "stop", "rename", "rm"].contains(arguments.first ?? "") { mutationCount += 1 }
        if arguments.first == "rename" {
            renameCount += 1
            if failSecondRenameOnce && renameCount.isMultiple(of: 2) {
                failSecondRenameOnce = false
                return DockerCommandResult(exitCode: 1, stderr: "injected rename failure")
            }
        }
        let imageTag = BrowserComputerService<MappedDockerRunner, MemoryBrowserTokens>.image
        let mapped = arguments.map { $0 == imageTag ? configuredImageID : $0 }
        let result = try docker.run(mapped, timeout: timeout)
        if arguments.first == "create", result.exitCode == 0 {
            let id = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { createdContainerIDs.append(id) }
        }
        return result
    }
}
