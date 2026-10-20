import AgentBoxPlatform
import AgentBoxStore
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
        // Uma instância por pasta de dados: duas janelas no mesmo PTY brigam pelo tamanho e o Claude redesenha para a largura da
        // outra (texto sobreposto e duplicado). O lock é da pasta de dados: uma cópia de teste com `AGENTBOX_HOME` próprio não
        // impede o app do dono (e vice-versa). A segunda ativa a dona do lock e sai antes de tocar no daemon ou no store.
        if let owner = Self.acquireInstanceLock(environment: ProcessInfo.processInfo.environment) {
            NSRunningApplication(processIdentifier: owner)?.activate()
            log.publicInfo("another instance owns this data folder: yielding to it")
            exit(0)
        }
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

    /// fd do lock da pasta de dados; fica aberto a vida toda do processo (o `flock` some com ele).
    private nonisolated(unsafe) static var instanceLock: Int32 = -1  // SAFETY: gravado uma vez no main thread, no launch.

    /// `flock` em `<dados>/run/app.lock` com o pid dentro. `nil`: o lock é nosso; senão, o pid de quem o tem.
    static func acquireInstanceLock(environment: [String: String]) -> pid_t? {
        guard Bundle.main.bundleURL.pathExtension == "app", environment["AGENTBOX_SCREEN"] == nil else { return nil }
        let run = StorePaths.default(environment: environment).root.appendingPathComponent("run", isDirectory: true)
        try? FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        let fd = open(run.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            instanceLock = fd
            _ = ftruncate(fd, 0)
            let pid = "\(ProcessInfo.processInfo.processIdentifier)"
            _ = pid.withCString { write(fd, $0, strlen($0)) }
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: 32)
        let count = pread(fd, &buffer, buffer.count, 0)
        close(fd)
        return count > 0 ? pid_t(String(decoding: buffer.prefix(count), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1 : -1
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
