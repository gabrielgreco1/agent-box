import AgentBoxCore
import AgentBoxProtocol
import AppKit

/// Item da barra de menus (03 §17, 06 §1.9): contagem de agentes vivos, "Open Agent Box", "Stop All Agents…" e
/// "Quit Agent Box Completely". Servido pelo próprio processo do app (sem helper de login, R1 D-03). `NSStatusItem` porque
/// a casca é AppKit puro (00 T5). Os itens disparam ações do registro, as mesmas de `ctl`.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let registry: ActionRegistry
    private var statusItem: NSStatusItem?
    public private(set) var state = MenuBarState()

    public init(registry: ActionRegistry) {
        self.registry = registry
        super.init()
    }

    /// Texto do botão (número ao lado do ícone). Exposto para testes.
    public var buttonTitle: String { state.badgeTitle }
    public var isInstalled: Bool { statusItem != nil }

    public func update(_ newState: MenuBarState) {
        state = newState
        if newState.isVisible {
            install()
            refreshButton()
        } else {
            remove()
        }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.icon
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityIdentifier(A11yID.menuBarIcon.rawValue)
        item.button?.setAccessibilityLabel(String(localized: "Agent Box", bundle: .module))
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    private func remove() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    private func refreshButton() {
        guard let button = statusItem?.button else { return }
        let title = state.badgeTitle
        button.title = title.isEmpty ? "" : " " + title
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.setAccessibilityValue(state.headerText)
    }

    private static var icon: NSImage? {
        let image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    // MARK: Menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem.sectionHeader(title: state.headerText)
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Open Agent Box", bundle: .module), .appOpenMainWindow, .menuBarOpen))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Stop All Agents…", bundle: .module), .appStopAllAgents, .menuBarStopAll))
        menu.addItem(item(String(localized: "Quit Agent Box Completely", bundle: .module), .appQuitCompletely, .menuBarQuitCompletely))
    }

    /// Cada item dispara a ação do registro (as mesmas de `ctl ui action`); o estado vem de `availability`.
    private func item(_ title: String, _ action: ActionID, _ id: A11yID) -> NSMenuItem {
        let entry = ActionMenuItem(action, title: title, key: "", modifiers: [], registry: registry)
        entry.setAccessibilityIdentifier(id.rawValue)
        return entry
    }
}
