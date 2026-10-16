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
