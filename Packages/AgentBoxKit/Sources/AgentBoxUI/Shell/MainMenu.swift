import AgentBoxProtocol
import AppKit

/// Item de menu que dispara uma ação do registro (08 AR-805): estado e motivo vêm de `availability`.
nonisolated final class ActionMenuItem: NSMenuItem {
    let actionID: ActionID
    let argument: ActionArgument
    private weak var registry: ActionRegistry?

    nonisolated init(
        _ id: ActionID, title: String, key: String, modifiers: NSEvent.ModifierFlags = [.command], argument: ActionArgument = .press,
        registry: ActionRegistry
    ) {
        actionID = id
        self.argument = argument
        self.registry = registry
        super.init(title: title, action: #selector(fire(_:)), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable) required nonisolated init(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    @objc nonisolated private func fire(_ sender: Any?) {
        guard let registry else { return }
        let id = actionID, argument = argument
        Task { @MainActor in _ = try? await registry.perform(id, argument) }
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
                m.addItem(ActionMenuItem(.appSetup, title: "Set Up Agent Box…", key: "", registry: registry))
                m.addItem(ActionMenuItem(.appSettings, title: "Settings…", key: ",", registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.appHideAppName, title: "Hide App Name", key: "", registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.appQuit, title: "Quit Agent Box", key: "q", registry: registry))
            })
        main.addItem(
            submenu(title: "File") { m in
                m.addItem(ActionMenuItem(.sessionNewClean, title: "New Clean Session", key: "n", modifiers: [.shift, .command], registry: registry))
                m.addItem(
                    ActionMenuItem(
                        .sessionNewCleanInFolder, title: "New Clean Session in Folder…", key: "n", modifiers: [.option, .shift, .command],
                        registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.tabQuickLaunch, title: "New Tab…", key: "n", modifiers: [.option, .command], registry: registry))
                m.addItem(ActionMenuItem(.tabNewAgent, title: "New Agent Tab", key: "t", modifiers: [.option, .command], registry: registry))
                m.addItem(ActionMenuItem(.tabNewTerminal, title: "New Terminal", key: "t", registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.paneClose, title: "Close Pane", key: "w", registry: registry))
                m.addItem(ActionMenuItem(.tabClose, title: "Close Tab", key: "", registry: registry))
                m.addItem(ActionMenuItem(.tabReopen, title: "Reopen Closed Tab", key: "t", modifiers: [.shift, .command], registry: registry))
            })
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        main.addItem(
            submenu(title: "View") { m in
                m.addItem(ActionMenuItem(.viewToggleSidebar, title: "Toggle Sidebar", key: "b", registry: registry))
                m.addItem(ActionMenuItem(.rightPanelToggleFiles, title: "Files", key: "1", modifiers: [.option, .command], registry: registry))
                m.addItem(ActionMenuItem(.rightPanelToggleInsights, title: "Insights", key: "2", modifiers: [.option, .command], registry: registry))
                m.addItem(ActionMenuItem(.rightPanelToggle, title: "Toggle Right Panel", key: "0", modifiers: [.option, .command], registry: registry))
                m.addItem(ActionMenuItem(.rightPanelSwap, title: "Swap Right Panel Modules", key: "", registry: registry))
                m.addItem(ActionMenuItem(.panelComputers, title: "Computers Panel", key: "c", modifiers: [.shift, .command], registry: registry))
                m.addItem(ActionMenuItem(.pageInbox, title: "Inbox", key: "i", modifiers: [.shift, .command], registry: registry))
                m.addItem(ActionMenuItem(.navBack, title: "Back", key: left, modifiers: [.option, .command], registry: registry))
                m.addItem(ActionMenuItem(.navForward, title: "Forward", key: right, modifiers: [.option, .command], registry: registry))
            })
        main.addItem(
            submenu(title: "Computer") { m in
                m.addItem(ActionMenuItem(.pageComputers, title: "Computers", key: "", registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.computerTakeOver, title: "Take Over / Hand Back", key: "r", modifiers: [.shift, .command], registry: registry))
                m.addItem(ActionMenuItem(.computerReleaseKeyboard, title: "Release Keyboard", key: "", registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.computerPaste, title: "Paste to Computer", key: "", registry: registry))
                m.addItem(ActionMenuItem(.computerCopySelection, title: "Copy Selection from Computer", key: "", registry: registry))
                m.addItem(ActionMenuItem(.computerPopOut, title: "Open in New Window", key: "", registry: registry))
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
        let selectTabs: [ActionID] = [
            .tabSelect1, .tabSelect2, .tabSelect3, .tabSelect4, .tabSelect5, .tabSelect6, .tabSelect7, .tabSelect8, .tabSelect9,
        ]
        main.addItem(
            submenu(title: "Terminal") { m in
                m.addItem(ActionMenuItem(.paneSplitRight, title: "Split Right", key: "d", registry: registry))
                m.addItem(ActionMenuItem(.paneSplitDown, title: "Split Down", key: "d", modifiers: [.shift, .command], registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.paneNext, title: "Next Pane", key: "]", registry: registry))
                m.addItem(ActionMenuItem(.panePrevious, title: "Previous Pane", key: "[", registry: registry))
                m.addItem(ActionMenuItem(.paneToggleExpand, title: "Expand Pane", key: "\r", modifiers: [.shift, .command], registry: registry))
                m.addItem(ActionMenuItem(.paneEqualize, title: "Equalize Pane Sizes", key: "", registry: registry))
                m.addItem(.separator())
                m.addItem(ActionMenuItem(.tabNext, title: "Next Tab", key: "}", modifiers: [.shift, .command], registry: registry))
                m.addItem(ActionMenuItem(.tabPrevious, title: "Previous Tab", key: "{", modifiers: [.shift, .command], registry: registry))
                m.addItem(ActionMenuItem(.tabRecent, title: "Recent Tab", key: "\t", modifiers: [.control], registry: registry))
                m.addItem(
                    ActionMenuItem(.tabRecent, title: "Recent Tab (Reverse)", key: "\t", modifiers: [.control, .shift], argument: .select("reverse"), registry: registry))
                for (i, action) in selectTabs.enumerated() {
                    m.addItem(ActionMenuItem(action, title: "Select Tab \(i + 1)", key: "\(i + 1)", modifiers: [.control], registry: registry))
                }
                m.addItem(ActionMenuItem(.tabRename, title: "Rename Tab…", key: "r", registry: registry))
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
