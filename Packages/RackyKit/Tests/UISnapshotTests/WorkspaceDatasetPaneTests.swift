import RackyProtocol
import RackyStore
import AppKit
import Foundation
import Testing

@testable import RackyUI

/// Dataset como tab da sessão e como pane ao lado do agente: abrir, dividir, arrastar, virar tab própria, fechar e persistir.
extension WorkspaceModelTests {
    @Test func aDatasetOpensAsItsOwnTabAndReusesIt() async throws {
        let rig = try await make(tabs: 1)
        defer { Task { await cleanup(rig) } }
        rig.model.contentSize = CGSize(width: 1400, height: 800)
        rig.model.datasetTitle = { $0 == "DS1" ? "books" : nil }
        let agentTab = try #require(rig.model.activeTabID)
        let pane = try #require(rig.model.openDataset("DS1"))
        #expect(rig.model.tabs.count == 2 && rig.model.activeTab?.layout.datasetIDs == ["DS1"])
        #expect(rig.model.activeTab.map { rig.model.displayTitle(of: $0) } == "books", "the tab is named after the dataset")
        rig.model.selectTab(agentTab)
        #expect(rig.model.openDataset("DS1") == pane && rig.model.tabs.count == 2, "opening again focuses the same tab")
        await rig.model.settlePersistence()
        let stored = try await rig.store.tabs(sessionID: rig.session.id)
        #expect(stored.contains { $0.layout.datasetIDs == ["DS1"] }, "the dataset tab is saved with the session")
    }

    @Test func aDatasetTabRenamesLikeAnyTab() async throws {
        let rig = try await make(tabs: 1)
        defer { Task { await cleanup(rig) } }
        rig.model.contentSize = CGSize(width: 1400, height: 800)
        rig.model.datasetTitle = { $0 == "DS1" ? "books2" : nil }
        _ = rig.model.openDataset("DS1")
        let tab = try #require(rig.model.activeTab)
        #expect(rig.model.beginRename(tab.id))
        rig.model.commitRename("Livros do teste")
        #expect(rig.model.activeTab.map { rig.model.displayTitle(of: $0) } == "Livros do teste")
    }

    @Test func besideTheAgentSplitsTheActiveTabAndMovesAnExistingDatasetTabIn() async throws {
        let rig = try await make(tabs: 1)
        defer { Task { await cleanup(rig) } }
        rig.model.contentSize = CGSize(width: 1400, height: 800)
        let agentTab = try #require(rig.model.activeTabID)
        let terminal = try #require(rig.model.activeTab?.layout.terminalIDs.first)
        // Já aberto numa tab própria: "beside" junta essa tab à do agente.
        _ = rig.model.openDataset("DS1")
        rig.model.selectTab(agentTab)
        _ = rig.model.openDataset("DS1", beside: true)
        #expect(rig.model.tabs.count == 1 && rig.model.activeTabID == agentTab)
        guard case .split(let axis, _, let first, let second)? = rig.model.activeTab?.layout else { Issue.record("expected a split"); return }
        #expect(axis == .horizontal && first.terminalIDs == [terminal] && second.datasetIDs == ["DS1"], "agent left, table right")
        #expect(rig.model.focusedTerminalID == terminal, "the agent keeps the keyboard")
        // Outro dataset ao lado, direto.
        _ = rig.model.openDataset("DS2", beside: true)
        #expect(rig.model.activeTab?.layout.datasetIDs.sorted() == ["DS1", "DS2"] && rig.model.tabs.count == 1)
    }

    @Test func aDatasetPaneDragsBetweenSidesTabsAndItsOwnTab() async throws {
        let rig = try await make(tabs: 2)
        defer { Task { await cleanup(rig) } }
        rig.model.contentSize = CGSize(width: 1400, height: 800)
        let tabs = rig.model.tabs
        let agent = try #require(tabs[0].layout.terminalIDs.first)
        let agentPane = try #require(tabs[0].layout.pane(forTerminal: agent)?.id)
        rig.model.selectTab(tabs[0].id)
        let pane = try #require(rig.model.openDataset("DS1", beside: true))
        // Para baixo do agente (vertical).
        #expect(rig.model.performDrop(.otherPane(pane), onPane: agentPane, zone: .bottom) == .applied)
        guard case .split(let axis, _, _, let second)? = rig.model.tab(tabs[0].id)?.layout else { Issue.record("split"); return }
        #expect(axis == .vertical && second.datasetIDs == ["DS1"])
        // Sobre o pane do agente da outra tab: vai para lá.
        let other = try #require(tabs[1].layout.terminalIDs.first)
        rig.model.selectTab(tabs[1].id)
        #expect(rig.model.performDrop(.otherPane(pane), onTerminal: other, zone: .left) == .applied)
        #expect(rig.model.tab(tabs[1].id)?.layout.datasetIDs == ["DS1"] && rig.model.tab(tabs[0].id)?.layout.datasetIDs == [])
        // Para a tab row: vira tab própria.
        #expect(rig.model.detachPane(paneID: pane, toIndex: 0) == .applied)
        #expect(rig.model.tabs.first?.layout.datasetIDs == ["DS1"] && rig.model.tabs.count == 3)
        // Um terminal arrastado para cima do pane do dataset também divide.
        #expect(rig.model.performDrop(.pane(agent), onPane: pane, zone: .right) == .applied)
        #expect(rig.model.tabs.first?.layout.terminalIDs == [agent] && rig.model.tabs.first?.layout.datasetIDs == ["DS1"])
        #expect(rig.model.performDrop(.otherPane(pane), onPane: pane, zone: .left) == .invalid, "a pane can't drop on itself")
    }

    @Test func closingADatasetPaneKeepsTheAgentAndClosingItsTabRemovesIt() async throws {
        let rig = try await make(tabs: 1)
        defer { Task { await cleanup(rig) } }
        rig.model.contentSize = CGSize(width: 1400, height: 800)
        let agentTab = try #require(rig.model.activeTabID)
        let terminal = try #require(rig.model.activeTab?.layout.terminalIDs.first)
        let beside = try #require(rig.model.openDataset("DS1", beside: true))
        rig.model.closePane(id: beside)
        #expect(rig.model.tabs.count == 1 && rig.model.activeTab?.layout.terminalIDs == [terminal] && rig.model.activeTab?.layout.datasetIDs == [])
        _ = rig.model.openDataset("DS1")
        let datasetTab = try #require(rig.model.activeTabID)
        #expect(datasetTab != agentTab)
        rig.model.closeTab(datasetTab)
        #expect(rig.model.tabs.map(\.id) == [agentTab], "a dataset-only tab closes without asking")
        await rig.model.settlePersistence()
        #expect(try await rig.store.tab(id: datasetTab)?.closedAt != nil)
    }

    @Test func paneContentRoundTripsThroughJSON() throws {
        let layout = PaneLayout.split(
            axis: .horizontal, ratio: 0.5, first: .leaf(Pane(content: .terminal(UUID()))), second: .leaf(Pane(content: .dataset("01DATASET"))))
        let decoded = try JSONDecoder().decode(PaneLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout && decoded.datasetIDs == ["01DATASET"])
    }
}
