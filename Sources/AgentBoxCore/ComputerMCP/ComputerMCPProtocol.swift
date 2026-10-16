import Foundation
import CoreFoundation

public enum ComputerMCPResult: Sendable {
    case text(String)
    case jpeg(Data)
    var content: [[String: Any]] {
        switch self {
        case .text(let text): return [["type": "text", "text": text]]
        case .jpeg(let data): return [["type": "image", "mimeType": "image/jpeg", "data": data.base64EncodedString()]]
        }
    }
}

/// MCP stdio JSON-RPC endpoint; no container credentials or arbitrary shell route.
public actor ComputerMCPProtocol {
    public typealias ToolHandler = @Sendable (String, Data) async throws -> ComputerMCPResult
    private let call: ToolHandler
    private var initialized = false
    public init(call: @escaping ToolHandler) { self.call = call }

    public func respond(_ data: Data) async throws -> Data {
        guard data.count <= 65536,
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            return try encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid request"]])
        }
        guard let id = message["id"], !(id is NSNull) else { return Data() }
        guard id is String || (id is NSNumber && CFGetTypeID(id as CFTypeRef) != CFBooleanGetTypeID()) else {
            return try encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid request id"]])
        }
        func reply(_ result: [String: Any]) throws -> Data { try encode(["jsonrpc": "2.0", "id": id, "result": result]) }
        func error(_ code: Int, _ text: String) throws -> Data { try encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]) }
        if method == "initialize" {
            initialized = true
            let requested = (message["params"] as? [String: Any])?["protocolVersion"] as? String ?? ""
            let version = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"].contains(requested) ? requested : "2025-11-25"
            return try reply(["protocolVersion": version, "capabilities": ["tools": ["listChanged": false]],
                              "serverInfo": ["name": "agentbox", "version": "0.6.0"],
                              "instructions": "Operate only this assigned computer. When control is human-owned, wait for release. Request help for login or CAPTCHA. Never infer that a failed write completed."])
        }
        if method == "ping" { return try reply([:]) }
        guard initialized else { return try error(-32002, "Initialize first") }
        if method == "tools/list" { return try reply(["tools": Self.tools]) }
        guard method == "tools/call" else { return try error(-32601, "Method not found") }
        guard let params = message["params"] as? [String: Any], let name = params["name"] as? String,
              Self.tools.contains(where: { $0["name"] as? String == name }),
              let arguments = params["arguments"] as? [String: Any] ?? (params["arguments"] == nil ? [:] : nil) else {
            return try error(-32602, "Invalid tool call")
        }
        do {
            let output = try await call(name, encode(arguments))
            return try reply(["content": output.content, "isError": false])
        } catch {
            let text: String
            switch error {
            case ComputerControlBridgeError.noTicket, ComputerControlBridgeError.writeDenied,
                 ControlBrokerError.activeRuntimeLease, ControlBrokerError.transitionInProgress:
                text = "Computer control is unavailable or held by the user. Wait for the user to release control."
            case ComputerPolicyError.creationDisabled, BrowserComputerError.networkDisabled:
                text = "Computer access is disabled by the current policy."
            default: text = "Computer operation failed. Check the computer in Agent Box; do not assume the action completed."
            }
            return try reply(["content": [["type": "text", "text": text]], "isError": true])
        }
    }

    private func encode(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    public static var tools: [[String: Any]] {
        func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], _ required: [String] = []) -> [String: Any] {
            ["name": name, "description": description,
             "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false]]
        }
        return [
            tool("computer_status", "Read mode and who controls the assigned computer."),
            tool("computer_screenshot", "Read a JPEG screenshot of the assigned browser or full desktop."),
            tool("computer_mode", "Choose HTTP, headless Chromium or full desktop. Mode changes restart the browser; persistent profile remains but page state may be lost.", ["mode": ["type": "string", "enum": ["http", "headless", "desktop"]]], ["mode"]),
            tool("computer_navigate", "Navigate the assigned browser to an HTTP(S) URL. Requires headless or desktop mode.", ["url": ["type": "string"]], ["url"]),
            tool("computer_input", "Operate the desktop using pixel coordinates (1280 x 800). Key names follow X11; use text for typing. Requires desktop mode and agent control.",
                 ["kind": ["type": "string", "enum": ["move", "click", "key", "text", "scroll"]],
                  "x": ["type": "integer", "minimum": 0, "maximum": 1279], "y": ["type": "integer", "minimum": 0, "maximum": 799],
                  "button": ["type": "integer", "enum": [1, 2, 3]], "key": ["type": "string", "maxLength": 60],
                  "text": ["type": "string", "maxLength": 4096], "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
                  "clicks": ["type": "integer", "minimum": 1, "maximum": 20]], ["kind"]),
            tool("computer_request_help", "Release agent control and ask the user to take over for login, CAPTCHA, download or another manual action. No CAPTCHA is solved automatically.",
                 ["reason": ["type": "string", "maxLength": 500]], ["reason"])
        ]
    }
}
