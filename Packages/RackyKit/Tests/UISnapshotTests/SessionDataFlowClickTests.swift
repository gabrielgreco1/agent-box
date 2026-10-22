import RackyCore
import RackyProtocol
import RackyStore
import AppKit
import Foundation
import Testing

@testable import RackyUI

/// O caminho de quem usa: numa sessão com agentes e um dataset, abrir a tabela pelo "+", pôr ao lado do agente, voltar para as tabs
/// e seguir a trilha. Tudo com cliques de mouse de verdade (eventos da janela), não as ações direto.
@MainActor
@Suite(.serialized, .offscreenAppKit, .tags(.integration)) struct SessionDataFlowClickTests {
    private struct Rig {
        let env: AppEnvironment
        let window: NSWindow
        let controller: MainWindowController
        let store: RackyStore
        let home: URL
        let datasetID: String
    }

    private func make() async throws -> Rig {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("racky-flow-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let env = AppEnvironment(environment: ["RACKY_SKIP_ONBOARDING": "1", "RACKY_HOME": home.path, "RACKY_TEST_HEADLESS": "1", "RACKY_DATA_DEMO": "1"])
        let cast = SidebarFixtures.full()
        env.sidebar.apply(cast.snapshot)
        let session = try #require(cast.selectedSessionID)
        env.sidebar.select(session)
        let c = await EmptyWindowTreeTests.host(env, size: NSSize(width: 1500, height: 900))
        let window = try #require(c.window)
        window.makeKeyAndOrderFront(nil)
        let store = try await RackyStore.open(paths: StorePaths(root: home))
        try await store.save(Session(id: session, kind: .clean, folderPath: "/tmp/books", title: "Book prices"))
        await env.datasets.attach(store: store)
        let service = DatasetService(store: store)
        _ = try await service.define(session: session, name: "books2", columns: [DatasetColumn(name: "title", required: true)], key: ["title"])
        _ = try await service.append(session: session, name: "books2", rows: [["title": .string("Doctor Sleep")]], provenance: .none)
        await env.datasets.reloadList()
        let id = try #require(env.datasets.summaries.first { $0.dataset.name == "books2" }?.dataset.id)
        await VisualBatchTests.settle(500)
        return Rig(env: env, window: window, controller: c, store: store, home: home, datasetID: id)
    }

    private func close(_ rig: Rig) async {
        rig.window.close()
        try? await rig.store.close()
        try? FileManager.default.removeItem(at: rig.home)
    }

    /// Com `RACKY_FLOW_SHOTS=<pasta>`, salva a janela como ela está (para a rodada de testers por tarefa).
    private func shot(_ rig: Rig, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["RACKY_FLOW_SHOTS"], let view = rig.window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func click(_ rig: Rig, _ id: A11yID, count: Int = 1) throws {
        let frame = try #require(rig.env.elements.frame(of: id), "\(id.rawValue) is not on screen")
        let height = rig.window.contentView?.bounds.height ?? 0
        let point = CGPoint(x: frame.midX, y: height - frame.midY)
        for n in 1...count {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                rig.window.sendEvent(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: rig.window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: n, pressure: type == .leftMouseUp ? 0 : 1)!)
            }
        }
    }

    /// O "+" abre o menu logo abaixo dele (não no canto da janela), com seções nomeadas e o dataset da sessão.
    @Test func plusOpensTheMenuUnderItAndOffersTheSessionData() async throws {
        let rig = try await make()
        defer { Task { await close(rig) } }
        shot(rig, "flow-1-session")
        try click(rig, .tabsNew)
        await VisualBatchTests.settle(500)
        shot(rig, "flow-2-plus-menu")
        // A view do menu na janela (os frames de dentro do menu são relativos a ele).
        func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
        let root = try #require(rig.window.contentView)
        let plus = try #require(rig.env.elements.frame(of: .tabsNew))
        let menu = try #require(views(root).first { abs($0.frame.width - QuickLaunchModel.width) < 1 && $0 !== root }, "the menu should open")
        let menuFrame = menu.convert(menu.bounds, to: nil)
        let menuTop = root.bounds.height - menuFrame.maxY
        #expect(abs(menuTop - plus.maxY) < 40, "the menu hangs right under the + (menu top \(menuTop), + bottom \(plus.maxY))")
        #expect(abs(menuFrame.minX - plus.minX) < QuickLaunchModel.width, "the menu sits by the +, not in the window corner (x \(menuFrame.minX), + \(plus.minX))")
        // Digita o nome e aperta Enter: "Open books2" abre a tabela numa tab da sessão.
        func key(_ chars: String, code: UInt16) throws {
            rig.window.sendEvent(try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: rig.window.windowNumber,
                context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)))
        }
        for ch in "books2" { try key(String(ch), code: 0) }
        await VisualBatchTests.settle(200)
        try key("\r", code: 36)
        await VisualBatchTests.settle(600)
        shot(rig, "flow-3-table-tab")
        let active = try #require(rig.env.workspace.activeTab)
        #expect(rig.env.workspace.datasetOnly(active) == rig.datasetID, "Open books2 should show the table in its own tab")
        #expect(rig.env.workspace.displayTitle(of: active) == "books2")
    }

    /// Da tab do dataset, "Beside the agent" junta a tabela com o agente na mesma tab; o nome da tab dos agentes não vira books2.
    @Test func besideTheAgentFromTheDatasetTabJoinsTheAgentTab() async throws {
        let rig = try await make()
        defer { Task { await close(rig) } }
        _ = try await rig.env.registry.perform(.datasetOpen, .select(rig.datasetID))
        await VisualBatchTests.settle(600)
        try click(rig, .dataBeside)
        await VisualBatchTests.settle(600)
        shot(rig, "flow-4-beside")
        let active = try #require(rig.env.workspace.activeTab)
        #expect(!active.layout.terminalIDs.isEmpty, "the table should now sit in the agent's tab")
        #expect(active.layout.pane(forDataset: rig.datasetID) != nil)
        #expect(rig.env.workspace.displayTitle(of: active) != "books2", "the agents' tab keeps its own name")
        // Ao lado do agente, "Own tab" devolve a tabela para uma tab própria.
        try click(rig, .dataOwnTab)
        await VisualBatchTests.settle(500)
        let own = try #require(rig.env.workspace.activeTab)
        #expect(rig.env.workspace.datasetOnly(own) == rig.datasetID, "Own tab puts the table back in its own tab")
    }

    /// Na trilha da tabela dentro da sessão, clicar num lugar leva para a área Data já nele.
    @Test func aPathChipInTheSessionGoesToThatPlace() async throws {
        let rig = try await make()
        defer { Task { await close(rig) } }
        _ = try await rig.env.registry.perform(.datasetOpen, .select(rig.datasetID))
        await VisualBatchTests.settle(600)
        // A cópia de exemplo no Supabase (books2 alimenta public.books nas conexões de exemplo).
        let chip = A11yID.dataFlowItem("place-conn-supabase-public.books")
        guard rig.env.elements.frame(of: chip) != nil else {
            Issue.record("the Supabase copy is not in the session's path")
            return
        }
        try click(rig, chip)
        await VisualBatchTests.settle(600)
        shot(rig, "flow-5-after-path-click")
        #expect(rig.env.datasets.currentPage() == .datasets, "the click should open the Data area")
        #expect(rig.env.dataHub.active == .table(connection: "conn-supabase", schema: "public", name: "books"))
        // E volta para a sessão pelo "‹ Session" que aparece no topo da área Data.
        try click(rig, .dataBackToSession)
        await VisualBatchTests.settle(500)
        #expect(rig.env.datasets.currentPage() == .workspace, "‹ Session goes back to the session")
    }

    /// Abre a tabela, vai para o agente e volta clicando na tab da tabela: as duas tabs têm nomes diferentes e o clique troca de tab.
    @Test func goingToTheAgentAndBackToTheTableByClickingTabs() async throws {
        let rig = try await make()
        defer { Task { await close(rig) } }
        let agentTab = try #require(rig.env.workspace.activeTab)
        _ = try await rig.env.registry.perform(.datasetOpen, .select(rig.datasetID))
        await VisualBatchTests.settle(500)
        let datasetTab = try #require(rig.env.workspace.activeTab)
        #expect(datasetTab.id != agentTab.id)
        #expect(rig.env.workspace.displayTitle(of: agentTab) != rig.env.workspace.displayTitle(of: datasetTab), "two tabs with the same name can't be told apart")
        try click(rig, .tabsTab(agentTab.id.uuidString))
        await VisualBatchTests.settle(400)
        shot(rig, "flow-6-agent-tab-with-table-tab")
        #expect(rig.env.workspace.activeTab?.id == agentTab.id, "clicking the agent's tab shows the agent")
        try click(rig, .tabsTab(datasetTab.id.uuidString))
        await VisualBatchTests.settle(400)
        #expect(rig.env.workspace.activeTab?.id == datasetTab.id, "clicking the table's tab goes back to the table")
    }
}
