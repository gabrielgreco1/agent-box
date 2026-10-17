import AgentBoxPlatform
import AppKit

/// Ciclo de vida AppKit da casca (00 T5): cria o `MainWindowController` e o menu principal.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let env = AppEnvironment()
    private var windowController: MainWindowController?
    private let log = LogFacade(.app, category: "lifecycle")

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log.publicInfo("launch")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let controller = MainWindowController(env: env)
        windowController = controller
        NSApp.mainMenu = MainMenu.build(registry: env.registry)
        // Com a automação ligada o app abre sem tirar o foco de quem o lançou (`open -g`).
        controller.present(activate: !env.automationEnabled)
        Task { await env.start() }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController?.present(activate: true) }
        return true
    }
}
