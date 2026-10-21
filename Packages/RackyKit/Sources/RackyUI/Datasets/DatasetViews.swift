import RackyCore
import RackyDesignSystem
import RackyProtocol
import RackyStore
import SwiftUI

// Datasets v1: a lista (03 §12.5) e a tabela viva de um dataset com a proveniência da linha selecionada. Tudo passa pelo
// `DatasetsController`; os controles são `ActionButton`/`DSButton` do registro de ações.

enum DatasetMetrics {
    static let rowHeight = DS.Space.s6 + DS.Space.s2
    static let colName: CGFloat = 200
    static let colSession: CGFloat = 180
    static let colCount: CGFloat = 90
    static let colUpdated: CGFloat = 110
    static let colStatus: CGFloat = 64
    static let colString: CGFloat = 200
    static let colURL: CGFloat = 280
    static let colNumber: CGFloat = 90
    static let colBoolean: CGFloat = 70
    static let colDate: CGFloat = 110
    static let colDateTime: CGFloat = 180
    static let colJSON: CGFloat = 220
    static let searchWidth: CGFloat = 220
    static let exportWidth: CGFloat = 120
    static let provenanceLabel: CGFloat = 92

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
}

// MARK: Lista

struct DatasetsPageView: View {
    let controller: DatasetsController

    var body: some View {
        let summaries = controller.summaries
        VStack(spacing: 0) {
            PageHeader(title: "Datasets") {
                Text(verbatim: Self.summaryText(summaries)).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
            }
            if summaries.isEmpty {
                Text("No datasets yet. Subagents create them when they collect tables of data.", bundle: .module)
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textQuaternary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .a11y(.datasetsEmpty, kind: "text")
            } else {
                header
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(summaries) { summary in
                            ActionButton(.datasetOpen, id: .datasetsRow(summary.dataset.id), argument: .select(summary.dataset.id)) {
                                row(summary)
                            }
                            .buttonStyle(DSListRowStyle())
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
        HStack(spacing: DS.Space.s4) {
            column("Name", DatasetMetrics.colName)
            column("Session", DatasetMetrics.colSession)
            column("Rows", DatasetMetrics.colCount, trailing: true)
            column("Invalid", DatasetMetrics.colCount, trailing: true)
            column("Columns", DatasetMetrics.colCount, trailing: true)
            column("Updated", DatasetMetrics.colUpdated)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: ComputersMetrics.tableHeader)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func column(_ title: LocalizedStringKey, _ width: CGFloat, trailing: Bool = false) -> some View {
        Text(title, bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary).frame(width: width, alignment: trailing ? .trailing : .leading)
    }

    private func row(_ summary: DatasetSummary) -> some View {
        HStack(spacing: DS.Space.s4) {
            Text(verbatim: summary.dataset.name).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                .frame(width: DatasetMetrics.colName, alignment: .leading)
            Text(verbatim: controller.title(of: summary)).dsFont(DS.Font.body).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                .frame(width: DatasetMetrics.colSession, alignment: .leading)
            number(summary.rowCount)
            number(summary.invalidCount, warn: summary.invalidCount > 0)
            number(summary.dataset.columns.count)
            Text(verbatim: controller.relative(summary.dataset.updatedAt)).dsFont(DS.Font.body).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                .frame(width: DatasetMetrics.colUpdated, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(height: ComputersMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private func number(_ value: Int, warn: Bool = false) -> some View {
        Text(verbatim: value.formatted()).dsFont(DS.Font.monoPane).foregroundStyle(warn ? DS.Color.warning : DS.Color.textSecondary).lineLimit(1)
            .frame(width: DatasetMetrics.colCount, alignment: .trailing)
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

    var body: some View {
        let snapshot = controller.snapshot
        VStack(spacing: 0) {
            PageHeader(verbatim: snapshot?.summary.dataset.name ?? "") {
                if let snapshot { Text(verbatim: summaryLine(snapshot)).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary).lineLimit(1) }
                DSCombobox(
                    id: .datasetExport, selection: "", entries: exportEntries, action: .datasetExport,
                    placeholder: String(localized: "Export", bundle: .module), height: DSMetrics.fieldHeightComposer)
                    .frame(width: DatasetMetrics.exportWidth)
            }
            toolbar(snapshot)
            if let snapshot {
                table(snapshot)
                provenance(snapshot)
            } else {
                Spacer(minLength: 0)
            }
        }
        .background(DS.Color.canvas)
        .a11y(.datasetPage, kind: "page")
    }

    private func summaryLine(_ snapshot: DatasetPageSnapshot) -> String {
        let summary = snapshot.summary
        let session = controller.title(of: summary)
        let rows = summary.rowCount == 1 ? String(localized: "1 row", bundle: .module) : String(localized: "\(summary.rowCount.formatted()) rows", bundle: .module)
        let invalid = String(localized: "\(summary.invalidCount.formatted()) invalid", bundle: .module)
        let updated = String(localized: "updated \(controller.relative(summary.dataset.updatedAt))", bundle: .module)
        return "\(session) · \(rows) · \(invalid) · \(updated)"
    }

    private func toolbar(_ snapshot: DatasetPageSnapshot?) -> some View {
        HStack(spacing: DS.Space.s2) {
            DSSegmented(
                [.init("all", "All"), .init("invalid", "Invalid")], selection: controller.filter.rawValue, action: .datasetFilter, id: .datasetFilter)
            DSTextField("Search rows", text: $controller.search, id: .datasetSearch, action: .datasetSearch, compact: true)
                .frame(width: DatasetMetrics.searchWidth)
            Spacer(minLength: 0)
            if let snapshot, snapshot.matching != snapshot.summary.rowCount || controller.filter == .invalid {
                Text("\(snapshot.matching.formatted()) matching", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
    }

    private func table(_ snapshot: DatasetPageSnapshot) -> some View {
        let columns = snapshot.summary.dataset.columns
        return GeometryReader { viewport in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    tableHeader(columns)
                    if snapshot.rows.isEmpty {
                        Text(emptyMessage(snapshot), bundle: .module)
                            .dsFont(DS.Font.small).foregroundStyle(DS.Color.textQuaternary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .a11y(.datasetEmpty, kind: "text")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(snapshot.rows) { row in
                                    ActionButton(.datasetSelectRow, id: .datasetRow(row.id), argument: .select(row.id)) {
                                        rowView(row, columns: columns)
                                    }
                                    .buttonStyle(DSListRowStyle(selected: controller.selectedRowKey == row.id))
                                    .a11y(.datasetRow(row.id), kind: "row", label: row.cells.first ?? "", value: row.row.valid ? "valid" : "invalid")
                                }
                                if snapshot.matching > snapshot.rows.count {
                                    DSButton(.datasetLoadMore, id: .datasetLoadMore, "Load more", variant: .outline, size: .xs)
                                        .padding(DS.Space.s3)
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: viewport.size.width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .a11y(.datasetTable, kind: "table")
    }

    private func emptyMessage(_ snapshot: DatasetPageSnapshot) -> LocalizedStringKey {
        if controller.filter == .invalid, controller.search.isEmpty { return "No invalid rows." }
        if !controller.search.isEmpty || controller.filter == .invalid { return "No rows match." }
        return "No rows yet. They appear here as the subagents append them."
    }

    private func tableHeader(_ columns: [DatasetColumn]) -> some View {
        HStack(spacing: DS.Space.s4) {
            Color.clear.frame(width: DatasetMetrics.colStatus)
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                let width = DatasetMetrics.width(column.type, first: index == .zero)
                let alignment: Alignment = DatasetMetrics.isNumeric(column.type) ? .trailing : .leading
                Text(verbatim: column.name).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary).lineLimit(1).frame(width: width, alignment: alignment)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: ComputersMetrics.tableHeader)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func rowView(_ row: DatasetDisplayRow, columns: [DatasetColumn]) -> some View {
        HStack(spacing: DS.Space.s4) {
            Group {
                if !row.row.valid { Text("Invalid", bundle: .module).dsFont(DS.Font.micro).foregroundStyle(DS.Color.warning) } else { Color.clear }
            }
            .frame(width: DatasetMetrics.colStatus, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                let text = index < row.cells.count ? row.cells[index] : ""
                let numeric = DatasetMetrics.isNumeric(column.type)
                let first = index == .zero
                let width = DatasetMetrics.width(column.type, first: first)
                let alignment: Alignment = numeric ? .trailing : .leading
                Text(verbatim: text).dsFont(numeric ? DS.Font.monoPane : (first ? DS.Font.bodyStrong : DS.Font.body))
                    .foregroundStyle(first ? DS.Color.textPrimary : DS.Color.textSecondary).lineLimit(1).truncationMode(.tail)
                    .frame(width: width, alignment: alignment)
            }
            Spacer(minLength: 0)
        }
        .frame(height: DatasetMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    // MARK: Proveniência

    @ViewBuilder private func provenance(_ snapshot: DatasetPageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            if let selected = controller.selectedRow {
                ProvenanceView(row: selected.row, controller: controller)
            } else {
                Text("Select a row to see where it came from.", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textQuaternary)
            }
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.chrome)
        .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .a11y(.datasetProvenance, kind: "panel")
    }
}

struct ProvenanceView: View {
    let row: DatasetRow
    let controller: DatasetsController

    private var trustLabel: String {
        switch row.trust {
        case .observed: String(localized: "Observed", bundle: .module)
        case .reported: String(localized: "Agent-reported", bundle: .module)
        case .none: String(localized: "No source", bundle: .module)
        }
    }

    private var webURL: Bool { row.sourceURL.flatMap(DatasetsController.webURL) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            line("Source") {
                HStack(spacing: DS.Space.s2) {
                    mono(row.sourceURL)
                    if webURL { DSButton(.datasetOpenSource, id: nil, "Open", variant: .ghost, size: .xs, argument: .select(row.rowKey)) }
                }
            }
            .a11y(.datasetProvenanceSource, kind: "text", value: row.sourceURL ?? "")
            line("Computer") { mono(row.computer) }.a11y(.datasetProvenanceComputer, kind: "text", value: row.computer ?? "")
            line("Run") { mono(row.runID) }.a11y(.datasetProvenanceRun, kind: "text", value: row.runID ?? "")
            line("Request") {
                HStack(spacing: DS.Space.s2) {
                    mono(row.requestID)
                    if let request = row.requestID, let computer = row.computer {
                        DSButton(.computerOpenEvidence, id: nil, "Open", variant: .ghost, size: .xs, argument: .select("\(computer)|\(request)"))
                    }
                    DSBadge(trustLabel, variant: row.trust == .none ? .neutral : .pill)
                        .a11y(.datasetProvenanceTrust, kind: "badge", value: row.trust.rawValue)
                }
            }
            .a11y(.datasetProvenanceRequest, kind: "text", value: row.requestID ?? "")
            line("Seen") {
                Text(verbatim: seenText).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
            }
            .a11y(.datasetProvenanceSeen, kind: "text", value: "\(row.seenCount)")
            if !row.valid, let error = row.error {
                line("Error") { Text(verbatim: error).dsFont(DS.Font.small).foregroundStyle(DS.Color.warning).lineLimit(2) }
                    .a11y(.datasetProvenanceError, kind: "text", value: error)
            }
        }
    }

    private var seenText: String {
        let first = controller.absolute(row.firstSeen), last = controller.absolute(row.lastSeen)
        let times = row.seenCount == 1 ? String(localized: "1 time", bundle: .module) : String(localized: "\(row.seenCount) times", bundle: .module)
        return String(localized: "First \(first) · Last \(last) · \(times)", bundle: .module)
    }

    private func line<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(title, bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary).frame(width: DatasetMetrics.provenanceLabel, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Space.s6)
    }

    private func mono(_ text: String?) -> some View {
        Text(verbatim: text ?? "—").dsFont(DS.Font.monoMicro).foregroundStyle(text == nil ? DS.Color.textQuaternary : DS.Color.textPrimary)
            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
    }
}
