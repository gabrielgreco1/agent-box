import AgentBoxPlatform
import AgentBoxProtocol
import Foundation

/// Servidor MCP (JSON-RPC 2.0) das capacidades do computador (08 §0, §1: o MCP mora no app; o helper `agentbox mcp` só liga
/// o stdio do CLI ao `app.sock`). Sem estado por conexão: cada requisição traz a identidade do filho.
public struct ComputerMCPServer: Sendable {
    public static let supportedVersions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
    public static let serverVersion = "1.0.0"

    public let tools: ComputerToolService

    public init(tools: ComputerToolService) { self.tools = tools }

    private static func reply(_ id: JSON, result: JSON) -> Data {
        JSON.object(["jsonrpc": "2.0", "id": id, "result": result]).data()
    }

    private static func fail(_ id: JSON, code: Int, _ message: String) -> Data {
        JSON.object(["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]]).data()
    }

    /// Resposta à mensagem JSON-RPC `message` do `child`. `nil` para notificações (sem `id`).
    public func handle(_ message: Data, child: String) async -> Data? {
        guard let parsed = try? JSON.parse(message), case .object(let object) = parsed, object["jsonrpc"]?.string == "2.0",
              let method = object["method"]?.string else {
            return Self.fail(.null, code: -32600, "Invalid request")
        }
        guard let id = object["id"], !id.isNull else { return nil }  // notificação (`notifications/initialized`...)
        guard id.string != nil || id.int != nil else { return Self.fail(.null, code: -32600, "Invalid request id") }
        let params = object["params"]
        switch method {
        case "initialize":
            let requested = params?["protocolVersion"]?.string ?? ""
            let version = Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions.last!
            let isParent = await tools.hub.role(of: child) == .parent
            return Self.reply(id, result: [
                "protocolVersion": .string(version), "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "agentbox", "version": .string(Self.serverVersion)],
                "instructions": .string(isParent ? ToolCatalog.parentInstructions : ToolCatalog.serverInstructions),
            ])
        case "ping":
            return Self.reply(id, result: [:])
        case "tools/list":
            let isParent = await tools.hub.role(of: child) == .parent
            return Self.reply(id, result: ["tools": .array((isParent ? ToolCatalog.parentTools : ToolCatalog.all).map(\.mcpJSON))])
        case "tools/call":
            guard let name = params?["name"]?.string else { return Self.fail(id, code: -32602, "Invalid tool call: name is required") }
            let arguments = params?["arguments"] ?? [:]
            guard arguments.object != nil || arguments.isNull else { return Self.fail(id, code: -32602, "Invalid tool call: arguments must be an object") }
            let outcome = await tools.call(name, arguments: arguments, child: child)
            return Self.reply(id, result: ["content": .array(outcome.content), "isError": .bool(outcome.isError)])
        default:
            return Self.fail(id, code: -32601, "Method not found")
        }
    }
}

/// Serviço `mcp` de `app.sock` (08 AR-106): frame 1 = identidade, frame 2 = mensagem JSON-RPC, uma resposta, e a conexão fecha.
public struct McpServiceProvider: AppSockServiceProvider {
    public let service = AppSockService.mcp
    private let server: ComputerMCPServer
    private let hub: ComputerHub

    public init(server: ComputerMCPServer, hub: ComputerHub) {
        self.server = server
        self.hub = hub
    }

    public func admit() -> CtlError? { nil }

    public func makeHandler() -> AppSockServer.Handler {
        let session = McpSession(server: server, hub: hub)
        return { frame in await session.receive(frame) }
    }
}

actor McpSession {
    private let server: ComputerMCPServer
    private let hub: ComputerHub
    private var child: String?

    init(server: ComputerMCPServer, hub: ComputerHub) {
        self.server = server
        self.hub = hub
    }

    func receive(_ frame: Data) async -> AppSockReply {
        if child == nil {
            guard let identity = try? JSONDecoder().decode(McpIdentity.self, from: frame), await hub.authorize(child: identity.child, capability: identity.capability) else {
                // JSON-RPC sem id: o helper traduz em erro de ferramenta legível.
                let denied = JSON.object(["jsonrpc": "2.0", "id": .null, "error": ["code": -32001, "message": "unauthorized: unknown child or capability"]]).data()
                return AppSockReply(frames: [denied], close: true)
            }
            child = identity.child
            return AppSockReply()
        }
        guard let child else { return AppSockReply(close: true) }
        let response = await server.handle(frame, child: child)
        return AppSockReply(frames: response.map { [$0] } ?? [], close: true)
    }
}
