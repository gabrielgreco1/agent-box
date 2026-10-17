import AgentBoxCore
import AgentBoxDesignSystem
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
    /// Tab row e árvore de panes da sessão selecionada (T1-14).
    let workspace: WorkspaceModel
    /// Settings em página inteira e onboarding mínimo (T1-26): detecção de CLIs, perfis de lançamento e configuração.
    public let settings: SettingsModel
    public let onboarding: OnboardingModel
    let projects: ProjectsController
    public let keyBindings: KeyBindingRegistry
    /// Atenção, Inbox e notificações (Fatia 2). `nil` na Fatia 1: sem hooks o agente vivo é `Status unavailable`.
    public let attention: AttentionCoordinator?
    /// `AGENTBOX_NOTIFICATIONS=fake`: o que seria entregue ao sistema fica em memória e em `run/fake-notifications.jsonl`.
    public let fakeNotifier: RecordingNotificationCenter?
    /// Troca o `NSApp.dockTile.badgeLabel` (testes).
    let dockBadgeOverride: (@MainActor (String?) -> Void)?
    /// Pane de terminal focado: destino das ações de zoom, busca, copiar/colar e limpar (T1-09).
    public let terminalRouter = TerminalActionRouter()
    /// Computadores (T3-05): viewer, página Computers, painel direito, pedido de ajuda e ações `computer.*`.
    public let computers = ComputersController()
    /// "Subagent computers" por sessão (F12): ícone, menu, `Restart to apply`.
    private(set) var subagentComputers: SubagentComputersController!
    /// Hover card do computador de um subagente (pré-visualização ao vivo).
    private(set) var subagentHoverCards: SubagentHoverCardController!
    /// O orquestrador nasce depois do Store (as identidades e a árvore são persistidas); o lançamento o encontra por aqui.
    let orchestratorHolder: OrchestratorHolder
    var computerSweeper: Task<Void, Never>?
    /// ⌘Q com agentes vivos, modo accessory e barra de menus (T1-24).
    public private(set) var lifecycle: AppLifecycleCoordinator!
    public let automationEnabled: Bool
    public let fixture: String?
    public let socketPath: String
    private var ctl: CtlServer?
    private var hub: AppSockHub?
    var activity: ActivityService?
    private var store: AgentBoxStore?
    /// `session.launch`: sessão com o agente já rodando (P9, M-501).
    private var launcher: SessionLauncher?
    /// Sessões limpas (⇧⌘N, ⌥⇧⌘N, arquivar, apagar, mover) e Quick Launch (⌥⌘N, "+" da tab row) — T1-17 e T1-21.
    private(set) var cleanSessions: CleanSessionController?
    private var quickLaunch: QuickLaunchController?
    /// Composer ⌘N (T1-20): overlay, ações `composer.*` e `session.new*`.
    private(set) var composer: ComposerController?
    /// "Open in…" e "Open in Editor" (T1-27).
    private(set) var openIn: OpenInController?
    let environmentVariables: [String: String]
    private let log = LogFacade(.app, category: "ui")

    /// `AGENTBOX_AUTOMATION=1` liga o canal `ctl` (o toggle em Settings > Advanced chega com T1-26).
    /// `AGENTBOX_SLICE=<n>` e `AGENTBOX_SCREEN=<tela>` valem só para dev e testes.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment, dockBadge: (@MainActor (String?) -> Void)? = nil) {
        dockBadgeOverride = dockBadge
        let holder = OrchestratorHolder()
        orchestratorHolder = holder
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
        let settings = SettingsModel(flags: flags, probe: Self.makeProbe(fixture: environment["AGENTBOX_SCREEN"]))
        self.settings = settings
        self.onboarding = OnboardingModel(settings: settings)
        let screen = environment["AGENTBOX_SCREEN"]
        autoOnboarding = environment["AGENTBOX_SKIP_ONBOARDING"] != "1" && (screen == nil || screen == Self.setupDemoFixture)
        self.projects = ProjectsController(sidebar: sidebar, overlays: overlays, toasts: toasts, automationEnabled: automationEnabled)
        elements.enablement = { [registry] id in registry.availability(of: id) }
        let storeRoot = StorePaths.default(environment: environment).root
        let slice2 = flags.isEnabled(.slice2)
        if slice2 {
            let center: any NotificationCentering
            if environment["AGENTBOX_NOTIFICATIONS"] == "fake" {
                let recorder = RecordingNotificationCenter(
                    authorization: .notDetermined, logURL: storeRoot.appendingPathComponent("run/fake-notifications.jsonl"))
                fakeNotifier = recorder
                center = recorder
            } else {
                fakeNotifier = nil
                center = SystemNotificationCenter()
            }
            attention = AttentionCoordinator(notifier: center)
        } else {
            fakeNotifier = nil
            attention = nil
        }
        let loginProvider = LoginShellEnvProvider(
            config: LoginShellEnvConfig(runDirectory: storeRoot.appendingPathComponent("run", isDirectory: true)))
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1.0 (dev)"
        let runtime = TerminalRuntime(
            configuration: TerminalRuntime.Configuration(
                daemonHome: storeRoot, daemonExecutable: environment["AGENTBOX_DAEMON"].map { URL(fileURLWithPath: $0) },
                stopDaemonOnQuit: automationEnabled || environment["AGENTBOX_STOP_DAEMON_ON_QUIT"] == "1",
                appSocketPath: socketPath, build: build,
                backgroundAgent: Self.makeBackgroundAgent(environment: environment, storeRoot: storeRoot),
                loginEnvironment: { await loginProvider.environment().variables },
                slice: slice2 ? .slice2 : .slice1, helperPath: slice2 ? Self.helperPath(environment) : nil,
                prepareOrchestration: { info in
                    guard let orchestrator = holder.value else { return nil }
                    return try? await orchestrator.prepareParent(info)
                },
                endOrchestration: { parent in await holder.value?.endParent(parent) }),
            registry: registry, elements: elements)
        workspace = WorkspaceModel(runtime: runtime)
        subagentComputers = SubagentComputersController(sidebar: sidebar, workspace: workspace, overlays: overlays, elements: elements)
        workspace.subagent = subagentComputers
        sidebar.subagent = subagentComputers
        lifecycle = AppLifecycleCoordinator(registry: registry, overlays: overlays)
        registerShellActions()
        wireLifecycle()
        do { try sidebar.registerActions(in: registry) } catch { log.publicError("duplicate sidebar action registration") }
        do { try projects.registerActions(in: registry) } catch { log.publicError("duplicate project action registration") }
        wireOverlays()
        wireWorkspace()
        if fixture == Self.overlayDemoFixture || fixture == SidebarFixtures.screenID { registerOverlayDemo() }
        if fixture == SidebarFixtures.screenID { registerSidebarDemo() }
        do { try terminalRouter.register(in: registry) } catch { log.publicError("duplicate terminal action registration") }
        wireSettings()
        wireAttention(environment: environment)
        wireComputers()
    }

    /// Liga o controlador de computadores: ações `computer.*`, ⌘W fecha a página do viewer e a notificação de pedido de ajuda.
    private func wireComputers() {
        do { try computers.register(in: registry) } catch { log.publicError("duplicate computer action registration") }
        do { try subagentComputers.register(in: registry) } catch { log.publicError("duplicate subagent computers registration") }
        subagentHoverCards = SubagentHoverCardController(computers: computers, registry: registry, elements: elements)
        computers.model.sessionTitle = { [computers, sidebar] name in computers.model.sessionIDs[name].flatMap { sidebar.session($0)?.title } }
        workspace.pageCloser = { [computers] in
            guard computers.page != .workspace else { return false }
            computers.closePage()
            return true
        }
        if !automationEnabled {
            let system = SystemHelpNotifier(open: { [computers, registry] name, takeOver in
                NSApp.activate()
                computers.openViewer(name)
                if takeOver { Task { _ = try? await registry.perform(.computerTakeOver, .select(name)) } }
            })
            system?.decide = { [computers] id, decision in computers.model.decide(id, decision) }
            computers.notifier = system ?? NoopHelpNotifier()
        }
    }

    /// `AGENTBOX_SCREEN=setup-demo`: onboarding e Settings com CLIs de mentira (Claude logado, Codex deslogado, OpenCode ausente),
    /// para a evidência visual não depender do que está instalado no Mac.
    public static let setupDemoFixture = "setup-demo"
    private let autoOnboarding: Bool

    private static func makeProbe(fixture: String?) -> AgentProbe {
        if fixture == setupDemoFixture {
            return { provider, _ in
                switch provider {
                case .claude: CLIProbeResult(provider: .claude, executable: "/Users/demo/.local/bin/claude", version: CLIVersion(2, 1, 302), login: .loggedIn)
                case .codex: CLIProbeResult(provider: .codex, executable: "/opt/homebrew/bin/codex", version: CLIVersion(0, 160, 0), login: .loggedOut)
                default: CLIProbeResult(provider: provider, executable: nil, login: .unknown("not installed"))
                }
            }
        }
        let loginEnv = LoginShellEnvProvider()
        let prober = CLIProber(environment: { await loginEnv.environment().captured.variables })
        return { provider, force in await prober.probe(ProviderAdapters.adapter(for: provider), checkLogin: true, force: force) }
    }

    /// Liga Settings e onboarding ao registro de ações, aos overlays e aos toasts.
    private func wireSettings() {
        settings.toasts = toasts
        do {
            try settings.registerActions(in: registry)
            try onboarding.registerActions(in: registry)
        } catch {
            log.publicError("duplicate settings action registration")
        }
        onboarding.present = { [overlays, onboarding] in overlays.present(onboarding.overlaySpec(), from: nil) }
        onboarding.dismiss = { [overlays] in
            if overlays.top?.spec.name == "onboarding" { overlays.dismiss(.action) }
        }
        let previous = settings.onPresentationChange
        settings.onPresentationChange = { [onboarding] open in
            previous(open)
            // Abrir o Settings (Review Profiles, ⌘,) tira o onboarding da frente sem registrá-lo como concluído.
            if open { onboarding.hide() }
        }
    }

    /// Fixture de dev e evidência (`AGENTBOX_SCREEN=workspace-demo`): uma sessão limpa com uma tab de shell, selecionada.
    /// Os splits vêm de `ctl ui action pane.splitRight` etc.
    static let workspaceDemoFixture = "workspace-demo"

    private func seedWorkspaceDemo(into store: AgentBoxStore) async throws {
        guard try await store.sessions().isEmpty else { return }
        let folder = StorePaths.default(environment: environmentVariables).root
        var session = Session(kind: .clean, folderPath: folder.path, title: "demo-session")
        session.managedFolder = true
        try await store.save(session)
        let tabID = UUID.v7(), termID = UUID.v7()
        let terminal = Terminal(id: termID, tabID: tabID, provider: .shell, title: "demo-session", cwd: folder.path, launchSpec: LaunchSpec(provider: .shell))
        let tab = Tab(id: tabID, sessionID: session.id, title: "demo-session", layout: .leaf(Pane(content: .terminal(termID))), focusedTerminalID: termID)
        try await store.save(tab)
        try await store.save(terminal)
        try await store.setUIState(SidebarModel.uiStateKey, SidebarPersistedState(selectedSession: session.id))
    }

    /// Liga o workspace (tabs e panes) à sidebar, aos overlays e ao registro de ações (T1-14). No fixture do overlay
    /// (`overlay-demo`) as ações de fechar do demo continuam suas.
    private func wireWorkspace() {
        workspace.overlays = overlays
        workspace.toasts = toasts
        workspace.sessionLookup = { [sidebar] id in sidebar.session(id) }
        sidebar.onSelectionChange = { [workspace] id in workspace.setSession(id) }
        sidebar.onSnapshot = { [workspace, lifecycle] snapshot in
            workspace.ingest(snapshot)
            lifecycle?.update(terminals: snapshot.terminals)
        }
        workspace.runtime.contextMenu = { [workspace, registry] id in workspace.paneContextMenu(registry: registry, terminalID: id) }
        let demo = fixture == Self.overlayDemoFixture
        do {
            try workspace.registerActions(
                in: registry, elements: elements, includeCloseDialog: !demo, excluding: demo ? [.paneClose] : [])
        } catch {
            log.publicError("duplicate workspace action registration")
        }
        sidebar.cancelLaunchFallback = { [workspace] id in
            guard workspace.terminal(id) != nil else { return false }
            workspace.cancelLaunch(id)
            return true
        }
        // Agente padrão e instalação detectada vêm do Settings; ⌥⌘T e o Quick Launch usam os mesmos.
        workspace.defaultAgent = { [settings] in settings.settings.agents.defaultAgent }
        workspace.agentInstalled = { [settings] in settings.agent($0)?.installedState }
        let isolatedHome = environmentVariables["AGENTBOX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let sessionsRoot: () -> URL = { [settings] in
            CleanSessionPaths.sessionsRoot(configured: settings.settings.general.cleanSessionFolder, isolatedHome: isolatedHome)
        }
        let sessionLauncher = SessionLauncher(sidebar: sidebar, workspace: workspace, elements: elements, sessionsRoot: sessionsRoot)
        launcher = sessionLauncher
        sessionLauncher.settings = settings
        do { try sessionLauncher.register(in: registry) } catch { log.publicError("duplicate session.launch registration") }
        let clean = CleanSessionController(
            launcher: sessionLauncher, sidebar: sidebar, workspace: workspace, overlays: overlays, toasts: toasts, elements: elements,
            settings: settings, projects: projects, sessionsRoot: sessionsRoot,
            runsRoot: { CleanSessionPaths.runsRoot(isolatedHome: isolatedHome) }, automationEnabled: automationEnabled)
        cleanSessions = clean
        do { try clean.register(in: registry) } catch { log.publicError("duplicate clean session registration") }
        let open = OpenInController(sidebar: sidebar, overlays: overlays, toasts: toasts, elements: elements)
        openIn = open
        do { try open.register(in: registry) } catch { log.publicError("duplicate open-in registration") }
        let quick = QuickLaunchController(workspace: workspace, overlays: overlays, elements: elements, settings: settings)
        quickLaunch = quick
        do { try quick.register(in: registry) } catch { log.publicError("duplicate quick launch registration") }
        let composerController = ComposerController(
            sidebar: sidebar, settings: settings, overlays: overlays, toasts: toasts, elements: elements, launcher: sessionLauncher,
            automationEnabled: automationEnabled)
        composer = composerController
        do { try composerController.register(in: registry) } catch { log.publicError("duplicate composer registration") }
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
                AppLifecycleCoordinator.requestTermination()
                return nil
            }
            try registry.register(.appQuitCompletely) { [unowned self] _ in
                lifecycle.quitCompletely()
                return nil
            }
            try registry.register(.appOpenMainWindow) { [unowned self] _ in
                lifecycle.leaveBackground()
                return nil
            }
            try registry.register(
                .appStopAllAgents,
                enablement: { [weak self] in (self?.lifecycle.cachedCounts.agents ?? 0) > 0 ? .enabled : .disabled(reason: "No agents are running.") }
            ) { [unowned self] _ in
                guard await lifecycle.requestStopAll() else { throw ActionError.failed(.appStopAllAgents, message: "No agents are running.") }
                return nil
            }
            try registry.register(.dialogQuitKeepRunning) { [unowned self] _ in
                lifecycle.choose(.keepRunning(dontAskAgain: lifecycle.dontAskChecked))
                return nil
            }
            try registry.register(.dialogQuitStopAll) { [unowned self] _ in
                lifecycle.choose(.stopAll)
                return nil
            }
            try registry.register(.dialogQuitStopAllConfirm) { [unowned self] _ in
                lifecycle.confirmStopAll()
                return nil
            }
            try registry.register(.dialogQuitCancel) { [unowned self] _ in
                lifecycle.choose(.cancel)
                return nil
            }
            try registry.register(.dialogQuitDontAsk) { [unowned self] arg in
                lifecycle.setDontAsk(arg.value.map { $0 == "on" } ?? !lifecycle.dontAskChecked)
                return lifecycle.dontAskChecked ? "on" : "off"
            }
        } catch {
            log.publicError("duplicate action registration")
        }
    }

    /// LaunchAgent do daemon (T1-24). Só dentro do `.app` com o plist embutido, e nunca em fixtures, automação ou com
    /// `AGENTBOX_HOME` próprio (testes usam o daemon filho), salvo `AGENTBOX_LAUNCHD=1` (label de teste, 08 §0.1).
    static func makeBackgroundAgent(environment: [String: String], storeRoot: URL) -> BackgroundAgentHost? {
        let explicit = environment["AGENTBOX_LAUNCHD"] == "1"
        if environment["AGENTBOX_LAUNCHD"] == "0" { return nil }
        if !explicit, environment["AGENTBOX_HOME"] != nil || environment["AGENTBOX_AUTOMATION"] == "1" || environment["AGENTBOX_SCREEN"] != nil
            || environment["AGENTBOX_DAEMON"] != nil
        {
            return nil
        }
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return nil }
        let identity = BackgroundAgentIdentity.resolve(environment: environment)
        return BackgroundAgentHost(
            identity: identity, service: SMBackgroundAgentService(plistName: identity.plistName), bundleURL: bundleURL,
            daemonExecutable: ChildDaemon.launcherExecutable(),
            stateFile: storeRoot.appendingPathComponent("run/ptyd-registration.json"))
    }

    /// ⌘Q, accessory, barra de menus e o aviso de aprovação do LaunchAgent.
    private func wireLifecycle() {
        lifecycle.dependencies = AppLifecycleCoordinator.Dependencies(
            countLive: { [weak self] in await self?.liveCounts() ?? LiveProcessCounts() },
            preferences: { [weak self] in
                let general = self?.settings.settings.general
                return QuitPreferences(keepAgentsRunning: general?.keepAgentsRunning ?? true, askBeforeQuit: general?.askBeforeQuit ?? true)
            },
            disableAsking: { [weak self] in self?.settings.disableAskBeforeQuit() },
            promptShownBefore: { [weak self] in await self?.quitPromptShown() ?? false },
            markPromptShown: { [weak self] in self?.recordQuitPromptShown() },
            stopAll: { [weak self] in await self?.stopAllProcesses() },
            markCleanExit: { [weak self] in await self?.markCleanExit() })
        settings.openLoginItems = { [workspace] in workspace.runtime.openLoginItemsSettings() }
        workspace.runtime.onHostModeChange = { [settings] mode in
            settings.backgroundNeedsApproval = mode.fallbackReason == .requiresApproval
        }
    }

    private static let quitPromptKey = "quit.promptShown"

    /// Terminais com processo vivo segundo o banco (também sessões que não estão na tela).
    func liveCounts() async -> LiveProcessCounts {
        guard let store else { return lifecycle.cachedCounts }
        let running = (try? await store.terminals(in: .running)) ?? []
        let launching = (try? await store.terminals(in: .launching)) ?? []
        return LiveProcessCounts(counting: running + launching)
    }

    private func quitPromptShown() async -> Bool {
        guard let store else { return false }
        return (try? await store.uiState(Self.quitPromptKey, as: Bool.self)) ?? false
    }

    private func recordQuitPromptShown() {
        guard let store else { return }
        Task { try? await store.setUIState(Self.quitPromptKey, true) }
    }

    /// `Stop All and Quit`: `kill graceful` em todos, espera até 5 s e só então força o que sobrou (o usuário já confirmou duas vezes).
    func stopAllProcesses() async {
        let client = workspace.runtime.client
        func running() async -> [SessionSummary] { ((try? await client.list()) ?? []).filter { $0.state == .running } }
        for summary in await running() { try? await client.kill(sessionID: summary.sessionID, mode: .graceful) }
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, !(await running()).isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
        for summary in await running() { try? await client.kill(sessionID: summary.sessionID, mode: .force) }
    }

    /// Fixture de desenvolvimento (`AGENTBOX_SCREEN=overlay-demo`): liga ações que abrem overlays e toasts de exemplo (o composer é o real).
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
        let confirmation = ConfirmationModel.closeTerminal(
            message: String(localized: "Claude Code is still working. Closing ends the process; you can resume the conversation later.", bundle: .module))
        let router = overlays, toasts = toasts
        func add(_ id: ActionID, _ handler: @escaping @MainActor (ActionArgument) async throws -> String?) {
            try? registry.register(id, handler: handler)
        }
        add(.paneClose) { _ in
            router.present(.confirmation(confirmation), from: nil) ? "opened" : "stack full"
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
        if let script = scriptSteps { runDemoScript(script) }
    }

    /// Fixture `AGENTBOX_SCREEN=sidebar-demo`: controles cujo fluxo é de outra tarefa (composer, adicionar projeto, Settings,
    /// páginas) ganham handlers de exemplo para a evidência visual mostrar a sidebar completa. Nada disso roda em uso normal.
    private func registerSidebarDemo() {
        for id in [ActionID.appSettings, .projectNewSession, .pageInbox, .pageComputers, .pageLibrary] where attention == nil || id != .pageInbox {
            try? registry.register(id) { _ in "demo" }
        }
    }

    /// Abre o Store (em `AGENTBOX_HOME` se definido) e liga a sidebar a ele (T1-05). Sem Store a sidebar fica vazia, nunca trava a UI.
    private func startStore() async {
        guard store == nil else { return }
        do {
            let opened = try await AgentBoxStore.open(paths: .default(environment: environmentVariables))
            store = opened
            subagentComputers.attach(store: opened)
            await startOrchestrator(store: opened)
            if fixture == Self.workspaceDemoFixture { try await seedWorkspaceDemo(into: opened) }
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
            launcher?.attach(store: opened)
            cleanSessions?.attach(store: opened)
            openIn?.attach(store: opened)
            await restoreSessions(store: opened)
            await composer?.attach(store: opened)
            // A evidência de atenção semeia depois do restore: os terminais "running" de mentira não viram `interrupted`.
            if fixture == AttentionFixtures.screenID, attention != nil {
                try await AttentionFixtures.seed(into: opened, home: NSHomeDirectory())
            }
            await workspace.attach(store: opened)
            await sidebar.attach(store: opened)
            await settings.attach(store: opened)
            await startActivity(store: opened)
            if autoOnboarding { await onboarding.attach(store: opened, forceVisible: fixture == Self.setupDemoFixture) }
            projects.attach(store: opened)
        } catch {
            log.error("store failed to open: \(error)")
        }
    }

    /// Reabertura (T1-23): ver `WorkspaceModel.restoreSessions`. Avisa uma vez quantos terminais voltaram vivos.
    private func restoreSessions(store: AgentBoxStore) async {
        guard let report = await workspace.restoreSessions(store: store) else { return }
        log.info("restore: \(report.alive.count) alive, \(report.exited.count) exited, \(report.interrupted.count) interrupted")
        if !report.alive.isEmpty {
            toasts.show(kind: .info, title: String(localized: "Reconnected to \(report.alive.count) running terminals.", bundle: .module))
        }
    }

    /// `AGENTBOX_DEMO_SCRIPT=composer;agent;...` (só no fixture, para evidência e testes): abre o composer e comboboxes/menus
    /// em sequência, sem cliques. Passos: `composer`, `project`, `agent`, `profile`, `appmenu`.
    var scriptSteps: [String]? {
        guard let raw = ProcessInfo.processInfo.environment["AGENTBOX_DEMO_SCRIPT"], !raw.isEmpty else { return nil }
        return raw.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private func runDemoScript(_ steps: [String]) {
        let router = overlays, registry = registry, elements = elements
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            for step in steps {
                switch step {
                case "composer":
                    _ = try? await registry.perform(.sessionNew, .press)
                case "project", "agent", "profile":
                    guard let model = self?.composer?.model else { break }
                    let (id, selection, entries, action, hint): (A11yID, String, [DSMenuEntry], ActionID, String) =
                        switch step {
                        case "project": (.overlayComposerProject, model.draft.projectID?.uuidString ?? "none", model.projectEntries, .composerSetProject, "Search projects…")
                        case "agent": (.overlayComposerAgent, model.draft.provider.rawValue, model.agentEntries, .composerSetAgent, "Search agents…")
                        default: (.overlayComposerProfile, model.draft.profileID?.uuidString ?? "", model.profileEntries, .composerSetProfile, "Search profiles…")
                        }
                    if let anchor = elements.frame(of: id) {
                        router.presentPopover(
                            DSCombobox.popoverSpec(
                                id: id, selection: selection, entries: entries, action: action, searchPlaceholder: hint, anchor: anchor,
                                registry: registry))
                    }
                case "appmenu":
                    if let anchor = elements.frame(of: .windowAppName) {
                        DSMenuPanel.present(router: router, registry: registry, name: "appMenu", anchor: anchor, entries: AppMenuEntries.entries)
                    }
                default: break
                }
                try? await Task.sleep(for: .seconds(0.8))
            }
        }
    }


    /// Sobe o servidor `ctl` se a automação estiver ligada. Chamado uma vez, no primeiro `.task` da janela.
    public func start() async {
        await startStore()
        computers.startRefreshing()
        computers.startDemo(environment: environmentVariables)
        // Fatia 2: `app.sock` é de um hub só (ctl + hook); os hooks chegam mesmo com a automação desligada.
        if let activity, hub == nil {
            let enabled = automationEnabled
            var providers: [any AppSockServiceProvider] = [
                CtlServiceProvider(dispatcher: registry, isEnabled: { enabled }), HookServiceProvider(activity: activity),
            ]
            if let orchestrator = orchestratorHolder.value { providers.append(orchestrator.mcpProvider) }
            let server = AppSockHub(socketPath: socketPath, providers: providers)
            do {
                try await server.start()
                hub = server
            } catch {
                log.error("app.sock hub failed to start: \(error)")
            }
            return
        }
        guard automationEnabled, ctl == nil, hub == nil else { return }
        let server = CtlServer(socketPath: socketPath, dispatcher: registry)
        do {
            try await server.start()
            ctl = server
        } catch {
            log.error("ctl failed to start: \(error)")
        }
    }

    /// Encerra o daemon filho se esta execução o possui (automação, testes, `AGENTBOX_STOP_DAEMON_ON_QUIT=1`).
    public func shutdownSync() {
        workspace.runtime.shutdown()
    }

    /// Saída limpa (T1-23): a próxima abertura distingue "parou com o app fechado" de "parou sem aviso".
    public func markCleanExit() async {
        if let store { await SessionReconciler.markCleanExit(store: store) }
    }

    public func stop() async {
        sidebar.detach()
        projects.detach()
        computers.stopRefreshing()
        await computers.tearDownDemo()
        computerSweeper?.cancel()
        await ctl?.stop()
        ctl = nil
        await hub?.stop()
        hub = nil
        attention?.stop()
        await activity?.stop()
        activity = nil
    }
}
