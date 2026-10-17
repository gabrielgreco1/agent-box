import AgentBoxProtocol
import AppKit

/// Item de menu que dispara uma ação do registro (08 AR-805): estado e motivo vêm de `availability`.
nonisolated final class ActionMenuItem: NSMenuItem {
    let actionID: ActionID
    private weak var registry: ActionRegistry?

    nonisolated init(_ id: ActionID, title: String, key: String, modifiers: NSEvent.ModifierFlags = [.command], registry: ActionRegistry) {
        actionID = id
        self.registry = registry
        super.init(title: title, action: #selector(fire(_:)), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable) required nonisolated init(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    @objc nonisolated private func fire(_ sender: Any?) {
        guard let registry else { return }
        let id = actionID
        Task { @MainActor in _ = try? await registry.perform(id, .press) }
    }

    nonisolated override var isEnabled: Bool {
        get {
            let registry = self.registry, id = actionID
            return MainActor.assumeIsolated { registry?.availability(of: id).isEnabled ?? false }
        }
        set {}
    }
}

/// Menu principal mínimo da T1-10: Agent Box (Hide App Name, Quit), View (Toggle Sidebar, Back, Forward), Window.
@MainActor
enum MainMenu {
    static func build(registry: ActionRegistry) -> NSMenu {
        let main = NSMenu()
        main.addItem(
            submenu(title: "Agent Box") { m in
                m.addItem(ActionMenuItem(.appHideAppName, title: "Hide App Name", key: "", registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.appQuit, title: "Quit Agent Box", key: "q", registry: registry))
            })
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        main.addItem(
            submenu(title: "View") { m in
                m.addItem(ActionMenuItem(.viewToggleSidebar, title: "Toggle Sidebar", key: "b", registry: registry))
                m.addItem(ActionMenuItem(.navBack, title: "Back", key: left, modifiers: [.option, .command], registry: registry))
                m.addItem(ActionMenuItem(.navForward, title: "Forward", key: right, modifiers: [.option, .command], registry: registry))
            })
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let selects: [ActionID] = [
            .sessionSelect1, .sessionSelect2, .sessionSelect3, .sessionSelect4, .sessionSelect5,
            .sessionSelect6, .sessionSelect7, .sessionSelect8, .sessionSelect9,
        ]
        main.addItem(
            submenu(title: "Session") { m in
                m.addItem(ActionMenuItem(.sessionRename, title: "Rename Session…", key: "r", modifiers: [.option, .command], registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.sessionPrevious, title: "Previous Session", key: up, modifiers: [.shift, .command], registry: registry))
                m.addItem(ActionMenuItem(.sessionNext, title: "Next Session", key: down, modifiers: [.shift, .command], registry: registry))
                for (i, action) in selects.enumerated() {
                    m.addItem(ActionMenuItem(action, title: "Select Session \(i + 1)", key: "\(i + 1)", registry: registry))
                }
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.sidebarFocus, title: "Focus Session List", key: "0", modifiers: [.shift, .command], registry: registry))
            })
        let window = submenu(title: "Window") { m in
            // lint-ui: allow buttons seletor padrão do sistema (sem ação de produto)
            m.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
            // lint-ui: allow buttons seletor padrão do sistema (sem ação de produto)
            m.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        }
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        return main
    }

    private static func submenu(title: String, _ fill: (NSMenu) -> Void) -> NSMenuItem {
        let menu = NSMenu(title: title)
        fill(menu)
        // lint-ui: allow buttons contêiner de submenu (não é gatilho)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
