import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AppKit
import Foundation
import Observation

/// Estado mínimo da casca vazia (T1-02). O modelo de domínio (projetos, sessões, tabs) entra com T1-05.
@MainActor
@Observable
public final class ShellModel {
    public var appNameHidden = false
    public init() {}
}

/// Ambiente de serviços montado no `@main` (08 AR-133): registro de ações, atalhos, árvore de UI,
/// feature flag por fatia e o canal `ctl` (opt-in). Sem singletons.
@MainActor
public final class AppEnvironment {
    public let flags: SliceFlags
    public let shell = ShellModel()
    public let elements = UIElementStore()
    public let registry: ActionRegistry
    public let keyBindings: KeyBindingRegistry
    public let automationEnabled: Bool
    public let fixture: String?
    public let socketPath: String
    private var ctl: CtlServer?
    private let log = LogFacade(.app, category: "ui")

    /// `AGENTBOX_AUTOMATION=1` liga o canal `ctl` (o toggle em Settings > Advanced chega com T1-26).
    /// `AGENTBOX_SLICE=<n>` e `AGENTBOX_SCREEN=<tela>` valem só para dev e testes.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let flags = SliceFlags.fromEnvironment(environment)
        self.flags = flags
        self.automationEnabled = environment["AGENTBOX_AUTOMATION"] == "1"
        self.fixture = environment["AGENTBOX_SCREEN"]
        self.socketPath = AppSockPath.resolve(environment: environment)
        let surface = WindowAutomation(store: elements, flags: flags, fixture: fixture, automationEnabled: automationEnabled)
        self.registry = ActionRegistry(flags: flags, surface: surface)
        var bindings = KeyBindingRegistry()
        do { bindings = try KeyBindingRegistry.canonical() } catch { log.publicError("canonical key bindings invalid") }
        if !bindings.conflicts().isEmpty { log.publicError("key binding conflicts detected") }
        self.keyBindings = bindings
        elements.enablement = { [registry] id in registry.availability(of: id) }
        registerShellActions()
    }

    /// Ações reais da casca vazia; as demais entram com a tela que as possui.
    private func registerShellActions() {
        do {
            try registry.register(.appHideAppName) { [shell] _ in
                shell.appNameHidden.toggle()
                return shell.appNameHidden ? "hidden" : "shown"
            }
            try registry.register(.appQuit) { _ in
                NSApp.terminate(nil)
                return nil
            }
        } catch {
            log.publicError("duplicate action registration")
        }
    }

    /// Sobe o servidor `ctl` se a automação estiver ligada. Chamado uma vez, no primeiro `.task` da janela.
    public func start() async {
        guard automationEnabled, ctl == nil else { return }
        let server = CtlServer(socketPath: socketPath, dispatcher: registry)
        do {
            try await server.start()
            ctl = server
        } catch {
            log.error("ctl failed to start: \(error)")
        }
    }

    public func stop() async {
        await ctl?.stop()
        ctl = nil
    }
}
