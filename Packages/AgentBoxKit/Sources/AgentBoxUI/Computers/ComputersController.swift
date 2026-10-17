import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AppKit
import Foundation
import Observation

/// O que ocupa o centro da janela no lugar das tabs de terminal (03 §12): páginas e o viewer.
public enum CenterPage: Equatable, Sendable {
    case workspace
    case viewer(String)
    case computers
}

extension CenterPage {
    var isViewer: Bool { if case .viewer = self { true } else { false } }
}

/// Controlador de computadores da UI (T3-05): registro dos computadores, viewer, página Computers, painel direito,
/// pedido de ajuda (Inbox, Dock, notificação) e as ações `computer.*` (03 §24.5). O hub é o mesmo que o MCP usa.
@MainActor
@Observable
public final class ComputersController {
    public let model = ComputersModel()
    /// O hub do app: o mesmo que o MCP usa. `useOrchestrator` troca pelo do orquestrador (F12).
    @ObservationIgnored public private(set) var hub = ComputerHub()
    @ObservationIgnored public private(set) var orchestrator: ComputerOrchestrator?
    public private(set) var page: CenterPage = .workspace
    public private(set) var panelOpen = false
    public private(set) var viewers: [String: ComputerViewerController] = [:]
    @ObservationIgnored public var onPageChange: () -> Void = {}
    @ObservationIgnored public var onPanelChange: (Bool) -> Void = { _ in }
    @ObservationIgnored public var notifier: any HelpNotifying = NoopHelpNotifier()
    @ObservationIgnored private let log = LogFacade(.app, category: "computers")
    @ObservationIgnored private var refresher: Task<Void, Never>?
    @ObservationIgnored private var popOuts: [String: ViewerPopOut] = [:]
    @ObservationIgnored private var demoRig: DemoComputerRig?
    /// O hover card de um subagente está aberto: só então a miniatura corre (≤ 1 fps) fora do painel e da página Computers.
    @ObservationIgnored private var hoverPreviewOpen = false

    public func setHoverPreview(open: Bool) { hoverPreviewOpen = open }

    public init() {
        // Sem coordenador de atenção (Fatia 1) o próprio controlador mantém o badge; com ele, `AppEnvironment` religa isto
        // e o badge é a soma única (agentes + pedidos de ajuda) em `AttentionCoordinator.refreshDock`.
        model.onAttentionChange = { count in
            NSApp?.dockTile.badgeLabel = count > 0 ? "\(count)" : ""
        }
        model.onApprovalRequested = { [weak self] request in
            guard let self else { return }
            self.notifier.notify(approval: request)
            if NSApp?.isActive == false { NSApp.requestUserAttention(.informationalRequest) }
        }
        model.onHelpRequested = { [weak self] item, content in
            guard let self else { return }
            self.notifier.notify(item: item, content: content)
            if NSApp?.isActive == false { NSApp.requestUserAttention(.informationalRequest) }
        }
    }

    // MARK: Computadores

    /// F12: os computadores que o scheduler cria no `boxes_reserve` chegam aqui (linha filha da sidebar, viewer) e saem quando liberados.
    public func useOrchestrator(_ orchestrator: ComputerOrchestrator) async {
        self.orchestrator = orchestrator
        hub = orchestrator.hub
        let model = model
        await hub.setObservers(
            onRegister: { computer in
                Task { @MainActor in
                    await model.attach(computer)
                    model.sessionIDs[computer.name] = await orchestrator.sessionID(ofComputer: computer.name)
                }
            },
            onRemove: { name in Task { @MainActor in model.detach(name: name) } })
        await orchestrator.approvals.setObserver { requests in Task { @MainActor in model.setApprovals(requests) } }
        model.decide = { id, decision in Task { await orchestrator.approvals.decide(id: id, decision) } }
    }

    public func add(_ computer: ManagedComputer) async {
        await hub.register(computer)
        await model.attach(computer)
    }

    public func startRefreshing() {
        refresher?.cancel()
        refresher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Miniaturas só quando alguém as vê (painel aberto ou página Computers) e ≤ 1 fps por computador (CS-403).
                let visible = self.panelOpen || self.page == .computers || self.hoverPreviewOpen
                await self.model.refresh(withThumbnails: visible)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stopRefreshing() { refresher?.cancel() }

    // MARK: Centro

    public func show(_ page: CenterPage) {
        guard self.page != page else { return }
        let old = self.page
        self.page = page
        if case .viewer(let name) = old, old != page { closeViewer(name) }
        if case .viewer(let name) = page { ensureViewer(name) }
        onPageChange()
    }

    public func closePage() {
        guard page != .workspace else { return }
        show(.workspace)
    }

    @discardableResult
    func ensureViewer(_ name: String) -> ComputerViewerController? {
        if let existing = viewers[name] { return existing }
        guard let computer = model.computer(named: name) else { return nil }
        let controller = ComputerViewerController(computer: computer)
        controller.onClose = { [weak self] in self?.closePage() }
        viewers[name] = controller
        return controller
    }

    private func closeViewer(_ name: String) {
        // Fechar o viewer não para o computador, não resolve o pedido e não muda o lease (CS-405).
        viewers[name]?.stop()
        viewers[name] = nil
    }

    public func openViewer(_ name: String) {
        guard model.computer(named: name) != nil else { return }
        show(.viewer(name))
        model.markReadForComputer(name)
    }

    /// O viewer no centro, ou o da janela própria.
    public var activeViewer: ComputerViewerController? {
        if case .viewer(let name) = page { return viewers[name] }
        return popOuts.values.first?.controller
    }

    func viewer(for argument: ActionArgument) -> ComputerViewerController? {
        if let name = argument.value, !name.isEmpty, let controller = viewers[name] ?? popOuts[name]?.controller { return controller }
        return activeViewer
    }

    // MARK: Painel direito

    public func setPanel(open: Bool) {
        guard panelOpen != open else { return }
        panelOpen = open
        onPanelChange(open)
    }

    public func togglePanel() { setPanel(open: !panelOpen) }

    // MARK: Janela própria (03 §11)

    public func popOut(_ name: String) {
        guard popOuts[name] == nil, let controller = viewers[name] else { return }
        let popOut = ViewerPopOut(controller: controller, computers: self) { [weak self] in
            self?.popOuts[name] = nil
            controller.stop()
        }
        popOuts[name] = popOut
        viewers[name] = nil
        if page == .viewer(name) {
            page = .workspace
            onPageChange()
        }
        popOut.show()
    }

    // MARK: Ações

    public func register(in registry: ActionRegistry) throws {
        let hasComputer: ActionRegistry.Enablement = { [unowned self] in
            model.rows.isEmpty && viewers.isEmpty ? .disabled(reason: String(localized: "No computers yet.", bundle: .module)) : .enabled
        }
        let viewerOpen: ActionRegistry.Enablement = { [unowned self] in
            activeViewer == nil ? .disabled(reason: String(localized: "Open a computer first.", bundle: .module)) : .enabled
        }
        try registry.register(.pageComputers) { [unowned self] _ in
            show(page == .computers ? .workspace : .computers)
            return page == .computers ? "computers" : "workspace"
        }
        try registry.register(.panelComputers) { [unowned self] _ in
            togglePanel()
            return panelOpen ? "open" : "closed"
        }
        try registry.register(.pageClose, enablement: { [unowned self] in page == .workspace ? .disabled(reason: "No page is open") : .enabled }) { [unowned self] _ in
            closePage()
            return nil
        }
        try registry.register(.computerOpenViewer, enablement: hasComputer) { [unowned self] arg in
            guard let name = arg.value ?? model.rows.first?.id else { throw ActionError.failed(.computerOpenViewer, message: "expected select(<computer>)") }
            openViewer(name)
            return name
        }
        try registry.register(.computerPopOut, enablement: viewerOpen) { [unowned self] arg in
            guard let controller = viewer(for: arg) else { return nil }
            popOut(controller.name)
            return controller.name
        }
        // ⇧⌘R: Take Over e Hand Back. De fora do viewer (Inbox, miniatura, notificação) abre o viewer antes.
        try registry.register(.computerTakeOver, enablement: hasComputer) { [unowned self] arg in
            if let name = arg.value, viewers[name] == nil, popOuts[name] == nil { openViewer(name) }
            guard let controller = viewer(for: arg) ?? activeViewer else { throw ActionError.failed(.computerTakeOver, message: "no viewer is open") }
            await controller.toggleControl()
            return controller.model.control.rawValue
        }
        try registry.register(.computerHandBack, enablement: viewerOpen) { [unowned self] arg in
            guard let controller = viewer(for: arg) else { return nil }
            if arg.kind == .set, controller.model.control == .human {  // `ctl ui action computer.handBack set "<nota>"`
                controller.model.handBackNote = arg.value ?? ""
                await controller.handBack()
                return controller.model.control.rawValue
            }
            switch arg.value {
            case "confirm": await controller.handBack()
            case "cancel": controller.model.cancelHandBackNote()
            default:
                if controller.model.control == .human { controller.model.showHandBackNote() }
            }
            return controller.model.control.rawValue
        }
        try registry.register(.computerForceTakeOver, enablement: viewerOpen) { [unowned self] arg in
            guard let controller = viewer(for: arg) else { return nil }
            await controller.takeOver(force: true)
            return controller.model.control.rawValue
        }
        try registry.register(.computerDeclineHelp, enablement: viewerOpen) { [unowned self] arg in
            guard let controller = viewer(for: arg) else { return nil }
            switch arg.value {
            case "confirm": await controller.model.confirmDecline()
            case "cancel": controller.model.cancelDecline()
            default: controller.model.showDecline()
            }
            return nil
        }
        try registry.register(
            .computerReleaseKeyboard,
            enablement: { [unowned self] in activeViewer?.model.keyboardCaptured == true ? .enabled : .disabled(reason: String(localized: "The keyboard is not captured.", bundle: .module)) }
        ) { [unowned self] _ in
            activeViewer?.releaseKeyboard()
            return nil
        }
        try registry.register(.computerReconnect, enablement: viewerOpen) { [unowned self] arg in
            viewer(for: arg)?.reconnectNow()
            return nil
        }
        let humanOnly: ActionRegistry.Enablement = { [unowned self] in
            activeViewer?.model.control == .human ? .enabled : .disabled(reason: String(localized: "Take over first.", bundle: .module))
        }
        try registry.register(.computerPaste, enablement: humanOnly) { [unowned self] _ in
            let count = await activeViewer?.pasteFromClipboard() ?? 0
            return "\(count)"
        }
        try registry.register(.computerCopySelection, enablement: viewerOpen) { [unowned self] _ in
            await activeViewer?.copySelection() == true ? "copied" : "empty"
        }
        // F12, modo Ask: o card de aprovação, o item do Inbox e a notificação disparam estas ações.
        let waiting: ActionRegistry.Enablement = { [unowned self] in
            model.approvals.isEmpty ? .disabled(reason: String(localized: "No computer request is waiting.", bundle: .module)) : .enabled
        }
        func decision(_ id: ActionID, _ decision: ComputerApprovalDecision) throws {
            try registry.register(id, enablement: waiting) { [unowned self] arg in
                guard let request = arg.value.flatMap({ value in model.approvals.first { $0.id == value } }) ?? model.approvals.first else {
                    throw ActionError.failed(id, message: "No computer request is waiting.")
                }
                model.decide(request.id, decision)
                return request.id
            }
        }
        try decision(.computerAllowRequest, .allow)
        try decision(.computerAllowRequestSession, .allowForSession)
        try decision(.computerDenyRequest, .deny)
        // "Open Docker": a linha do computador e o Settings oferecem quando o Docker está parado (07 CS-104).
        try registry.register(.dockerStart) { _ in
            DockerLauncher.open()
            return "opening"
        }
    }

    // MARK: Desenvolvimento e evidência (nunca em uso normal)

    /// `AGENTBOX_DEMO_COMPUTER=1`: sobe um computador de teste (labels `agentbox.test=1`), abre o viewer e, com `AGENTBOX_DEMO_HELP=1`,
    /// simula o filho pedindo ajuda (CAPTCHA). `AGENTBOX_VIEWER_MEASURE=<arquivo>` grava fps e latência medidos no WKWebView.
    public func startDemo(environment: [String: String]) {
        guard environment["AGENTBOX_DEMO_COMPUTER"] == "1" else { return }
        let home = (environment["AGENTBOX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) })
            ?? DemoComputerRig.defaultHome
        guard let root = environment["AGENTBOX_REPO_ROOT"].map({ URL(fileURLWithPath: $0, isDirectory: true) }) else {
            log.error("demo computer needs AGENTBOX_REPO_ROOT")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rig = try await DemoComputerRig.provision(repoRoot: root, home: home)
                self.demoRig = rig
                let marker = home.appendingPathComponent("demo-computer.run")
                try? Data("\(rig.runID)\n".utf8).write(to: marker)
                await self.add(rig.computer)
                await self.hub.registerChild(id: "demo-child", capability: "demo-capability")
                let service = ComputerToolService(hub: self.hub)
                _ = await service.call("box_claim", arguments: ["name": "demo-a", "wait_s": 5], child: "demo-child")
                _ = await service.call("browser_eval", arguments: DemoComputerRig.installScript(DemoComputerRig.animationHTML), child: "demo-child")
                self.startRefreshing()
                self.openViewer("demo-a")
                self.watchSnapshotRequests(home: home)
                await self.runDemoScript(rig: rig, service: service, environment: environment, home: home)
            } catch {
                self.log.error("demo computer failed: \(error)")
            }
        }
    }

    /// Evidência: o canvas do noVNC não entra na captura AppKit da janela (`ctl screenshot`). Escrever um caminho PNG em
    /// `<home>/snapshot-request` faz o app gravar a imagem do próprio WebView nesse caminho (`WKWebView.takeSnapshot`).
    private func watchSnapshotRequests(home: URL) {
        let trigger = home.appendingPathComponent("snapshot-request")
        try? Data().write(to: trigger)
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                guard let path = (try? String(contentsOf: trigger, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { continue }
                try? Data().write(to: trigger)
                if let png = await self.activeViewer?.web.snapshotPNG() { try? png.write(to: URL(fileURLWithPath: path)) }
            }
        }
    }

    private func runDemoScript(rig: DemoComputerRig, service: ComputerToolService, environment: [String: String], home: URL) async {
        if let path = environment["AGENTBOX_VIEWER_MEASURE"], let controller = viewers["demo-a"] {
            let seconds = Int(environment["AGENTBOX_VIEWER_MEASURE_SECONDS"] ?? "") ?? 12
            let result = await controller.measure(seconds: seconds) {
                _ = try? await rig.computer.backend.runtime("eval", DemoComputerRig.installScript(DemoComputerRig.inputHTML), timeout: 15)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(result) { try? data.write(to: URL(fileURLWithPath: path)) }
            await controller.handBack()
            _ = try? await rig.computer.backend.runtime("eval", DemoComputerRig.installScript(DemoComputerRig.animationHTML), timeout: 15)
        }
        guard environment["AGENTBOX_DEMO_HELP"] == "1" else { return }
        _ = try? await rig.computer.backend.runtime("eval", DemoComputerRig.installScript(DemoComputerRig.captchaHTML), timeout: 15)
        let requested = await service.call(
            "help_request", arguments: ["kind": "captcha", "reason": "hCaptcha on the permit search page", "url": "http://aca-prod.example.test/search"], child: "demo-child")
        let requestID = requested.content.first?["text"].flatMap { try? JSON.parse($0.string ?? "") }?["request_id"]?.string ?? ""
        let waited = await service.call("help_wait", arguments: ["request_id": .string(requestID), "wait_s": 50], child: "demo-child")
        var outcome = waited.content.first?["text"]?.string ?? ""
        for _ in 0..<20 where outcome.contains("\"open\"") {
            let again = await service.call("help_wait", arguments: ["request_id": .string(requestID), "wait_s": 50], child: "demo-child")
            outcome = again.content.first?["text"]?.string ?? ""
        }
        try? Data(outcome.utf8).write(to: home.appendingPathComponent("demo-help-wait.json"))
    }

    public func tearDownDemo() async { await demoRig?.cleanup() }
}

extension ComputersModel {
    /// Abrir o viewer de um computador marca como lidos os pedidos dele (03 §9.1: clicar leva ao viewer e marca lido).
    func markReadForComputer(_ name: String) {
        for item in inbox where item.computer == name { markRead(item.id) }
    }
}
