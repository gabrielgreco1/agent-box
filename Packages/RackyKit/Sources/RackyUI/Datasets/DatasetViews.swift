import RackyCore
import RackyDesignSystem
import RackyProtocol
import RackyStore
import SwiftUI

// Datasets: a lista (03 §12.5) e a página de um dataset, no tom do editor de tabelas do Supabase com o volume do Datadog: uma barra
// só (nome, "Collecting", números, busca, filtro, export), um gráfico fino de linhas novas, a grade densa e o painel da linha
// selecionada. Tudo passa pelo `DatasetsController`; os controles são `ActionButton`/`DSButton` do registro de ações.

enum DatasetMetrics {
    static let barHeight = DS.Space.s10 + DS.Space.s2
    static let chartHeight = DS.Space.s10
    static let chartBarGap: CGFloat = 3
    static let headerHeight = DS.Space.s8
    static let rowHeight = DS.Space.s8
    static let listRowHeight = DS.Space.s10 + DS.Space.s1
    static let cellPadding = DS.Space.s3
    static let marker: CGFloat = 2
    static let liveDot: CGFloat = 6
    static let colName: CGFloat = 220
    static let colSession: CGFloat = 160
    static let colCount: CGFloat = 90
    static let colString: CGFloat = 200
    static let colURL: CGFloat = 320
    static let colNumber: CGFloat = 96
    static let colBoolean: CGFloat = 72
    static let colDate: CGFloat = 110
    static let colDateTime: CGFloat = 170
    static let colJSON: CGFloat = 220
    static let colCaptured: CGFloat = 96
    static let searchWidth: CGFloat = 220
    static let searchMinWidth: CGFloat = 120
    static let filterWidth: CGFloat = 120
    static let exportWidth: CGFloat = 108
    static let panelWidth: CGFloat = 300
    static let panelLabel: CGFloat = 84

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

    /// Rótulo curto do tipo no cabeçalho (`text`, `num`, `int`…).
    static func typeLabel(_ type: DatasetColumnType) -> String {
        switch type {
        case .string: "text"
        case .integer: "int"
        case .number: "num"
        case .boolean: "bool"
        case .date: "date"
        case .datetime: "time"
        case .url: "url"
        case .json: "json"
        }
    }
}

/// "● Collecting" em verde enquanto algum computador da sessão roda.
private struct CollectingBadge: View {
    var body: some View {
        HStack(spacing: DS.Space.s1_5) {
            Circle().fill(DS.Color.success).frame(width: DatasetMetrics.liveDot, height: DatasetMetrics.liveDot)
            Text("Collecting", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.success)
        }
        .fixedSize()
    }
}

/// Número em mono seguido do rótulo apagado: `1,213 rows`.
private struct CountLabel: View {
    let value: String
    let label: String
    var warn = false

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            Text(verbatim: value).dsFont(DS.Font.monoCell).foregroundStyle(warn ? DS.Color.warning : DS.Color.textPrimary)
            Text(verbatim: label).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textTertiary)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Barra de cima das duas páginas: título, conteúdo do meio e o fechar da página (mesmo canto do `PageHeader`).
private struct DatasetBar<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.pageTrailingInset) private var trailingInset

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            content()
            ActionButton(.pageClose, tooltip: String(localized: "Close", bundle: .module)) { Image(systemName: "xmark") }
                .buttonStyle(DSIconButtonStyle(.header))
        }
        .padding(.leading, DS.Space.s4)
        .padding(.trailing, DS.Space.s3 + trailingInset)
        .frame(height: DatasetMetrics.barHeight)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
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
                    CountLabel(value: summaries.count.formatted(), label: summaries.count == 1 ? String(localized: "dataset", bundle: .module) : String(localized: "datasets", bundle: .module))
                    CountLabel(value: summaries.reduce(0) { $0 + $1.rowCount }.formatted(), label: String(localized: "rows", bundle: .module))
                }
                Spacer(minLength: 0)
            }
            if summaries.isEmpty {
                VStack(spacing: DS.Space.s1_5) {
                    Text("No datasets yet", bundle: .module).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textSecondary)
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
                                ListRow { row(summary) }
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
            VStack(alignment: .leading, spacing: .zero) {
                Text(verbatim: summary.dataset.name).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Text(verbatim: summary.dataset.columns.map(\.name).joined(separator: " · "))
                    .dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
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
                    CollectingBadge()
                } else {
                    Text(verbatim: controller.relative(summary.dataset.updatedAt)).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                }
            }
            .padding(.horizontal, DatasetMetrics.cellPadding)
            .frame(width: DatasetMetrics.colSession, alignment: .leading)
        }
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

/// Linha clicável da lista, com o fundo de hover da grade (sem o recuo do `DSListRowStyle`, para alinhar com o cabeçalho).
private struct ListRow<Content: View>: View {
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
    @Bindable var controller: DatasetsController

    private var exportEntries: [DSMenuEntry] {
        [
            .item(DSMenuItem(DatasetExportFormat.csv.rawValue, String(localized: "CSV", bundle: .module))),
            .item(DSMenuItem(DatasetExportFormat.jsonl.rawValue, String(localized: "JSON Lines", bundle: .module))),
            .item(DSMenuItem(DatasetExportFormat.json.rawValue, String(localized: "JSON", bundle: .module))),
        ]
    }

    private func filterEntries(_ snapshot: DatasetPageSnapshot?) -> [DSMenuEntry] {
        let summary = snapshot?.summary
        return [
            .item(DSMenuItem(DatasetRowFilter.all.rawValue, String(localized: "All", bundle: .module), detail: summary.map { $0.rowCount.formatted() })),
            .item(DSMenuItem(DatasetRowFilter.invalid.rawValue, String(localized: "Invalid", bundle: .module), detail: summary.map { $0.invalidCount.formatted() })),
        ]
    }

    var body: some View {
        let snapshot = controller.snapshot
        VStack(spacing: 0) {
            bar(snapshot)
            if let snapshot {
                ActivityChart(buckets: snapshot.activity)
                HStack(spacing: 0) {
                    grid(snapshot)
                    if let selected = controller.selectedRow {
                        RowPanel(row: selected, columns: snapshot.summary.dataset.columns, controller: controller)
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .background(DS.Color.canvas)
        .a11y(.datasetPage, kind: "page")
    }

    private func bar(_ snapshot: DatasetPageSnapshot?) -> some View {
        DatasetBar {
            Text(verbatim: snapshot?.summary.dataset.name ?? "").dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                .fixedSize()
            if let snapshot {
                // Em área estreita (painéis abertos) os números somem antes do nome: primeiro o ritmo e as inválidas, depois tudo.
                ViewThatFits(in: .horizontal) {
                    counts(snapshot, full: true)
                    counts(snapshot, full: false)
                    Color.clear.frame(width: .zero, height: .zero)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DSTextField("Search rows", text: $controller.search, id: .datasetSearch, action: .datasetSearch, compact: true)
                .frame(minWidth: DatasetMetrics.searchMinWidth, maxWidth: DatasetMetrics.searchWidth)
            DSCombobox(
                id: .datasetFilter, selection: controller.filter.rawValue, entries: filterEntries(snapshot), action: .datasetFilter,
                placeholder: String(localized: "Filter", bundle: .module), height: DSMetrics.fieldHeightComposer)
                .frame(width: DatasetMetrics.filterWidth)
            DSCombobox(
                id: .datasetExport, selection: "", entries: exportEntries, action: .datasetExport,
                placeholder: String(localized: "Export", bundle: .module), height: DSMetrics.fieldHeightComposer)
                .frame(width: DatasetMetrics.exportWidth)
        }
    }

    private func counts(_ snapshot: DatasetPageSnapshot, full: Bool) -> some View {
        HStack(spacing: DS.Space.s3) {
            if controller.isCollecting(snapshot.summary) { CollectingBadge() }
            CountLabel(value: snapshot.summary.rowCount.formatted(), label: String(localized: "rows", bundle: .module))
            if full, snapshot.summary.invalidCount > 0 {
                CountLabel(value: snapshot.summary.invalidCount.formatted(), label: String(localized: "invalid", bundle: .module), warn: true)
            }
            if full, snapshot.perMinute > 0 {
                CountLabel(value: snapshot.perMinute.formatted(), label: String(localized: "/min", bundle: .module))
            }
        }
    }

    private func grid(_ snapshot: DatasetPageSnapshot) -> some View {
        let columns = snapshot.summary.dataset.columns
        return VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        gridHeader(columns)
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
                                            GridRow(row: row, columns: columns, selected: controller.selectedRowKey == row.id, captured: controller.clock(row.row.lastSeen))
                                        }
                                        .buttonStyle(.plain)
                                        .a11y(.datasetRow(row.id), kind: "row", label: row.cells.first ?? "", value: row.row.valid ? "valid" : "invalid")
                                    }
                                    if snapshot.matching > snapshot.rows.count {
                                        DSButton(.datasetLoadMore, id: .datasetLoadMore, "Load more", variant: .ghost, size: .xs)
                                            .padding(DS.Space.s3)
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
        if controller.filter == .invalid, controller.search.isEmpty { return "No invalid rows." }
        if !controller.search.isEmpty || controller.filter == .invalid { return "No rows match." }
        return "No rows yet. They appear here as the subagents append them."
    }

    private func gridHeader(_ columns: [DatasetColumn]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                let numeric = DatasetMetrics.isNumeric(column.type)
                HStack(spacing: DS.Space.s1_5) {
                    Text(verbatim: column.name).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                    Text(verbatim: DatasetMetrics.typeLabel(column.type)).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textQuaternary)
                }
                .padding(.horizontal, DatasetMetrics.cellPadding)
                .frame(width: DatasetMetrics.width(column.type, first: index == .zero), alignment: numeric ? .trailing : .leading)
            }
            Text("captured", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DatasetMetrics.cellPadding)
                .frame(width: DatasetMetrics.colCaptured, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(height: DatasetMetrics.headerHeight)
        .overlay(alignment: .bottom) { DS.Color.borderStrong.frame(height: ComputersMetrics.separator) }
    }

    private func footer(_ snapshot: DatasetPageSnapshot) -> some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: rangeText(snapshot)).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            Spacer(minLength: 0)
            if let key = keyText(snapshot) {
                Text(verbatim: key).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DatasetMetrics.headerHeight)
        .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func rangeText(_ snapshot: DatasetPageSnapshot) -> String {
        guard !snapshot.rows.isEmpty else { return String(localized: "0 rows", bundle: .module) }
        return String(localized: "1–\(snapshot.rows.count.formatted()) of \(snapshot.matching.formatted())", bundle: .module)
    }

    private func keyText(_ snapshot: DatasetPageSnapshot) -> String? {
        let key = snapshot.summary.dataset.key
        guard !key.isEmpty else { return nil }
        return String(localized: "Key: \(key.joined(separator: ", "))", bundle: .module)
    }
}

/// Gráfico fino de linhas novas na última hora: cinza para válidas, âmbar para inválidas (onde um site começou a falhar).
private struct ActivityChart: View {
    let buckets: [DatasetActivityBucket]

    var body: some View {
        Canvas { context, size in
            guard !buckets.isEmpty else { return }
            let peak = max(buckets.map { $0.valid + $0.invalid }.max() ?? 0, 1)
            let gap = DatasetMetrics.chartBarGap
            let width = (size.width - gap * CGFloat(buckets.count - 1)) / CGFloat(buckets.count)
            for (index, bucket) in buckets.enumerated() {
                let x = CGFloat(index) * (width + gap)
                let valid = size.height * CGFloat(bucket.valid) / CGFloat(peak)
                let invalid = size.height * CGFloat(bucket.invalid) / CGFloat(peak)
                if valid > 0 {
                    context.fill(Path(CGRect(x: x, y: size.height - valid, width: width, height: valid)), with: .color(DS.Color.fg18))
                }
                if invalid > 0 {
                    context.fill(Path(CGRect(x: x, y: size.height - valid - invalid, width: width, height: invalid)), with: .color(DS.Color.warning))
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s1_5)
        .frame(height: DatasetMetrics.chartHeight)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .accessibilityHidden(true)
    }
}

/// Uma linha da grade: números em mono à direita, URLs em mono apagado, a célula com problema em âmbar e uma marca à esquerda
/// (branca na selecionada, âmbar na inválida).
private struct GridRow: View {
    let row: DatasetDisplayRow
    let columns: [DatasetColumn]
    let selected: Bool
    let captured: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                cell(index: index, column: column)
            }
            Text(verbatim: captured).dsFont(DS.Font.monoCell).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                .padding(.horizontal, DatasetMetrics.cellPadding)
                .frame(width: DatasetMetrics.colCaptured, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(height: DatasetMetrics.rowHeight)
        .background(selected ? DS.Color.secondary.opacity(0.6) : (hovering ? DS.Color.hoverRow : Color.clear))
        .overlay(alignment: .leading) {
            if selected || !row.row.valid {
                (selected ? DS.Color.textPrimary : DS.Color.warning).frame(width: DatasetMetrics.marker)
            }
        }
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private func cell(index: Int, column: DatasetColumn) -> some View {
        let text = index < row.cells.count ? row.cells[index] : ""
        let problem = index < row.problems.count ? row.problems[index] : nil
        let numeric = DatasetMetrics.isNumeric(column.type)
        let shown = problem ?? (text.isEmpty ? "null" : Self.display(text, type: column.type))
        let color: Color = problem != nil ? DS.Color.warning
            : text.isEmpty ? DS.Color.textQuaternary
            : column.type == .url ? DS.Color.textTertiary
            : index == .zero ? DS.Color.textPrimary : DS.Color.textSecondary
        Text(verbatim: shown)
            .dsFont(problem != nil || text.isEmpty || DatasetMetrics.isMono(column.type) ? DS.Font.monoCell : DS.Font.cell)
            .foregroundStyle(color).lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, DatasetMetrics.cellPadding)
            .frame(width: DatasetMetrics.width(column.type, first: index == .zero), alignment: numeric ? .trailing : .leading)
    }

    /// URLs sem o `https://` (a coluna já diz que é url).
    static func display(_ text: String, type: DatasetColumnType) -> String {
        guard type == .url else { return text }
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { return String(text.dropFirst(prefix.count)) }
        return text
    }
}

// MARK: Linha selecionada

/// Painel à direita: os valores da linha e de onde ela veio, com Open page, Show request e Copy embaixo.
private struct RowPanel: View {
    let row: DatasetDisplayRow
    let columns: [DatasetColumn]
    let controller: DatasetsController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: row.cells.first.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Row", bundle: .module))
                    .dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                ActionButton(.datasetSelectRow, argument: .select(""), tooltip: String(localized: "Close", bundle: .module)) { Image(systemName: "xmark") }
                    .buttonStyle(DSIconButtonStyle(.header))
            }
            .padding(.leading, DS.Space.s4)
            .padding(.trailing, DS.Space.s2)
            .frame(height: DatasetMetrics.headerHeight + DS.Space.s1)
            .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    VStack(alignment: .leading, spacing: DS.Space.s1_5) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                            let problem = index < row.problems.count ? row.problems[index] : nil
                            let value = index < row.cells.count ? row.cells[index] : ""
                            pair(column.name, problem ?? (value.isEmpty ? "null" : value), mono: DatasetMetrics.isMono(column.type) || problem != nil,
                                 tone: problem != nil ? DS.Color.warning : (value.isEmpty ? DS.Color.textQuaternary : DS.Color.textPrimary))
                        }
                    }
                    ProvenanceView(row: row.row, controller: controller)
                }
                .padding(DS.Space.s4)
            }
            actions
        }
        .frame(width: DatasetMetrics.panelWidth)
        .overlay(alignment: .leading) { DS.Color.border.frame(width: ComputersMetrics.separator) }
        .a11y(.datasetProvenance, kind: "panel")
    }

    private var actions: some View {
        HStack(spacing: DS.Space.s1_5) {
            if row.row.sourceURL.flatMap(DatasetsController.webURL) != nil {
                DSButton(.datasetOpenSource, "Open page", variant: .outline, size: .xs, argument: .select(row.row.rowKey))
            }
            if let request = row.row.requestID, let computer = row.row.computer {
                DSButton(.computerOpenEvidence, "Show request", variant: .outline, size: .xs, argument: .select("\(computer)|\(request)"))
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
        .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func pair(_ key: String, _ value: String, mono: Bool, tone: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: key).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                .frame(width: DatasetMetrics.panelLabel, alignment: .leading)
            Text(verbatim: mono ? GridRowText.short(value) : value).dsFont(mono ? DS.Font.monoCell : DS.Font.cell).foregroundStyle(tone)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// De onde a linha veio: computador, página, pedido, quando e a evidência.
struct ProvenanceView: View {
    let row: DatasetRow
    let controller: DatasetsController

    private var trustLabel: String {
        switch row.trust {
        case .observed: String(localized: "Seen in network", bundle: .module)
        case .reported: String(localized: "Agent-reported", bundle: .module)
        case .none: String(localized: "No source", bundle: .module)
        }
    }

    private var trustColor: Color {
        switch row.trust {
        case .observed: DS.Color.success
        case .reported: DS.Color.textSecondary
        case .none: DS.Color.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            Text("Source", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                .padding(.bottom, DS.Space.s0_5)
            line("Page", row.sourceURL.map { GridRowText.short($0) }, mono: true)
                .a11y(.datasetProvenanceSource, kind: "text", value: row.sourceURL ?? "")
            line("Computer", row.computer, mono: false)
                .a11y(.datasetProvenanceComputer, kind: "text", value: row.computer ?? "")
            // Run e request ficam fora da vista (ids crus); seguem na árvore de automação e o request abre em "Show request".
            Color.clear.frame(height: .zero)
                .a11y(.datasetProvenanceRun, kind: "text", value: row.runID ?? "")
                .a11y(.datasetProvenanceRequest, kind: "text", value: row.requestID ?? "")
            line("Captured", seenText, mono: false)
                .a11y(.datasetProvenanceSeen, kind: "text", value: "\(row.seenCount)")
            HStack(spacing: DS.Space.s2) {
                Text("Evidence", bundle: .module).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textTertiary)
                    .frame(width: DatasetMetrics.panelLabel, alignment: .leading)
                Text(verbatim: trustLabel).dsFont(DS.Font.cell).foregroundStyle(trustColor)
                Spacer(minLength: 0)
            }
            .a11y(.datasetProvenanceTrust, kind: "badge", value: row.trust.rawValue)
            if !row.valid, let error = row.error {
                line("Error", error, mono: false, tone: DS.Color.warning)
                    .a11y(.datasetProvenanceError, kind: "text", value: error)
            }
        }
    }

    private var seenText: String {
        let ago = controller.relative(row.lastSeen)
        return row.seenCount == 1 ? ago : String(localized: "\(ago) · seen \(row.seenCount)×", bundle: .module)
    }

    private func line(_ title: LocalizedStringKey, _ value: String?, mono: Bool, tone: Color = DS.Color.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(title, bundle: .module).dsFont(DS.Font.cell).foregroundStyle(DS.Color.textTertiary)
                .frame(width: DatasetMetrics.panelLabel, alignment: .leading)
            Text(verbatim: value ?? "—").dsFont(mono ? DS.Font.monoCell : DS.Font.cell)
                .foregroundStyle(value == nil ? DS.Color.textQuaternary : tone)
                .lineLimit(mono ? 1 : 2).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// URL sem o esquema, para caber no painel.
enum GridRowText {
    static func short(_ url: String) -> String {
        for prefix in ["https://", "http://"] where url.hasPrefix(prefix) { return String(url.dropFirst(prefix.count)) }
        return url
    }
}
