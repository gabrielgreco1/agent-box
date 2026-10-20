import Foundation

/// Variáveis de ambiente do nome antigo (`AGENTBOX_*`, `AGENT_BOX_*`) viram `RACKY_*`. O nome novo sempre vence.
/// Serve scripts e sessões de agente iniciadas por uma versão anterior (o helper `racky` herda o ambiente delas).
public enum LegacyEnvironment {
    /// Cópia do ambiente com cada variável antiga promovida ao nome novo, salvo quando o novo já existe.
    public static func promoted(_ environment: [String: String]) -> [String: String] {
        var result = environment
        for (key, value) in environment {
            guard let renamed = newName(for: key), result[renamed] == nil else { continue }
            result[renamed] = value
        }
        return result
    }

    /// `AGENTBOX_HOME` -> `RACKY_HOME`; `nil` quando a chave não é do nome antigo.
    public static func newName(for key: String) -> String? {
        for prefix in LegacyNames.environmentPrefixes where key.hasPrefix(prefix) {
            return "RACKY_" + key.dropFirst(prefix.count)
        }
        return nil
    }

    /// Promove no próprio processo (`setenv`): `ProcessInfo.processInfo.environment` e os filhos passam a ver os nomes novos.
    /// Chamar uma vez, no início do `main` do app, do daemon e do helper.
    public static func promoteProcessEnvironment() {
        let current = ProcessInfo.processInfo.environment
        let promoted = promoted(current)
        for (key, value) in promoted where current[key] == nil {
            setenv(key, value, 0)
        }
    }
}
