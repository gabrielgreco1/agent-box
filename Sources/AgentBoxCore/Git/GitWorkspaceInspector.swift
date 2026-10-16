import Foundation

public struct GitRemote: Equatable, Sendable {
    public let host: String
    public let path: String
    public let displayName: String
    public let webURL: URL?
}

public struct GitCheckout: Equatable, Sendable {
    public let rootURL: URL
    /// Nil means detached HEAD. An unborn branch still has a name.
    public let branch: String?
    public let isDirty: Bool
    public let remote: GitRemote?
}

public enum GitWorkspaceError: Error, LocalizedError {
    case invalidDirectory
    case unexpectedResponse
    case commandFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidDirectory: return "O caminho não é uma pasta existente."
        case .unexpectedResponse: return "Git retornou uma resposta inesperada."
        case .commandFailed(let detail): return "Git: \(detail)"
        }
    }
}

public struct GitWorkspaceInspector<Runner: GitCommandRunning> {
    public let runner: Runner
    public init(runner: Runner) { self.runner = runner }

    /// Returns nil for a plain folder, including a terminal opened outside Git.
    public func inspect(at directoryURL: URL) throws -> GitCheckout? {
        let directory = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GitWorkspaceError.invalidDirectory
        }
        let inside = try runner.run(["-C", directory.path, "rev-parse", "--is-inside-work-tree"], timeout: 5)
        guard inside.exitCode == 0, inside.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return nil
        }
        let root = try checked(["-C", directory.path, "rev-parse", "--show-toplevel"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { throw GitWorkspaceError.unexpectedResponse }
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let branchResult = try runner.run(["-C", rootURL.path, "symbolic-ref", "--quiet", "--short", "HEAD"], timeout: 5)
        let branch = branchResult.exitCode == 0
            ? branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let status = try checked(["-C", rootURL.path, "status", "--porcelain=v1", "--untracked-files=normal"])
        let remotes = try checked(["-C", rootURL.path, "remote"])
            .stdout.split(whereSeparator: \.isNewline).map(String.init)
        let remoteName = remotes.contains("origin") ? "origin" : remotes.first
        var remote: GitRemote?
        if let remoteName {
            let response = try runner.run(["-C", rootURL.path, "remote", "get-url", remoteName], timeout: 5)
            if response.exitCode == 0 { remote = GitRemoteNormalizer.normalize(response.stdout) }
        }
        return GitCheckout(rootURL: rootURL, branch: branch, isDirty: !status.stdout.isEmpty, remote: remote)
    }

    private func checked(_ args: [String]) throws -> GitCommandResult {
        let result = try runner.run(args, timeout: 5)
        guard result.exitCode == 0 else {
            throw GitWorkspaceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }
}

public extension GitWorkspaceInspector where Runner == GitProcessRunner {
    init() { self.init(runner: GitProcessRunner()) }
}

public enum GitRemoteNormalizer {
    public static func normalize(_ rawValue: String) -> GitRemote? {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var host: String, path: String
        if let parts = URLComponents(string: raw), let scheme = parts.scheme,
           ["https", "http", "ssh", "git"].contains(scheme.lowercased()),
           let parsedHost = parts.host {
            host = parsedHost.lowercased()
            path = parts.path
        } else if let colon = raw.firstIndex(of: ":"), let at = raw[..<colon].lastIndex(of: "@") {
            host = String(raw[raw.index(after: at)..<colon]).lowercased()
            path = String(raw[raw.index(after: colon)...])
        } else { return nil }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path.removeLast(4) }
        guard !host.isEmpty, !path.isEmpty, !host.contains("@"), !path.contains("\n") else { return nil }
        let webURL: URL?
        if host == "github.com" {
            var components = URLComponents()
            components.scheme = "https"; components.host = host
            components.path = "/" + path
            webURL = components.url
        } else { webURL = nil }
        return GitRemote(host: host, path: path, displayName: "\(host)/\(path)", webURL: webURL)
    }
}
