import Foundation

public enum GitWorktreeError: Error, LocalizedError {
    case notRepository
    case invalidReference
    case invalidBranch
    case branchExists
    case invalidDestination(String)
    case creationFailed(String, cleanupIncomplete: Bool)

    public var errorDescription: String? {
        switch self {
        case .notRepository: return "A pasta escolhida não é um repositório Git."
        case .invalidReference: return "A referência Git não existe ou não aponta para um commit."
        case .invalidBranch: return "O nome da nova branch é inválido."
        case .branchExists: return "A branch já existe. Escolha outro nome."
        case .invalidDestination(let detail): return "Destino do worktree inválido: \(detail)"
        case .creationFailed(let detail, let cleanupIncomplete):
            return "Falha ao criar worktree: \(detail)" +
                (cleanupIncomplete ? " Verifique branch e destino antes de tentar novamente." : "")
        }
    }
}

public struct GitWorktreeManager<Runner: GitCommandRunning> {
    public let runner: Runner
    public init(runner: Runner) { self.runner = runner }

    /// Explicit operation only. Creates a new branch from a verified local commit.
    /// Never stashes, resets, removes existing worktrees, or modifies a dirty checkout.
    public func createWorktree(repositoryURL: URL, reference: String,
                               newBranch: String, destinationURL: URL) throws -> GitCheckout {
        let inspector = GitWorkspaceInspector(runner: runner)
        guard let checkout = try inspector.inspect(at: repositoryURL) else { throw GitWorktreeError.notRepository }
        let root = checkout.rootURL
        let commit = try resolvedCommit(reference, at: root)
        try validateBranch(newBranch, at: root)
        let destination = try validatedDestination(destinationURL, relativeTo: root)
        let existedBefore = FileManager.default.fileExists(atPath: destination.path)
        let result = try runner.run(["-C", root.path, "worktree", "add", "-b", newBranch,
                                     "--", destination.path, commit], timeout: 30)
        guard result.exitCode == 0 else {
            let cleaned = rollbackFailedCreation(root: root, branch: newBranch, commit: commit,
                                                 destination: destination, existedBefore: existedBefore)
            throw GitWorktreeError.creationFailed(clean(result.stderr.isEmpty ? result.stdout : result.stderr),
                                                  cleanupIncomplete: !cleaned)
        }
        guard let created = try inspector.inspect(at: destination),
              created.rootURL.path == destination.path,
              created.branch == newBranch else {
            throw GitWorktreeError.creationFailed("Git retornou sucesso, mas o checkout não pôde ser confirmado.",
                                                  cleanupIncomplete: true)
        }
        return created
    }

    private func resolvedCommit(_ reference: String, at root: URL) throws -> String {
        guard !reference.isEmpty, !reference.hasPrefix("-"),
              !reference.contains("\n"), !reference.contains("\0") else { throw GitWorktreeError.invalidReference }
        let result = try runner.run(["-C", root.path, "rev-parse", "--verify", "--end-of-options",
                                     "\(reference)^{commit}"], timeout: 5)
        let value = clean(result.stdout)
        guard result.exitCode == 0, value.range(of: "^[0-9a-fA-F]{40,64}$", options: .regularExpression) != nil else {
            throw GitWorktreeError.invalidReference
        }
        return value
    }

    private func validateBranch(_ branch: String, at root: URL) throws {
        guard !branch.isEmpty, !branch.hasPrefix("-"), !branch.contains("\n"), !branch.contains("\0") else {
            throw GitWorktreeError.invalidBranch
        }
        let format = try runner.run(["-C", root.path, "check-ref-format", "--branch", branch], timeout: 5)
        guard format.exitCode == 0 else { throw GitWorktreeError.invalidBranch }
        let exists = try runner.run(["-C", root.path, "show-ref", "--verify", "--quiet",
                                     "refs/heads/\(branch)"], timeout: 5)
        if exists.exitCode == 0 { throw GitWorktreeError.branchExists }
        guard exists.exitCode == 1 else {
            throw GitWorktreeError.creationFailed(clean(exists.stderr), cleanupIncomplete: false)
        }
    }

    private func validatedDestination(_ destinationURL: URL, relativeTo root: URL) throws -> URL {
        guard destinationURL.isFileURL else { throw GitWorktreeError.invalidDestination("Use um caminho local.") }
        let requested = destinationURL.standardizedFileURL
        if let attributes = try? FileManager.default.attributesOfItem(atPath: requested.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw GitWorktreeError.invalidDestination("Links simbólicos não são aceitos como destino.")
        }
        let destination = requested.resolvingSymlinksInPath()
        guard !destination.path.isEmpty, destination.path != "/",
              destination.path != root.path, !destination.path.hasPrefix(root.path + "/") else {
            throw GitWorktreeError.invalidDestination("Escolha uma pasta fora do checkout existente.")
        }
        let parent = destination.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue, FileManager.default.isWritableFile(atPath: parent.path) else {
            throw GitWorktreeError.invalidDestination("A pasta pai deve existir e permitir escrita.")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw GitWorktreeError.invalidDestination("Links simbólicos não são aceitos como destino.")
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty else {
                throw GitWorktreeError.invalidDestination("A pasta deve estar vazia.")
            }
        }
        return destination
    }

    /// Deletes only the branch made by this failed call when it still points at the initial commit
    /// and has no registered worktree. Never removes non-empty filesystem contents.
    private func rollbackFailedCreation(root: URL, branch: String, commit: String,
                                        destination: URL, existedBefore: Bool) -> Bool {
        var cleanState = true
        let worktrees = try? runner.run(["-C", root.path, "worktree", "list", "--porcelain"], timeout: 5)
        let registered = worktrees?.stdout.split(whereSeparator: \.isNewline)
            .contains("worktree \(destination.path)") ?? true
        if registered { cleanState = false }
        if !registered {
            let hash = try? runner.run(["-C", root.path, "show-ref", "--verify", "--hash",
                                        "refs/heads/\(branch)"], timeout: 5)
            if hash?.exitCode == 0 {
                if clean(hash?.stdout ?? "") == commit {
                    let deleted = try? runner.run(["-C", root.path, "branch", "-D", "--", branch], timeout: 5)
                    if deleted?.exitCode != 0 { cleanState = false }
                } else { cleanState = false }
            }
            if !existedBefore && FileManager.default.fileExists(atPath: destination.path) {
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: destination.path), contents.isEmpty {
                    do { try FileManager.default.removeItem(at: destination) } catch { cleanState = false }
                } else { cleanState = false }
            }
        }
        return cleanState
    }
    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
}

public extension GitWorktreeManager where Runner == GitProcessRunner {
    init() { self.init(runner: GitProcessRunner()) }
}
