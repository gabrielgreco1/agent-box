import AgentBoxDesignSystem
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
    var stripWidth: () -> CGFloat = { 0 }

    init(split: NSView, strip: NSView, overlay: NSView) {
        self.split = split
        self.strip = strip
        self.overlay = overlay
        super.init(frame: .zero)
        addSubview(split)
        addSubview(strip)
        addSubview(overlay)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        split.frame = bounds
        overlay.frame = bounds
        let h = DS.Layout.titlebarHeight
        strip.frame = NSRect(x: 0, y: bounds.height - h, width: min(stripWidth(), bounds.width), height: h)
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
        container = ChromeContainerView(split: split.view, strip: strip, overlay: overlayHost)

        let window = NSWindow(
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

        container.stripWidth = { [weak self] in self?.currentStripWidth() ?? 0 }
        window.center()
        if let autosaveName { window.setFrameAutosaveName(autosaveName) }
        positioner = TrafficLightPositioner(window: window)
        env.elements.window = window
        overlayFocus.window = window
        overlayFocus.hostView = overlayHost
        env.overlays.focus = overlayFocus
        env.elements.register(mainToken, id: .windowMain, kind: "window", label: "Agent Box", value: nil, action: nil, parent: nil)
        registerActions()
        observeLayout()
        window.layoutIfNeeded()
        container.needsLayout = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Abre sem ativar o app (o chamador decide se traz para frente).
    public func present(activate: Bool) {
        guard let window else { return }
        if activate {
            showWindow(nil)
            NSApp.activate()
        } else {
            window.orderFront(nil)
        }
        positioner?.apply()
        updateMainFrame()
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
