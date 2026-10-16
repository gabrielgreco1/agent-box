import Foundation
import XCTest
@testable import AgentBoxCore

final class BrowserImageUpdateTests: XCTestCase {
    private func fixture() throws -> (URL, UpdateDockerRunner, UpdateTokenStore, BrowserComputerService<UpdateDockerRunner, UpdateTokenStore>) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let policy = ComputerPolicyStore(fileURL: root.appendingPathComponent("policy.json"))
        try policy.save(ComputerPolicy(creation: .manual,
            limits: .init(cpus: 1, memoryMiB: 2048, maxComputers: 2)))
        let docker = UpdateDockerRunner()
        let tokens = UpdateTokenStore()
        let service = BrowserComputerService(runner: docker, tokens: tokens, policyStore: policy,
            metadataStore: BrowserComputerMetadataStore(url: root.appendingPathComponent("metadata.json")))
        return (root, docker, tokens, service)
    }

    func testStoppedUpdatePreservesIdentityVolumeTokenMetadataAndHardening() throws {
        let (root, docker, tokens, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try service.createAndStart(for: UUID())
        let originalMetadata = try XCTUnwrap(service.metadataStore.load().first)
        let originalToken = try tokens.read(computerID: initial.id)
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: initial.id)) {
            XCTAssertEqual($0 as? BrowserComputerError, .computerRunning)
        }
        XCTAssertFalse(docker.commands.contains(where: { $0.first == "rename" }))
        try service.stop(computerID: initial.id)
        let status = try service.imageUpdateStatus(computerID: initial.id)
        XCTAssertTrue(status.updateAvailable)
        XCTAssertEqual(status.currentImageID, docker.oldImageID)
        XCTAssertEqual(status.availableImageID, docker.newImageID)
        let updated = try service.updateStoppedImage(computerID: initial.id)
        XCTAssertFalse(updated.running)
        XCTAssertEqual(updated.id, initial.id)
        XCTAssertEqual(updated.terminalID, initial.terminalID)
        XCTAssertEqual(updated.volumeName, initial.volumeName)
        XCTAssertNotEqual(updated.containerID, initial.containerID)
        XCTAssertEqual(try tokens.read(computerID: initial.id), originalToken)
        let metadata = try XCTUnwrap(service.metadataStore.load().first)
        XCTAssertEqual(metadata.containerID, updated.containerID)
        XCTAssertEqual(metadata.createdAt, originalMetadata.createdAt)
        XCTAssertEqual(metadata.volumeName, originalMetadata.volumeName)
        XCTAssertFalse(try service.imageUpdateStatus(computerID: initial.id).updateAvailable)
        let create = try XCTUnwrap(docker.commands.last(where: { $0.first == "create" }))
        XCTAssertEqual(create.last, docker.newImageID)
        for argument in ["--read-only", "--init", "--cap-drop", "ALL", "no-new-privileges",
                         "127.0.0.1::8765", "type=volume,source=\(initial.volumeName),target=/data"] {
            XCTAssertTrue(create.contains(argument), "Missing \(argument)")
        }
        XCTAssertFalse(docker.commands.contains(where: { $0 == ["start", updated.containerID] }))
        XCTAssertFalse(docker.commands.contains(where: { $0.first == "volume" && $0.dropFirst().first == "rm" }))
        XCTAssertFalse(tokens.deleted.contains(initial.id))
        XCTAssertNil(try service.pendingImageUpdate())
    }

    func testCreateFailureAfterSideEffectRemovesOnlyNewContainer() throws {
        let (root, docker, tokens, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try service.createAndStart(for: UUID())
        try service.stop(computerID: old.id)
        docker.failNextCreateAfterEffect = true
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: old.id))
        XCTAssertEqual(try service.computer(for: old.terminalID)?.containerID, old.containerID)
        XCTAssertEqual(try service.metadataStore.load().first?.containerID, old.containerID)
        XCTAssertEqual(docker.containers.count, 1)
        XCTAssertFalse(tokens.deleted.contains(old.id))
        XCTAssertNil(try service.pendingImageUpdate())
    }

    func testTransientInspectFailureLeavesJournalAndContainersUntouchedUntilRecovery() throws {
        let (root, docker, _, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try service.createAndStart(for: UUID())
        try service.stop(computerID: old.id)
        docker.failNextCreateAfterEffect = true
        docker.transientAfterFailedCreate = true
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: old.id)) {
            XCTAssertEqual($0 as? BrowserComputerError, .updateRecoveryRequired)
        }
        XCTAssertEqual(docker.containers.count, 2)
        XCTAssertEqual(try service.pendingImageUpdate()?.computerID, old.id)
        XCTAssertEqual(try service.computer(for: old.terminalID)?.containerID, old.containerID)
        try service.recoverStoppedImageUpdate()
        XCTAssertNil(try service.pendingImageUpdate())
        XCTAssertEqual(docker.containers.count, 1)
    }

    func testRenameFailureRestoresOldCanonicalContainer() throws {
        let (root, docker, _, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try service.createAndStart(for: UUID())
        try service.stop(computerID: old.id)
        docker.failNextRenameToCanonical = true
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: old.id))
        XCTAssertEqual(try service.computer(for: old.terminalID)?.containerID, old.containerID)
        XCTAssertEqual(try service.metadataStore.load().first?.containerID, old.containerID)
        XCTAssertEqual(docker.containers.count, 1)
        XCTAssertNil(try service.pendingImageUpdate())
    }

    func testMetadataWriteFailureKeepsOldBoxRecoverable() throws {
        let (root, docker, _, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        let old = try service.createAndStart(for: UUID())
        try service.stop(computerID: old.id)
        docker.afterRenameToCanonical = {
            try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        }
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: old.id)) {
            XCTAssertEqual($0 as? BrowserComputerError, .updateRecoveryRequired)
        }
        XCTAssertEqual(try service.computer(for: old.terminalID)?.containerID, old.containerID)
        XCTAssertEqual(try service.metadataStore.load().first?.containerID, old.containerID)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try service.recoverStoppedImageUpdate()
        XCTAssertNil(try service.pendingImageUpdate())
        XCTAssertEqual(docker.containers.count, 1)
    }

    func testCommittedUpdateRetainsBackupUntilExplicitRecoveryWhenRemoveFails() throws {
        let (root, docker, _, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try service.createAndStart(for: UUID())
        try service.stop(computerID: old.id)
        docker.failNextRemove = true
        let updated = try service.updateStoppedImage(computerID: old.id)
        XCTAssertEqual(try service.metadataStore.load().first?.containerID, updated.containerID)
        XCTAssertEqual(try service.pendingImageUpdate()?.computerID, old.id)
        XCTAssertEqual(docker.containers.count, 2)
        XCTAssertThrowsError(try service.start(computerID: old.id)) {
            XCTAssertEqual($0 as? BrowserComputerError, .updateRecoveryRequired)
        }
        try service.recoverStoppedImageUpdate()
        XCTAssertNil(try service.pendingImageUpdate())
        XCTAssertEqual(docker.containers.count, 1)
        XCTAssertEqual(try service.computer(for: old.terminalID)?.containerID, updated.containerID)
    }

    func testMissingLocalImageAndRunningBoxNeverMutateContainer() throws {
        let (root, docker, _, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try service.createAndStart(for: UUID())
        try service.stop(computerID: old.id)
        docker.localImageAvailable = false
        XCTAssertThrowsError(try service.imageUpdateStatus(computerID: old.id)) {
            XCTAssertEqual($0 as? BrowserComputerError, .imageUnavailable)
        }
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: old.id)) {
            XCTAssertEqual($0 as? BrowserComputerError, .imageUnavailable)
        }
        XCTAssertFalse(docker.commands.contains(where: { $0.first == "rename" }))
        XCTAssertEqual(try service.computer(for: old.terminalID)?.containerID, old.containerID)
    }

    func testStoppedUpdateSupportsExplicitKeychainAuthorization() throws {
        let (root, docker, tokens, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try service.createAndStart(for: UUID())
        try service.stop(computerID: old.id)
        tokens.requiresAuthorization = true
        XCTAssertThrowsError(try service.updateStoppedImage(computerID: old.id)) {
            XCTAssertEqual($0 as? BrowserComputerError, .tokenAuthorizationRequired)
        }
        XCTAssertFalse(docker.commands.contains(where: { $0.first == "rename" }))
        let updated = try service.updateStoppedImage(computerID: old.id, interactiveAuthorization: true)
        XCTAssertNotEqual(updated.containerID, old.containerID)
        XCTAssertEqual(tokens.interactiveReads, 1)
    }

    func testExplicitRecoveryAcrossRenameAndMetadataCrashWindows() throws {
        for (newRenamed, metadataCommitted) in [(false, false), (true, false), (true, true)] {
            let (root, docker, _, service) = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let old = try service.createAndStart(for: UUID())
            try service.stop(computerID: old.id)
            let nonce = UUID().uuidString.lowercased()
            let temporaryName = "agentbox-updating-\(nonce)"
            let backupName = "agentbox-backup-\(nonce)"
            var create = try XCTUnwrap(docker.commands.first(where: { $0.first == "create" }))
            let nameIndex = try XCTUnwrap(create.firstIndex(of: "--name")) + 1
            create[nameIndex] = temporaryName
            create[create.count - 1] = docker.newImageID
            let created = try docker.run(create, timeout: 120)
            let newID = created.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(try docker.run(["rename", old.containerID, backupName], timeout: 20).exitCode, 0)
            if newRenamed {
                XCTAssertEqual(try docker.run(["rename", newID, old.name], timeout: 20).exitCode, 0)
            }
            if metadataCommitted {
                var records = try service.metadataStore.load()
                let prior = try XCTUnwrap(records.first)
                records[0] = BrowserComputerMetadata(computerID: prior.computerID,
                    terminalID: prior.terminalID, containerID: newID,
                    volumeName: prior.volumeName, createdAt: prior.createdAt)
                try service.metadataStore.save(records)
            }
            let journalURL = service.metadataStore.url.appendingPathExtension("image-update.json")
            let journal: [String: Any] = ["computerID": old.id.uuidString,
                "terminalID": old.terminalID.uuidString, "volumeName": old.volumeName,
                "oldContainerID": old.containerID, "newContainerID": newID,
                "temporaryName": temporaryName, "backupName": backupName,
                "targetImageID": docker.newImageID]
            try JSONSerialization.data(withJSONObject: journal).write(to: journalURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
            XCTAssertEqual(try service.pendingImageUpdate()?.computerID, old.id)
            XCTAssertThrowsError(try service.start(computerID: old.id)) {
                XCTAssertEqual($0 as? BrowserComputerError, .updateRecoveryRequired)
            }
            try service.recoverStoppedImageUpdate()
            XCTAssertNil(try service.pendingImageUpdate())
            let expectedID = metadataCommitted ? newID : old.containerID
            XCTAssertEqual(try service.computer(for: old.terminalID)?.containerID, expectedID)
            XCTAssertEqual(try service.metadataStore.load().first?.containerID, expectedID)
            XCTAssertEqual(docker.containers.count, 1)
        }
    }
}

private final class UpdateTokenStore: BrowserComputerTokenStoring {
    var values: [UUID: String] = [:]
    var deleted: Set<UUID> = []
    var requiresAuthorization = false
    var interactiveReads = 0
    func put(computerID: UUID, value: String) throws { values[computerID] = value }
    func read(computerID: UUID) throws -> String {
        if requiresAuthorization { throw BrowserComputerError.tokenAuthorizationRequired }
        guard let value = values[computerID] else { throw BrowserComputerError.missingToken }
        return value
    }
    func readInteractively(computerID: UUID) throws -> String {
        interactiveReads += 1
        guard let value = values[computerID] else { throw BrowserComputerError.missingToken }
        return value
    }
    func delete(computerID: UUID) throws { deleted.insert(computerID); values.removeValue(forKey: computerID) }
}

private final class UpdateDockerRunner: DockerCommandRunning {
    struct Container {
        let id: String
        var name: String
        let computerID: UUID
        let terminalID: UUID
        let volume: String
        let imageID: String
        var running = false
    }
    let oldImageID = "sha256:" + String(repeating: "a", count: 64)
    let newImageID = "sha256:" + String(repeating: "b", count: 64)
    var localImageAvailable = true
    var failNextCreateAfterEffect = false
    var transientAfterFailedCreate = false
    var failNextInspectID = false
    var failNextRenameToCanonical = false
    var failNextRemove = false
    var afterRenameToCanonical: (() -> Void)?
    var commands: [[String]] = []
    var containers: [String: Container] = [:]
    var volumeOwners: [String: UUID] = [:]

    func run(_ arguments: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        commands.append(arguments)
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if arguments.starts(with: ["volume", "inspect"]) {
            let name = arguments.last ?? ""
            guard let owner = volumeOwners[name] else { return .init(exitCode: 1) }
            if arguments.contains("--format") {
                return .init(exitCode: 0, stdout: "{\"com.agentbox.browser-managed\":\"true\",\"com.agentbox.browser-computer-id\":\"\(owner.uuidString.lowercased())\"}")
            }
            return .init(exitCode: 0, stdout: name)
        }
        if arguments.starts(with: ["volume", "create"]) {
            guard let name = arguments.last,
                  let label = arguments.first(where: { $0.hasPrefix("com.agentbox.browser-computer-id=") }),
                  let owner = UUID(uuidString: String(label.split(separator: "=").last ?? "")) else { return .init(exitCode: 1) }
            volumeOwners[name] = owner
            return .init(exitCode: 0, stdout: name)
        }
        if arguments.starts(with: ["image", "inspect"]) {
            return localImageAvailable ? .init(exitCode: 0, stdout: newImageID) : .init(exitCode: 1)
        }
        if arguments.first == "ps" {
            let all = arguments.contains("-a")
            let ids = containers.values.filter { all || $0.running }.map(\.id).sorted()
            return .init(exitCode: 0, stdout: ids.joined(separator: "\n") + (ids.isEmpty ? "" : "\n"))
        }
        if arguments.first == "create" {
            guard let name = value("--name"), let mount = value("--mount"),
                  let volume = mount.split(separator: ",").first(where: { $0.hasPrefix("source=") }).map({ String($0.dropFirst(7)) }),
                  let computer = arguments.first(where: { $0.hasPrefix("com.agentbox.browser-computer-id=") })
                    .flatMap({ UUID(uuidString: String($0.split(separator: "=").last ?? "")) }),
                  let terminal = arguments.first(where: { $0.hasPrefix("com.agentbox.browser-terminal-id=") })
                    .flatMap({ UUID(uuidString: String($0.split(separator: "=").last ?? "")) }),
                  !containers.values.contains(where: { $0.name == name }) else { return .init(exitCode: 1) }
            let id = String(repeating: String(containers.count + 1, radix: 16), count: 64)
            let image = arguments.last == BrowserComputerService<UpdateDockerRunner, UpdateTokenStore>.image
                ? oldImageID : (arguments.last ?? "")
            containers[id] = Container(id: id, name: name, computerID: computer,
                                       terminalID: terminal, volume: volume, imageID: image)
            if failNextCreateAfterEffect {
                failNextCreateAfterEffect = false
                if transientAfterFailedCreate { failNextInspectID = true; transientAfterFailedCreate = false }
                return .init(exitCode: 1, stderr: "injected create failure")
            }
            return .init(exitCode: 0, stdout: id)
        }
        if arguments.first == "inspect" {
            if value("--format") == "{{.Id}}" && failNextInspectID {
                failNextInspectID = false
                return .init(exitCode: 1, stderr: "Docker daemon unavailable")
            }
            guard let reference = arguments.last,
                  let item = containers.values.first(where: { $0.id == reference || $0.name == reference }) else {
                return .init(exitCode: 1, stderr: "Error: No such object: \(arguments.last ?? "")")
            }
            let format = value("--format")
            switch format {
            case "{{.Id}}": return .init(exitCode: 0, stdout: item.id)
            case "{{.Image}}": return .init(exitCode: 0, stdout: item.imageID)
            case "{{json .Mounts}}":
                return .init(exitCode: 0, stdout: "[{\"Type\":\"volume\",\"Name\":\"\(item.volume)\",\"Destination\":\"/data\"}]")
            default:
                let json = "{\"Id\":\"\(item.id)\",\"Name\":\"/\(item.name)\",\"Config\":{\"Labels\":{\"com.agentbox.browser-managed\":\"true\",\"com.agentbox.browser-computer-id\":\"\(item.computerID.uuidString.lowercased())\",\"com.agentbox.browser-terminal-id\":\"\(item.terminalID.uuidString.lowercased())\"}},\"State\":{\"Running\":\(item.running)}}"
                return .init(exitCode: 0, stdout: json)
            }
        }
        if arguments.first == "rename" {
            guard arguments.count == 3, var item = containers[arguments[1]],
                  !containers.values.contains(where: { $0.name == arguments[2] }) else { return .init(exitCode: 1) }
            if failNextRenameToCanonical && arguments[2].hasPrefix("agentbox-browser-") {
                failNextRenameToCanonical = false
                return .init(exitCode: 1, stderr: "injected rename failure")
            }
            item.name = arguments[2]; containers[item.id] = item
            if arguments[2].hasPrefix("agentbox-browser-"),
               let callback = afterRenameToCanonical {
                afterRenameToCanonical = nil
                callback()
            }
            return .init(exitCode: 0)
        }
        if arguments.first == "rm" {
            guard arguments.count == 2, let item = containers[arguments[1]], !item.running else { return .init(exitCode: 1) }
            if failNextRemove { failNextRemove = false; return .init(exitCode: 1, stderr: "injected remove failure") }
            containers.removeValue(forKey: arguments[1])
            return .init(exitCode: 0)
        }
        if arguments.first == "start", arguments.count == 2, var item = containers[arguments[1]] {
            item.running = true; containers[item.id] = item; return .init(exitCode: 0)
        }
        if arguments.first == "stop", let id = arguments.last, var item = containers[id] {
            item.running = false; containers[id] = item; return .init(exitCode: 0)
        }
        return .init(exitCode: 1, stderr: "unexpected command")
    }
}
