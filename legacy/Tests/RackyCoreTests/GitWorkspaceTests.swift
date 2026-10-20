import XCTest
@testable import RackyCore

final class GitWorkspaceTests: XCTestCase {
    private let git = GitProcessRunner()

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("racky-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @discardableResult private func run(_ args: [String]) throws -> GitCommandResult {
        let result = try git.run(args, timeout: 10)
        XCTAssertEqual(result.exitCode, 0, "git \(args): \(result.stderr)")
        return result
    }
    private func repository(in base: URL) throws -> URL {
        let repo = base.appendingPathComponent("repo with spaces")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try run(["-C", repo.path, "init", "-q"])
        try "first\n".write(to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try run(["-C", repo.path, "add", "tracked.txt"])
        try run(["-C", repo.path, "-c", "user.name=Racky Test", "-c", "user.email=test@example.invalid",
                 "commit", "-qm", "initial"])
        return repo
    }

    func testPlainFolderHasNoGitMetadata() throws {
        let base = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertNil(try GitWorkspaceInspector().inspect(at: base))
    }

    func testBranchDirtyStateAndCredentialFreeRemote() throws {
        let base = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        let repo = try repository(in: base)
        try run(["-C", repo.path, "remote", "add", "origin",
                 "https://alice:secret-token@github.com/owner/repo.git"])
        let inspector = GitWorkspaceInspector()
        let clean = try XCTUnwrap(inspector.inspect(at: repo))
        XCTAssertFalse(clean.isDirty)
        XCTAssertNotNil(clean.branch)
        XCTAssertEqual(clean.remote?.displayName, "github.com/owner/repo")
        XCTAssertEqual(clean.remote?.webURL?.absoluteString, "https://github.com/owner/repo")
        XCTAssertFalse(String(describing: clean.remote).contains("secret-token"))
        try "changed\n".write(to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(try XCTUnwrap(inspector.inspect(at: repo)).isDirty)
    }

    func testExplicitWorktreeWithSpaceAndShellMetacharacters() throws {
        let base = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        let repo = try repository(in: base)
        try "uncommitted\n".write(to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        let destination = base.appendingPathComponent("work tree;$(touch owned)")
        let created = try GitWorktreeManager().createWorktree(repositoryURL: repo, reference: "HEAD",
                                                              newBranch: "feature/test", destinationURL: destination)
        XCTAssertEqual(created.rootURL.path, destination.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(created.branch, "feature/test")
        XCTAssertFalse(base.appendingPathComponent("owned").path.fileExists)
        XCTAssertTrue(try XCTUnwrap(GitWorkspaceInspector().inspect(at: repo)).isDirty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("tracked.txt").path))
    }

    func testRejectsExistingBranchAndNonemptyDestinationWithoutMutation() throws {
        let base = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        let repo = try repository(in: base)
        let manager = GitWorktreeManager()
        let first = base.appendingPathComponent("first")
        _ = try manager.createWorktree(repositoryURL: repo, reference: "HEAD", newBranch: "feature/existing", destinationURL: first)
        XCTAssertThrowsError(try manager.createWorktree(repositoryURL: repo, reference: "HEAD",
                                                        newBranch: "feature/existing",
                                                        destinationURL: base.appendingPathComponent("second"))) { error in
            guard case GitWorktreeError.branchExists = error else { return XCTFail("Expected branchExists") }
        }
        XCTAssertThrowsError(try manager.createWorktree(repositoryURL: repo, reference: "--help",
                                                        newBranch: "feature/ref-reject",
                                                        destinationURL: base.appendingPathComponent("bad-ref"))) { error in
            guard case GitWorktreeError.invalidReference = error else { return XCTFail("Expected invalidReference") }
        }
        XCTAssertThrowsError(try manager.createWorktree(repositoryURL: repo, reference: "HEAD",
                                                        newBranch: "-malicious",
                                                        destinationURL: base.appendingPathComponent("bad-branch"))) { error in
            guard case GitWorktreeError.invalidBranch = error else { return XCTFail("Expected invalidBranch") }
        }
        let occupied = base.appendingPathComponent("occupied")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        try "keep".write(to: occupied.appendingPathComponent("data"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try manager.createWorktree(repositoryURL: repo, reference: "HEAD",
                                                        newBranch: "feature/new", destinationURL: occupied))
        XCTAssertTrue(FileManager.default.fileExists(atPath: occupied.appendingPathComponent("data").path))
    }
}

private extension String {
    var fileExists: Bool { FileManager.default.fileExists(atPath: self) }
}
