import AgentBoxCore
import AgentBoxViewerKit
import AppKit
import Foundation
import Observation

/// Medições do viewer dentro do WKWebView (spike S3): quadros por segundo do noVNC e latência de input.
public struct ViewerMeasurement: Codable, Sendable, Equatable {
    public var fpsSamples: [Double] = []
    public var fpsAverage = 0.0
    public var fpsMin = 0.0
    public var latencySamplesMs: [Double] = []
    public var latencyP50Ms = 0.0
    public var latencyP95Ms = 0.0
    public var appActive = false
    public var windowVisible = false
    public var note = ""
}

/// Liga o modelo do viewer ao `WKWebView` (noVNC): pede o ticket, conecta, reconecta com recuo, repassa o lease ao WebView
/// (input só com humano no controle e stream vivo) e traduz os atalhos reservados (⇧⌘R, ⌘⎋, ⌃⌥, ⌘V).
@MainActor
@Observable
public final class ComputerViewerController {
    public let model: ComputerViewerModel
    @ObservationIgnored public let web: ComputerViewerWebView
    public let computer: ManagedComputer
    public private(set) var lastError: String?
    /// Estado das medições do S3 (só com `AGENTBOX_VIEWER_MEASURE`).
    public private(set) var measurement: ViewerMeasurement?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var reconnect: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var fpsHistory: [Double] = []
    @ObservationIgnored public var onClose: () -> Void = {}
    @ObservationIgnored public var onRequestPopOut: () -> Void = {}

    public var name: String { computer.name }

    public init(computer: ManagedComputer) {
        self.computer = computer
        model = ComputerViewerModel(computer: computer)
        web = ComputerViewerWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        web.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: Ciclo de vida

    public func start() async {
        guard !started else { return }
        started = true
        await web.load()
        await model.refresh()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.model.tick()
                await self.model.refresh()
                self.syncInput()
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        reconnect?.cancel()
        web.disconnect()
        started = false
    }

    /// Pede um ticket novo (uso único, 60 s) e conecta. O ticket nunca é reaproveitado numa reconexão.
    public func connect() async {
        guard model.connection != .stopped else { return }
        do {
            let url = try await model.computer.vncEndpoint()
            web.connect(to: url)
            lastError = nil
        } catch {
            lastError = "\(error)"
            model.streamError("\(error)")
        }
    }

    public func reconnectNow() {
        reconnect?.cancel()
        model.reconnectRequested()
        Task { await connect() }
    }

    // MARK: Eventos do WebView

    func handle(_ event: ViewerEvent) {
        switch event {
        case .ready:
            Task { await connect() }
        case .state(let value, let detail):
            model.streamState(value, detail: detail)
            if value == "disconnected", case .reconnecting(let attempt) = model.connection { scheduleReconnect(attempt: attempt) }
            if value == "live" { syncInput() }
        case .stats(let fps, let frames, let silentMs, _):
            model.streamStats(fps: fps, frames: frames, silentMs: silentMs)
            if model.connection == .live { fpsHistory.append(fps) }
        case .keyboard(let captured):
            model.keyboard(captured: captured)
        case .reserved(let action):
            reserved(action)
        case .blockedInput:
            model.blockedClick()
        case .error(let detail):
            model.streamError(detail)
        case .blockedNavigation, .desktopName:
            break
        }
    }

    private func scheduleReconnect(attempt: Int) {
        reconnect?.cancel()
        reconnect = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(min(Double(1 << min(attempt, 3)), 8)))
            guard !Task.isCancelled, let self, case .reconnecting = self.model.connection else { return }
            await self.connect()
        }
    }

    private func reserved(_ action: String) {
        switch action {
        case "handback": Task { await toggleControl() }
        case "release-keyboard": releaseKeyboard()
        case "paste": Task { await pasteFromClipboard() }
        default: break
        }
    }

    /// O WebView só aceita input com humano no controle e stream vivo (CS-402, CS-404).
    func syncInput() {
        web.setInputEnabled(model.inputEnabled)
    }

    // MARK: Ações

    public func takeOver(force: Bool = false) async {
        _ = await model.takeOver(force: force)
        syncInput()
        if model.control == .human { web.focusCanvas() }
    }

    public func toggleControl() async {
        switch model.control {
        case .agent: await takeOver()
        case .human:
            if model.handBackNoteVisible { await handBack() } else { model.showHandBackNote() }
        case .revoking: break
        }
    }

    public func handBack() async {
        await model.handBack()
        web.releaseKeyboard()
        syncInput()
    }

    public func releaseKeyboard() {
        model.releaseKeyboard()
        web.releaseKeyboard()
    }

    /// `Paste to Computer`: ação explícita (⌘V no viewer com controle humano ou o botão). Digita o texto do clipboard no computador.
    @discardableResult
    public func pasteFromClipboard() async -> Int {
        guard model.control == .human, model.inputEnabled, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return 0 }
        return await web.typeText(text)
    }

    /// `Copy Selection from Computer`: só a seleção da página, só por ação explícita.
    @discardableResult
    public func copySelection() async -> Bool {
        guard let out = try? await computer.backend.runtime("selection", [:], timeout: 8), let text = out["text"]?.string, !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    // MARK: Medição (S3)

    /// Mede o fps do noVNC por `seconds` (a página do computador deve estar animando) e a latência de input (a página deve
    /// reagir ao mouse). `prepareLatency` troca a página; o lease humano é pedido aqui.
    public func measure(seconds: Int, prepareLatency: @escaping @MainActor () async -> Void) async -> ViewerMeasurement {
        var result = ViewerMeasurement()
        fpsHistory = []
        for _ in 0..<80 where model.connection != .live { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(2))
        fpsHistory = []
        try? await Task.sleep(for: .seconds(seconds))
        result.fpsSamples = fpsHistory
        result.fpsAverage = fpsHistory.isEmpty ? 0 : fpsHistory.reduce(0, +) / Double(fpsHistory.count)
        result.fpsMin = fpsHistory.min() ?? 0
        await prepareLatency()
        try? await Task.sleep(for: .seconds(1))
        await takeOver()
        try? await Task.sleep(for: .milliseconds(500))
        var samples = await web.probeLatency(count: 40, gapMs: 150)
        samples.sort()
        result.latencySamplesMs = samples
        if !samples.isEmpty {
            result.latencyP50Ms = samples[samples.count / 2]
            result.latencyP95Ms = samples[max(0, Int((Double(samples.count) * 0.95).rounded(.up)) - 1)]
        }
        result.appActive = NSApp.isActive
        result.windowVisible = web.window?.occlusionState.contains(.visible) ?? false
        measurement = result
        return result
    }
}
