import XCTest
@testable import RackyCore
import Foundation

final class BrowserRuntimeTests: XCTestCase {
    private let id = UUID(uuidString: "a635d250-14d1-4432-bac5-af57f613bb3a")!

    func testCaptureAuthenticatedCursorAndExplicitConfiguration() async throws {
        let batch = CaptureBatch(schemaVersion: 1, captureID: UUID(), coverageVersion: "racky-capture/1",
            computerID: id.uuidString, enabled: true, coverage: ["browser_context_requests"],
            gaps: ["websocket_frames"], events: [], nextCursor: 42, dropped: 3)
        let bytes = try JSONEncoder().encode(batch)
        BrowserRouteURLProtocol.configure(["/v1/capture": bytes, "/v1/capture/config": bytes, "/v1/capture/clear": bytes])
        let client = try routeClient()
        let received = try await client.capture(after: 41)
        XCTAssertEqual(received.captureID, batch.captureID)
        XCTAssertEqual(received.dropped, 3)
        XCTAssertEqual(BrowserRouteURLProtocol.requests().first?.url?.query, "after=41")
        let config = CaptureConfiguration(enabled: true, hosts: ["example.com"])
        _ = try await client.configureCapture(config)
        _ = try await client.clearCaptures()
        XCTAssertEqual(BrowserRouteURLProtocol.paths(), ["/v1/capture", "/v1/capture/config", "/v1/capture/clear"])
        XCTAssertTrue(BrowserRouteURLProtocol.allAuthenticated())
        XCTAssertEqual(BrowserRouteURLProtocol.requests().map(\.httpMethod), ["GET", "POST", "POST"])
        XCTAssertTrue(BrowserRouteURLProtocol.requests().allSatisfy { $0.value(forHTTPHeaderField: "X-Racky-Control-Token") == nil })
        XCTAssertEqual(try JSONDecoder().decode(CaptureConfiguration.self,
            from: XCTUnwrap(BrowserRouteURLProtocol.bodies()[1])), config)
        do { _ = try await client.capture(after: -1); XCTFail("Negative cursor accepted") }
        catch BrowserRuntimeError.invalidResponse { }
        do { _ = try await client.configureCapture(.init(enabled: true)); XCTFail("Missing host accepted") }
        catch CaptureError.invalidConfiguration { }
        XCTAssertEqual(BrowserRouteURLProtocol.requests().count, 3)
    }

    func testCaptureRejectsForeignComputerAndMalformedCursor() async throws {
        for (foreignID, schema, cursor, expectedIdentity) in [
            (UUID().uuidString, 1, 0, true), (id.uuidString, 2, 0, false), (id.uuidString, 1, -1, false)
        ] {
            let batch = CaptureBatch(schemaVersion: schema, captureID: UUID(), coverageVersion: "racky-capture/1",
                computerID: foreignID, enabled: false, coverage: [], gaps: [], events: [], nextCursor: cursor, dropped: 0)
            BrowserRouteURLProtocol.configure(["/v1/capture": try JSONEncoder().encode(batch)])
            do { _ = try await routeClient().capture(); XCTFail("Invalid capture accepted") }
            catch BrowserRuntimeError.identityMismatch { XCTAssertTrue(expectedIdentity) }
            catch BrowserRuntimeError.invalidResponse { XCTAssertFalse(expectedIdentity) }
        }
    }

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

    func testPageReadsBoundedAuthenticatedSnapshotAndRejectsStaleIdentity() async throws {
        let health = frameHealth(mode: "headless", source: "browser", browserReady: true, displayReady: false)
        let page = """
        {"computer_id":"\(id.uuidString)","generation":4,"url":"https://example.com/","title":"Example","text":"Hello page","links":[{"url":"https://example.com/a","label":"A"}],"truncated":false}
        """
        BrowserRouteURLProtocol.configure(["/v1/health": Data(health.utf8), "/v1/page": Data(page.utf8)])
        let snapshot = try await routeClient().page()
        XCTAssertEqual(snapshot.title, "Example")
        XCTAssertEqual(snapshot.links.first?.label, "A")
        XCTAssertEqual(BrowserRouteURLProtocol.paths(), ["/v1/health", "/v1/page"])
        XCTAssertTrue(BrowserRouteURLProtocol.allAuthenticated())

        for badPage in [page.replacingOccurrences(of: id.uuidString, with: UUID().uuidString),
                        page.replacingOccurrences(of: "\"generation\":4", with: "\"generation\":5")] {
            BrowserRouteURLProtocol.configure(["/v1/health": Data(health.utf8), "/v1/page": Data(badPage.utf8)])
            do { _ = try await routeClient().page(); XCTFail("Foreign or stale page must fail") }
            catch BrowserRuntimeError.identityMismatch { }
        }
    }

    func testPageRejectsOversizedTextAndUnavailableBrowserBeforeFetch() async throws {
        let health = frameHealth(mode: "headless", source: "browser", browserReady: true, displayReady: false)
        let page = """
        {"computer_id":"\(id.uuidString)","generation":4,"url":"https://example.com/","title":"Example","text":"\(String(repeating: "x", count: 65_537))","links":[],"truncated":true}
        """
        BrowserRouteURLProtocol.configure(["/v1/health": Data(health.utf8), "/v1/page": Data(page.utf8)])
        do { _ = try await routeClient().page(); XCTFail("Oversized page text must fail") }
        catch BrowserRuntimeError.invalidResponse { }

        let unavailable = frameHealth(mode: "http", source: "none", browserReady: false, displayReady: false)
        BrowserRouteURLProtocol.configure(["/v1/health": Data(unavailable.utf8), "/v1/page": Data(page.utf8)])
        do { _ = try await routeClient().page(); XCTFail("HTTP-only mode has no DOM") }
        catch BrowserRuntimeError.invalidResponse { }
        XCTAssertEqual(BrowserRouteURLProtocol.paths(), ["/v1/health"])
    }

    func testHTTPRoundTripUsesLeaseHeadersAndChecksBoundedIdentity() async throws {
        let lease = try JSONDecoder().decode(BrowserRuntimeGrantedLease.self, from: Data(
            #"{"actor_id":"agent:one","epoch":7,"paths":["http_request"],"control_token":"private-control"}"#.utf8))
        let body = Data("hello".utf8).base64EncodedString()
        func response(_ computerID: UUID, _ generation: Int, _ encoded: String) -> Data {
            Data("""
            {"computer_id":"\(computerID.uuidString)","generation":\(generation),"status":200,"content_type":"text/plain","body_base64":"\(encoded)"}
            """.utf8)
        }
        BrowserRouteURLProtocol.configure(["/v1/http/request": response(id, 4, body)])
        let result = try await routeClient().httpRequest(to: URL(string: "https://example.com/data")!, method: "GET", lease: lease)
        XCTAssertEqual(result.body, Data("hello".utf8))
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(result.contentType, "text/plain")
        XCTAssertEqual(BrowserRouteURLProtocol.paths(), ["/v1/http/request"])
        XCTAssertTrue(BrowserRouteURLProtocol.allAuthenticated())
        let request = try XCTUnwrap(BrowserRouteURLProtocol.requests().first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Racky-Actor-ID"), "agent:one")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Racky-Lease-Epoch"), "7")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Racky-Control-Token"), "private-control")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(BrowserRouteURLProtocol.bodies().first ?? nil)) as? [String: String])
        XCTAssertEqual(sent, ["url": "https://example.com/data", "method": "GET"])

        BrowserRouteURLProtocol.configure(["/v1/http/request": response(id, 4, "")])
        let head = try await routeClient().httpRequest(to: URL(string: "https://example.com/data")!, method: "HEAD", lease: lease)
        XCTAssertTrue(head.body.isEmpty)
        BrowserRouteURLProtocol.configure(["/v1/http/request": response(id, 4, body)])
        do { _ = try await routeClient().httpRequest(to: URL(string: "https://example.com")!, method: "HEAD", lease: lease)
            XCTFail("HEAD must not return a body") }
        catch BrowserRuntimeError.invalidResponse { }

        for invalid in [response(UUID(), 4, body), response(id, 5, body)] {
            BrowserRouteURLProtocol.configure(["/v1/http/request": invalid])
            do { _ = try await routeClient().httpRequest(to: URL(string: "https://example.com")!, method: "GET", lease: lease)
                XCTFail("Foreign or stale HTTP result must fail") }
            catch BrowserRuntimeError.identityMismatch { }
        }
        BrowserRouteURLProtocol.configure(["/v1/http/request": response(id, 4, Data(count: 1_048_577).base64EncodedString())])
        do { _ = try await routeClient().httpRequest(to: URL(string: "https://example.com")!, method: "GET", lease: lease)
            XCTFail("HTTP body over 1 MiB must fail") }
        catch BrowserRuntimeError.invalidResponse { }
        BrowserRouteURLProtocol.configure(["/v1/http/request": response(id, 4, body)])
        do { _ = try await routeClient().httpRequest(to: URL(string: "https://example.com")!, method: "POST", lease: lease)
            XCTFail("Only GET/HEAD are allowed") }
        catch BrowserRuntimeError.invalidResponse { }
        XCTAssertTrue(BrowserRouteURLProtocol.paths().isEmpty)
    }

    private func routeClient() throws -> BrowserRuntimeClient {
        let endpoint = try BrowserRuntimeEndpoint(baseURL: URL(string: "http://127.0.0.1:8765")!,
            apiToken: String(repeating: "a", count: 40), computerID: id, generation: 4)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserRouteURLProtocol.self]
        return BrowserRuntimeClient(endpoint: endpoint, session: URLSession(configuration: config))
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

private final class BrowserRouteURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var routes: [String: Data] = [:]
    private static var seen: [URLRequest] = []
    private static var seenBodies: [Data?] = []
    static func configure(_ routes: [String: Data]) {
        lock.lock(); defer { lock.unlock() }
        self.routes = routes
        seen = []
        seenBodies = []
    }
    static func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    static func bodies() -> [Data?] { lock.lock(); defer { lock.unlock() }; return seenBodies }
    static func paths() -> [String] { requests().map { $0.url?.path ?? "" } }
    static func allAuthenticated() -> Bool {
        requests().allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "a", count: 40) }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        Self.lock.lock()
        Self.seen.append(request)
        Self.seenBodies.append(body)
        let data = Self.routes[request.url!.path]
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: data == nil ? 404 : 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
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
            ? ["Content-Type": "image/jpeg", "X-Racky-Frame-Source": source]
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
