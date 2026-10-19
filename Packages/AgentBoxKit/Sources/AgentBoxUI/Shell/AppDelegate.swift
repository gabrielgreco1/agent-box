import AgentBoxPlatform
import AppKit

/// Ciclo de vida AppKit da casca (00 T5): cria o `MainWindowController` e o menu principal.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let env = AppEnvironment()
    private var windowController: MainWindowController?
    private let log = LogFacade(.app, category: "lifecycle")
    private var termination: ExternalTerminationSignals?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log.publicInfo("launch")
        if env.headless { MainWindowController.invisibleForTests = true }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Telas de fixture (dev e evidência) não leem nem gravam o frame salvo do usuário.
        let controller = MainWindowController(env: env, autosaveName: env.fixture == nil ? "workspace" : nil)
        windowController = controller
        env.lifecycle.dependencies.showWindow = { [weak controller] in controller?.present(activate: true) }
        env.lifecycle.dependencies.hideWindow = { [weak controller] in controller?.hide() }
        if !env.headless { NSApp.mainMenu = MainMenu.build(registry: env.registry) }
        // Com a automação ligada o app abre sem tirar o foco de quem o lançou (`open -g`).
        controller.present(activate: !env.automationEnabled && !env.headless)
        Task { await env.start() }
        let signals = ExternalTerminationSignals { [weak self] number in
            self?.log.info("received signal \(number): leaving the agents running")
            self?.env.lifecycle.externalTerminationRequested()
        }
        signals.install()
        termination = signals
    }

    /// ⌘Q (T1-24): a política decide entre sair, manter os agentes em segundo plano ou perguntar no overlay da janela.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        env.lifecycle.shouldTerminate { shouldQuit in
            NSApp.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        env.shutdownSync()
    }

    /// Fechar a janela com agente vivo não encerra o app: ele passa a accessory e o ícone da barra de menus fica (06 §1.6).
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if env.lifecycle.shouldStayAfterLastWindowClosed {
            env.lifecycle.enterBackground()
            return false
        }
        return true
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { env.lifecycle.leaveBackground() }
        return true
    }
}
