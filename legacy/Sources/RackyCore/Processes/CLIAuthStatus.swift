import Foundation

public enum CLIAuthStatus: Equatable {
    case authenticated
    case unauthenticated
    case unavailable
    case unrecognized

    public static func interpret(_ result: CLICommandResult, provider: CLIProvider) -> CLIAuthStatus {
        if result.timedOut { return .unavailable }
        switch provider {
        case .claude:
            guard let data = result.output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let loggedIn = json["loggedIn"] as? Bool else { return .unrecognized }
            return loggedIn ? .authenticated : .unauthenticated
        case .codex:
            let normalized = result.output.lowercased()
            if normalized.contains("not logged in") { return .unauthenticated }
            if result.exitCode == 0 && normalized.contains("logged in") { return .authenticated }
            return .unrecognized
        case .opencode, .shell:
            return .unrecognized
        }
    }
}
