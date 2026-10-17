import AgentBoxDocker
import Foundation

/// Resultado de uma ferramenta: JSON (sempre) e, no screenshot, a imagem PNG.
public struct ToolResult: Sendable {
    public var json: JSON
    public var image: Data?
    public init(_ json: JSON, image: Data? = nil) { self.json = json; self.image = image }
}

/// O que volta ao MCP: blocos de conteúdo e `isError`.
public struct ToolOutcome: Sendable {
    public var content: [JSON]
    public var isError: Bool
}

/// Argumentos já validados pelo schema (sem `null`). Os padrões de 07 §3.2 são aplicados por quem lê.
struct Args {
    var values: [String: JSON]
    init(_ json: JSON) { values = ObjectSpec.stripNulls(json.object ?? [:]) }
    func has(_ key: String) -> Bool { values[key] != nil }
    func string(_ key: String) -> String? { values[key]?.string }
    func int(_ key: String) -> Int? { values[key]?.int }
    func double(_ key: String) -> Double? { values[key]?.double }
    func bool(_ key: String) -> Bool? { values[key]?.bool }
    func strings(_ key: String) -> [String]? { values[key]?.array?.compactMap(\.string) }
    func stringMap(_ key: String) -> [String: String]? {
        values[key]?.object?.compactMapValues(\.string)
    }
    /// Os mesmos argumentos como objeto JSON (para repassar ao runtime).
    var json: JSON { .object(values) }
}

/// Executa as ferramentas MCP de 07 §3 no computador do filho que chama. O roteamento é por filho (identidade da
/// configuração do processo MCP), nunca por argumento. Cada chamada devolve em ≤ 50 s; o que for longo tem `*_poll`/`*_wait`.
public actor ComputerToolService {
    public let hub: ComputerHub
    var jobs: [String: JobMeta] = [:]

    struct JobMeta {
        var computer: String
        var number: Int
        var request: BackendExec
        var started: Date
        var logged = false
    }

    public init(hub: ComputerHub) { self.hub = hub }

    /// Ferramentas que precisam do container vivo (as demais só tocam o host: diário, reqlog, ajuda, resultado).
    static let needsContainer: Set<String> = [
        "computer_mode", "browser_open", "browser_read", "browser_screenshot", "browser_click", "browser_type", "browser_press", "browser_select",
        "browser_scroll", "browser_wait", "browser_eval", "browser_cookies", "browser_tabs", "browser_back", "browser_forward", "browser_reload",
        "browser_download", "browser_upload", "exec", "exec_start", "http_request", "proxy_set", "render",
    ]

    /// Ponto de entrada: valida o schema, executa e traduz o erro para o conjunto fechado de códigos.
    public func call(_ name: String, arguments: JSON, child: String) async -> ToolOutcome {
        let started = ContinuousClock.now
        guard let definition = ToolCatalog.byName[name] else {
            return Self.failure(ToolError(.notFound, "unknown tool \(name)"), box: nil)
        }
        let cleaned = JSON.object(ObjectSpec.stripNulls(arguments.object ?? [:]))
        if arguments.object == nil && !arguments.isNull { return Self.failure(.invalid("arguments must be an object"), box: nil) }
        let violations = Schema.object(definition.spec).validate(cleaned)
        if !violations.isEmpty {
            return Self.failure(.invalid(violations.joined(separator: "; "), details: ["violations": .array(violations.map { .string($0) })]), box: nil)
        }
        var boxName: String?
        do {
            let args = Args(cleaned)
            let computer = definition.access == .identity ? nil : try await hub.computer(for: child)
            boxName = computer?.name
            if let computer {
                if Self.needsContainer.contains(name), let gate = await computer.stateGate() { throw gate }
                if definition.access == .write, let pause = await computer.pauseReason() { throw pause }
            }
            var result = try await execute(name, args, child: child, computer: computer)
            if case .object(var object) = result.json {
                let ms = started.duration(to: .now).components
                object["took_ms"] = .int(Int(ms.seconds * 1000 + ms.attoseconds / 1_000_000_000_000_000))
                if let boxName, object["box"] == nil { object["box"] = .string(boxName) }
                result.json = .object(object)
            }
            var content: [JSON] = [["type": "text", "text": .string(result.json.text)]]
            if let image = result.image { content.append(["type": "image", "data": .string(image.base64EncodedString()), "mimeType": "image/png"]) }
            return ToolOutcome(content: content, isError: false)
        } catch let error as ToolError {
            return Self.failure(error, box: boxName)
        } catch let error as DockerError {
            return Self.failure(Self.map(error), box: boxName)
        } catch {
            return Self.failure(ToolError(.boxRestarted, "computer operation failed: \(error.localizedDescription)", retryAfterS: 5), box: boxName)
        }
    }

    static func failure(_ error: ToolError, box: String?) -> ToolOutcome {
        var json = error.json
        if let box, case .object(var o) = json { o["box"] = .string(box); json = .object(o) }
        return ToolOutcome(content: [["type": "text", "text": .string(json.text)]], isError: true)
    }

    static func map(_ error: DockerError) -> ToolError {
        switch error {
        case .runtimeUnavailable(let m): ToolError(.dockerUnavailable, m, retryAfterS: 10)
        case .timeout(let op): ToolError(.timeout, "docker operation timed out: \(op)")
        case .notFound, .conflict: ToolError(.boxRestarted, "the computer container is gone or stopped", retryAfterS: 5)
        default: ToolError(.boxRestarted, "docker error: \(error)", retryAfterS: 5)
        }
    }

    // MARK: Despacho

    func execute(_ name: String, _ args: Args, child: String, computer: ManagedComputer?) async throws -> ToolResult {
        if name == "box_claim" { return try await claim(args, child: child) }
        guard let c = computer else { throw ToolError(.notClaimed, "call box_claim first") }
        switch name {
        case "box_status": return try await status(c)
        case "box_release": return try await releaseBox(args, child: child, c)
        case "computer_mode": return try await mode(args, c)
        case "exec": return try await exec(args, c)
        case "exec_start": return try await execStart(args, c)
        case "exec_poll": return try await execPoll(args, c)
        case "exec_cancel": return try await execCancel(args, c)
        case "http_request": return try await httpRequest(args, c)
        case "reqlog_query": return try reqlogQuery(args, c)
        case "reqlog_get": return try reqlogGet(args, c)
        case "reqlog_as_curl": return try reqlogAsCurl(args, c)
        case "proxy_set": return try await proxySet(args, c)
        case "proxy_status": return try await proxyStatus(c)
        case "render": return try await render(args, c)
        case "journal": return try await journal(args, c)
        case "timeline": return try await timeline(args, c)
        case "result_submit": return try await resultSubmit(args, c)
        case "help_request": return try await helpRequest(args, c)
        case "help_wait": return try await helpWait(args, c)
        case "help_cancel": return try await helpCancel(args, c)
        default:
            if name.hasPrefix("browser_") { return try await browser(name, args, c) }
            throw ToolError(.notFound, "tool \(name) is not implemented")
        }
    }

    // MARK: A. Computador e identidade

    func claim(_ args: Args, child: String) async throws -> ToolResult {
        let name = args.string("name") ?? ""
        let computer = try await hub.claim(name: name, child: child)
        let wait = min(max(args.double("wait_s") ?? 45, 0), 45)
        let state = await computer.waitUntilReady(timeout: .seconds(wait))
        var out: [String: JSON] = [
            "box": .string(computer.name), "display": .string(await computer.display.rawValue), "state": .string(state.rawValue),
            "work_path_host": .string(computer.run.work.path), "work_path_box": "/work",
            "proxy": .string(await computer.proxy), "proxies_allowed": .array(computer.proxiesAllowed.map { .string($0) }),
        ]
        if let position = await computer.queuePosition { out["position"] = .int(position) }
        if let profile = computer.profile { out["profile"] = .string(profile) }
        if let previous = await computer.takePreviousRun() { out["previous_run"] = previous }
        return ToolResult(.object(out))
    }

    func status(_ c: ManagedComputer) async throws -> ToolResult {
        let state = await c.state
        var out: [String: JSON] = [
            "box": .string(c.name), "state": .string(state.rawValue), "display": .string(await c.display.rawValue), "lease": .string(await c.lease.rawValue),
            "proxy": .string(await c.proxy),
        ]
        if let position = await c.queuePosition { out["position"] = .int(position) }
        if (state == .ready || state == .inUse), await c.display != .http,
           let page = try? await c.backend.runtime("status", [:], timeout: 10), page["ready"]?.bool == true {
            out["url"] = page["url"] ?? .null
            out["title"] = page["title"] ?? .null
        }
        out["usage"] = (try? await c.backend.usage()) ?? Self.emptyUsage
        if let help = await c.openHelpID { out["help_open"] = .string(help) }
        return ToolResult(.object(out))
    }

    static let emptyUsage: JSON = ["requests": 0, "tunnels": 0, "bytes": 0, "renders": 0]

    func releaseBox(_ args: Args, child: String, _ c: ManagedComputer) async throws -> ToolResult {
        try await flushJobLogs(c)
        try await hub.release(child: child, keep24h: args.string("keep") == "24h")
        return ToolResult(["released": true])
    }

    func mode(_ args: Args, _ c: ManagedComputer) async throws -> ToolResult {
        guard let target = args.string("display").flatMap(ComputerDisplay.init(rawValue:)) else { throw ToolError.invalid("display is required") }
        let current = await c.display
        if target == current {
            return ToolResult(["display": .string(target.rawValue), "reloaded": false, "state": .string(await c.state.rawValue)])
        }
        guard current != .http, target != .http else {
            throw ToolError(.notSupported, "switching to or from display http needs a different container set; reserve the computer with that display")
        }
        let out = try await c.backend.runtime("mode", ["display": .string(target.rawValue)], timeout: 30)
        await c.setDisplay(target)
        await c.logEvent("mode", "display -> \(target.rawValue)")
        return ToolResult(["display": .string(target.rawValue), "reloaded": out["reloaded"] ?? false, "state": .string(await c.state.rawValue)])
    }
}
