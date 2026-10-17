import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxStore
import AppKit
import Foundation

/// Seletor de pasta de "New Clean Session in Folder…" (03 §2.10): `NSOpenPanel` escuro. O app não cria nem apaga nada na pasta.
@MainActor
struct CleanFolderPicker: FolderPicking {
    func chooseFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.title = String(localized: "New Clean Session in Folder", bundle: .module)
        panel.message = String(localized: "Pick the folder the session works in. Agent Box won't create or delete anything in it.", bundle: .module)
        panel.prompt = String(localized: "Start Session", bundle: .module)
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
        return response == .OK ? panel.url : nil
    }
}

/// Sessões limpas (P10, P11): criar em um clique, criar numa pasta escolhida, arquivar, apagar e promover a projeto.
/// Os handlers vão para o `ActionRegistry`: sidebar, menu File, landing, atalhos e `ctl ui action` disparam o mesmo código.
@MainActor
final class CleanSessionController {
    private let launcher: SessionLauncher
    private let sidebar: SidebarModel
    private let workspace: WorkspaceModel
    private let overlays: OverlayRouter
    private let toasts: ToastCenter
    private let elements: UIElementStore
    private let settings: SettingsModel
    private let projects: ProjectsController
    private let sessionsRoot: () -> URL
    private let runsRoot: () -> URL
    private let automationEnabled: Bool
    var picker: any FolderPicking = CleanFolderPicker()
    /// Move para o Lixo do macOS (recuperável); os testes trocam por um destino temporário.
    var trashItem: (URL) throws -> Void = CleanSessionFolders.systemTrash
    private var store: AgentBoxStore?
    private var pendingArchive: UUID?
    private(set) var pendingDelete: DeleteSessionState?
    private(set) var pendingMove: MoveToProjectState?
    private weak var registry: ActionRegistry?
    private let log = LogFacade(.app, category: "clean-sessions")

    init(
        launcher: SessionLauncher, sidebar: SidebarModel, workspace: WorkspaceModel, overlays: OverlayRouter, toasts: ToastCenter,
        elements: UIElementStore, settings: SettingsModel, projects: ProjectsController, sessionsRoot: @escaping () -> URL,
        runsRoot: @escaping () -> URL, automationEnabled: Bool
    ) {
        self.launcher = launcher
        self.sidebar = sidebar
        self.workspace = workspace
        self.overlays = overlays
        self.toasts = toasts
        self.elements = elements
        self.settings = settings
        self.projects = projects
        self.sessionsRoot = sessionsRoot
        self.runsRoot = runsRoot
        self.automationEnabled = automationEnabled
    }

    func attach(store: AgentBoxStore) { self.store = store }

    // MARK: Criar

    /// Agente padrão pronto para uso? `nil` = pode usar; senão o motivo (03 §24.2).
    private func defaultAgentBlockReason() -> String? {
        let agent = settings.settings.agents.defaultAgent
        guard settings.agent(agent)?.installedState == false else { return nil }
        return String(localized: "Install \(AgentInfo.displayName(agent)) or choose another default agent.", bundle: .module)
    }

    /// ⇧⌘N e o `+` de "Sessions": pasta nova gerenciada + agente padrão, sem diálogo (AC-1101). `set(<json>)` troca o agente, o modelo,
    /// os argumentos ou o prompt (automação e testes; é o mesmo pedido de `session.launch`).
    func newCleanSession(_ arg: ActionArgument) async throws -> String? {
        var request = SessionLaunchRequest()
        if arg.kind == .set, let raw = arg.value, let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(SessionLaunchRequest.self, from: data) {
            request = decoded
            request.cwd = nil
        }
        return try await start(request, action: .sessionNewClean)
    }

    /// ⌥⇧⌘N: `NSOpenPanel` e sessão na pasta escolhida (AC-1105). `set(<pasta ou json>)` pula o painel (só com a automação ligada).
    func newCleanSessionInFolder(_ arg: ActionArgument) async throws -> String? {
        var request = SessionLaunchRequest()
        if arg.kind == .set {
            guard automationEnabled, let raw = arg.value, !raw.isEmpty else {
                throw ActionError.failed(.sessionNewCleanInFolder, message: "Automation is off")
            }
            if let data = raw.data(using: .utf8), let decoded = try? JSONDecoder().decode(SessionLaunchRequest.self, from: data) {
                request = decoded
            } else {
                request.cwd = raw
            }
            guard request.cwd?.isEmpty == false else { throw ActionError.failed(.sessionNewCleanInFolder, message: "expected a folder") }
        } else {
            guard let url = await picker.chooseFolder() else { return "cancelled" }
            request.cwd = url.path
        }
        return try await start(request, action: .sessionNewCleanInFolder)
    }

    private func start(_ original: SessionLaunchRequest, action: ActionID) async throws -> String? {
        var request = original
        if request.provider == nil {
            if let reason = defaultAgentBlockReason() { throw ActionError.failed(action, message: reason) }
            request.provider = settings.settings.agents.defaultAgent.rawValue
        }
        if request.origin == nil, let frame = elements.frame(of: .sidebarCleanSessionsNew), frame.width > 0 {
            request.origin = [Double(frame.midX), Double(frame.midY)]
        }
        return try await launcher.launch(request)
    }

    // MARK: Arquivar

    private func target(_ arg: ActionArgument, _ id: ActionID) throws -> Session {
        let raw = arg.kind == .select ? arg.value : sidebar.selectedSession?.uuidString
        guard let raw, let uuid = UUID(uuidString: raw), let session = sidebar.session(uuid) else {
            throw ActionError.failed(id, message: "Session not found")
        }
        return session
    }

    func archive(_ session: Session) async throws {
        guard let store else { throw ActionError.failed(.dialogArchiveConfirm, message: "Store not ready") }
        sidebar.leave(session: session.id)
        await workspace.stopTerminals(ofSession: session.id)
        var archived = session
        archived.lifecycle = .archived
        archived.archivedAt = Date()
        try await store.save(archived)
        toasts.show(kind: .success, title: String(localized: "Session archived.", bundle: .module))
    }

    // MARK: Apagar

    /// Apaga a sessão: para os terminais, remove o registro e, só para pasta criada pelo app, move a pasta para o Lixo
    /// (recuperável) e, se pedido, apaga os run folders (AC-1108). Pasta escolhida nunca é tocada (AC-1105).
    func delete(_ state: DeleteSessionState) async throws {
        guard let store, let session = sidebar.session(state.sessionID) else { throw ActionError.failed(.dialogDeleteSessionConfirm, message: "Session not found") }
        sidebar.leave(session: session.id)
        await workspace.stopTerminals(ofSession: session.id)
        try await store.deleteSession(id: session.id)
        if state.managedFolder, state.trashFolder {
            do {
                try CleanSessionFolders.trash(folder: session.folderPath, managed: session.managedFolder, sessionsRoot: sessionsRoot(), mover: trashItem)
            } catch {
                log.error("could not trash session folder: \(error)")
                toasts.show(kind: .error, title: String(localized: "Couldn't move the folder to the Trash.", bundle: .module), detail: error.localizedDescription)
            }
        }
        if state.deleteRuns { _ = try? CleanSessionFolders.deleteRunFolders(forSession: session.id, runsRoot: runsRoot()) }
        if state.dontAsk, let registry { _ = try? await registry.perform(.settingsGeneralConfirmDeleteSession, .set("off")) }
        toasts.show(kind: .success, title: String(localized: "Session deleted.", bundle: .module))
    }

    // MARK: Promover

    func move(_ state: MoveToProjectState) async throws {
        guard let store, let session = sidebar.session(state.sessionID) else { throw ActionError.failed(.dialogMoveToProjectConfirm, message: "Session not found") }
        let projectID: UUID
        let name: String
        if state.isConvert {
            // "New Project from This Folder": a pasta vira a raiz; tipo `git` se já é repositório, sem `git init`.
            let project = try await projects.addProject(folder: URL(fileURLWithPath: session.folderPath, isDirectory: true))
            projectID = project.id
            name = project.name
        } else if let id = state.projectID, let project = sidebar.project(id) {
            projectID = id
            name = project.name
        } else {
            throw ActionError.failed(.dialogMoveToProjectConfirm, message: "Choose a project.")
        }
        try await store.save(SessionPromotion.attach(session, to: projectID))
        toasts.show(kind: .success, title: String(localized: "Moved to \(name).", bundle: .module))
    }

    // MARK: Registro de ações

    func register(in registry: ActionRegistry) throws {
        self.registry = registry
        let blocked: ActionRegistry.Enablement = { [unowned self] in
            defaultAgentBlockReason().map { .disabled(reason: $0) } ?? .enabled
        }
        try registry.register(.sessionNewClean, enablement: blocked) { [unowned self] arg in try await newCleanSession(arg) }
        try registry.register(.sessionNewCleanInFolder, enablement: blocked) { [unowned self] arg in try await newCleanSessionInFolder(arg) }

        // Arquivar (03 §16.2)
        try registry.register(.sessionArchive) { [unowned self] arg in
            let session = try target(arg, .sessionArchive)
            pendingArchive = session.id
            let opened = overlays.present(.confirmation(.archiveSession(name: session.title)), from: .sidebarSession(session.id.uuidString))
            if !opened { pendingArchive = nil }
            return opened ? "confirming" : "busy"
        }
        try registry.register(.dialogArchiveCancel) { [unowned self] _ in
            pendingArchive = nil
            overlays.dismiss(.action)
            return nil
        }
        try registry.register(.dialogArchiveConfirm) { [unowned self] _ in
            guard let id = pendingArchive, let session = sidebar.session(id) else { throw ActionError.failed(.dialogArchiveConfirm, message: "Nothing to archive") }
            pendingArchive = nil
            overlays.dismiss(.action)
            try await archive(session)
            return "archived"
        }

        // Apagar (03 §16.5)
        try registry.register(.sessionDelete) { [unowned self] arg in
            let session = try target(arg, .sessionDelete)
            guard session.kind == .clean else {
                toasts.show(kind: .info, title: String(localized: "Deleting worktree and project sessions isn't available yet.", bundle: .module),
                            detail: String(localized: "Archive it instead.", bundle: .module))
                return "unsupported"
            }
            let state = DeleteSessionState(sessionID: session.id, title: session.title, managedFolder: session.managedFolder)
            guard settings.settings.general.confirmDeleteSession else {
                try await delete(state)
                return "deleted"
            }
            pendingDelete = state
            let opened = overlays.present(.deleteSession(state), from: .sidebarSession(session.id.uuidString))
            if !opened { pendingDelete = nil }
            return opened ? "confirming" : "busy"
        }
        func flag(_ arg: ActionArgument, current: Bool) -> Bool {
            switch arg.value {
            case "on": true
            case "off": false
            default: !current
            }
        }
        try registry.register(.dialogDeleteSessionTrashFolder) { [unowned self] arg in
            guard let state = pendingDelete else { return nil }
            state.trashFolder = flag(arg, current: state.trashFolder)
            return state.trashFolder ? "on" : "off"
        }
        try registry.register(.dialogDeleteSessionDeleteRuns) { [unowned self] arg in
            guard let state = pendingDelete else { return nil }
            state.deleteRuns = flag(arg, current: state.deleteRuns)
            return state.deleteRuns ? "on" : "off"
        }
        try registry.register(.dialogDeleteSessionDontAsk) { [unowned self] arg in
            guard let state = pendingDelete else { return nil }
            state.dontAsk = flag(arg, current: state.dontAsk)
            return state.dontAsk ? "on" : "off"
        }
        try registry.register(.dialogDeleteSessionCancel) { [unowned self] _ in
            pendingDelete = nil
            overlays.dismiss(.action)
            return nil
        }
        try registry.register(.dialogDeleteSessionConfirm) { [unowned self] _ in
            guard let state = pendingDelete else { throw ActionError.failed(.dialogDeleteSessionConfirm, message: "Nothing to delete") }
            pendingDelete = nil
            overlays.dismiss(.action)
            try await delete(state)
            return "deleted"
        }

        // Promover (03 §16.8)
        func presentMove(_ arg: ActionArgument, convert: Bool, id: ActionID) throws -> String? {
            let session = try target(arg, id)
            guard session.kind == .clean else { throw ActionError.failed(id, message: "Only a clean session can be moved to a project") }
            let live = sidebar.snapshot.projects.filter { $0.archivedAt == nil }
            let state = MoveToProjectState(
                sessionID: session.id, title: session.title, projects: live, selection: convert ? MoveToProjectState.convertID : "")
            pendingMove = state
            let opened = overlays.present(.moveToProject(state), from: .sidebarSession(session.id.uuidString))
            if !opened { pendingMove = nil }
            return opened ? "opened" : "busy"
        }
        try registry.register(.sessionMoveToProject) { arg in try presentMove(arg, convert: false, id: .sessionMoveToProject) }
        try registry.register(.sessionConvertToProject) { arg in try presentMove(arg, convert: true, id: .sessionConvertToProject) }
        try registry.register(.dialogMoveToProjectSetProject) { [unowned self] arg in
            guard let state = pendingMove, arg.kind == .select, let value = arg.value else { return nil }
            guard value == MoveToProjectState.convertID || state.projects.contains(where: { $0.id.uuidString == value }) else {
                throw ActionError.failed(.dialogMoveToProjectSetProject, message: "Unknown project")
            }
            state.selection = value
            return value
        }
        try registry.register(.dialogMoveToProjectCancel) { [unowned self] _ in
            pendingMove = nil
            overlays.dismiss(.action)
            return nil
        }
        try registry.register(
            .dialogMoveToProjectConfirm,
            enablement: { [unowned self] in
                (pendingMove?.selection ?? "").isEmpty ? .disabled(reason: String(localized: "Choose a project.", bundle: .module)) : .enabled
            }
        ) { [unowned self] _ in
            guard let state = pendingMove else { throw ActionError.failed(.dialogMoveToProjectConfirm, message: "Nothing to move") }
            pendingMove = nil
            overlays.dismiss(.action)
            try await move(state)
            return "moved"
        }
    }
}
