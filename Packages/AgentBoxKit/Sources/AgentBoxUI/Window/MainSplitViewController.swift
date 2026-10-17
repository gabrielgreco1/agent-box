import AgentBoxDesignSystem
import AgentBoxProtocol
import AppKit
import SwiftUI

/// Divisor com a cor de borda do DS (1 pt), no lugar do divisor padrão do sistema.
final class ChromeSplitView: NSSplitView {
    override var dividerColor: NSColor { DS.ColorSpec.border.nsColor }
    override var dividerThickness: CGFloat { 1 }
}

/// Hosting view sem safe area: a faixa e o conteúdo desenham sob a titlebar (`fullSizeContentView`).
final class ChromeHostingView: NSHostingView<AnyView> {
    /// Enquanto há overlay, estas views recusam o foco: Tab e cliques ficam dentro do overlay (02 §12.17).
    var inputBlocked: () -> Bool = { false }

    override var acceptsFirstResponder: Bool { inputBlocked() ? false : super.acceptsFirstResponder }

    init(content: some View) {
        super.init(rootView: AnyView(content))
        safeAreaRegions = []
    }

    @MainActor @preconcurrency required init(rootView: AnyView) { super.init(rootView: rootView) }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Sidebar (T1-13) e centro (landing mínima). Sidebar 280 (220–500), recolhível (⌘B). Painel direito oculto.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    private let env: AppEnvironment
    let sidebarItem: NSSplitViewItem
    let contentItem: NSSplitViewItem
    /// Painel direito (03 §10): nasce recolhido; ⇧⌘C abre a aba Computers (T3-05).
    let rightItem: NSSplitViewItem
    private var didSetInitialWidth = false

    init(env: AppEnvironment) {
        self.env = env
        let sidebarVC = NSViewController()
        let sidebarView = ChromeHostingView(
            content: SidebarView(model: env.sidebar).environment(\.elementStore, env.elements).environment(\.actionRegistry, env.registry)
                .environment(\.subagentHoverCards, env.subagentHoverCards).environment(\.a11yParent, .windowMain))
        sidebarView.inputBlocked = { [overlays = env.overlays] in overlays.blocksTerminalInput }
        sidebarVC.view = sidebarView
        let contentVC: NSViewController
        if env.fixture == "terminal-demo" {
            // Tela de dev da T1-09 (um pane de terminal real, fora do workspace).
            contentVC = TerminalDemoViewController(env: env)
        } else {
            contentVC = WorkspaceViewController(env: env)
        }
        let rightVC = NSViewController()
        let rightView = ChromeHostingView(
            content: ComputersPanelView(controller: env.computers).environment(\.elementStore, env.elements).environment(\.actionRegistry, env.registry)
                .environment(\.a11yParent, .windowMain))
        rightView.inputBlocked = { [overlays = env.overlays] in overlays.blocksTerminalInput }
        rightVC.view = rightView
        sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        contentItem = NSSplitViewItem(viewController: contentVC)
        rightItem = NSSplitViewItem(viewController: rightVC)
        super.init(nibName: nil, bundle: nil)
        let split = ChromeSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        splitView = split
        sidebarItem.minimumThickness = DS.Layout.sidebarMinWidth
        sidebarItem.maximumThickness = DS.Layout.sidebarMaxWidth
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1)
        contentItem.minimumThickness = DS.Layout.windowMinWidth - DS.Layout.sidebarMaxWidth
        rightItem.minimumThickness = DS.Layout.rightPanelMinWidth
        rightItem.maximumThickness = DS.Layout.rightPanelMaxWidth
        rightItem.canCollapse = true
        rightItem.isCollapsed = true
        rightItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1)
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(rightItem)
        split.autosaveName = nil
        env.computers.onPanelChange = { [weak self] open in self?.setRightPanelOpen(open) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var sidebarWidth: CGFloat { sidebarItem.isCollapsed ? 0 : sidebarItem.viewController.view.frame.width }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !didSetInitialWidth, splitView.bounds.width > 0 {
            didSetInitialWidth = true
            splitView.setPosition(DS.Layout.sidebarWidth, ofDividerAt: 0)
        }
    }

    func setRightPanelOpen(_ open: Bool) {
        guard rightItem.isCollapsed == open else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            rightItem.isCollapsed = !open
        } else {
            rightItem.animator().isCollapsed = !open
        }
        if open {
            splitView.setPosition(max(0, splitView.bounds.width - DS.Layout.rightPanelWidth), ofDividerAt: 1)
        }
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        guard sidebarItem.isCollapsed != collapsed else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            sidebarItem.isCollapsed = collapsed
        } else {
            sidebarItem.animator().isCollapsed = collapsed
        }
    }
}

/// Centro vazio: landing mínima (03 §19). Só `Add Project…` por enquanto (T1-19); os demais botões entram com as
/// tarefas dos fluxos que eles abrem (`isOffered`: sem handler registrado, o botão não aparece).
struct LandingView: View {
    let automationOn: Bool
    @Environment(\.actionRegistry) private var registry

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Text("Agent Box", bundle: .module)
                .font(DS.Font.display.font)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Run Claude Code, Codex and OpenCode side by side, each in its own folder.", bundle: .module)
                .font(DS.Font.dialogBody.font)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: DS.Space.s2) {
                if let registry, registry.isOffered(.projectAdd) {
                    DSButton(.projectAdd, id: .landingAddProject, "Add Project…", variant: .primary)
                }
                if let registry, registry.isOffered(.sessionNewClean) {
                    DSButton(.sessionNewClean, id: .landingNewCleanSession, "New Clean Session", variant: .secondary)
                }
            }
            .padding(.top, DS.Space.s4)
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.canvas)
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            // Selo do canal de automação (AR-806): fora da faixa de 280 pt, que não comporta o texto ao lado dos controles.
            if automationOn {
                Text("Automation on", bundle: .module)
                    .font(DS.Font.micro.font)
                    .foregroundStyle(DS.Color.warning)
                    .padding(DS.Space.s2)
                    .a11y(.windowAutomationBadge, kind: "text", label: "Automation on")
            }
        }
        .a11y(.landing, kind: "container")
    }
}
