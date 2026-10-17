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
        // Telas de fixture (dev e evidência) não leem nem gravam o frame salvo do usuário.
        let controller = MainWindowController(env: env, autosaveName: env.fixture == nil ? "workspace" : nil)
        windowController = controller
        NSApp.mainMenu = MainMenu.build(registry: env.registry)
        // Com a automação ligada o app abre sem tirar o foco de quem o lançou (`open -g`).
        controller.present(activate: !env.automationEnabled)
        Task { await env.start() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        env.shutdownSync()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController?.present(activate: true) }
        return true
    }
}
