import Foundation
import Observation
import RackyCore
import RackyProtocol
import RackyStore

/// Estado da área Data: conexões, o que está expandido no explorer, as tabs abertas e a ativa. Os datasets do Racky vêm do
/// `DatasetsController` (a página de dataset continua sendo a dele); as conexões são de exemplo na etapa 2.
@MainActor
@Observable
public final class DataHubController {
    public let datasets: DatasetsController
    public private(set) var connections: [DataConnection] = []
    public private(set) var tabs: [DataObject] = []
    public private(set) var active: DataObject?
    public private(set) var expanded: Set<String> = []
    /// Página da grade de cada tabela de conexão.
    public private(set) var tablePages: [DataObject: Int] = [:]
    public func tablePage(_ object: DataObject) -> Int { tablePages[object] ?? 0 }

    /// Sub-aba de cada tabela aberta (`data`, `structure`, `writers`).
    public private(set) var tableTabs: [DataObject: DataTableTab] = [:]
    /// Texto de cada consulta aberta e o resultado da última execução.
    public var queryText: [DataObject: String] = [:]
    public private(set) var queryResult: [DataObject: (grid: DataGrid, milliseconds: Int)] = [:]
    public private(set) var showingConnect = false
    /// Explorer: largura arrastada pelo usuário e se está recolhido.
    public var explorerWidth: CGFloat = 268
    public private(set) var explorerHidden = false
    /// Quem o usuário pausou (agentes e cópias), por id.
    public private(set) var paused: Set<String> = []
    private var nextQuery = 1
    @ObservationIgnored var now: () -> Date = { Date() }

    /// Conexões de exemplo (RACKY_DATA_DEMO=1): a página avisa que nada está conectado.
    public let isDemo: Bool

    public init(datasets: DatasetsController, demo: Bool) {
        self.datasets = datasets
        isDemo = demo
        if demo {
            connections = DataHubFixtures.connections
            expanded = [DataHubFixtures.supabase, "\(DataHubFixtures.supabase)/public"]
        }
    }

    // MARK: Leitura

    public func connection(_ id: String?) -> DataConnection? { connections.first { $0.id == id } }

    /// Sessões com datasets, na ordem da lista (a mais recente primeiro).
    public var rackyGroups: [(session: String, datasets: [DatasetSummary])] {
        var order: [String] = []
        var groups: [String: [DatasetSummary]] = [:]
        for summary in datasets.summaries {
            let title = datasets.title(of: summary)
            if groups[title] == nil { order.append(title) }
            groups[title, default: []].append(summary)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    public func summary(ofDataset id: String) -> DatasetSummary? { datasets.summaries.first { $0.dataset.id == id } }

    public func datasetID(named name: String) -> String? { datasets.summaries.first { $0.dataset.name == name }?.dataset.id }

    public func writers(of object: DataObject) -> [DataWriter] {
        if case .dataset(let id) = object, let summary = summary(ofDataset: id) {
            // Os agentes da sessão que coletaram (computadores do dataset).
            // Cada computador que coletou, com o nome do agente que o usou ("Codex 1"; id = o computador).
            let agents = (datasets.models[id]?.snapshot?.facets[.computer] ?? []).map { (computer: $0.value, name: datasets.computerLabel($0.value) ?? $0.value) }
            let live = datasets.isCollecting(summary)
            let session = datasets.title(of: summary)
            guard !agents.isEmpty else {
                // Sem o nome do agente (dataset antigo): pelo menos a sessão que coletou.
                return summary.rowCount == 0 ? [] : [DataWriter(id: "session", kind: .agent(session: session), name: String(localized: "Agents", bundle: .module), live: live, detail: live ? "writing now" : "")]
            }
            return agents.map { DataWriter(id: $0.computer, kind: .agent(session: session), name: $0.name, live: live && !paused.contains($0.computer), detail: live ? "writing now" : "") }
        }
        return DataHubFixtures.writers(of: object) { [weak self] in self?.datasetID(named: $0) }.map { writer in
            var writer = writer
            if paused.contains(writer.id) { writer.live = false; writer.detail = String(localized: "paused", bundle: .module) }
            return writer
        }
    }

    public func destinations(of object: DataObject) -> [DataDestination] {
        guard case .dataset(let id) = object, let name = summary(ofDataset: id)?.dataset.name, !connections.isEmpty else { return [] }
        return DataHubFixtures.destinations(ofDataset: name)
    }

    /// A fonte de uma cópia: o dataset do Racky que um sync copia para cá (a "fonte de verdade").
    public func copySource(of object: DataObject) -> String? {
        for writer in writers(of: object) { if case .sync(let from) = writer.kind, case .dataset(let name) = from { return name } }
        return nil
    }

    /// Nome mostrado de um dataset do Mac a partir do nome original (depois de renomear, os textos usam o novo).
    public func displayName(ofDatasetNamed name: String) -> String {
        datasetID(named: name).flatMap { datasets.name(of: $0) } ?? name
    }

    /// Algo está gravando neste nó agora (ponto "live" no explorer)?
    public func isLive(_ object: DataObject) -> Bool { writers(of: object).contains { $0.live } }

    // MARK: Ações locais

    public func open(_ object: DataObject) {
        if !tabs.contains(object) { tabs.append(object) }
        active = object
        if case .dataset(let id) = object { Task { _ = await datasets.openInHub(id) } }
        if tableTabs[object] == nil { tableTabs[object] = .data }
        if let feeding = feedingDataset(of: object) { Task { await datasets.prepare(feeding) } }
        if case .query = object, queryText[object] == nil { queryText[object] = DataHubFixtures.sampleQuery }
    }

    public func close(_ object: DataObject) {
        guard let index = tabs.firstIndex(of: object) else { return }
        tabs.remove(at: index)
        if active == object { active = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)] }
        if let active, case .dataset(let id) = active { Task { _ = await datasets.openInHub(id) } }
    }

    public func activate(_ object: DataObject) {
        active = object
        if case .dataset(let id) = object { Task { _ = await datasets.openInHub(id) } }
    }

    public func toggle(_ node: String) {
        if expanded.contains(node) { expanded.remove(node) } else { expanded.insert(node) }
    }

    public func newQuery(on connection: String) -> DataObject {
        let object = DataObject.query(connection: connection, id: nextQuery)
        nextQuery += 1
        open(object)
        return object
    }

    public func run(_ object: DataObject) {
        guard case .query = object else { return }
        queryResult[object] = (DataHubFixtures.grid(for: object), 42)
    }

    public func tableTab(_ object: DataObject) -> DataTableTab {
        let tab = tableTabs[object] ?? .data
        return tabs(for: object).contains(tab) ? tab : .data
    }

    /// Mesmas abas para o que os agentes alimentam, no Mac ou numa conexão; tabela que o Racky não alimenta é só navegação.
    public func tabs(for object: DataObject) -> [DataTableTab] {
        switch object {
        case .dataset: return [.data, .overview, .structure, .writers]
        case .table: return copySource(of: object) != nil ? [.data, .overview, .structure, .writers] : [.data, .structure]
        default: return []
        }
    }

    /// O dataset do Mac que alimenta este objeto (ele mesmo, se for um dataset).
    public func feedingDataset(of object: DataObject) -> String? {
        if case .dataset(let id) = object { return id }
        return copySource(of: object).flatMap(datasetID(named:))
    }

    /// Dataset sendo renomeado no lugar (título da barra ou linha do explorer).
    public private(set) var renaming: String?
    /// Onde a edição começou (`title` na barra, `explorer` na lista): só ali aparece o campo.
    public private(set) var renamingIn = "title"
    public func beginRename(_ id: String?, in place: String = "title") {
        renaming = id
        renamingIn = place
    }

    /// Opções de "Save data to" no formulário de nova sessão: o Racky e cada tabela, pasta, aba ou webhook das conexões.
    func composerDestinations() -> [ComposerDataDestination] {
        var out = [ComposerDataDestination(
            key: "racky", title: String(localized: "This Mac (a dataset of this session)", bundle: .module), group: String(localized: "This Mac", bundle: .module), production: false,
            explanation: String(localized: "Agents save what they collect in a dataset of this session, on this Mac. You can copy it to a connection later.", bundle: .module))]
        for connection in connections {
            let prod = connection.protected
            let place = connection.name + (prod ? " (protected)" : "")
            func add(_ object: DataObject, _ title: String, _ explanation: String) {
                out.append(ComposerDataDestination(
                    key: object.key, title: title, group: connection.name, production: prod, explanation: explanation, brand: connection.kind.brand))
            }
            switch connection.kind.family {
            case .database, .warehouse:
                for schema in connection.children {
                    for table in schema.children where table.kind == .table {
                        let object = DataObject.table(connection: connection.id, schema: schema.name, name: table.name)
                        add(object, "\(connection.name) › \(schema.name).\(table.name)",
                            String(localized: "Collected on this Mac first, then copied live to \(schema.name).\(table.name) on \(place).", bundle: .module))
                    }
                }
            case .storage:
                for folder in connection.children {
                    add(.folder(connection: connection.id, path: [folder.name]), "\(connection.name) › \(folder.name)/",
                        String(localized: "Agents collect into a dataset on this Mac and Racky writes it as Parquet files into \(folder.name)/ on \(connection.name).", bundle: .module))
                }
            case .spreadsheet:
                for book in connection.children {
                    for tab in book.children {
                        add(.tab(connection: connection.id, spreadsheet: book.name, name: tab.name), "\(connection.name) › \(tab.name)",
                            String(localized: "Agents collect into a dataset on this Mac and Racky appends each new row to the \(tab.name) tab of \(book.name).", bundle: .module))
                    }
                }
            case .outgoing:
                add(.webhook(connection: connection.id), connection.name,
                    String(localized: "Agents collect into a dataset on this Mac and Racky posts each new row to \(connection.address).", bundle: .module))
            }
        }
        return out
    }

    // MARK: Registro

    public func register(in registry: ActionRegistry) throws {
        try registry.register(.dataOpen) { [unowned self] arg in
            guard let raw = arg.value, let object = DataObject(key: raw) else {
                throw ActionError.failed(.dataOpen, message: String(localized: "No such object.", bundle: .module))
            }
            open(object)
            // Clicado de dentro de uma sessão (a trilha do dataset numa tab): leva para a área Data, já no lugar.
            if datasets.currentPage() != .datasets {
                await datasets.reloadList()
                datasets.showPage(.datasets)
            }
            return raw
        }
        try registry.register(.dataClose) { [unowned self] arg in
            guard let object = arg.value.flatMap(DataObject.init(key:)) ?? active else { return "" }
            close(object)
            return object.key
        }
        try registry.register(.dataToggleNode) { [unowned self] arg in
            guard let id = arg.value else { throw ActionError.failed(.dataToggleNode, message: "expected select(<node>)") }
            toggle(id)
            return expanded.contains(id) ? "open" : "closed"
        }
        try registry.register(.dataNewQuery) { [unowned self] arg in
            guard let id = arg.value, connection(id)?.kind.speaksSQL == true else {
                throw ActionError.failed(.dataNewQuery, message: String(localized: "This connection doesn't run SQL.", bundle: .module))
            }
            return newQuery(on: id).key
        }
        try registry.register(.dataTableTab) { [unowned self] arg in
            guard let active, let raw = arg.value, let tab = DataTableTab(rawValue: raw), tabs(for: active).contains(tab) else {
                throw ActionError.failed(.dataTableTab, message: "expected select(data|overview|structure|writers) with a dataset or table open")
            }
            tableTabs[active] = tab
            return raw
        }
        try registry.register(.dataQueryRun) { [unowned self] _ in
            guard let active, case .query = active else { throw ActionError.failed(.dataQueryRun, message: "no query open") }
            run(active)
            return "ok"
        }
        try registry.register(.dataAddConnection) { [unowned self] arg in
            showingConnect = arg.value != "close"
            return showingConnect ? "open" : "closed"
        }
        try registry.register(.dataSendTo) { _ in "" }
        try registry.register(.dataTablePage) { [unowned self] arg in
            guard let active, case .table = active else { throw ActionError.failed(.dataTablePage, message: "no table open") }
            let pages = DataHubFixtures.pageCount(for: active)
            let page = tablePage(active)
            switch arg.value {
            case "next": tablePages[active] = min(page + 1, pages - 1)
            case "prev": tablePages[active] = max(page - 1, 0)
            default: throw ActionError.failed(.dataTablePage, message: "expected select(next|prev)")
            }
            return "\(tablePage(active) + 1)"
        }
        try registry.register(.dataRenameDataset) { [unowned self] arg in
            // `@explorer:<id>`: a edição começa na linha do explorer (não no título).
            if let raw = arg.value, raw.hasPrefix("@explorer:") {
                let id = String(raw.dropFirst("@explorer:".count))
                guard summary(ofDataset: id) != nil else { throw ActionError.failed(.dataRenameDataset, message: String(localized: "No such dataset.", bundle: .module)) }
                beginRename(id, in: "explorer")
                return "editing"
            }
            let parts = (arg.value ?? "").split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let id = parts.first, summary(ofDataset: id) != nil else {
                throw ActionError.failed(.dataRenameDataset, message: String(localized: "No such dataset.", bundle: .module))
            }
            guard parts.count == 2 else { beginRename(id); return "editing" }
            renaming = nil
            await datasets.rename(id, to: parts[1])
            return datasets.name(of: id) ?? ""
        }
        try registry.register(.dataToggleExplorer) { [unowned self] _ in
            explorerHidden.toggle()
            return explorerHidden ? "hidden" : "shown"
        }
        try registry.register(.dataPauseWriter) { [unowned self] arg in
            guard let active else { return "" }
            let ids = arg.value == "all" || arg.value == nil ? writers(of: active).filter(\.live).map(\.id) : [arg.value ?? ""]
            for id in ids { if paused.contains(id) { paused.remove(id) } else { paused.insert(id) } }
            return ids.joined(separator: ",")
        }
        try registry.register(.dataWebhookTest) { _ in "sent" }
    }
}

/// Abas de um dataset ou tabela: os dados (padrão, ocupa a tela), a visão geral (números, gráfico, caminho), as colunas e quem grava.
public enum DataTableTab: String, CaseIterable, Sendable { case data, overview, structure, writers }

extension DataObject {
    /// Chave estável (argumento das ações e sufixo dos IDs de acessibilidade).
    public var key: String {
        switch self {
        case .dataset(let id): "dataset:\(id)"
        case .table(let c, let s, let n): "table:\(c):\(s):\(n)"
        case .query(let c, let n): "query:\(c):\(n)"
        case .folder(let c, let path): "folder:\(c):\(path.joined(separator: "/"))"
        case .webhook(let c): "webhook:\(c)"
        case .tab(let c, let s, let n): "sheet:\(c):\(s):\(n)"
        }
    }

    public init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard let kind = parts.first else { return nil }
        switch (kind, parts.count) {
        case ("dataset", 2): self = .dataset(parts[1])
        case ("table", 4): self = .table(connection: parts[1], schema: parts[2], name: parts[3])
        case ("query", 3): guard let n = Int(parts[2]) else { return nil }; self = .query(connection: parts[1], id: n)
        case ("folder", 3): self = .folder(connection: parts[1], path: parts[2].split(separator: "/").map(String.init))
        case ("webhook", 2): self = .webhook(connection: parts[1])
        case ("sheet", 4): self = .tab(connection: parts[1], spreadsheet: parts[2], name: parts[3])
        default: return nil
        }
    }
}
