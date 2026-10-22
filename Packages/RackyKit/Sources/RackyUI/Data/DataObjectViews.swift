import RackyCore
import RackyDesignSystem
import RackyProtocol
import RackyStore
import SwiftUI

// O conteúdo de cada objeto aberto na área Data: dataset do Racky (a página de dataset), tabela de uma conexão, consulta SQL,
// pasta de bucket, aba de planilha e webhook. Mais a folha "Add connection".

struct DataObjectView: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        switch object {
        case .dataset(let id):
            if let model = hub.datasets.models[id] {
                DatasetPageView(controller: hub.datasets, model: model, paneID: nil, drag: nil, showsBar: false, hub: hub)
            } else {
                Color.clear
            }
        case .table: TableObjectView(hub: hub, object: object)
        case .query: QueryObjectView(hub: hub, object: object)
        case .folder(let connection, let path): FolderObjectView(hub: hub, connection: connection, path: path)
        case .webhook: WebhookObjectView(hub: hub, object: object)
        case .tab: DataGridView(grid: DataHubFixtures.grid(for: object), footer: String(localized: "Columns A–C · first 10 rows", bundle: .module))
        }
    }
}

/// Ações à direita da barra de localização, por tipo de objeto.
struct DataObjectActions: View {
    let hub: DataHubController
    let object: DataObject
    /// Pouco espaço: só os ícones (o nome vai no tooltip).
    var compact = false
    /// Um pouco de espaço a menos: nomes curtos ("Copy…") antes de virar só ícones.
    var short = false
    /// Num pane da sessão: `true` = sozinho numa tab ("Beside the agent"); `false` = ao lado do agente ("Own tab"); `nil` = fora da sessão.
    var besideAgent: Bool? = nil

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            switch object {
            case .dataset(let id):
                // Numa tab sozinha da sessão: leva a tabela para o lado do agente (os dois juntos na tela).
                if let besideAgent {
                    // Sozinha numa tab: leva para o lado do agente. Já ao lado: devolve para uma tab própria.
                    if besideAgent {
                        button(.datasetOpen, id: .dataBeside, String(localized: "Beside the agent", bundle: .module), "rectangle.split.2x1", .select("\(id)|beside"))
                    } else {
                        button(.datasetOpen, id: .dataOwnTab, String(localized: "Own tab", bundle: .module), "rectangle", .select("\(id)|tab"))
                    }
                }
                // "Copy to…" volta com a etapa de entrega (cópias de verdade para um banco); um botão que não faz nada não fica na tela.
                if let model = hub.datasets.models[id] { DatasetToolbar(model: model, labels: !compact) }
            case .table(let connection, _, _):
                button(.dataNewQuery, id: .dataQueryTarget, String(localized: "New query", bundle: .module), "terminal", .select(connection))
            case .query:
                if compact {
                    button(.dataQueryRun, id: .dataQueryRun, String(localized: "Run", bundle: .module), "play.fill", .press)
                } else {
                    DSButton(.dataQueryRun, id: .dataQueryRun, "Run", variant: .primary, size: .sm, symbol: "play.fill", keycap: "⌘Return")
                }
            case .webhook:
                button(.dataWebhookTest, id: .dataWebhookTest, String(localized: "Test: post 2 sample rows to this URL…", bundle: .module), "paperplane", .press)
            case .folder, .tab:
                EmptyView()
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func button(_ action: ActionID, id: A11yID, _ title: String, _ symbol: String, _ argument: ActionArgument) -> some View {
        if compact {
            ActionButton(action, id: id, argument: argument, tooltip: title) { Image(systemName: symbol) }
                .buttonStyle(DSIconButtonStyle(.header))
        } else {
            DSButton(action, id: id, LocalizedStringKey(title), variant: .outline, size: .sm, symbol: symbol, argument: argument)
        }
    }
}

// MARK: Grade

/// Grade de leitura (tabela, resultado, arquivo, planilha): cabeçalho com nome e tipo, números à direita em mono, rodapé com o total.
struct DataGridView: View {
    let grid: DataGrid
    var footer: String? = nil
    @State private var moreColumns = false
    /// Anterior/seguinte habilitados (tabelas de conexão paginadas); `nil` = sem paginação.
    var pager: (previous: Bool, next: Bool)? = nil

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(grid.columns.enumerated()), id: \.offset) { _, column in
                            HStack(spacing: DS.Space.s1_5) {
                                Text(verbatim: column.name).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1).fixedSize()
                                Text(verbatim: column.type).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary).lineLimit(1).fixedSize()
                                if column.key { Text("KEY", bundle: .module).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.warning) }
                            }
                            .padding(.horizontal, DatasetMetrics.cellPadding)
                            .frame(width: width(column), height: DatasetMetrics.headerHeight, alignment: numeric(column) ? .trailing : .leading)
                            .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
                        }
                    }
                    .background(DS.Color.chrome)
                    .overlay(alignment: .bottom) { DS.Color.borderStrong.frame(height: ComputersMetrics.separator) }
                    ForEach(Array(grid.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(grid.columns.enumerated()), id: \.offset) { index, column in
                                let text = index < row.count ? row[index] : ""
                                Text(verbatim: text).dsFont(numeric(column) || column.type.contains("time") ? DS.Font.monoCell : DS.Font.cell)
                                    .foregroundStyle(column.key ? DS.Color.textSecondary : DS.Color.textPrimary)
                                    .lineLimit(1).truncationMode(.tail)
                                    .padding(.horizontal, DatasetMetrics.cellPadding)
                                    .frame(width: width(column), height: DatasetMetrics.rowHeight, alignment: numeric(column) ? .trailing : .leading)
                                    .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
                            }
                        }
                        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
                    }
                }
                // A grade começa no canto de cima, mesmo com poucas linhas.
                .frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .topLeading)
            }
            .moreColumnsCue($moreColumns)
            }
            HStack(spacing: DS.Space.s2) {
                if let pager {
                    pageButton("chevron.left", id: .dataTablePagePrev, argument: "prev", enabled: pager.previous)
                    pageButton("chevron.right", id: .dataTablePageNext, argument: "next", enabled: pager.next)
                }
                Text(verbatim: footer ?? String(localized: "Showing \(grid.rows.count) of \(grid.total.formatted()) rows", bundle: .module))
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                Spacer(minLength: 0)
                if moreColumns { MoreColumnsNote() }
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(height: DatasetMetrics.footerHeight)
            .background(DS.Color.chrome)
            .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        }
        .a11y(.dataTableGrid, kind: "table", value: "\(grid.rows.count)")
    }

    private func pageButton(_ symbol: String, id: A11yID, argument: String, enabled: Bool) -> some View {
        ActionButton(.dataTablePage, id: id, argument: .select(argument)) {
            Image(systemName: symbol).font(.system(size: DS.Space.s2_5, weight: .semibold))
                .foregroundStyle(enabled ? DS.Color.textSecondary : DS.Color.textQuaternary)
                .frame(width: DS.Space.s6, height: DS.Space.s6)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.borderStrong))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func numeric(_ column: DataGrid.Column) -> Bool {
        ["int", "numeric", "double", "number", "int4", "int8", "int32", "float"].contains { column.type.hasPrefix($0) }
    }

    private func width(_ column: DataGrid.Column) -> CGFloat {
        // Largo o bastante para "avg_price numeric" e "2026-10-22 11:59:04" numa linha.
        if numeric(column) { return DatasetMetrics.colNumber + DS.Space.s10 }
        if column.type.contains("time") { return DatasetMetrics.colDateTime + DS.Space.s8 }
        return column.key ? DatasetMetrics.colURL : DatasetMetrics.colName
    }
}

// MARK: Tabela

/// Tabela de uma conexão: Data (grade), Structure (colunas) e Writers (quem grava aqui), com o selo de edição.
struct TableObjectView: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        let grid = DataHubFixtures.grid(for: object)
        VStack(spacing: 0) {
            DataTabsBar(hub: hub, object: object)
            switch hub.tableTab(object) {
            case .data:
                let page = hub.tablePage(object)
                let pages = DataHubFixtures.pageCount(for: object)
                DataGridView(
                    grid: DataHubFixtures.grid(for: object, page: page),
                    footer: String(localized: "Page \(page + 1) of \(pages.formatted()) · \(grid.total.formatted()) rows", bundle: .module),
                    pager: (page > 0, page + 1 < pages))
            case .overview: DataOverviewView(hub: hub, object: object)
            case .structure:
                DataGridView(
                    grid: DataGrid(
                        columns: [.init(name: "column", type: "name"), .init(name: "type", type: "text"), .init(name: "nullable", type: "bool"), .init(name: "key", type: "text")],
                        rows: grid.columns.map { [$0.name, $0.type, $0.nullable ? "yes" : "no", $0.key ? "primary key" : ""] },
                        total: grid.columns.count),
                    footer: String(localized: "\(grid.columns.count) columns", bundle: .module))
            case .writers: DataWritersView(hub: hub, object: object)
            }
        }
    }
}

/// As abas de um dataset ou tabela, sempre as mesmas para o que os agentes alimentam. À direita, uma linha sobre o que dá para fazer.
struct DataTabsBar: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        let tab = hub.tableTab(object)
        HStack(spacing: DS.Space.s4) {
            ForEach(hub.tabs(for: object), id: \.self) { item in
                ActionButton(.dataTableTab, id: .dataTableTab(item.rawValue), argument: .select(item.rawValue)) {
                    VStack(spacing: DS.Space.s1) {
                        HStack(spacing: DS.Space.s1) {
                            Text(verbatim: title(item)).dsFont(tab == item ? DS.Font.tabActive : DS.Font.tab)
                                .foregroundStyle(tab == item ? DS.Color.textPrimary : DS.Color.textTertiary)
                            if item == .writers, !hub.writers(of: object).isEmpty {
                                // A contagem num selinho, separada do nome da aba.
                                Text(verbatim: "\(hub.writers(of: object).count)").dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textSecondary)
                                    .padding(.horizontal, DS.Space.s1)
                                    .background(Capsule().fill(DS.Color.secondary))
                            }
                        }
                        (tab == item ? DS.Color.textPrimary : Color.clear).frame(height: DS.Space.s0_5)
                    }
                    .padding(.top, DS.Space.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            Spacer(minLength: DS.Space.s2)
            if let note { Text(verbatim: note).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(1) }
        }
        .padding(.horizontal, DS.Space.s4)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    /// Tabela que o Racky não alimenta: dizer que é só navegação.
    private var note: String? {
        guard case .table = object, hub.copySource(of: object) == nil else { return nil }
        return String(localized: "Browsing your database · Racky doesn't write here", bundle: .module)
    }

    private func title(_ tab: DataTableTab) -> String {
        switch tab {
        case .data: String(localized: "Data", bundle: .module)
        case .overview: String(localized: "Overview", bundle: .module)
        case .structure: String(localized: "Structure", bundle: .module)
        case .writers: String(localized: "Who writes here", bundle: .module)
        }
    }
}

/// Visão geral: o caminho inteiro do dado e os números da coleta (os mesmos no Mac e na cópia, porque vêm da coleta no Mac).
struct DataOverviewView: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DataLineageStrip(hub: hub, object: object)
                if let id = hub.feedingDataset(of: object), let snapshot = hub.datasets.models[id]?.snapshot {
                    if case .dataset = object {} else {
                        // Os números são da coleta no Mac que alimenta esta cópia (não do banco): dito como título da seção.
                        HStack(spacing: DS.Space.s1_5) {
                            Image(systemName: "laptopcomputer").font(.system(size: DS.Space.s3)).foregroundStyle(DS.Color.textSecondary)
                            Text(verbatim: String(localized: "Collection on this Mac that feeds this table: \(hub.datasets.name(of: id) ?? "")", bundle: .module))
                                .dsFont(DS.Font.sectionLabel).foregroundStyle(DS.Color.textPrimary)
                        }
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                    }
                    DatasetOverviewTiles(snapshot: snapshot, controller: hub.datasets, wrap: true)
                    ActivityChart(snapshot: snapshot, controller: hub.datasets, rangeMenu: AnyView(EmptyView()), height: InsightMetrics.overviewChartHeight)
                }
            }
        }
    }
}

/// Quem grava aqui: agentes (com a sessão) e cópias, com pausar.
struct DataWritersView: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        let list = hub.writers(of: object)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if list.isEmpty {
                    Text("Nothing in Racky writes here. Pick it under Save data to when you start a session.", bundle: .module)
                        .dsFont(DS.Font.body).foregroundStyle(DS.Color.textTertiary)
                }
                ForEach(list) { writer in
                    HStack(spacing: DS.Space.s3) {
                        mark(writer)
                            .frame(width: DS.Space.s8, height: DS.Space.s8)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.secondary))
                        VStack(alignment: .leading, spacing: .zero) {
                            HStack(spacing: DS.Space.s1_5) {
                                Text(verbatim: { if case .sync = writer.kind { String(localized: "Racky, copying from \(hub.displayName(ofDatasetNamed: writer.name)) (this Mac)", bundle: .module) } else { writer.name } }())
                                    .dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary)
                                if writer.live { LiveDot() }
                            }
                            Text(verbatim: detail(writer)).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                        }
                        Spacer(minLength: 0)
                        if writer.live || hub.paused.contains(writer.id) {
                            DSButton(
                                .dataPauseWriter, id: .dataWriterPause(writer.id), hub.paused.contains(writer.id) ? "Resume" : "Pause",
                                variant: .outline, size: .xs, symbol: hub.paused.contains(writer.id) ? "play.fill" : "pause.fill", argument: .select(writer.id))
                        }
                    }
                    .padding(DS.Space.s3)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.panel))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.border))
                }
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func mark(_ writer: DataWriter) -> some View {
        switch writer.kind {
        case .agent:
            if let provider = DataLineageStrip.provider(named: writer.name) {
                DSAgentLogo(QuickLaunchModel.kind(provider), size: DS.Space.s4)
            } else {
                DSAgentLogo(QuickLaunchModel.kind(TerminalProvider.claude), size: DS.Space.s4)
            }
        case .sync: Image(systemName: "laptopcomputer").font(.system(size: DS.Space.s3 + 2)).foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func detail(_ writer: DataWriter) -> String {
        switch writer.kind {
        case .agent(let session): String(localized: "Agent in session \(session) · \(writer.detail). Pause stops its new writes; rows already written stay.", bundle: .module)
        case .sync(let from):
            if case .dataset(let name) = from { String(localized: "One-way: rows go from \(hub.displayName(ofDatasetNamed: name)) on this Mac (the original) to here · \(writer.detail)", bundle: .module) } else { writer.detail }
        }
    }
}

/// Colunas de um dataset do Mac: nome, tipo, obrigatória, chave.
struct DataColumnsView: View {
    let dataset: Dataset

    var body: some View {
        DataGridView(
            grid: DataGrid(
                columns: [.init(name: "column", type: "name"), .init(name: "type", type: "text"), .init(name: "required", type: "bool"), .init(name: "key", type: "text")],
                rows: dataset.columns.map { [$0.name, DatasetMetrics.typeLabel($0.type), $0.required ? "yes" : "no", dataset.key.contains($0.name) ? "key" : ""] },
                total: dataset.columns.count),
            footer: String(localized: "\(dataset.columns.count) columns", bundle: .module))
    }
}

// MARK: Consulta

/// Editor SQL: a conexão alvo bem à vista (em âmbar se for produção), o texto e o resultado.
struct QueryObjectView: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        let connection = hub.connection(object.connectionID)
        // Produção já tem a faixa âmbar em cima; aqui só a conexão alvo.
        let prod = false
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s1_5) {
                Image(systemName: prod ? "exclamationmark.triangle.fill" : "play.circle").font(.system(size: DS.Space.s3))
                Text(verbatim: connection.map { $0.kind.title == $0.name ? String(localized: "Runs on \($0.name)", bundle: .module) : String(localized: "Runs on \($0.name) · \($0.kind.title)", bundle: .module) } ?? "")
                    .dsFont(DS.Font.label)
                if let connection { ConnectionBadges(connection) }
                if prod {
                    Text("This connection is protected: changes ask you to confirm.", bundle: .module).dsFont(DS.Font.small)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(prod ? DS.Color.warning : DS.Color.textSecondary)
            .padding(.horizontal, DS.Space.s4)
            .frame(height: DS.Space.s8)
            .background(prod ? DS.Color.warning.opacity(0.06) : Color.clear)
            .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
            .a11y(.dataQueryTarget, kind: "text", label: connection?.name ?? "")
            TextEditor(text: Binding(get: { hub.queryText[object] ?? "" }, set: { hub.queryText[object] = $0 }))
                .font(.system(size: DS.Space.s3 + 1, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(DS.Space.s3)
                .frame(height: DataMetrics.editorHeight)
                .background(DS.Color.canvas)
                .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
                .a11y(.dataQueryEditor, kind: "textarea")
            if let result = hub.queryResult[object] {
                DataGridView(grid: result.grid, footer: String(localized: "\(result.grid.rows.count) rows · \(result.milliseconds) ms", bundle: .module))
                    .a11y(.dataQueryResult, kind: "table")
            } else {
                Text("Run the query to see the result here.", bundle: .module).dsFont(DS.Font.body).foregroundStyle(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: Pasta

/// Pasta de um bucket: arquivos com formato, tamanho e data; clicar num arquivo de dados mostra a prévia ao lado.
struct FolderObjectView: View {
    let hub: DataHubController
    let connection: String
    let path: [String]
    @State private var selected: String?

    var body: some View {
        let entries = DataHubFixtures.files(in: path)
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        let open: DataObject? = entry.folder ? .folder(connection: connection, path: path + [entry.name]) : nil
                        Group {
                            if let open {
                                ActionButton(.dataOpen, id: .dataFolderEntry(entry.name), argument: .select(open.key)) { row(entry) }.buttonStyle(.plain)
                            } else {
                                // lint-ui: allow buttons escolhe o arquivo para a prévia (estado local)
                                Button { selected = entry.name } label: { row(entry) }
                                    .buttonStyle(.plain)
                                    .a11y(.dataFolderEntry(entry.name), kind: "row", label: entry.name)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear { if selected == nil { selected = entries.first { !$0.folder && $0.format != "JSON" }?.name } }
            if let selected, let entry = entries.first(where: { $0.name == selected }), entry.format != "JSON" {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(verbatim: entry.name).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary)
                        Text(verbatim: entry.format).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: DS.Space.s8 + DS.Space.s1)
                    .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
                    DataGridView(grid: DataHubFixtures.grid(for: .folder(connection: connection, path: path)), footer: String(localized: "Preview · first 10 of 80 rows", bundle: .module))
                }
                .frame(width: DataMetrics.previewWidth)
                .overlay(alignment: .leading) { DS.Color.border.frame(width: ComputersMetrics.separator) }
                .a11y(.dataFolderPreview, kind: "container", label: entry.name)
            }
        }
    }

    private func row(_ entry: DataHubFixtures.FileEntry) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: entry.folder ? "folder" : "doc").font(.system(size: DataMetrics.icon)).foregroundStyle(DS.Color.textSecondary)
                .frame(width: DS.Space.s4)
            Text(verbatim: entry.name).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: entry.folder ? String(localized: "Folder", bundle: .module) : entry.format).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                .frame(width: DatasetMetrics.colCount, alignment: .leading)
            Text(verbatim: entry.folder ? "–" : ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file))
                .dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textSecondary)
                .frame(width: DatasetMetrics.colCount, alignment: .trailing)
            Text(verbatim: entry.modified).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                .frame(width: DatasetMetrics.colCount, alignment: .trailing)
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DatasetMetrics.rowHeight)
        .background(selected == entry.name ? DS.Color.dataKey.opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .contentShape(Rectangle())
    }
}

// MARK: Webhook

/// Webhook: só recebe. Mostra para onde vai, como vai e o log das entregas.
struct WebhookObjectView: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        let connection = hub.connection(object.connectionID)
        let deliveries = DataHubFixtures.deliveries(now: hub.now())
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s6) {
                fact(String(localized: "Endpoint", bundle: .module), "POST " + (connection?.address ?? ""))
                fact(String(localized: "Body", bundle: .module), String(localized: "JSON array of the new rows, as they arrive", bundle: .module))
                fact(String(localized: "Delivered today", bundle: .module), String(localized: "\(deliveries.count) of \(deliveries.count), 1 after a retry", bundle: .module))
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s4)
            .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
            Text("A webhook only receives data: Racky posts rows to this address. There is nothing to browse, so this shows what each delivery carries and the log of deliveries.", bundle: .module)
                .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s3)
            VStack(alignment: .leading, spacing: DS.Space.s1_5) {
                Text("Each delivery looks like this", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                Text(verbatim: DataHubFixtures.samplePayload).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textPrimary)
                    .padding(DS.Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.chrome))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.border))
            }
            .padding(DS.Space.s4)
            .a11y(.dataWebhookPayload, kind: "text")
            Text("Deliveries", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
            DataGridView(
                grid: DataGrid(
                    columns: [.init(name: "sent", type: "time"), .init(name: "status", type: "int"), .init(name: "rows", type: "int"), .init(name: "duration", type: "int")],
                    rows: deliveries.map { [hub.datasets.clock($0.at), "\($0.status)", "\($0.rows)", "\($0.milliseconds) ms"] },
                    total: deliveries.count),
                footer: String(localized: "\(deliveries.count) deliveries · the 502 was retried and went through", bundle: .module))
                .a11y(.dataWebhookLog, kind: "table")
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s0_5) {
            Text(verbatim: title).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            Text(verbatim: value).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
        }
    }
}

// MARK: Adicionar conexão

/// Folha de tipos: agrupados por família, cada um com o logo, o nome e o que é; o grupo diz se dá para navegar e gravar ou só gravar.
struct DataConnectSheet: View {
    let hub: DataHubController

    var body: some View {
        GeometryReader { geo in
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("Add connection", bundle: .module).dsFont(DS.Font.dialogTitle).foregroundStyle(DS.Color.textPrimary)
                        Text("A place outside Racky: browse it here, and let agents write to it.", bundle: .module).dsFont(DS.Font.body).foregroundStyle(DS.Color.textTertiary)
                    }
                    Spacer(minLength: 0)
                    ActionButton(.dataAddConnection, argument: .select("close"), tooltip: String(localized: "Close", bundle: .module)) { Image(systemName: "xmark") }
                        .buttonStyle(DSIconButtonStyle(.header))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        ForEach(DataConnectionKind.Family.allCases, id: \.self) { family in
                            VStack(alignment: .leading, spacing: DS.Space.s2) {
                                HStack(spacing: DS.Space.s2) {
                                    Text(verbatim: Self.title(family)).dsFont(DS.Font.sectionLabel).foregroundStyle(DS.Color.textPrimary)
                                    Text(verbatim: family == .outgoing ? String(localized: "Write only", bundle: .module) : String(localized: "Browse and write", bundle: .module))
                                        .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                                }
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
                                    ForEach(DataConnectionKind.allCases.filter { $0.family == family }, id: \.self) { kind in KindCard(kind: kind) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.s6)
            // Cabe tudo quando a janela deixa; senão, a lista rola dentro da folha.
            .frame(width: DataMetrics.connectWidth)
            // Do tamanho do conteúdo; numa janela baixa, para na altura disponível e a lista rola.
            .frame(maxHeight: min(DataMetrics.connectHeight, geo.size.height - DataMetrics.connectMargin))
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: DS.Radius.large).fill(DS.Color.panel))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Color.borderStrong))
            .shadow(color: .black.opacity(0.45), radius: DS.Space.s6, y: DS.Space.s2)
            .a11y(.dataConnectSheet, kind: "dialog")
        }
        .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Um tipo: logo da marca num ladrilho, o nome e uma linha do que é.
    private struct KindCard: View {
        let kind: DataConnectionKind
        @State private var hovering = false

        var body: some View {
            HStack(spacing: DS.Space.s2_5) {
                DSDataLogo(kind.brand, size: DataMetrics.connectLogo, tile: true)
                VStack(alignment: .leading, spacing: .zero) {
                    Text(verbatim: kind.title).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    Text(verbatim: kind.tagline).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(height: DataMetrics.connectCard)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(hovering ? DS.Color.secondary : DS.Color.chrome))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(hovering ? DS.Color.borderStrong : DS.Color.border))
            .onHover { hovering = $0 }
            .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.hover), value: hovering)
            .help(kind.tagline)
            .a11y(.dataConnectKind(kind.rawValue), kind: "button", label: kind.title)
        }
    }

    static func title(_ family: DataConnectionKind.Family) -> String {
        switch family {
        case .database: String(localized: "Databases", bundle: .module)
        case .warehouse: String(localized: "Warehouses", bundle: .module)
        case .storage: String(localized: "Storage", bundle: .module)
        case .spreadsheet: String(localized: "Spreadsheets", bundle: .module)
        case .outgoing: String(localized: "Outgoing", bundle: .module)
        }
    }
}
