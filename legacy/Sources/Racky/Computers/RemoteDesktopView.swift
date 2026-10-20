import AppKit
import Foundation
import SwiftUI
import RackyCore

/// Supplied by the host broker only after runtime revoke ACK and a successful human grant.
/// The UI never calls `/v1/control/grant` or manufactures a control token.
struct RemoteDesktopControlActions {
    let assume: () async throws -> ControlGrant
    let release: (ControlGrant) async throws -> Void
    let streamDisconnected: (ControlGrant) async -> Void
    let pointer: (ControlGrant, DesktopPointerInput) async throws -> Void
    let key: (ControlGrant, String) async throws -> Void
}

enum DesktopPointerInput {
    case move(x: Double, y: Double)
    case button(x: Double, y: Double, button: Int, pressed: Bool)
    case scroll(direction: String, clicks: Int)
}

private enum DesktopConnectionState: Equatable {
    case connecting
    case reconnecting
    case live
    case delayed
    case disconnected
    case unavailable(String)
}

@MainActor private final class RemoteDesktopModel: ObservableObject {
    @Published var frame: NSImage?
    @Published var state: DesktopConnectionState = .connecting
    @Published var humanGrant: ControlGrant?
    @Published var controlError: String?

    private let endpoint: BrowserRuntimeEndpoint
    private let control: RemoteDesktopControlActions?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var streamDelegate: MJPEGStreamDelegate?
    private var monitor: Task<Void, Never>?
    private var lastFrameAt: Date?
    private var streamStartedAt: Date?
    private var active = false
    private var connectionAttempt = UUID()
    private var pendingInput: Task<Void, Never>?

    init(endpoint: BrowserRuntimeEndpoint, control: RemoteDesktopControlActions?) {
        self.endpoint = endpoint
        self.control = control
    }

    var canInput: Bool { state == .live && humanGrant?.actor == .human }

    func connect() async {
        let hasConnectedBefore = frame != nil || state == .disconnected
        let attempt = UUID()
        connectionAttempt = attempt
        stopStream()
        active = false
        state = hasConnectedBefore ? .reconnecting : .connecting
        if let grant = humanGrant {
            humanGrant = nil
            await control?.streamDisconnected(grant)
        }
        guard connectionAttempt == attempt else { return }
        active = true
        frame = nil
        controlError = nil
        do {
            try validateEndpoint()
            let healthURL = endpoint.baseURL.appendingPathComponent("v1/health")
            var request = URLRequest(url: healthURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
            request.setValue("Bearer \(endpoint.apiToken)", forHTTPHeaderField: "Authorization")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            let healthSession = URLSession(configuration: configuration,
                                           delegate: LoopbackRedirectRejectingDelegate(), delegateQueue: nil)
            defer { healthSession.invalidateAndCancel() }
            let (data, response) = try await healthSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw DesktopViewerError.healthUnavailable
            }
            let health = try JSONDecoder().decode(BrowserRuntimeHealth.self, from: data)
            guard health.computerID == endpoint.computerID,
                  health.generation == endpoint.generation else { throw DesktopViewerError.identityChanged }
            guard health.isFullDesktopReady else {
                throw DesktopViewerError.desktopUnavailable
            }
            guard active, connectionAttempt == attempt else { return }
            startStream()
        } catch {
            if active, connectionAttempt == attempt { state = .unavailable(error.localizedDescription) }
        }
    }

    func disconnect() {
        connectionAttempt = UUID()
        active = false
        stopStream()
        state = .disconnected
        if let grant = humanGrant {
            humanGrant = nil
            Task { await control?.streamDisconnected(grant) }
        }
    }

    func assume() async {
        guard state == .live, let control else { return }
        let attempt = connectionAttempt
        do {
            let grant = try await control.assume()
            guard grant.computerID == endpoint.computerID, grant.actor == .human,
                  grant.paths.contains(.input) else { throw DesktopViewerError.invalidGrant }
            guard active, state == .live, connectionAttempt == attempt else {
                await control.streamDisconnected(grant)
                return
            }
            humanGrant = grant
            controlError = nil
        } catch { controlError = error.localizedDescription }
    }

    func release() async {
        guard let grant = humanGrant, let control else { return }
        do {
            try await control.release(grant)
            if humanGrant == grant { humanGrant = nil }
            controlError = nil
        } catch { controlError = error.localizedDescription }
    }

    func sendPointer(_ input: DesktopPointerInput) {
        guard canInput, let grant = humanGrant, let control else { return }
        enqueueInput(grant: grant) { try await control.pointer(grant, input) }
    }

    func sendKey(_ value: String) {
        guard canInput, let grant = humanGrant, let control else { return }
        enqueueInput(grant: grant) { try await control.key(grant, value) }
    }

    private func enqueueInput(grant: ControlGrant, _ operation: @escaping () async throws -> Void) {
        let previous = pendingInput
        pendingInput = Task { [weak self] in
            await previous?.value
            guard let self, self.canInput, self.humanGrant == grant else { return }
            do { try await operation() }
            catch {
                guard self.humanGrant == grant else { return }
                self.controlError = error.localizedDescription
                self.humanGrant = nil
                await self.control?.streamDisconnected(grant)
            }
        }
    }

    private func validateEndpoint() throws {
        let url = endpoint.baseURL
        guard url.scheme == "http", url.host == "127.0.0.1" || url.host == "::1",
              let port = url.port, (1...65535).contains(port),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path == "/" || url.path.isEmpty,
              !endpoint.apiToken.isEmpty else { throw DesktopViewerError.invalidEndpoint }
    }

    private func startStream() {
        streamStartedAt = Date()
        let attempt = connectionAttempt
        let delegate = MJPEGStreamDelegate { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self, self.active, self.connectionAttempt == attempt,
                      let image = NSImage(data: data) else { return }
                self.frame = image
                self.lastFrameAt = Date()
                self.state = .live
            }
        } onEnd: { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.connectionAttempt == attempt else { return }
                self.streamEnded(message)
            }
        }
        streamDelegate = delegate
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("v1/stream"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("Bearer \(endpoint.apiToken)", forHTTPHeaderField: "Authorization")
        task = session.dataTask(with: request)
        task?.resume()
        monitor = Task { [weak self] in
            while let self, self.active, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard self.active else { break }
                let frameReference = self.lastFrameAt ?? self.streamStartedAt
                if let last = frameReference, Date().timeIntervalSince(last) > 4 {
                    self.state = .delayed
                    if let grant = self.humanGrant {
                        self.humanGrant = nil
                        await self.control?.streamDisconnected(grant)
                    }
                }
            }
        }
    }

    private func streamEnded(_ message: String) {
        guard active else { return }
        stopStream()
        state = .unavailable(message)
        if let grant = humanGrant {
            humanGrant = nil
            Task { await control?.streamDisconnected(grant) }
        }
    }

    private func stopStream() {
        monitor?.cancel(); monitor = nil
        task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
        streamDelegate = nil
        lastFrameAt = nil
        streamStartedAt = nil
    }
}

private enum DesktopViewerError: LocalizedError {
    case invalidEndpoint, healthUnavailable, identityChanged, desktopUnavailable, invalidGrant
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "O endpoint do desktop não é um endereço loopback válido."
        case .healthUnavailable: return "O health do desktop não respondeu corretamente."
        case .identityChanged: return "O computador ou sua geração mudou. Reabra o viewer."
        case .desktopUnavailable: return "Desktop completo indisponível; esta box pode estar em modo HTTP ou headless."
        case .invalidGrant: return "O broker não confirmou um lease humano de input para este computador."
        }
    }
}

/// CFNetwork first delivers the multipart response, then a response for every JPEG part.
/// Only accept parts after the authenticated full-desktop stream header was validated.
struct DesktopStreamResponseValidator {
    private var acceptedStream = false
    mutating func accepts(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        let type = http.mimeType?.lowercased()
        if !acceptedStream {
            guard type == "multipart/x-mixed-replace",
                  http.value(forHTTPHeaderField: "X-Racky-Frame-Source") == "desktop" else { return false }
            acceptedStream = true
            return true
        }
        return type == "image/jpeg"
    }
}

private final class MJPEGStreamDelegate: NSObject, URLSessionDataDelegate {
    private let onFrame: (Data) -> Void
    private let onEnd: (String) -> Void
    private var buffer = Data()
    private var ended = false
    private var responseValidator = DesktopStreamResponseValidator()
    private let startMarker = Data([0xff, 0xd8])
    private let endMarker = Data([0xff, 0xd9])

    init(onFrame: @escaping (Data) -> Void, onEnd: @escaping (String) -> Void) {
        self.onFrame = onFrame; self.onEnd = onEnd
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard responseValidator.accepts(response) else {
            finish("O stream de desktop não retornou MJPEG autenticado.")
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        finish("O endpoint tentou redirecionar o stream.")
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let start = buffer.range(of: startMarker) {
            guard let end = buffer.range(of: endMarker, in: start.lowerBound..<buffer.endIndex) else { break }
            let frame = buffer.subdata(in: start.lowerBound..<end.upperBound)
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
            onFrame(frame)
        }
        if buffer.count > 16_000_000 {
            buffer.removeAll(keepingCapacity: true)
            finish("O frame do desktop excedeu o limite de 16 MB.")
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error?.localizedDescription ?? "O stream de desktop foi encerrado.")
    }

    private func finish(_ message: String) {
        guard !ended else { return }
        ended = true
        onEnd(message)
    }
}

private final class LoopbackRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct DesktopCanvasView: NSViewRepresentable {
    let image: NSImage?
    let pointer: ((DesktopPointerInput) -> Void)?
    let key: ((String) -> Void)?

    func makeNSView(context: Context) -> DesktopCanvas { DesktopCanvas() }
    func updateNSView(_ view: DesktopCanvas, context: Context) {
        view.image = image
        view.pointer = pointer
        view.key = key
        if pointer == nil { view.resetInput() }
        view.needsDisplay = true
    }
}

enum DesktopKeyboardMapping {
    static let specialCodes: Set<UInt16> = [36, 76, 48, 53, 51, 117, 123, 124, 125, 126, 115, 119, 116, 121]
    static func text(for event: NSEvent) -> String? {
        guard !specialCodes.contains(event.keyCode),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let text = event.characters, !text.isEmpty else { return nil }
        // Shift and the keyboard layout are already represented in `characters`.
        return text
    }
}

private final class DesktopCanvas: NSView {
    var image: NSImage?
    var pointer: ((DesktopPointerInput) -> Void)?
    var key: ((String) -> Void)?
    private var capturedButton: Int?
    override var acceptsFirstResponder: Bool { key != nil }

    func resetInput() { capturedButton = nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 39/255, green: 43/255, blue: 51/255, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        image.draw(in: imageRect(for: image))
    }

    override func mouseDown(with event: NSEvent) { mouseButton(event, button: 0, pressed: true) }
    override func mouseUp(with event: NSEvent) { mouseButton(event, button: 0, pressed: false) }
    override func rightMouseDown(with event: NSEvent) { mouseButton(event, button: 2, pressed: true) }
    override func rightMouseUp(with event: NSEvent) { mouseButton(event, button: 2, pressed: false) }
    override func otherMouseDown(with event: NSEvent) { mouseButton(event, button: 1, pressed: true) }
    override func otherMouseUp(with event: NSEvent) { mouseButton(event, button: 1, pressed: false) }
    override func mouseDragged(with event: NSEvent) { move(event, clamped: true) }
    override func rightMouseDragged(with event: NSEvent) { move(event, clamped: true) }
    override func otherMouseDragged(with event: NSEvent) { move(event, clamped: true) }

    override func scrollWheel(with event: NSEvent) {
        guard pointer != nil, normalizedPoint(event, clamped: false) != nil else { return }
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(delta) >= 0.5 else { return }
        let vertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
        let direction = vertical ? (delta > 0 ? "up" : "down") : (delta > 0 ? "left" : "right")
        let clicks = min(20, max(1, Int(ceil(abs(delta) / (event.hasPreciseScrollingDeltas ? 8 : 1)))))
        pointer?(.scroll(direction: direction, clicks: clicks))
    }

    override func keyDown(with event: NSEvent) {
        guard let key else { return }
        if let text = DesktopKeyboardMapping.text(for: event) { key(text); return }
        let name: String
        switch event.keyCode {
        case 36, 76: name = "Return"
        case 48: name = "Tab"
        case 53: name = "Escape"
        case 51: name = "BackSpace"
        case 117: name = "Delete"
        case 123: name = "Left"
        case 124: name = "Right"
        case 125: name = "Down"
        case 126: name = "Up"
        case 115: name = "Home"
        case 119: name = "End"
        case 116: name = "Prior"
        case 121: name = "Next"
        default: name = event.charactersIgnoringModifiers ?? ""
        }
        guard !name.isEmpty else { return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags.isEmpty {
            if name == (event.charactersIgnoringModifiers ?? ""), let characters = event.characters, !characters.isEmpty {
                key(characters)
            } else { key(name) }
            return
        }
        var modifiers: [String] = []
        if flags.contains(.command) || flags.contains(.control) { modifiers.append("ctrl") }
        if flags.contains(.option) { modifiers.append("alt") }
        if flags.contains(.shift) { modifiers.append("shift") }
        let keyName: String
        switch name.lowercased() {
        case " ": keyName = "space"
        case "-": keyName = "minus"
        case "=": keyName = "equal"
        case "[": keyName = "bracketleft"
        case "]": keyName = "bracketright"
        case ";": keyName = "semicolon"
        case "'": keyName = "apostrophe"
        case "`": keyName = "grave"
        case ",": keyName = "comma"
        case ".": keyName = "period"
        case "/": keyName = "slash"
        case "\\": keyName = "backslash"
        default: keyName = DesktopKeyboardMapping.specialCodes.contains(event.keyCode) ? name : name.lowercased()
        }
        guard keyName.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }) else { return }
        key((modifiers + [keyName]).joined(separator: "+"))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard key != nil, window?.firstResponder === self, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    private func imageRect(for image: NSImage) -> NSRect {
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func normalizedPoint(_ event: NSEvent, clamped: Bool) -> (Double, Double)? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let rect = imageRect(for: image)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let location = convert(event.locationInWindow, from: nil)
        guard clamped || rect.contains(location) else { return nil }
        let x = min(1, max(0, (location.x - rect.minX) / rect.width))
        let y = min(1, max(0, 1 - (location.y - rect.minY) / rect.height))
        return (Double(x), Double(y))
    }

    private func mouseButton(_ event: NSEvent, button: Int, pressed: Bool) {
        guard let pointer else { capturedButton = nil; return }
        if pressed {
            guard capturedButton == nil, let (x, y) = normalizedPoint(event, clamped: false) else { return }
            capturedButton = button
            window?.makeFirstResponder(self)
            pointer(.button(x: x, y: y, button: button, pressed: true))
        } else {
            guard capturedButton == button else { return }
            capturedButton = nil
            if let (x, y) = normalizedPoint(event, clamped: true) {
                pointer(.button(x: x, y: y, button: button, pressed: false))
            }
        }
    }

    private func move(_ event: NSEvent, clamped: Bool) {
        guard let pointer, let (x, y) = normalizedPoint(event, clamped: clamped) else { return }
        pointer(.move(x: x, y: y))
    }
}

@MainActor struct RemoteDesktopView: View {
    @StateObject private var model: RemoteDesktopModel
    private let control: RemoteDesktopControlActions?

    init(endpoint: BrowserRuntimeEndpoint, control: RemoteDesktopControlActions? = nil) {
        _model = StateObject(wrappedValue: RemoteDesktopModel(endpoint: endpoint, control: control))
        self.control = control
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Desktop completo").font(.system(size: 13, weight: .medium))
                Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if control != nil {
                    if model.humanGrant == nil {
                        Button("Assumir") { Task { await model.assume() } }.disabled(model.state != .live)
                    } else {
                        Button("Devolver") { Task { await model.release() } }
                    }
                }
                Button("Reconectar") { Task { await model.connect() } }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 38)
            if let error = model.controlError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).padding(8)
            }
            ZStack {
                DesktopCanvasView(image: model.frame,
                                  pointer: model.canInput ? { model.sendPointer($0) } : nil,
                                  key: model.canInput ? { model.sendKey($0) } : nil)
                if model.frame == nil {
                    Text(statusText).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Viewer do desktop Linux. Fechar esta janela para apenas a transmissão; a box continua em execução.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(minWidth: 640, minHeight: 430)
        .task { await model.connect() }
        .onDisappear { model.disconnect() }
    }

    private var statusText: String {
        switch model.state {
        case .connecting: return "Conectando…"
        case .reconnecting: return "Reconectando…"
        case .live: return model.humanGrant == nil ? "Ao vivo · somente leitura" : "Ao vivo · controle humano"
        case .delayed: return "Stream atrasado · input suspenso"
        case .disconnected: return "Desconectado"
        case .unavailable(let reason): return reason
        }
    }
}
