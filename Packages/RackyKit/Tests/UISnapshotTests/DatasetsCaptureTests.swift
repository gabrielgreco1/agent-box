import RackyCore
import RackyProtocol
import RackyStore
import AppKit
import Foundation
import Testing

@testable import RackyUI

/// Prints da janela inteira com a lista de datasets e a tabela de hotéis (30 linhas, 2 inválidas, uma linha selecionada com a proveniência),
/// para revisar o visual. Só roda com `RACKY_CAPTURE_DIR=<pasta>`; grava `datasets-list.png` e `dataset-page.png`. O store é de um
/// `RACKY_HOME` temporário.
@MainActor
@Suite(.serialized, .offscreenAppKit, .enabled(if: ProcessInfo.processInfo.environment["RACKY_CAPTURE_DIR"] != nil)) struct DatasetsCaptureTests {
    private func write(_ view: NSView, _ name: String) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RACKY_CAPTURE_DIR"]!)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    @Test func captureDatasetsPages() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("racky-datasets-capture-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(environment: ["RACKY_SKIP_ONBOARDING": "1", "RACKY_HOME": home.path, "RACKY_TEST_HEADLESS": "1"])
        // Sem `env.start()` (ele abriria o app.sock e o hub): a sidebar recebe o elenco de exemplo e o store temporário é ligado à mão.
        let cast = SidebarFixtures.full()
        env.sidebar.apply(cast.snapshot)
        let session = try #require(cast.selectedSessionID)
        env.sidebar.select(session)
        let c = await EmptyWindowTreeTests.host(env, size: NSSize(width: 1400, height: 860))
        defer { c.window?.close() }
        let store = try await RackyStore.open(paths: StorePaths(root: home))
        defer { Task { try? await store.close() } }
        try await store.save(Session(id: session, kind: .clean, folderPath: "/tmp/hotels", title: "Hotel prices"))
        await env.datasets.attach(store: store)
        let service = DatasetService(store: store)
        try await DatasetsFixture.seedHotels(service: service, session: session)
        try await store.createDataset(Dataset(
            id: ULID.generate(), sessionID: session, name: "permits", columns: [DatasetColumn(name: "permit_id"), DatasetColumn(name: "status")], key: ["permit_id"]))
        _ = try await service.define(session: session, name: "reviews", columns: [DatasetColumn(name: "hotel"), DatasetColumn(name: "stars", type: .integer)], key: nil)
        _ = try await service.append(session: session, name: "reviews", rows: (0..<240).map { ["hotel": .string("Hotel \($0 % 30)"), "stars": .int(1 + $0 % 5)] }, provenance: .none)
        await env.datasets.reloadList()

        _ = try await env.registry.perform(.pageDatasets, .press)
        await VisualBatchTests.settle(800)
        write(c.window!.contentView!, "datasets-list")

        let hotels = try #require(try await store.dataset(sessionID: session, name: "hotels"))
        _ = try await env.registry.perform(.datasetOpen, .select(hotels.id))
        let selected = try #require(env.datasets.snapshot?.rows.first)
        _ = try await env.registry.perform(.datasetSelectRow, .select(selected.id))
        await VisualBatchTests.settle(800)
        write(c.window!.contentView!, "dataset-page")
    }
}
