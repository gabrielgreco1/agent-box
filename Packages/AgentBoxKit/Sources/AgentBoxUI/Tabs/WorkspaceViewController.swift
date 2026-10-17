import AgentBoxDesignSystem
import AgentBoxProtocol
import AppKit
import SwiftUI

/// Raiz do centro da janela: landing (sem sessão selecionada) ou tab row (36) + área de panes.
@MainActor
final class WorkspaceRootView: NSView {
    let landing: NSView
    let tabRow: NSView
    let area: PaneAreaView

    override var isFlipped: Bool { true }

    init(landing: NSView, tabRow: NSView, area: PaneAreaView) {
        self.landing = landing
        self.tabRow = tabRow
        self.area = area
        super.init(frame: .zero)
        setWorkspaceVisible(false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    /// Troca landing e workspace tirando a outra parte da hierarquia: controles ocultos não ficam em `ctl ui tree`.
    func setWorkspaceVisible(_ visible: Bool) {
        if visible {
            landing.removeFromSuperview()
            if area.superview == nil { addSubview(area) }
            if tabRow.superview == nil { addSubview(tabRow) }
        } else {
            area.removeFromSuperview()
            tabRow.removeFromSuperview()
            if landing.superview == nil { addSubview(landing) }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        landing.frame = bounds
        tabRow.frame = NSRect(x: 0, y: 0, width: bounds.width, height: TabMetrics.chromeHeight)
        area.frame = NSRect(x: 0, y: TabMetrics.chromeHeight, width: bounds.width, height: max(0, bounds.height - TabMetrics.chromeHeight))
    }
}

/// Centro da janela (T1-14): tab row e árvore de panes da sessão selecionada, ligadas ao `WorkspaceModel`.
@MainActor
final class WorkspaceViewController: NSViewController {
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
        super.init(nibName: nil, bundle: nil)
        let blocked: () -> Bool = { [overlays = env.overlays] in overlays.blocksTerminalInput }
        let landing = ChromeHostingView(
            content: LandingView(automationOn: env.automationEnabled).environment(\.elementStore, env.elements)
                .environment(\.actionRegistry, env.registry).environment(\.a11yParent, .windowMain))
        landing.inputBlocked = blocked
        let tabRow = ChromeHostingView(
            content: TabRowView(model: env.workspace).environment(\.elementStore, env.elements)
                .environment(\.actionRegistry, env.registry).environment(\.a11yParent, .windowMain))
        tabRow.inputBlocked = blocked
        let area = PaneAreaView(model: env.workspace, registry: env.registry, elements: env.elements, router: env.terminalRouter)
        let root = WorkspaceRootView(landing: landing, tabRow: tabRow, area: area)
        view = root
        root.setWorkspaceVisible(env.workspace.currentSessionID != nil)
        env.workspace.addListener { [weak root, weak env] in
            guard let root, let env else { return }
            root.setWorkspaceVisible(env.workspace.currentSessionID != nil)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado
}
