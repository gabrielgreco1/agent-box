import AgentBoxDesignSystem
import AgentBoxPlatform
import AgentBoxProtocol
import AppKit
import SwiftUI

/// Contêiner do conteúdo: o split ocupa a janela inteira e a faixa de 36 pt flutua por cima
/// (largura da sidebar quando aberta; largura do próprio conteúdo quando recolhida, 03 §1.3).
@MainActor
final class ChromeContainerView: NSView {
    let strip: NSView
    let split: NSView
    /// Overlays e toasts: acima de tudo, cobrindo a janela inteira (02 §12.17).
    let overlay: NSView
    /// Settings em página inteira (03 §14): cobre sidebar, centro e painel; a faixa da titlebar fica por cima.
    let settings: NSView
    var stripWidth: () -> CGFloat = { 0 }

    init(split: NSView, strip: NSView, overlay: NSView, settings: NSView) {
        self.split = split
        self.strip = strip
        self.overlay = overlay
        self.settings = settings
        super.init(frame: .zero)
        settings.isHidden = true
        addSubview(split)
        addSubview(settings)
        addSubview(strip)
        addSubview(overlay)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        split.frame = bounds
        settings.frame = bounds
        overlay.frame = bounds
        let h = DS.Layout.titlebarHeight
        strip.frame = NSRect(x: 0, y: bounds.height - h, width: min(stripWidth(), bounds.width), height: h)
    }
}

/// Janela principal: tecla que chega e nenhum responder aceita (first responder preso na chrome, view oculta) vai para
/// `onUnhandledKey`, que devolve o foco ao terminal e reenvia (watchdog de digitação).
final class AgentBoxWindow: NSWindow {
    var onUnhandledKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if let onUnhandledKey, onUnhandledKey(event) { return }
        super.keyDown(with: event)
    }
}

/// Janela principal (03 §1.1, 00 T5): `fullSizeContentView`, titlebar transparente, sem `NSToolbar`,
/// semáforos nativos reposicionados, mínimo 760×480, inicial 1440×900.
@MainActor
public final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let env: AppEnvironment
    private let split: MainSplitViewController
    private let container: ChromeContainerView
    private let strip: ChromeHostingView
    private let overlayHost: OverlayHostingView
    private let settingsHost: ChromeHostingView
    private let overlayFocus = OverlayFocusCoordinator()
    private var positioner: TrafficLightPositioner?
    private var observers: [any NSObjectProtocol] = []
    private let mainToken = UUID()

    /// `autosaveName` é `nil` nos testes (não lê nem grava o frame do usuário).
    public init(env: AppEnvironment, autosaveName: String? = "workspace") {
        self.env = env
        split = MainSplitViewController(env: env)
        let strip = ChromeHostingView(
            content: TitlebarStrip(env: env).environment(\.elementStore, env.elements).environment(\.a11yParent, .windowMain))
        strip.inputBlocked = { [overlays = env.overlays] in overlays.blocksTerminalInput }
        self.strip = strip
        let overlayHost = OverlayHostingView(router: env.overlays, toasts: env.toasts, registry: env.registry, elements: env.elements)
        self.overlayHost = overlayHost
        let settingsHost = ChromeHostingView(
            content: SettingsView(model: env.settings).environment(\.elementStore, env.elements).environment(\.actionRegistry, env.registry)
                .environment(\.overlayRouter, env.overlays).environment(\.a11yParent, .windowMain))
        settingsHost.inputBlocked = { [overlays = env.overlays] in overlays.blocksTerminalInput }
        self.settingsHost = settingsHost
        container = ChromeContainerView(split: split.view, strip: strip, overlay: overlayHost, settings: settingsHost)

        let window = AgentBoxWindow(
            contentRect: NSRect(x: 0, y: 0, width: DS.Layout.windowDefaultWidth, height: DS.Layout.windowDefaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil
        window.isMovableByWindowBackground = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = DS.ColorSpec.canvas.nsColor
        window.contentMinSize = NSSize(width: DS.Layout.windowMinWidth, height: DS.Layout.windowMinHeight)
        window.title = "Agent Box"
        window.contentView = container
        window.contentViewController = nil
        super.init(window: window)
        window.delegate = self
        window.onUnhandledKey = { [weak self] event in self?.recoverTypingFocus(for: event) ?? false }

        container.stripWidth = { [weak self] in self?.currentStripWidth() ?? 0 }
        window.center()
        if let autosaveName { window.setFrameAutosaveName(autosaveName) }
        positioner = TrafficLightPositioner(window: window)
        env.elements.window = window
        overlayFocus.window = window
        overlayFocus.hostView = overlayHost
        env.overlays.focus = overlayFocus
        overlayFocus.fallbackFocus = { [weak env] in env?.workspace.focusTerminalOfActiveTab() }
        env.elements.register(mainToken, id: .windowMain, kind: "window", label: "Agent Box", value: nil, action: nil, parent: nil)
        registerActions()
        observeSettings()
        observeLayout()
        window.layoutIfNeeded()
        container.needsLayout = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private let focusLog = LogFacade(.app, category: "focus")

    /// Watchdog: `keyDown` chegou à janela sem que nenhum responder o tratasse. Sem overlay e sem Settings, o terminal do
    /// pane focado recebe o foco e a tecla. Devolve `true` se a tecla foi reenviada.
    func recoverTypingFocus(for event: NSEvent) -> Bool {
        let responder = window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let blocked = env.overlays.blocksTerminalInput
        let settingsOpen = !settingsHost.isHidden
        guard !event.modifierFlags.contains(.command), !blocked, !settingsOpen, let host = env.workspace.focusedHost() else {
            focusLog.publicError("keyDown reached the window but no terminal accepts it")
            focusLog.error("responder=\(responder) overlayBlocks=\(blocked) settingsOpen=\(settingsOpen)")
            return false
        }
        focusLog.publicError("keyDown reached the window unhandled; refocusing the terminal")
        focusLog.error("responder=\(responder)")
        host.focusTerminal()
        guard window?.firstResponder === host.surface else { return false }
        host.surface.keyDown(with: event)
        return true
    }

    /// Abre sem ativar o app (o chamador decide se traz para frente).
    /// Testes desligam: a janela nunca é ordenada para a frente (o AppKit puxaria uma janela titulada para dentro da tela).
    public var orderingEnabled = true

    public func present(activate: Bool) {
        guard let window else { return }
        guard orderingEnabled else {
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            positioner?.apply()
            updateMainFrame()
            return
        }
        if activate {
            showWindow(nil)
            NSApp.activate()
        } else {
            // Sem ativar (open -g, automação): sem a animação de entrada, que congela no meio com o app em segundo plano.
            window.animationBehavior = .none
            window.orderFront(nil)
        }
        positioner?.apply()
        updateMainFrame()
    }

    /// Keep Running: esconde a janela sem destruir as views de terminal (reabrir volta já anexada).
    public func hide() {
        window?.orderOut(nil)
    }

    /// Settings abre por cima da sidebar e do centro (03 §14): o split some enquanto a página está aberta e o foco vai para ela.
    private func observeSettings() {
        let previous = env.settings.onPresentationChange
        env.settings.onPresentationChange = { [weak self] open in
            previous(open)
            guard let self else { return }
            self.split.view.isHidden = open
            self.settingsHost.isHidden = !open
            self.container.needsLayout = true
            if open {
                self.window?.makeFirstResponder(self.settingsHost)
            } else {
                self.env.workspace.focusTerminalOfActiveTab()
            }
        }
    }

    private func currentStripWidth() -> CGFloat {
        env.shell.sidebarCollapsed ? strip.fittingSize.width : split.sidebarWidth
    }

    private func registerActions() {
        do {
            try env.registry.register(.viewToggleSidebar) { [weak self] _ in
                guard let self else { return nil }
                self.setSidebarCollapsed(!self.env.shell.sidebarCollapsed)
                return self.env.shell.sidebarCollapsed ? "collapsed" : "expanded"
            }
        } catch {
            // Já registrada (outra janela): nada a fazer.
        }
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        env.shell.sidebarCollapsed = collapsed
        split.setSidebarCollapsed(collapsed)
        // O SwiftUI da faixa troca de modo no próximo ciclo; refaz o layout depois.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            self.container.needsLayout = true
        }
    }

    private func observeLayout() {
        let center = NotificationCenter.default
        let view = split.sidebarItem.viewController.view
        view.postsFrameChangedNotifications = true
        observers.append(
            center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.container.needsLayout = true
                    self?.container.layoutSubtreeIfNeeded()
                }
            })
    }

    private func updateMainFrame() {
        guard let content = window?.contentView else { return }
        env.elements.updateFrame(mainToken, CGRect(origin: .zero, size: content.bounds.size))
    }

    // MARK: NSWindowDelegate

    /// Voltou de um NSOpenPanel, sheet ou outro app: o foco volta ao terminal, salvo overlay, Settings ou campo de texto.
    public func windowDidBecomeKey(_ notification: Notification) {
        restoreTerminalFocusIfLost()
    }

    public func windowDidResignKey(_ notification: Notification) {
        TooltipController.shared.dismiss(animated: false)
    }

    func restoreTerminalFocusIfLost() {
        guard let window, !env.overlays.blocksTerminalInput, settingsHost.isHidden else { return }
        let responder = window.firstResponder
        if responder is NSText { return }
        if let host = env.workspace.focusedHost(), responder !== host.surface { host.focusTerminal() }
    }

    public func windowDidResize(_ notification: Notification) {
        positioner?.apply()
        updateMainFrame()
        container.needsLayout = true
    }

    public func windowDidEnterFullScreen(_ notification: Notification) { env.shell.isFullScreen = true }
    public func windowDidExitFullScreen(_ notification: Notification) {
        env.shell.isFullScreen = false
        positioner?.apply()
    }
    public func windowDidChangeScreen(_ notification: Notification) { positioner?.apply() }
    public func windowDidChangeBackingProperties(_ notification: Notification) { positioner?.apply() }
}
