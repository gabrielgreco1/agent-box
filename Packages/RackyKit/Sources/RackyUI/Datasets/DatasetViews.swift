import RackyCore
import RackyDesignSystem
import RackyProtocol
import RackyStore
import SwiftUI

// Datasets: a lista (03 §12.5) e a página de um dataset no tom do editor de tabelas do Supabase com o Log Explorer do Datadog:
// números no topo, barra de consulta com período, gráfico de volume, facetas com contagem à esquerda, grade densa e o painel da linha
// com abas. Tudo passa pelo `DatasetsController`; os controles são `ActionButton`/`DSButton` do registro de ações.

enum DatasetMetrics {
    static let topBar = DS.Space.s10 + DS.Space.s3
    static let queryBar = DS.Space.s10 + DS.Space.s1_5
    static let chartHeight: CGFloat = 92
    static let chartBarGap: CGFloat = 3
    static let legendSwatch = DS.Space.s2
    static let headerHeight = DS.Space.s8 + DS.Space.s0_5
    static let rowHeight = DS.Space.s8
    static let footerHeight = DS.Space.s8 + DS.Space.s0_5
    static let listRowHeight = DS.Space.s10 + DS.Space.s1
    static let cellPadding = DS.Space.s2_5
    static let statGap = DS.Space.s4 + DS.Space.s1
    static let checkColumn: CGFloat = 36
    static let stripeColumn: CGFloat = 26
    static let stripeHeight: CGFloat = 16
    static let stripeWidth: CGFloat = 3
    static let checkbox: CGFloat = 13
    static let facetWidth: CGFloat = 212
    static let facetRow = DS.Space.s6
    static let facetDot: CGFloat = 7
    static let liveDot: CGFloat = 6
    static let iconTile = DS.Space.s6
    static let colName: CGFloat = 220
    static let colSession: CGFloat = 160
    static let colCount: CGFloat = 90
    static let colString: CGFloat = 200
    static let colURL: CGFloat = 300
    static let colNumber: CGFloat = 104
    static let colBoolean: CGFloat = 80
    static let colDate: CGFloat = 116
    static let colDateTime: CGFloat = 176
    static let colJSON: CGFloat = 220
    static let colCaptured: CGFloat = 132
    static let panelWidth: CGFloat = 330
    static let facetsMinWidth: CGFloat = 820
    static let panelInlineMinWidth: CGFloat = 1040
    static let sessionNameMinWidth: CGFloat = 900
    static let buttonLabelsMinWidth: CGFloat = 720
    static let panelLabel: CGFloat = 92
    static let tabUnderline: CGFloat = 2

    static func width(_ type: DatasetColumnType, first: Bool) -> CGFloat {
        switch type {
        case .string: first ? colName : colString
        case .url: colURL
        case .integer, .number: colNumber
        case .boolean: colBoolean
        case .date: colDate
        case .datetime: colDateTime
        case .json: colJSON
        }
    }

    static func isNumeric(_ type: DatasetColumnType) -> Bool { type == .integer || type == .number }
    static func isMono(_ type: DatasetColumnType) -> Bool { type != .string }

    /// Nome do tipo no cabeçalho, no estilo do Supabase.
    static func typeLabel(_ type: DatasetColumnType) -> String {
        switch type {
        case .string: "text"
        case .integer: "int"
        case .number: "numeric"
        case .boolean: "bool"
        case .date: "date"
        case .datetime: "timestamp"
        case .url: "url"
        case .json: "json"
        }
    }
}

// MARK: Peças

/// "● Collecting" numa pílula verde enquanto algum computador da sessão roda.
private struct CollectingPill: View {
    var body: some View {
        HStack(spacing: DS.Space.s1_5) {
            Circle().fill(DS.Color.dataValid).frame(width: DatasetMetrics.liveDot, height: DatasetMetrics.liveDot)
            Text("Collecting", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.dataValid)
        }
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s0_5)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.dataValid.opacity(0.12)))
        .fixedSize()
    }
}

/// Número em mono com o rótulo pequeno embaixo (topo da página).
private struct StatView: View {
    let value: String
    let label: String
    var tone: Color = DS.Color.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(verbatim: value).dsFont(DS.Font.monoCell).foregroundStyle(tone)
            Text(verbatim: label).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Caixinha de seleção desenhada (facetas e grade).
private struct CheckSquare: View {
    let on: Bool
    var tint: Color = DS.Color.textPrimary

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xs + 1)
            .fill(on ? tint : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xs + 1).strokeBorder(on ? tint : DS.Color.borderStrong))
            .frame(width: DatasetMetrics.checkbox, height: DatasetMetrics.checkbox)
    }
}

/// Botão que abre um menu do design system cujos itens levam a própria ação (marcar várias colunas, escolher formato ou período).
private struct MenuButton<Label: View>: View {
    let id: A11yID
    let action: ActionID
    let entries: [DSMenuEntry]
    var primary = false
    @ViewBuilder let label: () -> Label
    @State private var anchor: CGRect = .zero
    @State private var hovering = false
    @Environment(\.overlayRouter) private var router
    @Environment(\.actionRegistry) private var registry

    var body: some View {
        // lint-ui: allow buttons abre o popover do menu (apresentação); cada item dispara a ação do registro
        Button { open() } label: {
            HStack(spacing: DS.Space.s1_5) { label() }
                .dsFont(DS.Font.label)
                .foregroundStyle(primary ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                .padding(.horizontal, DS.Space.s2_5)
                .frame(height: DSMetrics.fieldHeightComposer - DS.Space.s1)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .fill(primary ? DS.Color.primary.opacity(hovering ? 0.9 : 1) : (hovering ? DS.Color.secondary : DS.Color.chrome)))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(primary ? Color.clear : DS.Color.borderStrong))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchor = $0 }
        .fixedSize()
        .a11y(id, kind: "menu", label: action.spec.label, action: action)
    }

    private func open() {
        guard let router else { return }
        router.presentPopover(
            DSMenuPanel.spec(
                name: id.rawValue, anchor: anchor, width: max(anchor.width, DS.Layout.menuMinWidth), entries: entries, selectedID: nil,
                searchable: false, searchPlaceholder: "", registry: registry))
    }
}

/// Barra de cima das páginas de dataset: conteúdo e o fechar da página (mesmo canto do `PageHeader`).
private struct DatasetBar<Content: View>: View {
    /// Num pane, o X fecha só o pane; na página, fecha a página.
    var closePane: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @Environment(\.pageTrailingInset) private var trailingInset

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            content()
            if let closePane {
                // lint-ui: allow buttons fecha o pane do dataset (layout do workspace, sem ação de registro própria)
                Button(action: closePane) { Image(systemName: "xmark") }
                    .buttonStyle(DSIconButtonStyle(.header))
                    .dsTooltip(String(localized: "Close", bundle: .module), shortcut: nil)
            } else {
                ActionButton(.pageClose, tooltip: String(localized: "Close", bundle: .module)) { Image(systemName: "xmark") }
                    .buttonStyle(DSIconButtonStyle(.header))
            }
        }
        .padding(.leading, DS.Space.s4)
        .padding(.trailing, DS.Space.s3 + trailingInset)
        .frame(height: DatasetMetrics.topBar)
        .background(DS.Color.chrome)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }
}

private struct TableIcon: View {
    var body: some View {
        Image(systemName: "tablecells").font(.system(size: DS.Space.s3)).foregroundStyle(DS.Color.textSecondary)
            .frame(width: DatasetMetrics.iconTile, height: DatasetMetrics.iconTile)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.secondary))
    }
}

// MARK: Lista

struct DatasetsPageView: View {
    let controller: DatasetsController

    var body: some View {
        let summaries = controller.summaries
        VStack(spacing: 0) {
            DatasetBar {
                Text("Datasets", bundle: .module).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary)
                if !summaries.isEmpty {
                    StatView(value: summaries.count.formatted(), label: summaries.count == 1 ? String(localized: "Dataset", bundle: .module).lowercased() : String(localized: "Datasets", bundle: .module).lowercased())
                        .padding(.leading, DS.Space.s2)
                    StatView(value: summaries.reduce(0) { $0 + $1.rowCount }.formatted(), label: String(localized: "Rows", bundle: .module).lowercased())
                }
                Spacer(minLength: 0)
            }
            if summaries.isEmpty {
                VStack(spacing: DS.Space.s1_5) {
                    TableIcon()
                    Text("No datasets yet", bundle: .module).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textSecondary).padding(.top, DS.Space.s2)
                    Text("Subagents create them when they collect tables of data.", bundle: .module)
                        .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .a11y(.datasetsEmpty, kind: "text")
            } else {
                header
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(summaries) { summary in
                            ActionButton(.datasetOpen, id: .datasetsRow(summary.dataset.id), argument: .select(summary.dataset.id)) {
                                HoverRow { row(summary) }
                            }
                            .buttonStyle(.plain)
                            .a11y(.datasetsRow(summary.dataset.id), kind: "row", label: summary.dataset.name, value: "\(summary.rowCount)")
                        }
                    }
                }
            }
        }
        .background(DS.Color.canvas)
        .a11y(.datasetsPage, kind: "page")
        .task { await controller.reloadList() }
    }

    static func summaryText(_ summaries: [DatasetSummary]) -> String {
        let rows = summaries.reduce(0) { $0 + $1.rowCount }
        let datasets = summaries.count == 1 ? String(localized: "1 dataset", bundle: .module) : String(localized: "\(summaries.count) datasets", bundle: .module)
        let count = rows == 1 ? String(localized: "1 row", bundle: .module) : String(localized: "\(rows.formatted()) rows", bundle: .module)
        return "\(datasets) · \(count)"
    }

    private var header: some View {
        HStack(spacing: 0) {
            column("Name", width: nil)
            column("Session", width: DatasetMetrics.colSession)
            column("Rows", width: DatasetMetrics.colCount, trailing: true)
            column("Invalid", width: DatasetMetrics.colCount, trailing: true)
            column("Updated", width: DatasetMetrics.colSession)
        }
        .padding(.horizontal, DS.Space.s1_5)
        .frame(height: DatasetMetrics.headerHeight)
        .overlay(alignment: .bottom) { DS.Color.borderStrong.frame(height: ComputersMetrics.separator) }
    }

    private func column(_ title: LocalizedStringKey, width: CGFloat?, trailing: Bool = false) -> some View {
        Text(title, bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
            .padding(.horizontal, DatasetMetrics.cellPadding)
            .frame(maxWidth: width ?? .infinity, alignment: trailing ? .trailing : .leading)
            .frame(width: width)
    }

    private func row(_ summary: DatasetSummary) -> some View {
        let collecting = controller.isCollecting(summary)
        return HStack(spacing: 0) {
            HStack(spacing: DS.Space.s2_5) {
                TableIcon()
                VStack(alignment: .leading, spacing: .zero) {
                    Text(verbatim: summary.dataset.name).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    Text(verbatim: summary.dataset.columns.map(\.name).joined(separator: " · "))
                        .dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                }
            }
            .padding(.horizontal, DatasetMetrics.cellPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: controller.title(of: summary)).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                .padding(.horizontal, DatasetMetrics.cellPadding)
                .frame(width: DatasetMetrics.colSession, alignment: .leading)
            number(summary.rowCount, dim: summary.rowCount == 0)
            number(summary.invalidCount, warn: summary.invalidCount > 0, dim: summary.invalidCount == 0)
            Group {
                if collecting {
                    CollectingPill()
                } else {
                    Text(verbatim: controller.relative(summary.dataset.updatedAt)).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                }
            }
            .padding(.horizontal, DatasetMetrics.cellPadding)
            .frame(width: DatasetMetrics.colSession, alignment: .leading)
        }
        .padding(.horizontal, DS.Space.s1_5)
        .frame(height: DatasetMetrics.listRowHeight)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .contentShape(Rectangle())
    }

    private func number(_ value: Int, warn: Bool = false, dim: Bool = false) -> some View {
        Text(verbatim: value.formatted()).dsFont(DS.Font.monoCell)
            .foregroundStyle(warn ? DS.Color.warning : (dim ? DS.Color.textTertiary : DS.Color.textPrimary)).lineLimit(1)
            .padding(.horizontal, DatasetMetrics.cellPadding)
            .frame(width: DatasetMetrics.colCount, alignment: .trailing)
    }
}

/// Linha clicável com o fundo de hover da grade.
private struct HoverRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .background(hovering ? DS.Color.hoverRow : Color.clear)
            .onHover { hovering = $0 }
    }
}

// MARK: Dataset

struct DatasetPageView: View {
    let controller: DatasetsController
    @Bindable var model: DatasetViewModel
    /// Pane que mostra a tabela (`nil` = página do centro): o título arrasta o pane e o X fecha só ele.
    var paneID: UUID?
    var drag: PaneDragController?

    /// Página do centro: o dataset ativo.
    init(controller: DatasetsController) {
        self.controller = controller
        self.model = controller.active ?? controller.model(for: "")
    }

    init(controller: DatasetsController, model: DatasetViewModel, paneID: UUID?, drag: PaneDragController?) {
        self.controller = controller
        self.model = model
        self.paneID = paneID
        self.drag = drag
    }

    var body: some View {
        let snapshot = model.snapshot
        GeometryReader { proxy in
            let width = proxy.size.width
            VStack(spacing: 0) {
                topBar(snapshot, width: width)
                if let snapshot {
                    queryBar
                    ActivityChart(snapshot: snapshot, controller: controller)
                    ZStack(alignment: .trailing) {
                        HStack(spacing: 0) {
                            if width >= DatasetMetrics.facetsMinWidth { FacetsPanel(snapshot: snapshot, controller: controller, model: model) }
                            grid(snapshot)
                            if let selected = model.selectedRow, width >= DatasetMetrics.panelInlineMinWidth {
                                RowPanel(row: selected, columns: snapshot.summary.dataset.columns, controller: controller, model: model)
                            }
                        }
                        // Estreito: o painel da linha fica por cima da grade, com sombra, em vez de espremer as colunas.
                        if let selected = model.selectedRow, width < DatasetMetrics.panelInlineMinWidth {
                            RowPanel(row: selected, columns: snapshot.summary.dataset.columns, controller: controller, model: model)
                                .shadow(color: .black.opacity(0.35), radius: DS.Space.s4)
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .background(DS.Color.canvas)
        .contentShape(Rectangle())
        .onHover { if $0 { controller.activate(model.id) } }
        .onAppear {
            controller.activate(model.id)
            controller.noteVisible(model.id, true)
        }
        .onDisappear { controller.noteVisible(model.id, false) }
        .a11y(.datasetPage, kind: "page")
    }

    // MARK: Topo

    private func topBar(_ snapshot: DatasetPageSnapshot?, width: CGFloat) -> some View {
        DatasetBar(closePane: paneID.map { id in { controller.closePane(id) } }) {
            HStack(spacing: DS.Space.s2_5) {
                TableIcon()
                HStack(spacing: DS.Space.s1_5) {
                    Text(verbatim: snapshot?.summary.dataset.name ?? "").dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary)
                    if let snapshot, width >= DatasetMetrics.sessionNameMinWidth {
                        Text(verbatim: "· " + controller.title(of: snapshot.summary)).dsFont(DS.Font.body).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .lineLimit(1)
            }
            // O título é a alça do pane: arrastar leva a tabela para outro lado, outra tab ou uma tab própria (como o cabeçalho
            // dos terminais).
            .overlay {
                if let paneID, let drag {
                    PaneDragSource(controller: drag, payload: .otherPane(paneID), title: { snapshot?.summary.dataset.name ?? "" })
                }
            }
            .layoutPriority(1)
            if let snapshot {
                if controller.isCollecting(snapshot.summary) { CollectingPill() }
                // Em área estreita os números somem do fim para o começo.
                ViewThatFits(in: .horizontal) {
                    stats(snapshot, count: 5)
                    stats(snapshot, count: 3)
                    stats(snapshot, count: 1)
                    Color.clear.frame(width: .zero, height: .zero)
                }
                .padding(.leading, DS.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .a11y(.datasetStats, kind: "group", value: "\(snapshot.stats.rows)")
                ActionButton(
                    .datasetOpen, argument: .select("\(model.id)|beside"), tooltip: String(localized: "Open beside the agent", bundle: .module)
                ) { Image(systemName: "rectangle.split.2x1") }
                    .buttonStyle(DSIconButtonStyle(.header))
                MenuButton(id: .datasetColumns, action: .datasetColumns, entries: columnEntries) {
                    Image(systemName: "line.3.horizontal.decrease")
                    if width >= DatasetMetrics.buttonLabelsMinWidth { Text("Columns", bundle: .module) }
                }
                MenuButton(id: .datasetExport, action: .datasetExport, entries: exportEntries, primary: true) {
                    Image(systemName: "arrow.down.to.line")
                    if width >= DatasetMetrics.buttonLabelsMinWidth { Text("Export", bundle: .module) }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private func stats(_ snapshot: DatasetPageSnapshot, count: Int) -> some View {
        let s = snapshot.stats
        return HStack(spacing: DatasetMetrics.statGap) {
            StatView(value: s.rows.formatted(), label: String(localized: "Rows", bundle: .module).lowercased())
            if count >= 3 {
                StatView(value: s.invalid.formatted(), label: String(localized: "Invalid", bundle: .module).lowercased(), tone: s.invalid > 0 ? DS.Color.warning : DS.Color.textTertiary)
                StatView(value: String(localized: "\(snapshot.perMinute)/min", bundle: .module), label: String(localized: "rate", bundle: .module))
            }
            if count >= 5 {
                StatView(value: s.filled.formatted(.percent.precision(.fractionLength(1))), label: String(localized: "filled", bundle: .module))
                StatView(value: s.computers.formatted(), label: s.computers == 1 ? String(localized: "Computer", bundle: .module).lowercased() : String(localized: "Computers", bundle: .module).lowercased())
            }
        }
    }

    private var columnEntries: [DSMenuEntry] {
        model.columns.map { column in
            .item(DSMenuItem(
                column.name, column.name, detail: DatasetMetrics.typeLabel(column.type), detailMono: true,
                checked: !model.hiddenColumns.contains(column.name), action: .datasetColumns, argument: .select(column.name)))
        }
    }

    private var exportEntries: [DSMenuEntry] {
        DatasetExportFormat.allCases.map { format in
            let title = switch format {
            case .csv: String(localized: "CSV", bundle: .module)
            case .jsonl: String(localized: "JSON Lines", bundle: .module)
            case .json: String(localized: "JSON", bundle: .module)
            }
            return .item(DSMenuItem(format.rawValue, title, action: .datasetExport, argument: .select(format.rawValue)))
        }
    }

    // MARK: Consulta

    private var queryBar: some View {
        HStack(spacing: DS.Space.s2) {
            DSTextField(
                "Filter: price:>200 name:plaza", text: $model.search, id: .datasetSearch, action: .datasetSearch, compact: true, mono: true)
            MenuButton(id: .datasetRange, action: .datasetRange, entries: rangeEntries) {
                Text(verbatim: Self.rangeTitle(model.range))
                Image(systemName: "chevron.down").font(.system(size: DS.Space.s2_5))
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DatasetMetrics.queryBar)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private var rangeEntries: [DSMenuEntry] {
        DatasetRange.allCases.map { range in
            .item(DSMenuItem(range.rawValue, Self.rangeTitle(range), checked: model.range == range, action: .datasetRange, argument: .select(range.rawValue)))
        }
    }

    static func rangeTitle(_ range: DatasetRange) -> String {
        switch range {
        case .minutes15: String(localized: "Last 15 minutes", bundle: .module)
        case .hour: String(localized: "Last 1 hour", bundle: .module)
        case .hours6: String(localized: "Last 6 hours", bundle: .module)
        case .day: String(localized: "Last 24 hours", bundle: .module)
        case .week: String(localized: "Last 7 days", bundle: .module)
        case .all: String(localized: "All time", bundle: .module)
        }
    }

    // MARK: Grade

    private func grid(_ snapshot: DatasetPageSnapshot) -> some View {
        let columns = model.visibleColumns
        let all = snapshot.summary.dataset.columns
        return VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        gridHeader(columns, key: snapshot.summary.dataset.key)
                        if snapshot.rows.isEmpty {
                            Text(emptyMessage(snapshot), bundle: .module)
                                .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .a11y(.datasetEmpty, kind: "text")
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(snapshot.rows) { row in
                                        ActionButton(.datasetSelectRow, id: .datasetRow(row.id), argument: .select(row.id)) {
                                            GridRow(
                                                row: row, columns: columns, allColumns: all, selected: model.selectedRowKey == row.id,
                                                captured: controller.clock(row.row.firstSeen))
                                        }
                                        .buttonStyle(.plain)
                                        .a11y(.datasetRow(row.id), kind: "row", label: row.cells.first ?? "", value: row.row.valid ? "valid" : "invalid")
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .top)
                }
            }
            footer(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .a11y(.datasetTable, kind: "table")
    }

    private func emptyMessage(_ snapshot: DatasetPageSnapshot) -> LocalizedStringKey {
        if snapshot.stats.rows == 0 { return "No rows yet. They appear here as the subagents append them." }
        return "No rows match."
    }

    private func gridHeader(_ columns: [DatasetColumn], key: [String]) -> some View {
        HStack(spacing: 0) {
            CheckSquare(on: false).frame(width: DatasetMetrics.checkColumn)
            Color.clear.frame(width: DatasetMetrics.stripeColumn)
                .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                let numeric = DatasetMetrics.isNumeric(column.type)
                HStack(spacing: DS.Space.s1_5) {
                    Text(verbatim: column.name).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    Text(verbatim: DatasetMetrics.typeLabel(column.type)).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
                    if key.contains(column.name) {
                        Text("KEY", bundle: .module).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.warning)
                    }
                }
                .padding(.horizontal, DatasetMetrics.cellPadding)
                .frame(width: DatasetMetrics.width(column.type, first: index == .zero), alignment: numeric ? .trailing : .leading)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
            }
            HStack(spacing: DS.Space.s1_5) {
                Text("Captured", bundle: .module).textCase(.lowercase).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                Text(verbatim: "time").dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DatasetMetrics.cellPadding)
            .frame(width: DatasetMetrics.colCaptured, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(height: DatasetMetrics.headerHeight)
        .background(DS.Color.chrome)
        .overlay(alignment: .bottom) { DS.Color.borderStrong.frame(height: ComputersMetrics.separator) }
    }

    private func footer(_ snapshot: DatasetPageSnapshot) -> some View {
        HStack(spacing: DS.Space.s2) {
            pageButton("chevron.left", id: .datasetPagePrev, argument: "prev", enabled: model.page > 0)
            pageButton("chevron.right", id: .datasetPageNext, argument: "next", enabled: model.page + 1 < model.pageCount)
            Text(verbatim: String(localized: "Page \(model.page + 1) of \(model.pageCount)", bundle: .module))
                .dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
                .padding(.leading, DS.Space.s1)
            Text(verbatim: "·").dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            Text(verbatim: String(localized: "\(snapshot.matching.formatted()) records", bundle: .module))
                .dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: footerDetail(snapshot)).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: DatasetMetrics.footerHeight)
        .background(DS.Color.chrome)
        .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func pageButton(_ symbol: String, id: A11yID, argument: String, enabled: Bool) -> some View {
        ActionButton(.datasetPage, id: id, argument: .select(argument)) {
            Image(systemName: symbol).font(.system(size: DS.Space.s2_5, weight: .semibold))
                .foregroundStyle(enabled ? DS.Color.textSecondary : DS.Color.textQuaternary)
                .frame(width: DS.Space.s6, height: DS.Space.s6)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.borderStrong))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func footerDetail(_ snapshot: DatasetPageSnapshot) -> String {
        var parts: [String] = []
        let key = snapshot.summary.dataset.key
        if !key.isEmpty { parts.append(String(localized: "Key: \(key.joined(separator: ", "))", bundle: .module)) }
        if snapshot.stats.duplicatesMerged > 0 {
            parts.append(String(localized: "duplicates merged: \(snapshot.stats.duplicatesMerged.formatted())", bundle: .module))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: Gráfico

/// Linhas novas no período: verde para válidas, âmbar para inválidas (onde um site começou a falhar), com legenda e eixo de horas.
private struct ActivityChart: View {
    let snapshot: DatasetPageSnapshot
    let controller: DatasetsController

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            HStack(spacing: DS.Space.s3) {
                legend(DS.Color.dataValid, String(localized: "Valid", bundle: .module).lowercased())
                legend(DS.Color.warning, String(localized: "Invalid", bundle: .module).lowercased())
                Spacer(minLength: 0)
                Text("new rows", bundle: .module).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary)
            }
            Canvas { context, size in draw(context, size) }
            axis
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        .frame(height: DatasetMetrics.chartHeight)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .a11y(.datasetChart, kind: "chart", value: "\(snapshot.activity.reduce(0) { $0 + $1.valid + $1.invalid })")
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: DS.Space.s1) {
            RoundedRectangle(cornerRadius: DS.Radius.xs).fill(color).frame(width: DatasetMetrics.legendSwatch, height: DatasetMetrics.legendSwatch)
            Text(verbatim: title).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        let buckets = snapshot.activity
        guard !buckets.isEmpty else { return }
        let peak = max(buckets.map { $0.valid + $0.invalid }.max() ?? 0, 1)
        let gap = DatasetMetrics.chartBarGap
        let width = (size.width - gap * CGFloat(buckets.count - 1)) / CGFloat(buckets.count)
        for (index, bucket) in buckets.enumerated() {
            let x = CGFloat(index) * (width + gap)
            let valid = size.height * CGFloat(bucket.valid) / CGFloat(peak)
            let invalid = bucket.invalid == 0 ? 0 : max(size.height * CGFloat(bucket.invalid) / CGFloat(peak), 2)
            if valid > 0 {
                context.fill(Path(CGRect(x: x, y: size.height - valid, width: width, height: valid)), with: .color(DS.Color.dataValid.opacity(0.7)))
            }
            if invalid > 0 {
                context.fill(Path(CGRect(x: x, y: size.height - valid - invalid, width: width, height: invalid)), with: .color(DS.Color.warning))
            }
            if valid + invalid == 0 {
                context.fill(Path(CGRect(x: x, y: size.height - 1, width: width, height: 1)), with: .color(DS.Color.borderStrong))
            }
        }
    }

    /// Seis marcas de hora de ponta a ponta; a última é `now`.
    private var axis: some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                Text(verbatim: label(index)).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textQuaternary)
                if index < 5 { Spacer(minLength: 0) }
            }
        }
    }

    private func label(_ index: Int) -> String {
        guard index < 5 else { return String(localized: "now", bundle: .module) }
        guard let start = snapshot.activityStart else { return "" }
        let span = controller.now().timeIntervalSince(start)
        return controller.clock(start.addingTimeInterval(span * Double(index) / 5), seconds: false)
    }
}

// MARK: Facetas

/// Coluna da esquerda: cada faceta com os valores e as contagens; clicar marca/desmarca (status, computador, site e evidência começam
/// todos marcados; erro começa desmarcado e marcar filtra).
private struct FacetsPanel: View {
    let snapshot: DatasetPageSnapshot
    let controller: DatasetsController
    let model: DatasetViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                ForEach(DatasetFacet.allCases, id: \.self) { facet in
                    let values = snapshot.facets[facet] ?? []
                    if !values.isEmpty {
                        VStack(alignment: .leading, spacing: .zero) {
                            Text(verbatim: Self.title(facet).uppercased()).dsFont(DS.Font.micro).tracking(0.6).foregroundStyle(DS.Color.textTertiary)
                                .padding(.bottom, DS.Space.s1_5)
                            ForEach(values) { value in row(facet, value) }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: DatasetMetrics.facetWidth)
        .background(DS.Color.chrome)
        .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
    }

    private func row(_ facet: DatasetFacet, _ value: DatasetFacetCount) -> some View {
        let on = model.isChecked(facet, value.value)
        return ActionButton(.datasetFacet, id: .datasetFacet(facet.rawValue, value.value), argument: .select("\(facet.rawValue):\(value.value)")) {
            HStack(spacing: DS.Space.s2) {
                CheckSquare(on: on)
                if facet == .status {
                    Circle().fill(value.value == "valid" ? DS.Color.dataValid : DS.Color.warning)
                        .frame(width: DatasetMetrics.facetDot, height: DatasetMetrics.facetDot)
                }
                Text(verbatim: Self.label(facet, value.value)).dsFont(DS.Font.cell)
                    .foregroundStyle(on || facet == .error ? DS.Color.textPrimary : DS.Color.textTertiary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: DS.Space.s1)
                Text(verbatim: value.count.formatted()).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
            }
            .frame(height: DatasetMetrics.facetRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func title(_ facet: DatasetFacet) -> String {
        switch facet {
        case .status: String(localized: "Status", bundle: .module)
        case .computer: String(localized: "Computer", bundle: .module)
        case .source: String(localized: "Source", bundle: .module)
        case .evidence: String(localized: "Evidence", bundle: .module)
        case .error: String(localized: "Error", bundle: .module)
        }
    }

    static func label(_ facet: DatasetFacet, _ value: String) -> String {
        switch (facet, value) {
        case (.status, "valid"): String(localized: "Valid", bundle: .module)
        case (.status, "invalid"): String(localized: "Invalid", bundle: .module)
        case (.evidence, "observed"): String(localized: "Seen in network", bundle: .module)
        case (.evidence, "reported"): String(localized: "Agent-reported", bundle: .module)
        case (.evidence, "none"): String(localized: "No source", bundle: .module)
        default: value
        }
    }
}

// MARK: Linha da grade

/// Uma linha: caixa de seleção, faixa de estado (verde válida, âmbar inválida), células (números em mono à direita, URL em mono,
/// NULL visível, erro como etiqueta âmbar) e a hora de captura.
private struct GridRow: View {
    let row: DatasetDisplayRow
    let columns: [DatasetColumn]
    let allColumns: [DatasetColumn]
    let selected: Bool
    let captured: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            CheckSquare(on: selected, tint: DS.Color.dataKey).frame(width: DatasetMetrics.checkColumn)
            RoundedRectangle(cornerRadius: DatasetMetrics.stripeWidth / 2)
                .fill(row.row.valid ? DS.Color.dataValid.opacity(0.8) : DS.Color.warning)
                .frame(width: DatasetMetrics.stripeWidth, height: DatasetMetrics.stripeHeight)
                .frame(width: DatasetMetrics.stripeColumn, height: DatasetMetrics.rowHeight)
                .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                cell(column: column, first: index == .zero)
            }
            Text(verbatim: captured).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                .padding(.horizontal, DatasetMetrics.cellPadding)
                .frame(width: DatasetMetrics.colCaptured, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(height: DatasetMetrics.rowHeight)
        .background(selected ? DS.Color.dataKey.opacity(0.08) : (hovering ? DS.Color.hoverRow : Color.clear))
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private func cell(column: DatasetColumn, first: Bool) -> some View {
        let index = allColumns.firstIndex { $0.name == column.name } ?? 0
        let text = index < row.cells.count ? row.cells[index] : ""
        let problem = index < row.problems.count ? row.problems[index] : nil
        let numeric = DatasetMetrics.isNumeric(column.type)
        Group {
            if let problem {
                Text(verbatim: problem).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.warning)
                    .padding(.horizontal, DS.Space.s1_5)
                    .padding(.vertical, DS.Space.s0_5)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.xs + 1).fill(DS.Color.warningBackground))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.xs + 1).strokeBorder(DS.Color.warningBorder))
            } else if text.isEmpty {
                Text(verbatim: "NULL").dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textQuaternary)
            } else {
                Text(verbatim: column.type == .url ? GridRowText.short(text) : text)
                    .dsFont(DatasetMetrics.isMono(column.type) ? DS.Font.monoCell : DS.Font.cell)
                    .foregroundStyle(column.type == .url ? DS.Color.textSecondary : DS.Color.textPrimary)
            }
        }
        .lineLimit(1).truncationMode(.tail)
        .padding(.horizontal, DatasetMetrics.cellPadding)
        .frame(width: DatasetMetrics.width(column.type, first: first), alignment: numeric ? .trailing : .leading)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
    }
}

// MARK: Painel da linha

/// Painel à direita: estado e nome, abas Attributes · Source · History e os botões Open page, Show request e Copy JSON.
private struct RowPanel: View {
    let row: DatasetDisplayRow
    let columns: [DatasetColumn]
    let controller: DatasetsController
    let model: DatasetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabs
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    switch model.panelTab {
                    case .attributes:
                        attributes
                        SourceCard(row: row.row, compact: true)
                    case .source:
                        SourceCard(row: row.row, compact: false)
                    case .history:
                        history
                    }
                }
                .padding(DS.Space.s4)
            }
            actions
        }
        .frame(width: DatasetMetrics.panelWidth)
        .background(DS.Color.chrome)
        .overlay(alignment: .leading) { DS.Color.border.frame(width: ComputersMetrics.separator) }
        .a11y(.datasetProvenance, kind: "panel")
    }

    private var title: String { row.cells.first.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Row", bundle: .module) }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s2) {
                    statusPill
                    Text(verbatim: title).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                }
                Text(verbatim: subtitle).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            ActionButton(.datasetSelectRow, argument: .select(""), tooltip: String(localized: "Close", bundle: .module)) { Image(systemName: "xmark") }
                .buttonStyle(DSIconButtonStyle(.header))
        }
        .padding(.leading, DS.Space.s4)
        .padding(.trailing, DS.Space.s2)
        .padding(.vertical, DS.Space.s3)
    }

    private var subtitle: String {
        let base = String(localized: "captured \(controller.clock(row.row.firstSeen))", bundle: .module)
        return row.row.seenCount > 1 ? base + " · " + String(localized: "seen \(row.row.seenCount)×", bundle: .module) : base
    }

    private var statusPill: some View {
        let valid = row.row.valid
        let tone = valid ? DS.Color.dataValid : DS.Color.warning
        return HStack(spacing: DS.Space.s1) {
            Circle().fill(tone).frame(width: DatasetMetrics.liveDot, height: DatasetMetrics.liveDot)
            Text(valid ? "Valid" : "Invalid", bundle: .module).dsFont(DS.Font.label).foregroundStyle(tone)
        }
        .padding(.horizontal, DS.Space.s1_5)
        .padding(.vertical, DS.Space.s0_5)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(tone.opacity(0.12)))
        .fixedSize()
    }

    private var tabs: some View {
        HStack(spacing: DS.Space.s4) {
            tab(.attributes, String(localized: "Attributes", bundle: .module))
            tab(.source, String(localized: "Source", bundle: .module))
            tab(.history, String(localized: "History", bundle: .module))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s4)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func tab(_ value: DatasetPanelTab, _ title: String) -> some View {
        let on = model.panelTab == value
        return ActionButton(.datasetPanelTab, id: .datasetPanelTab(value.rawValue), argument: .select(value.rawValue)) {
            Text(verbatim: title).dsFont(DS.Font.label).foregroundStyle(on ? DS.Color.textPrimary : DS.Color.textTertiary)
                .padding(.vertical, DS.Space.s2)
                .overlay(alignment: .bottom) { if on { DS.Color.textPrimary.frame(height: DatasetMetrics.tabUnderline) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Valores no estilo do Datadog: chave em azul, texto entre aspas em verde, números em branco, ausente como `null`.
    private var attributes: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                let problem = index < row.problems.count ? row.problems[index] : nil
                let value = index < row.cells.count ? row.cells[index] : ""
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(verbatim: column.name).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.dataKey).lineLimit(1)
                        .frame(width: DatasetMetrics.panelLabel, alignment: .leading)
                    attributeValue(column, value: value, problem: problem)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func attributeValue(_ column: DatasetColumn, value: String, problem: String?) -> some View {
        if let problem {
            Text(verbatim: problem).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.warning).lineLimit(1)
        } else if value.isEmpty {
            Text(verbatim: "null").dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textQuaternary)
        } else if DatasetMetrics.isNumeric(column.type) || column.type == .boolean {
            Text(verbatim: value).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
        } else {
            Text(verbatim: "\"" + (column.type == .url ? GridRowText.short(value) : value) + "\"").dsFont(DS.Font.monoCell)
                .foregroundStyle(DS.Color.dataString).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            PanelLine(label: String(localized: "First seen", bundle: .module), value: controller.absolute(row.row.firstSeen))
            PanelLine(label: String(localized: "Last seen", bundle: .module), value: controller.absolute(row.row.lastSeen))
            PanelLine(label: String(localized: "Times seen", bundle: .module), value: row.row.seenCount.formatted(), mono: true)
                .a11y(.datasetProvenanceSeen, kind: "text", value: "\(row.row.seenCount)")
            if !row.row.valid, let error = row.row.error {
                PanelLine(label: String(localized: "Error", bundle: .module), value: error, tone: DS.Color.warning, lines: 4)
                    .a11y(.datasetProvenanceError, kind: "text", value: error)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: DS.Space.s1_5) {
            if row.row.sourceURL.flatMap(DatasetsController.webURL) != nil {
                DSButton(.datasetOpenSource, "Open page", variant: .outline, size: .xs, argument: .select(row.row.rowKey))
            }
            if let request = row.row.requestID, let computer = row.row.computer {
                DSButton(.computerOpenEvidence, "Show request", variant: .outline, size: .xs, argument: .select("\(computer)|\(request)"))
            }
            DSButton(.datasetCopyRow, id: .datasetCopyRow, "Copy JSON", variant: .outline, size: .xs, argument: .select(row.row.rowKey))
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
        .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }
}

/// Rótulo à esquerda, valor à direita (cartão de origem e histórico).
private struct PanelLine: View {
    let label: String
    let value: String
    var mono = false
    var tone: Color = DS.Color.textPrimary
    var lines = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: label).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                .frame(width: DatasetMetrics.panelLabel, alignment: .leading)
            Spacer(minLength: 0)
            Text(verbatim: value).dsFont(mono ? DS.Font.monoCell : DS.Font.cell).foregroundStyle(tone)
                .lineLimit(lines).truncationMode(.middle).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

/// De onde a linha veio: página, computador, pedido (método · status · tempo) e evidência; a versão completa mostra também os ids.
private struct SourceCard: View {
    let row: DatasetRow
    let compact: Bool

    private var trust: (String, Color) {
        switch row.trust {
        case .observed: (String(localized: "Seen in network", bundle: .module), DS.Color.dataValid)
        case .reported: (String(localized: "Agent-reported", bundle: .module), DS.Color.textSecondary)
        case .none: (String(localized: "No source", bundle: .module), DS.Color.textTertiary)
        }
    }

    private var requestText: String? {
        guard let info = row.request else { return nil }
        let head = [info.method, info.status.map { "\($0)" }].compactMap { $0 }.joined(separator: " ")
        if let ms = info.milliseconds { return head.isEmpty ? "\(ms) ms" : "\(head) · \(ms) ms" }
        return head.isEmpty ? nil : head
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            PanelLine(label: String(localized: "Page", bundle: .module), value: row.sourceURL.map(GridRowText.short) ?? "—", mono: true)
                .a11y(.datasetProvenanceSource, kind: "text", value: row.sourceURL ?? "")
            PanelLine(label: String(localized: "Computer", bundle: .module), value: row.computer ?? "—")
                .a11y(.datasetProvenanceComputer, kind: "text", value: row.computer ?? "")
            PanelLine(label: String(localized: "Request", bundle: .module), value: requestText ?? "—", mono: true)
                .a11y(.datasetProvenanceRequest, kind: "text", value: row.requestID ?? "")
            HStack(spacing: DS.Space.s2) {
                Text("Evidence", bundle: .module).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textTertiary)
                Spacer(minLength: 0)
                Circle().fill(trust.1).frame(width: DatasetMetrics.liveDot, height: DatasetMetrics.liveDot)
                Text(verbatim: trust.0).dsFont(DS.Font.cell).foregroundStyle(trust.1)
            }
            .a11y(.datasetProvenanceTrust, kind: "badge", value: row.trust.rawValue)
            if !compact {
                PanelLine(label: String(localized: "Request ID", bundle: .module), value: row.requestID ?? "—", mono: true)
                PanelLine(label: String(localized: "Run", bundle: .module), value: row.runID ?? "—", mono: true)
                    .a11y(.datasetProvenanceRun, kind: "text", value: row.runID ?? "")
                PanelLine(label: String(localized: "Full URL", bundle: .module), value: row.sourceURL ?? "—", mono: true, lines: 3)
            }
        }
        .padding(DS.Space.s3)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Color.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Color.border))
    }
}

/// URL sem o esquema, para caber na grade e no painel.
enum GridRowText {
    static func short(_ url: String) -> String {
        for prefix in ["https://", "http://"] where url.hasPrefix(prefix) { return String(url.dropFirst(prefix.count)) }
        return url
    }
}
