import Foundation

public enum CLIResolutionError: LocalizedError, Equatable {
    case notFound(String)
    case notExecutable(String)
    case invalidWorkingDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let name): return "Executable \(name) was not found. Configure its path or install the CLI."
        case .notExecutable(let path): return "\(path) is not an executable file."
        case .invalidWorkingDirectory(let path): return "Working directory \(path) does not exist or is not a directory."
        }
    }
}

/// Resolves a user-selected CLI without invoking a shell or reading CLI credentials.
/// The extra directories cover common macOS installations when Finder supplies a short PATH.
public struct CLIExecutableResolver {
    public var overrides: [CLIProvider: String]
    public var environment: [String: String]
    public var homeDirectory: String

    public init(overrides: [CLIProvider: String] = [:], environment: [String: String] = ProcessInfo.processInfo.environment,
                homeDirectory: String = NSHomeDirectory()) {
        self.overrides = overrides
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    public func resolve(_ provider: CLIProvider) throws -> String {
        let name = provider.executableName
        if let override = overrides[provider], !override.isEmpty {
            guard isExecutable(override) else { throw CLIResolutionError.notExecutable(override) }
            return URL(fileURLWithPath: override).standardizedFileURL.path
        }
        let search = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + nvmBins() + [
            "\(homeDirectory)/.local/bin", "\(homeDirectory)/.claude/local", "\(homeDirectory)/.bun/bin",
            "\(homeDirectory)/.npm-global/bin", "\(homeDirectory)/.volta/bin", "\(homeDirectory)/.asdf/shims",
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
            "/usr/bin", "/bin"
        ]
        for directory in search where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if isExecutable(candidate) { return URL(fileURLWithPath: candidate).standardizedFileURL.path }
        }
        throw CLIResolutionError.notFound(name)
    }

    public func validateWorkingDirectory(_ path: String) throws -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIResolutionError.invalidWorkingDirectory(path)
        }
        return standardized
    }

    private func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    private func nvmBins() -> [String] {
        let root = "\(homeDirectory)/.nvm/versions/node"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        func version(_ name: String) -> [Int]? {
            guard name.hasPrefix("v") else { return nil }
            let numbers = name.dropFirst().split(separator: ".").compactMap { Int($0) }
            return numbers.count == 3 ? numbers : nil
        }
        return names.compactMap { name -> (String, [Int])? in
            guard let parsed = version(name) else { return nil }
            return (name, parsed)
        }.sorted { lhs, rhs in
            for (a, b) in zip(lhs.1, rhs.1) where a != b { return a > b }
            return lhs.0 > rhs.0
        }.prefix(32).map { "\(root)/\($0.0)/bin" }
    }
}
