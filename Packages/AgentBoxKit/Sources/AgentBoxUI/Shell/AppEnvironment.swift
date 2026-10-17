import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxStore
import AppKit
import Foundation
import Observation

/// Estado mínimo da casca vazia (T1-02). O modelo de domínio (projetos, sessões, tabs) entra com T1-05.
@MainActor
@Observable
public final class ShellModel {
    public var appNameHidden = false
    /// Sidebar recolhida (⌘B): a faixa da titlebar vira flutuante (03 §1.3).
    public var sidebarCollapsed = false
    /// Tela cheia: semáforos somem e o pad de 80 vira 0 (03 §1.2).
    public var isFullScreen = false
    /// Histórico de navegação (⌥⌘←/→). Sem páginas ainda: os dois lados ficam desabilitados com motivo.
    public var canGoBack = false
    public var canGoForward = false
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
    public let overlays = OverlayRouter()
    public let toasts = ToastCenter()
    let sidebar = SidebarModel()
    public let keyBindings: KeyBindingRegistry
    public let automationEnabled: Bool
    public let fixture: String?
    public let socketPath: String
    private var ctl: CtlServer?
    private var store: AgentBoxStore?
    private let environmentVariables: [String: String]
    private let log = LogFacade(.app, category: "ui")

    /// `AGENTBOX_AUTOMATION=1` liga o canal `ctl` (o toggle em Settings > Advanced chega com T1-26).
    /// `AGENTBOX_SLICE=<n>` e `AGENTBOX_SCREEN=<tela>` valem só para dev e testes.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let flags = SliceFlags.fromEnvironment(environment)
        self.flags = flags
        self.automationEnabled = environment["AGENTBOX_AUTOMATION"] == "1"
        self.fixture = environment["AGENTBOX_SCREEN"]
        self.socketPath = AppSockPath.resolve(environment: environment)
        self.environmentVariables = environment
        let surface = WindowAutomation(store: elements, flags: flags, fixture: fixture, automationEnabled: automationEnabled)
        self.registry = ActionRegistry(flags: flags, surface: surface)
        var bindings = KeyBindingRegistry()
        do { bindings = try KeyBindingRegistry.canonical() } catch { log.publicError("canonical key bindings invalid") }
        if !bindings.conflicts().isEmpty { log.publicError("key binding conflicts detected") }
        self.keyBindings = bindings
        elements.enablement = { [registry] id in registry.availability(of: id) }
        registerShellActions()
        do { try sidebar.registerActions(in: registry) } catch { log.publicError("duplicate sidebar action registration") }
        wireOverlays()
        if fixture == Self.overlayDemoFixture || fixture == SidebarFixtures.screenID { registerOverlayDemo() }
        if fixture == SidebarFixtures.screenID { registerSidebarDemo() }
    }

    /// Ações reais da casca vazia; as demais entram com a tela que as possui.
    private func registerShellActions() {
        do {
            try registry.register(.appHideAppName) { [shell] _ in
                shell.appNameHidden.toggle()
                return shell.appNameHidden ? "hidden" : "shown"
            }
            try registry.register(
                .navBack,
                enablement: { [shell] in shell.canGoBack ? .enabled : .disabled(reason: "No earlier page") },
                handler: { _ in nil })
            try registry.register(
                .navForward,
                enablement: { [shell] in shell.canGoForward ? .enabled : .disabled(reason: "No later page") },
                handler: { _ in nil })
            try registry.register(.appQuit) { _ in
                NSApp.terminate(nil)
                return nil
            }
        } catch {
            log.publicError("duplicate action registration")
        }
    }

    /// Fixture de desenvolvimento (`AGENTBOX_SCREEN=overlay-demo`): liga ações que abrem overlays e toasts de exemplo.
    public static let overlayDemoFixture = "overlay-demo"

    /// Liga o roteador de overlays ao registro (Esc dispara o Cancel) e à árvore de UI (origem da animação).
    private func wireOverlays() {
        overlays.performAction = { [registry] id in
            guard registry.availability(of: id).isEnabled else { return false }
            Task { _ = try? await registry.perform(id, .press) }
            return true
        }
        overlays.frameOf = { [elements] id in elements.frame(of: id) }
    }

    /// Ações de exemplo do overlay (só no fixture): `session.new` abre a amostra do composer a partir do botão da sidebar,
    /// `pane.close` abre "Close this terminal?" e `app.checkProblems` mostra toasts. Os handlers de `composer.*`
    /// e `dialog.closeTerminal.*` gravam nos modelos da amostra.
    private func registerOverlayDemo() {
        let composer = ComposerSampleModel()
        let confirmation = ConfirmationModel.closeTerminal(
            message: String(localized: "Claude Code is still working. Closing ends the process; you can resume the conversation later.", bundle: .module))
        let router = overlays, toasts = toasts
        func add(_ id: ActionID, _ handler: @escaping @MainActor (ActionArgument) async throws -> String?) {
            try? registry.register(id, handler: handler)
        }
        add(.sessionNew) { _ in
            router.present(.composerSample(composer), from: .windowSidebarToggle) ? "opened" : "stack full"
        }
        add(.paneClose) { _ in
            router.present(.confirmation(confirmation), from: nil) ? "opened" : "stack full"
        }
        add(.composerSetWhere) { arg in
            composer.whereValue = arg.value ?? composer.whereValue
            return composer.whereValue
        }
        add(.composerSetPrompt) { arg in
            composer.prompt = arg.value ?? ""
            return nil
        }
        add(.composerCreateMore) { arg in
            composer.createMore = arg.value == "on"
            return composer.createMore ? "on" : "off"
        }
        add(.composerCancel) { _ in
            router.dismiss(.action)
            return nil
        }
        add(.composerSubmit) { _ in
            router.dismiss(.action)
            return nil
        }
        add(.dialogCloseTerminalCancel) { _ in
            router.dismiss(.action)
            return nil
        }
        add(.dialogCloseTerminalConfirm) { _ in
            router.dismiss(.action)
            return nil
        }
        add(.dialogCloseTerminalDontAsk) { arg in
            confirmation.state.dontAsk = arg.value == "on"
            return nil
        }
        add(.appCheckProblems) { _ in
            toasts.show(kind: .error, title: String(localized: "Couldn't save setting.", bundle: .module),
                        detail: String(localized: "The file is read-only.", bundle: .module), duration: 6)
            toasts.show(kind: .success, title: String(localized: "Session archived.", bundle: .module),
                        action: ToastAction(.appCheckProblems, title: String(localized: "Undo", bundle: .module)), undo: true)
            return nil
        }
    }

    /// Fixture `AGENTBOX_SCREEN=sidebar-demo`: controles cujo fluxo é de outra tarefa (composer, adicionar projeto, Settings,
    /// páginas) ganham handlers de exemplo para a evidência visual mostrar a sidebar completa. Nada disso roda em uso normal.
    private func registerSidebarDemo() {
        for id in [ActionID.projectAdd, .sessionNewClean, .appSettings, .projectNewSession, .pageInbox, .pageComputers, .pageLibrary] {
            try? registry.register(id) { _ in "demo" }
        }
    }

    /// Abre o Store (em `AGENTBOX_HOME` se definido) e liga a sidebar a ele (T1-05). Sem Store a sidebar fica vazia, nunca trava a UI.
    private func startStore() async {
        guard store == nil else { return }
        do {
            let opened = try await AgentBoxStore.open(paths: .default(environment: environmentVariables))
            store = opened
            if fixture == SidebarFixtures.screenID {
                let cast = SidebarFixtures.full()
                try await SidebarFixtures.seed(cast, into: opened)
                if try await opened.uiState(SidebarModel.uiStateKey, as: SidebarPersistedState.self) == nil {
                    try await opened.setUIState(SidebarModel.uiStateKey, SidebarPersistedState(selectedSession: cast.selectedSessionID))
                }
                if sidebar.pending.isEmpty, let pid = cast.pendingProjectID {
                    sidebar.beginPending(PendingLaunch(name: String(localized: "Add retry logic", bundle: .module), projectID: pid, phase: .fetching))
                }
            }
            await sidebar.attach(store: opened)
        } catch {
            log.error("store failed to open: \(error)")
        }
    }

    /// Sobe o servidor `ctl` se a automação estiver ligada. Chamado uma vez, no primeiro `.task` da janela.
    public func start() async {
        await startStore()
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
        sidebar.detach()
        await ctl?.stop()
        ctl = nil
    }
}
