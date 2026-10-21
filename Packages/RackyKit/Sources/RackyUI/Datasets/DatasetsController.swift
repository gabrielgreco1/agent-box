import RackyCore
import RackyPlatform
import RackyProtocol
import RackyStore
import AppKit
import Foundation
import Observation

// Datasets v1 (docs/rebuild/spec/datasets.md): a lista de datasets e a tabela viva de um dataset. A UI nunca lê arquivo nem SQL: tudo passa
// por este controlador, que consulta o `RackyStore` fora da thread principal (`DatasetLoader`) e só publica o resultado já pronto.

/// Uma linha para mostrar: o registro e as células já em texto (decodificadas fora do main).
nonisolated public struct DatasetDisplayRow: Sendable, Equatable, Identifiable {
    public var row: DatasetRow
    public var cells: [String]
    public var id: String { row.rowKey }
}

/// O que a página de um dataset mostra agora.
nonisolated public struct DatasetPageSnapshot: Sendable, Equatable {
    public var summary: DatasetSummary
    public var rows: [DatasetDisplayRow]
    /// Linhas que casam o filtro e a busca (o `Load more` aparece quando é maior que `rows.count`).
    public var matching: Int
}

nonisolated enum DatasetLoader {
    @concurrent
    static func summaries(store: RackyStore) async -> [DatasetSummary] {
        (try? await store.datasetSummaries()) ?? []
    }

    @concurrent
    static func page(store: RackyStore, id: String, filter: DatasetRowFilter, search: String, limit: Int) async -> DatasetPageSnapshot? {
        guard let summary = try? await store.datasetSummary(id: id) else { return nil }
        let query = search.trimmingCharacters(in: .whitespaces)
        let rows = (try? await store.datasetRows(datasetID: id, filter: filter, search: query, limit: limit)) ?? []
        let matching = (try? await store.datasetRowCount(datasetID: id, filter: filter, search: query)) ?? rows.count
        let columns = summary.dataset.columns
        let display = rows.map { row -> DatasetDisplayRow in
            let object = DatasetExporter.decode(row)
            return DatasetDisplayRow(row: row, cells: columns.map { Self.text(object[$0.name]) })
        }
        return DatasetPageSnapshot(summary: summary, rows: display, matching: matching)
    }

    static func text(_ value: JSON?) -> String {
        guard let value else { return "" }
        switch value {
        case .null: return ""
        case .string(let s): return s.replacingOccurrences(of: "\n", with: " ")
        default: return value.text
        }
    }
}

enum DatasetExportFormat: String, CaseIterable {
    case csv, jsonl, json

    var exporter: DatasetExporter.Format {
        switch self {
        case .csv: .csv
        case .jsonl: .jsonl
        case .json: .json
        }
    }
}

@MainActor
@Observable
public final class DatasetsController {
    public static let pageSize = 1000

    public private(set) var summaries: [DatasetSummary] = []
    public private(set) var listLoaded = false
    public private(set) var currentID: String?
    public private(set) var snapshot: DatasetPageSnapshot?
    public internal(set) var filter: DatasetRowFilter = .all
    public var search = ""
    public private(set) var selectedRowKey: String?
    public private(set) var limit = DatasetsController.pageSize

    @ObservationIgnored public private(set) var store: RackyStore?
    /// Título da sessão (sidebar) e se algum computador dela está rodando (atualização a cada 1 s); ligados pelo `AppEnvironment`.
    @ObservationIgnored public var sessionTitle: (UUID) -> String? = { _ in nil }
    @ObservationIgnored public var isRunning: (UUID) -> Bool = { _ in false }
    @ObservationIgnored public var currentPage: () -> CenterPage = { .workspace }
    @ObservationIgnored public var showPage: (CenterPage) -> Void = { _ in }
    @ObservationIgnored public var hidePage: () -> Void = {}
    @ObservationIgnored public var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// A ação do viewer que abre a evidência de um request (a mesma do painel `Result`).
    @ObservationIgnored public var openEvidence: (_ computer: String, _ requestID: String) async throws -> Void = { _, _ in }
    @ObservationIgnored public var automationEnabled = false
    /// Relógio, fuso e idioma dos textos de data (testes fixam os três para a imagem não depender de quando roda).
    @ObservationIgnored public var now: () -> Date = { Date() }
    @ObservationIgnored public var timeZone: TimeZone = .current
    @ObservationIgnored public var locale: Locale = .current
    @ObservationIgnored private var refresher: Task<Void, Never>?

    public init() {}

    public func attach(store: RackyStore) async {
        self.store = store
        await reloadList()
    }

    // MARK: Datas

    /// `3 minutes ago`, relativo ao relógio do controlador.
    public func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now())
    }

    public func absolute(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
    }

    // MARK: Dados

    public func title(of summary: DatasetSummary) -> String { sessionTitle(summary.dataset.sessionID) ?? String(localized: "Unknown session", bundle: .module) }

    public func reloadList() async {
        guard let store else { return }
        let loaded = await DatasetLoader.summaries(store: store)
        if loaded != summaries { summaries = loaded }
        listLoaded = true
    }

    public func reloadPage() async {
        guard let store, let id = currentID else { return }
        let (filter, search, limit) = (filter, search, limit)
        let loaded = await DatasetLoader.page(store: store, id: id, filter: filter, search: search, limit: limit)
        // Uma consulta lenta não sobrescreve o que o usuário mudou enquanto ela rodava.
        guard currentID == id, self.filter == filter, self.search == search, self.limit == limit else { return }
        if loaded != snapshot { snapshot = loaded }
    }

    /// Abre o dataset: zera filtro, busca e seleção e carrega a primeira página.
    public func open(_ id: String) async -> Bool {
        guard let store, (try? await store.dataset(id: id)) != nil else { return false }
        currentID = id
        filter = .all
        search = ""
        selectedRowKey = nil
        limit = Self.pageSize
        snapshot = nil
        await reloadPage()
        showPage(.dataset(id))
        return true
    }

    public var selectedRow: DatasetDisplayRow? { snapshot?.rows.first { $0.row.rowKey == selectedRowKey } }

    // MARK: Atualização

    /// 1 s com um computador da sessão rodando; 5 s fora disso. Só trabalha quando a página está aberta.
    public func startRefreshing() {
        refresher?.cancel()
        refresher = Task { @MainActor [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                tick += 1
                await self.refreshVisible(tick: tick)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stopRefreshing() { refresher?.cancel() }

    func refreshVisible(tick: Int) async {
        switch currentPage() {
        case .datasets:
            if !listLoaded || tick % 2 == 0 { await reloadList() }
        case .dataset(let id) where id == currentID:
            let running = snapshot.map { isRunning($0.summary.dataset.sessionID) } ?? false
            if running || tick % 5 == 0 || snapshot == nil { await reloadPage() }
        default: break
        }
    }

    // MARK: Ações

    public func register(in registry: ActionRegistry) throws {
        let hasDataset: ActionRegistry.Enablement = { [unowned self] in
            currentID == nil ? .disabled(reason: String(localized: "Open a dataset first.", bundle: .module)) : .enabled
        }
        try registry.register(.pageDatasets) { [unowned self] _ in
            if currentPage() == .datasets {
                hidePage()
                return "workspace"
            }
            await reloadList()
            showPage(.datasets)
            return "datasets"
        }
        try registry.register(.datasetOpen) { [unowned self] arg in
            guard arg.kind == .select, let id = arg.value, !id.isEmpty, await open(id) else {
                throw ActionError.failed(.datasetOpen, message: String(localized: "No such dataset.", bundle: .module))
            }
            return id
        }
        try registry.register(.datasetFilter, enablement: hasDataset) { [unowned self] arg in
            guard arg.kind == .select, let raw = arg.value, let filter = DatasetRowFilter(rawValue: raw) else {
                throw ActionError.failed(.datasetFilter, message: "expected select(all|invalid)")
            }
            self.filter = filter
            limit = Self.pageSize
            await reloadPage()
            return filter.rawValue
        }
        try registry.register(.datasetSearch, enablement: hasDataset) { [unowned self] arg in
            let text = arg.value ?? ""
            guard text != search || snapshot == nil else { return text }
            search = text
            limit = Self.pageSize
            await reloadPage()
            return text
        }
        try registry.register(.datasetSelectRow, enablement: hasDataset) { [unowned self] arg in
            selectedRowKey = arg.kind == .select ? arg.value.flatMap { $0.isEmpty ? nil : $0 } : nil
            return selectedRowKey
        }
        try registry.register(.datasetLoadMore, enablement: hasDataset) { [unowned self] _ in
            limit += Self.pageSize
            await reloadPage()
            return "\(snapshot?.rows.count ?? 0)"
        }
        try registry.register(.datasetOpenSource, enablement: hasDataset) { [unowned self] arg in
            let key = arg.value ?? selectedRowKey
            guard let row = snapshot?.rows.first(where: { $0.row.rowKey == key })?.row, let raw = row.sourceURL, let url = Self.webURL(raw) else {
                throw ActionError.failed(.datasetOpenSource, message: String(localized: "This row has no source URL.", bundle: .module))
            }
            openURL(url)
            return url.absoluteString
        }
        try registry.register(.datasetExport, enablement: hasDataset) { [unowned self] arg in
            try await export(arg)
        }
    }

    /// Só `http(s)` abre no navegador (o texto da coluna veio de uma página).
    static func webURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    private func export(_ arg: ActionArgument) async throws -> String {
        guard let store, let id = currentID, let dataset = try await store.dataset(id: id) else {
            throw ActionError.failed(.datasetExport, message: String(localized: "Open a dataset first.", bundle: .module))
        }
        if arg.kind == .set, let value = arg.value, let split = value.firstIndex(of: "=") {
            guard automationEnabled else { throw ActionError.failed(.datasetExport, message: "Automation is off") }
            guard let format = DatasetExportFormat(rawValue: String(value[..<split])) else { throw ActionError.failed(.datasetExport, message: "expected set(csv|jsonl|json=<path>)") }
            let url = URL(fileURLWithPath: String(value[value.index(after: split)...]))
            try await DatasetExporter.write(store: store, dataset: dataset, format: format.exporter, to: url)
            return url.path
        }
        guard arg.kind == .select, let raw = arg.value, let format = DatasetExportFormat(rawValue: raw) else {
            throw ActionError.failed(.datasetExport, message: "expected select(csv|jsonl|json)")
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DatasetExporter.suggestedName(dataset: dataset.name, format: format.exporter)
        let response = await withCheckedContinuation { (c: CheckedContinuation<NSApplication.ModalResponse, Never>) in panel.begin { c.resume(returning: $0) } }
        guard response == .OK, let url = panel.url else { return "cancelled" }
        try await DatasetExporter.write(store: store, dataset: dataset, format: format.exporter, to: url)
        return url.path
    }
}

extension CenterPage {
    /// Id do dataset da página aberta.
    var datasetID: String? { if case .dataset(let id) = self { id } else { nil } }
}
