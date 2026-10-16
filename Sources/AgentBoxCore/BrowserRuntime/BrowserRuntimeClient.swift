import Foundation

public enum BrowserRuntimeError: Error, LocalizedError, Equatable {
    case invalidEndpoint
    case unauthorized
    case transportUnavailable
    case rejected(Int, String)
    case invalidResponse
    case identityMismatch
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "O endpoint do computador precisa ser local e autenticado."
        case .unauthorized: "A autenticação do computador falhou."
        case .transportUnavailable: "Não foi possível conectar ao computador."
        case .rejected(let code, let message): "Computador recusou a operação (\(code)): \(message)"
        case .invalidResponse: "Resposta inválida do computador."
        case .identityMismatch: "A resposta pertence a outro computador ou geração."
        }
    }
}

/// Ephemeral host-to-container capability. Keep in memory; never encode or log it.
public struct BrowserRuntimeEndpoint {
    public let baseURL: URL
    public let apiToken: String
    public let computerID: UUID
    public let generation: UInt64

    public init(baseURL: URL, apiToken: String, computerID: UUID, generation: UInt64) throws {
        guard baseURL.scheme == "http", ["127.0.0.1", "::1", "localhost"].contains(baseURL.host ?? ""),
              baseURL.port != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.path.isEmpty || baseURL.path == "/", baseURL.query == nil, baseURL.fragment == nil,
              apiToken.count >= 32 else { throw BrowserRuntimeError.invalidEndpoint }
        self.baseURL = baseURL; self.apiToken = apiToken
        self.computerID = computerID; self.generation = generation
    }

    public func request(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

public enum BrowserRuntimeMode: String, Codable { case http, headless, desktop }
public enum BrowserFrameSource: String, Codable { case none, browser, desktop }

public struct BrowserRuntimeLease: Codable, Equatable {
    public let actorID: String
    public let epoch: UInt64
    public let paths: [ControlWritePath]
    enum CodingKeys: String, CodingKey { case actorID = "actor_id", epoch, paths }
}

public struct BrowserRuntimeHealth: Codable, Equatable {
    public let computerID: UUID
    public let generation: UInt64
    public let mode: BrowserRuntimeMode
    public let browserReady: Bool
    public let displayReady: Bool
    public let frameSource: BrowserFrameSource
    public let activeLease: BrowserRuntimeLease?
    enum CodingKeys: String, CodingKey {
        case computerID = "computer_id", generation, mode
        case browserReady = "browser_ready", displayReady = "display_ready"
        case frameSource = "frame_source", activeLease = "active_lease"
    }
    public var isFullDesktopReady: Bool { mode == .desktop && displayReady && frameSource == .desktop }
}

public struct BrowserRuntimeGrantedLease: Codable {
    public let actorID: String
    public let epoch: UInt64
    public let paths: [ControlWritePath]
    public let controlToken: String
    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id", epoch, paths, controlToken = "control_token"
    }
}

public struct BrowserRuntimeRevocationAck: Codable {
    public let revokedActorID: String
    public let revokedEpoch: UInt64
    public let acknowledged: Bool
    enum CodingKeys: String, CodingKey {
        case revokedActorID = "revoked_actor_id", revokedEpoch = "revoked_epoch", acknowledged
    }
}

public enum BrowserDesktopInput: Encodable {
    case move(x: Int, y: Int)
    case click(button: Int)
    case button(button: Int, pressed: Bool)
    case key(String)
    case text(String)
    case scroll(direction: String, clicks: Int)

    private enum CodingKeys: String, CodingKey { case kind, x, y, button, pressed, key, text, direction, clicks }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .move(let x, let y):
            try value.encode("move", forKey: .kind)
            try value.encode(x, forKey: .x); try value.encode(y, forKey: .y)
        case .click(let button):
            try value.encode("click", forKey: .kind); try value.encode(button, forKey: .button)
        case .button(let button, let pressed):
            try value.encode("button", forKey: .kind)
            try value.encode(button, forKey: .button); try value.encode(pressed, forKey: .pressed)
        case .key(let key):
            try value.encode("key", forKey: .kind); try value.encode(key, forKey: .key)
        case .text(let text):
            try value.encode("text", forKey: .kind); try value.encode(text, forKey: .text)
        case .scroll(let direction, let clicks):
            try value.encode("scroll", forKey: .kind)
            try value.encode(direction, forKey: .direction); try value.encode(clicks, forKey: .clicks)
        }
    }
}

public struct BrowserDesktopInputResult: Decodable {
    public let accepted: Bool
    public let generation: UInt64
}

public struct BrowserRuntimeClient {
    public let endpoint: BrowserRuntimeEndpoint
    public let session: URLSession
    public init(endpoint: BrowserRuntimeEndpoint, session: URLSession? = nil) {
        self.endpoint = endpoint
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration)
        }
    }

    public func health() async throws -> BrowserRuntimeHealth {
        let value: BrowserRuntimeHealth = try await send(endpoint.request(path: "v1/health"))
        guard value.computerID == endpoint.computerID, value.generation == endpoint.generation else {
            throw BrowserRuntimeError.identityMismatch
        }
        return value
    }

    public func grant(actorID: String, epoch: UInt64, paths: Set<ControlWritePath>) async throws -> BrowserRuntimeGrantedLease {
        let body = try JSONEncoder().encode(GrantBody(actorID: actorID, epoch: epoch, paths: Array(paths)))
        let value: BrowserRuntimeGrantedLease = try await send(endpoint.request(path: "v1/control/grant", method: "POST", body: body))
        guard value.actorID == actorID, value.epoch == epoch else { throw BrowserRuntimeError.identityMismatch }
        return value
    }

    public func revoke(actorID: String, epoch: UInt64) async throws -> BrowserRuntimeRevocationAck {
        let body = try JSONEncoder().encode(RevocationBody(actorID: actorID, epoch: epoch))
        let value: BrowserRuntimeRevocationAck = try await send(endpoint.request(path: "v1/control/revoke", method: "POST", body: body))
        guard value.acknowledged, value.revokedActorID == actorID, value.revokedEpoch == epoch else {
            throw BrowserRuntimeError.identityMismatch
        }
        return value
    }

    public func changeMode(_ mode: BrowserRuntimeMode, lease: BrowserRuntimeGrantedLease) async throws -> BrowserRuntimeHealth {
        let body = try JSONEncoder().encode(["mode": mode.rawValue])
        let value: BrowserRuntimeHealth = try await send(authorized(endpoint.request(path: "v1/mode", method: "POST", body: body), lease: lease))
        guard value.computerID == endpoint.computerID, value.generation >= endpoint.generation else {
            throw BrowserRuntimeError.identityMismatch
        }
        return value
    }

    public func navigate(to url: URL, lease: BrowserRuntimeGrantedLease) async throws -> URL {
        let body = try JSONEncoder().encode(["url": url.absoluteString])
        let value: NavigateResult = try await send(authorized(endpoint.request(path: "v1/navigate", method: "POST", body: body), lease: lease))
        return value.url
    }

    public func input(_ action: BrowserDesktopInput, lease: BrowserRuntimeGrantedLease) async throws -> BrowserDesktopInputResult {
        let body = try JSONEncoder().encode(action)
        let value: BrowserDesktopInputResult = try await send(authorized(endpoint.request(path: "v1/input", method: "POST", body: body), lease: lease))
        guard value.accepted, value.generation == endpoint.generation else { throw BrowserRuntimeError.identityMismatch }
        return value
    }

    public func desktopFrame() async throws -> Data {
        let health = try await health()
        guard health.isFullDesktopReady else { throw BrowserRuntimeError.invalidResponse }
        let (data, response) = try await fetch(endpoint.request(path: "v1/frame"))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.value(forHTTPHeaderField: "X-AgentBox-Frame-Source") == "desktop",
              http.mimeType == "image/jpeg", data.count <= 8_388_608 else { throw BrowserRuntimeError.invalidResponse }
        return data
    }

    private func authorized(_ request: URLRequest, lease: BrowserRuntimeGrantedLease) -> URLRequest {
        var value = request
        value.setValue(lease.actorID, forHTTPHeaderField: "X-AgentBox-Actor-ID")
        value.setValue(String(lease.epoch), forHTTPHeaderField: "X-AgentBox-Lease-Epoch")
        value.setValue(lease.controlToken, forHTTPHeaderField: "X-AgentBox-Control-Token")
        return value
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse else { throw BrowserRuntimeError.invalidResponse }
        if http.statusCode == 401 { throw BrowserRuntimeError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let error = data.count <= 4096 ? try? JSONDecoder().decode(RuntimeErrorBody.self, from: data) : nil
            throw BrowserRuntimeError.rejected(http.statusCode, Self.safeError(error?.error))
        }
        guard data.count <= 2_097_152 else { throw BrowserRuntimeError.invalidResponse }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw BrowserRuntimeError.invalidResponse }
    }

    private func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: request, delegate: RuntimeRedirectRejector()) }
        catch { throw BrowserRuntimeError.transportUnavailable }
    }

    private static func safeError(_ raw: String?) -> String {
        guard let raw, raw.count <= 120, !raw.contains("\n"), !raw.contains("\r"),
              !raw.contains("://"), !raw.lowercased().contains("token"),
              !raw.lowercased().contains("bearer"), !raw.lowercased().contains("authorization"),
              raw.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) else {
            return "operação recusada pelo runtime"
        }
        return raw
    }
}

private final class RuntimeRedirectRejector: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct RuntimeErrorBody: Decodable { let error: String }
private struct GrantBody: Encodable {
    let actorID: String; let epoch: UInt64; let paths: [ControlWritePath]
    enum CodingKeys: String, CodingKey { case actorID = "actor_id", epoch, paths }
}
private struct RevocationBody: Encodable {
    let actorID: String; let epoch: UInt64
    enum CodingKeys: String, CodingKey { case actorID = "actor_id", epoch }
}
private struct NavigateResult: Decodable { let url: URL; let generation: UInt64 }
