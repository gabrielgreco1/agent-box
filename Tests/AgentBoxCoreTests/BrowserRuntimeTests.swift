import XCTest
@testable import AgentBoxCore
import Foundation

final class BrowserRuntimeTests: XCTestCase {
    private let id = UUID(uuidString: "a635d250-14d1-4432-bac5-af57f613bb3a")!

    func testDesktopButtonAndScrollEncoding() throws {
        let down = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BrowserDesktopInput.button(button: 1, pressed: true))) as! [String: Any]
        XCTAssertEqual(down["kind"] as? String, "button")
        XCTAssertEqual(down["button"] as? Int, 1)
        XCTAssertEqual(down["pressed"] as? Bool, true)
        let scroll = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BrowserDesktopInput.scroll(direction: "left", clicks: 2))) as! [String: Any]
        XCTAssertEqual(scroll["direction"] as? String, "left")
        XCTAssertEqual(scroll["clicks"] as? Int, 2)
    }

    func testEndpointRejectsNonLoopbackAndKeepsTokenInHeader() throws {
        XCTAssertThrowsError(try BrowserRuntimeEndpoint(baseURL: URL(string: "http://192.168.1.2:8765")!, apiToken: String(repeating: "a", count: 40), computerID: id, generation: 1))
        let endpoint = try BrowserRuntimeEndpoint(baseURL: URL(string: "http://127.0.0.1:8765")!, apiToken: String(repeating: "a", count: 40), computerID: id, generation: 1)
        let request = endpoint.request(path: "v1/health")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "a", count: 40))
        XCTAssertFalse(request.url!.absoluteString.contains(String(repeating: "a", count: 40)))
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertFalse(request.httpShouldHandleCookies)
        let client = BrowserRuntimeClient(endpoint: endpoint)
        XCTAssertNil(client.session.configuration.httpCookieStorage)
        XCTAssertNil(client.session.configuration.urlCache)
    }

    func testHealthRequiresMatchingComputerAndGeneration() async throws {
        let endpoint = try BrowserRuntimeEndpoint(baseURL: URL(string: "http://127.0.0.1:8765")!, apiToken: String(repeating: "a", count: 40), computerID: id, generation: 4)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserRuntimeURLProtocol.self]
        let session = URLSession(configuration: config)
        BrowserRuntimeURLProtocol.response = """
        {"computer_id":"\(id.uuidString)","generation":4,"mode":"desktop","browser_ready":true,"display_ready":true,"frame_source":"desktop","active_lease":null}
        """
        let client = BrowserRuntimeClient(endpoint: endpoint, session: session)
        let health = try await client.health()
        XCTAssertTrue(health.isFullDesktopReady)
        BrowserRuntimeURLProtocol.response = """
        {"computer_id":"\(id.uuidString)","generation":5,"mode":"desktop","browser_ready":true,"display_ready":true,"frame_source":"desktop","active_lease":null}
        """
        do {
            _ = try await client.health()
            XCTFail("A stale endpoint must not attach to a new generation")
        } catch BrowserRuntimeError.identityMismatch { }
    }

    func testRuntimeErrorDoesNotExposeBearerOrLongDiagnostic() async throws {
        let endpoint = try BrowserRuntimeEndpoint(baseURL: URL(string: "http://127.0.0.1:8765")!, apiToken: String(repeating: "a", count: 40), computerID: id, generation: 1)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserRuntimeURLProtocol.self]
        BrowserRuntimeURLProtocol.statusCode = 409
        BrowserRuntimeURLProtocol.response = "{\"error\":\"Bearer secret-value from browser diagnostic\"}"
        defer { BrowserRuntimeURLProtocol.statusCode = 200 }
        let client = BrowserRuntimeClient(endpoint: endpoint, session: URLSession(configuration: config))
        do {
            _ = try await client.health()
            XCTFail("The runtime should reject the request")
        } catch BrowserRuntimeError.rejected(let code, let reason) {
            XCTAssertEqual(code, 409)
            XCTAssertEqual(reason, "operação recusada pelo runtime")
            XCTAssertFalse(reason.contains("secret-value"))
        }
    }

    func testBrowserOrDesktopFrameAcceptsMatchingHeadlessAndDesktopSources() async throws {
        for (mode, source, browserReady, displayReady) in [
            ("headless", "browser", true, false),
            ("desktop", "desktop", true, true)
        ] {
            BrowserFrameURLProtocol.configure(health: frameHealth(mode: mode, source: source,
                browserReady: browserReady, displayReady: displayReady), frameSource: source)
            let client = try frameClient()
            let frame = try await client.browserOrDesktopFrame()
            XCTAssertEqual(frame, BrowserFrameURLProtocol.jpeg)
            XCTAssertEqual(BrowserFrameURLProtocol.requestPaths(), ["/v1/health", "/v1/frame"])
            XCTAssertTrue(BrowserFrameURLProtocol.allRequestsAuthenticated())
        }
    }

    func testBrowserOrDesktopFrameRejectsMismatchedAndAbsentSources() async throws {
        for (mode, healthSource, responseSource, expectedPaths) in [
            ("headless", "browser", "desktop", ["/v1/health", "/v1/frame"]),
            ("desktop", "desktop", "browser", ["/v1/health", "/v1/frame"]),
            ("http", "none", "browser", ["/v1/health"])
        ] {
            BrowserFrameURLProtocol.configure(health: frameHealth(mode: mode, source: healthSource,
                browserReady: mode != "http", displayReady: mode == "desktop"), frameSource: responseSource)
            let client = try frameClient()
            do {
                _ = try await client.browserOrDesktopFrame()
                XCTFail("A frame with source \(responseSource) must not satisfy \(healthSource)")
            } catch BrowserRuntimeError.invalidResponse { }
            XCTAssertEqual(BrowserFrameURLProtocol.requestPaths(), expectedPaths)
        }
    }

    func testBrowserOrDesktopFrameRejectsInconsistentHealthModeAndReadiness() async throws {
        for (mode, source, browserReady, displayReady) in [
            ("desktop", "browser", true, true),
            ("headless", "desktop", true, true),
            ("headless", "browser", false, false),
            ("desktop", "desktop", true, false)
        ] {
            BrowserFrameURLProtocol.configure(health: frameHealth(mode: mode, source: source,
                browserReady: browserReady, displayReady: displayReady), frameSource: source)
            let client = try frameClient()
            do {
                _ = try await client.browserOrDesktopFrame()
                XCTFail("Health cannot advertise \(source) in \(mode) with missing readiness")
            } catch BrowserRuntimeError.invalidResponse { }
            XCTAssertEqual(BrowserFrameURLProtocol.requestPaths(), ["/v1/health"])
        }
    }

    func testBrowserOrDesktopFrameChecksIdentityAndGenerationBeforeFetching() async throws {
        for (computerID, generation) in [(UUID(), UInt64(4)), (id, UInt64(5))] {
            BrowserFrameURLProtocol.configure(health: frameHealth(mode: "headless", source: "browser",
                browserReady: true, displayReady: false, computerID: computerID, generation: generation),
                frameSource: "browser")
            let client = try frameClient()
            do {
                _ = try await client.browserOrDesktopFrame()
                XCTFail("A stale or foreign computer cannot supply a frame")
            } catch BrowserRuntimeError.identityMismatch { }
            XCTAssertEqual(BrowserFrameURLProtocol.requestPaths(), ["/v1/health"])
        }
    }

    private func frameClient() throws -> BrowserRuntimeClient {
        let endpoint = try BrowserRuntimeEndpoint(baseURL: URL(string: "http://127.0.0.1:8765")!,
            apiToken: String(repeating: "a", count: 40), computerID: id, generation: 4)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserFrameURLProtocol.self]
        return BrowserRuntimeClient(endpoint: endpoint, session: URLSession(configuration: config))
    }

    private func frameHealth(mode: String, source: String, browserReady: Bool, displayReady: Bool,
                             computerID: UUID? = nil, generation: UInt64 = 4) -> String {
        """
        {"computer_id":"\((computerID ?? id).uuidString)","generation":\(generation),"mode":"\(mode)","browser_ready":\(browserReady),"display_ready":\(displayReady),"frame_source":"\(source)","active_lease":null}
        """
    }
}

private final class BrowserFrameURLProtocol: URLProtocol {
    static let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
    private static let lock = NSLock()
    private static var health = ""
    private static var frameSource = ""
    private static var paths: [String] = []
    private static var authenticated = true

    static func configure(health: String, frameSource: String) {
        lock.lock(); defer { lock.unlock() }
        self.health = health
        self.frameSource = frameSource
        paths = []
        authenticated = true
    }
    static func requestPaths() -> [String] { lock.lock(); defer { lock.unlock() }; return paths }
    static func allRequestsAuthenticated() -> Bool { lock.lock(); defer { lock.unlock() }; return authenticated }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.lock.lock()
        Self.paths.append(path)
        Self.authenticated = Self.authenticated &&
            request.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "a", count: 40)
        let health = Self.health
        let source = Self.frameSource
        Self.lock.unlock()
        let isFrame = path == "/v1/frame"
        let data = isFrame ? Self.jpeg : Data(health.utf8)
        let headers = isFrame
            ? ["Content-Type": "image/jpeg", "X-AgentBox-Frame-Source": source]
            : ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class BrowserRuntimeURLProtocol: URLProtocol {
    static var response = ""
    static var statusCode = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.response.data(using: .utf8)!
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
