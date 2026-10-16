import Foundation
import CoreFoundation

/// Parsed tool arguments. The help reason is intentionally discarded so it cannot
/// be carried into run metadata or another control request.
public enum ComputerMCPToolArguments {
    case status
    case screenshot
    case mode(BrowserRuntimeMode)
    case navigate(URL)
    case input(BrowserDesktopInput)
    case requestHelp

    public static func validate(name: String, data: Data) throws -> Self {
        guard data.count <= 65_536,
              let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw invalid()
        }
        switch name {
        case "computer_status":
            try requireKeys(arguments, [])
            return .status
        case "computer_screenshot":
            try requireKeys(arguments, [])
            return .screenshot
        case "computer_mode":
            try requireKeys(arguments, ["mode"])
            guard let raw = arguments["mode"] as? String,
                  let mode = BrowserRuntimeMode(rawValue: raw) else { throw invalid() }
            return .mode(mode)
        case "computer_navigate":
            try requireKeys(arguments, ["url"])
            guard let raw = arguments["url"] as? String,
                  raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
                  let components = URLComponents(string: raw),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil,
                  let url = components.url else { throw invalid() }
            return .navigate(url)
        case "computer_input":
            guard let kind = arguments["kind"] as? String else { throw invalid() }
            switch kind {
            case "move":
                try requireKeys(arguments, ["kind", "x", "y"])
                let x = try integer(arguments["x"], range: 0...1279)
                let y = try integer(arguments["y"], range: 0...799)
                return .input(.move(x: x, y: y))
            case "click":
                try requireKeys(arguments, ["kind", "button"])
                return .input(.click(button: try integer(arguments["button"], range: 1...3)))
            case "key":
                try requireKeys(arguments, ["kind", "key"])
                guard let key = arguments["key"] as? String,
                      !key.isEmpty, key.count <= 60 else { throw invalid() }
                return .input(.key(key))
            case "text":
                try requireKeys(arguments, ["kind", "text"])
                guard let text = arguments["text"] as? String,
                      !text.isEmpty, text.count <= 4096 else { throw invalid() }
                return .input(.text(text))
            case "scroll":
                try requireKeys(arguments, ["kind", "direction", "clicks"])
                guard let direction = arguments["direction"] as? String,
                      ["up", "down", "left", "right"].contains(direction) else { throw invalid() }
                return .input(.scroll(direction: direction,
                                      clicks: try integer(arguments["clicks"], range: 1...20)))
            default: throw invalid()
            }
        case "computer_request_help":
            try requireKeys(arguments, ["reason"])
            guard let reason = arguments["reason"] as? String,
                  !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  reason.count <= 500 else { throw invalid() }
            return .requestHelp
        default: throw invalid()
        }
    }

    private static func requireKeys(_ arguments: [String: Any], _ expected: Set<String>) throws {
        guard Set(arguments.keys) == expected else { throw invalid() }
    }

    private static func integer(_ value: Any?, range: ClosedRange<Int>) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType)),
              let integer = Int(number.stringValue), range.contains(integer) else { throw invalid() }
        return integer
    }

    private static func invalid() -> LibraryError {
        .invalid("Argumentos inválidos para a ferramenta de computador.")
    }
}
