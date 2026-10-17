import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxTerminalCore
import AppKit
import Foundation
import Synchronization
import SwiftTerm

/// `TerminalView` do SwiftTerm 1.99 com as regras do app (00 T6, 08 AR-105/AR-520/AR-708). Nunca
/// `LocalProcessTerminalView`: o PTY é do daemon, os bytes chegam por `feed` fora do main e o que o usuário digita sai
/// por `outputSink` com a origem marcada (06 §1.3).
///
/// Quem escreve no PTY, por origem (08 AR-105):
/// - teclado e mouse (main thread): `.key`; colagem (`pasteUser`): `.userPaste`.
/// - respostas do emulador a consultas do programa (DA, DSR, tamanho): `.terminalReply`. O parse roda fora do main,
///   então qualquer `send(source:)` chamado fora do main é resposta; elas passam por `UIReplyFilter` (OSC 52 nunca) e
///   ficam caladas durante o replay de um `snapshot` (consultas antigas do ring não podem ser respondidas de novo).
public final class TerminalSurfaceView: TerminalView {
    public typealias OutputSink = @Sendable ([UInt8], InputOrigin) -> Void

    private struct Routing {
        var sink: OutputSink?
        var replaying = false
        var userPasteOrigin: InputOrigin?
    }

    nonisolated private let routing = Mutex(Routing())
    /// Delegado forte: `TerminalView.terminalDelegate` é `weak`.
    private let surfaceDelegate = SurfaceDelegate()
    private let log = LogFacade(.app, category: "terminal")
    /// `true` se o renderer Metal subiu (AR-708); `false` registra o fallback para CoreGraphics.
    public private(set) var metalEnabled = false

    public init(appearance: TerminalAppearance = TerminalAppearance()) {
        let options = TerminalOptions(cols: 80, rows: 25, cursorStyle: .blinkBlock, scrollback: appearance.scrollback)
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 400), font: appearance.font, options: options)
        terminalDelegate = surfaceDelegate
        surfaceDelegate.surface = self
        TerminalTheme.apply(to: self, appearance: appearance)
        linkReporting = .implicit
        linkHighlightMode = .hoverWithModifier
        do {
            try setUseMetal(true)
            metalEnabled = isUsingMetalRenderer
        } catch {
            log.error("Metal unavailable, using CoreGraphics: \(error)")
        }
        if !metalEnabled { log.publicError("terminal renderer fell back to CoreGraphics") }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    /// Menu de contexto do terminal (03 §4.5): construído por quem hospeda o pane (o menu depende do estado do pane).
    public var contextMenuProvider: (() -> NSMenu?)?

    public override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?() ?? super.menu(for: event)
    }

    // MARK: Saída para o PTY

    /// Quem recebe o que a view quer escrever no PTY. Pode ser chamado de qualquer thread; ordem preservada pelo sink.
    public func setOutputSink(_ sink: OutputSink?) {
        routing.withLock { $0.sink = sink }
    }

    /// Replay de snapshot em andamento: as respostas do emulador ficam caladas (a thread de parse liga e desliga).
    public nonisolated func setReplaying(_ replaying: Bool) {
        routing.withLock { $0.replaying = replaying }
    }

    nonisolated var isReplaying: Bool { routing.withLock { $0.replaying } }

    /// Respostas do emulador (parse fora do main) e eventos gerados no main thread dentro do lock do terminal
    /// (colagem, mouse). Não passa por `onMain` como o `TerminalView` faz: o sink só enfileira.
    nonisolated public override func send(source: SwiftTerm.Terminal, data: ArraySlice<UInt8>) {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return }
        if Thread.isMainThread {
            let (sink, origin) = routing.withLock { ($0.sink, $0.userPasteOrigin ?? .key) }
            sink?(bytes, origin)
            return
        }
        let (sink, replaying) = routing.withLock { ($0.sink, $0.replaying) }
        guard !replaying, UIReplyFilter.allows(bytes) else { return }
        sink?(bytes, .terminalReply)
    }

    /// Input do `TerminalView` (teclado, IME, `send(data:)`): sempre `.key`.
    fileprivate func routeKeyboardInput(_ bytes: [UInt8]) {
        let sink = routing.withLock { $0.sink }
        sink?(bytes, .key)
    }

    // MARK: Colar

    /// Cola texto do usuário (⌘V, arrastar): sanitiza (ESC e controles C0/C1 saem, 08 A3), aplica bracketed paste
    /// se o programa o ligou e envia com a origem `.userPaste`.
    public func pasteUser(_ text: String, origin: InputOrigin = .userPaste) {
        routing.withLock { $0.userPasteOrigin = origin }
        defer { routing.withLock { $0.userPasteOrigin = nil } }
        pasteText(PasteSanitizer.sanitize(text))
    }

    public func pasteUser(from pasteboard: NSPasteboard) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        pasteUser(text)
    }

    public override func paste(_ sender: Any) {
        pasteUser(from: .general)
    }

    /// Ativa um link (⌘-clique): só passa o que `TerminalLinkPolicy` aceita.
    func activateLink(_ link: String) {
        guard let url = TerminalLinkPolicy.openableURL(link) else { return }
        surfaceDelegate.openURL(url)
    }

    // MARK: Callbacks de interface

    public var onResize: ((_ cols: Int, _ rows: Int) -> Void)? {
        get { surfaceDelegate.onResize }
        set { surfaceDelegate.onResize = newValue }
    }
    public var onTitle: ((String) -> Void)? {
        get { surfaceDelegate.onTitle }
        set { surfaceDelegate.onTitle = newValue }
    }
    public var onCwd: ((String?) -> Void)? {
        get { surfaceDelegate.onCwd }
        set { surfaceDelegate.onCwd = newValue }
    }
    public var onBell: (() -> Void)? {
        get { surfaceDelegate.onBell }
        set { surfaceDelegate.onBell = newValue }
    }
    /// OSC 52 de escrita (programas escrevem no clipboard). Ligado por padrão (02 §3); o aviso é do chamador.
    public var osc52WriteEnabled: Bool {
        get { surfaceDelegate.osc52WriteEnabled }
        set { surfaceDelegate.osc52WriteEnabled = newValue }
    }
    public var onClipboardWritten: (() -> Void)? {
        get { surfaceDelegate.onClipboardWritten }
        set { surfaceDelegate.onClipboardWritten = newValue }
    }
    /// Pasteboard alvo do OSC 52 (testes usam um privado).
    public var clipboardPasteboard: NSPasteboard {
        get { surfaceDelegate.pasteboard }
        set { surfaceDelegate.pasteboard = newValue }
    }
    /// Abre o link (⌘-clique); padrão: `NSWorkspace`. Só chega aqui o que passou por `TerminalLinkPolicy`.
    public var openURL: (URL) -> Void {
        get { surfaceDelegate.openURL }
        set { surfaceDelegate.openURL = newValue }
    }
    /// Contagem de pedidos de leitura de clipboard recusados (T6; evidência de teste).
    public var clipboardReadRefusals: Int { surfaceDelegate.clipboardReadRefusals }
}

/// Delegado da view: o único ponto onde a decisão de política (T6) acontece.
@MainActor
private final class SurfaceDelegate: TerminalViewDelegate {
    weak var surface: TerminalSurfaceView?
    var onResize: ((Int, Int) -> Void)?
    var onTitle: ((String) -> Void)?
    var onCwd: ((String?) -> Void)?
    var onBell: (() -> Void)?
    var onClipboardWritten: (() -> Void)?
    var osc52WriteEnabled = true
    var pasteboard = NSPasteboard.general
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private(set) var clipboardReadRefusals = 0

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { onResize?(newCols, newRows) }
    func setTerminalTitle(source: TerminalView, title: String) { onTitle?(title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { onCwd?(directory) }
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func bell(source: TerminalView) { onBell?() }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        surface?.routeKeyboardInput(Array(data))
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        surface?.activateLink(link)
    }

    /// OSC 52 de escrita: honra o setting. Nada além do texto vai ao pasteboard.
    func clipboardCopy(source: TerminalView, content: Data) {
        guard osc52WriteEnabled, !content.isEmpty, content.count <= 1 << 20 else { return }
        pasteboard.clearContents()
        pasteboard.setString(String(decoding: content, as: UTF8.self), forType: .string)
        onClipboardWritten?()
    }

    /// T6, AR-520: nunca devolve o clipboard a um programa do terminal.
    func clipboardRead(source: TerminalView) -> Data? {
        clipboardReadRefusals += 1
        return nil
    }
}
