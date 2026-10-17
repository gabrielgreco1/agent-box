import AgentBoxProtocol
import Foundation

// Geração, por lançamento, da configuração de hooks de atividade (06 §2.8, §3.2, §3.3.1). Funções puras: nada é
// escrito aqui e nada entra no argv ainda (a injeção em `--settings`/`-c` é a T2-02/T2-03). Nunca toca em `~/.claude`
// nem em `~/.codex`.

/// Onde está o `agentbox` que os hooks chamam: `AGENTBOX_HELPER` (dev e testes) ou `Contents/MacOS/agentbox` do app.
public enum HookHelperLocator {
    public static func path(environment: [String: String], bundleURL: URL) -> String? {
        if let path = environment["AGENTBOX_HELPER"], !path.isEmpty { return path }
        let bundled = bundleURL.appendingPathComponent("Contents/MacOS/agentbox").path
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : nil
    }
}

/// Comando canônico do hook (08 §0.2). Sem run id nem pane no comando: a correlação é só por env (06 §3.3.1), então o
/// hash de trust do Codex não muda entre execuções.
public enum HookCommandLine {
    public static func command(helperPath: String, provider: HookProvider, event: HookEventName) -> String {
        "\(shellQuote(helperPath)) hook --provider \(provider.rawValue) --event \(event.rawValue)"
    }

    /// Aspas duplas de `sh`: escapa `\`, `"`, `$` e crase.
    static func shellQuote(_ path: String) -> String {
        var out = "\""
        for ch in path {
            if ch == "\\" || ch == "\"" || ch == "$" || ch == "`" { out.append("\\") }
            out.append(ch)
        }
        return out + "\""
    }
}

/// Conteúdo das injeções por lançamento (Fatia 2+, 06 §2.8). Tudo é regenerado a cada start e a cada resume.
public struct LaunchInjection: Sendable, Equatable {
    /// Caminho absoluto do helper `agentbox` que os hooks chamam.
    public var helperPath: String
    /// Hashes de trust dos hooks do Codex (sondados via `hooks/list`); vazio = fallback rollout `estimated`.
    public var codexHookHashes: [HookEventName: String]
    /// Claude: JSON de `--mcp-config`. `nil`/vazio = flag omitida.
    public var claudeMCPConfig: Data?
    /// Claude: arquivos do plugin (`plugin/.claude-plugin/plugin.json`, skills…), nomes relativos ao diretório do
    /// lançamento. Vazio = `--plugin-dir` omitida.
    public var claudePluginFiles: [LaunchFile]
    /// Claude: JSON de `--agents` (definições de subagente com `mcpServers` inline como ARRAY, S-08). `nil`/vazio = flag omitida.
    public var claudeAgentsJSON: Data?
    /// Claude: regras de `permissions.deny` de `--settings` (ex.: `Skill(agentbox)`, S4). Valem também com `--dangerously-skip-permissions`.
    public var claudeDenyRules: [String]
    /// Claude: variáveis de ambiente do lançamento (ex.: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, CS-325).
    public var claudeEnvironment: [String: String]
    /// Claude: variáveis que NÃO podem chegar ao CLI mesmo vindas do shell de login (agent teams desligado, CS-310).
    public var claudeUnsetEnvironment: [String]

    public init(
        helperPath: String, codexHookHashes: [HookEventName: String] = [:], claudeMCPConfig: Data? = nil, claudePluginFiles: [LaunchFile] = [],
        claudeAgentsJSON: Data? = nil, claudeDenyRules: [String] = [], claudeEnvironment: [String: String] = [:], claudeUnsetEnvironment: [String] = []
    ) {
        self.helperPath = helperPath; self.codexHookHashes = codexHookHashes
        self.claudeMCPConfig = claudeMCPConfig; self.claudePluginFiles = claudePluginFiles
        self.claudeAgentsJSON = claudeAgentsJSON; self.claudeDenyRules = claudeDenyRules
        self.claudeEnvironment = claudeEnvironment; self.claudeUnsetEnvironment = claudeUnsetEnvironment
    }
}

extension LaunchInjection {
    static let mcpFileName = "mcp.json"
    static let pluginDirectoryName = "plugin"

    /// Claude: `--settings` sempre; `--mcp-config` e `--plugin-dir` só com conteúdo.
    func claudeInjection(launchDirectory: URL) throws -> (injected: [String], files: [LaunchFile]) {
        let dir = launchDirectory.standardizedFileURL.path
        var files = [try ClaudeHookSettings.launchFile(helperPath: helperPath, denyRules: claudeDenyRules)]
        var injected = ClaudeHookSettings.injectedArguments(settingsPath: "\(dir)/\(ClaudeHookSettings.fileName)")
        if let mcp = claudeMCPConfig, !mcp.isEmpty {
            files.append(LaunchFile(name: Self.mcpFileName, contents: mcp))
            injected += ["--mcp-config", "\(dir)/\(Self.mcpFileName)"]
        }
        if !claudePluginFiles.isEmpty {
            files += claudePluginFiles
            injected += ["--plugin-dir", "\(dir)/\(Self.pluginDirectoryName)"]
        }
        if let agents = claudeAgentsJSON, !agents.isEmpty {
            // `--agents` leva o JSON inline (o arquivo só vale com `--print`); fica no argv como UM argumento.
            injected += ["--agents", String(decoding: agents, as: UTF8.self)]
        }
        return (injected, files)
    }

    /// Codex: `-c hooks.<Evento>=…` e, com hashes, `-c hooks.state={…}` (P18). Nada em arquivo.
    func codexInjection() throws -> [String] {
        try CodexHookConfig.arguments(helperPath: helperPath, hashes: codexHookHashes).arguments
    }
}

// MARK: - Claude

public enum ClaudeHookSettings {
    public static let fileName = "settings.json"

    /// `{"hooks": {"<Evento>": [{"hooks": [{"type": "command", "command": "...", "timeout": 5}]}]}}` (06 §2.8).
    /// Saída determinística (chaves ordenadas). Hooks de `--settings` somam com os globais (S-05, V1 confirmado).
    public static func settingsJSON(helperPath: String, denyRules: [String] = []) throws -> Data {
        var hooks: [String: Any] = [:]
        for event in HookEventName.claudeRegistered {
            hooks[event.rawValue] = [[
                "hooks": [[
                    "type": "command",
                    "command": HookCommandLine.command(helperPath: helperPath, provider: .claude, event: event),
                    "timeout": HookLimits.cliHookTimeoutSeconds,
                ] as [String: Any]]
            ]]
        }
        var root: [String: Any] = ["hooks": hooks]
        if !denyRules.isEmpty { root["permissions"] = ["deny": denyRules] }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    /// Arquivo para `AB/run/launch/<runID>/settings.json` (`0600`).
    public static func launchFile(helperPath: String, denyRules: [String] = []) throws -> LaunchFile {
        LaunchFile(name: fileName, contents: try settingsJSON(helperPath: helperPath, denyRules: denyRules))
    }

    /// Segmento `injected` do argv (T2-02 o usa; aqui só a forma).
    public static func injectedArguments(settingsPath: String) -> [String] { ["--settings", settingsPath] }
}

// MARK: - Codex (P18, opção B)

public enum CodexHookConfig {
    public enum Failure: Error, Equatable { case invalidHash(String) }

    static let sessionFlagsPrefix = "/<session-flags>/config.toml"

    /// `SessionStart` -> `session_start` (nome do evento na chave de trust do Codex).
    static func snake(_ event: HookEventName) -> String {
        var out = ""
        for ch in event.rawValue {
            if ch.isUppercase, !out.isEmpty { out.append("_") }
            out.append(contentsOf: ch.lowercased())
        }
        return out
    }

    /// Chave de `hooks.state` de um hook vindo de `-c` (S-05): `/<session-flags>/config.toml:<evento>:0:0`.
    public static func stateKey(_ event: HookEventName) -> String { "\(sessionFlagsPrefix):\(snake(event)):0:0" }

    /// `-c hooks.<Evento>=[{hooks=[{type="command",command="…",timeout=5}]}]` para cada evento do Codex (06 §3.3).
    public static func hookOverrides(helperPath: String) -> [String] {
        var args: [String] = []
        for event in HookEventName.codexRegistered {
            let command = CodexAdapter.tomlString(HookCommandLine.command(helperPath: helperPath, provider: .codex, event: event))
            args += ["-c", "hooks.\(event.rawValue)=[{hooks=[{type=\"command\",command=\(command),timeout=\(HookLimits.cliHookTimeoutSeconds)}]}]"]
        }
        return args
    }

    /// `-c 'hooks.state={"<chave>"={trusted_hash="sha256:…"},…}'`: trust inline dos hooks do próprio app (P18).
    /// A forma pontilhada é ignorada pelo Codex (S-05); só a tabela inline vale. Nunca `--dangerously-bypass-hook-trust`.
    public static func trustOverride(hashes: [HookEventName: String]) throws -> [String] {
        guard !hashes.isEmpty else { return [] }
        var entries: [String] = []
        for event in HookEventName.codexRegistered {
            guard let hash = hashes[event] else { continue }
            guard isValidHash(hash) else { throw Failure.invalidHash(hash) }
            entries.append("\(CodexAdapter.tomlString(stateKey(event)))={trusted_hash=\(CodexAdapter.tomlString(hash))}")
        }
        return entries.isEmpty ? [] : ["-c", "hooks.state={\(entries.joined(separator: ","))}"]
    }

    static func isValidHash(_ s: String) -> Bool {
        guard s.hasPrefix("sha256:") else { return false }
        let hex = s.dropFirst("sha256:".count)
        return hex.count == 64 && hex.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Argumentos completos do lançamento: definições dos hooks e, se houver hashes sondados, o trust inline.
    /// Sem hashes devolve só as definições (`trusted == false`): o chamador cai no fallback de rollout `estimated`.
    public static func arguments(helperPath: String, hashes: [HookEventName: String]) throws -> (arguments: [String], trusted: Bool) {
        let trust = try trustOverride(hashes: hashes)
        return (hookOverrides(helperPath: helperPath) + trust, !trust.isEmpty)
    }

    /// Extrai o `currentHash` de cada hook `sessionFlags` da resposta de `hooks/list` do app-server do Codex
    /// (`result.data[].hooks[]`), ou do array `sessionFlags_hooks` das fixtures do S-05.
    public static func parseCurrentHashes(hooksList data: Data) -> [HookEventName: String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var hooks: [[String: Any]] = []
        let result = (root["result"] as? [String: Any]) ?? root
        if let entries = result["data"] as? [[String: Any]] {
            hooks = entries.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
        } else if let flat = root["sessionFlags_hooks"] as? [[String: Any]] {
            hooks = flat
        }
        var byKey: [String: String] = [:]
        for h in hooks where (h["source"] as? String) == "sessionFlags" {
            if let key = h["key"] as? String, let hash = h["currentHash"] as? String, isValidHash(hash) { byKey[key] = hash }
        }
        var out: [HookEventName: String] = [:]
        for event in HookEventName.codexRegistered {
            if let hash = byKey[stateKey(event)] { out[event] = hash }
        }
        return out
    }
}
