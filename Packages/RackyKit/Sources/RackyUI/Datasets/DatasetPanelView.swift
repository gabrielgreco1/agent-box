import RackyCore
import RackyDesignSystem
import RackyProtocol
import RackyStore
import SwiftUI

/// Módulo Data do painel direito: o dataset da sessão aberta enquanto os subagentes coletam, no lugar dos Insights. Mostra se está
/// chegando, de onde, quanto está bom e as linhas mais novas com as colunas nomeadas. Abre sozinho quando os dados começam a entrar;
/// "Open table" leva para a tabela inteira numa tab da sessão e fecha a prévia (não ficam as duas).
@MainActor
final class DataModule: RightPanelModule {
    let id = PanelModuleID.data
    let title = String(localized: "Data", bundle: .module)
    let icon = "tablecells"
    let toggleAction: ActionID? = .rightPanelToggleData
    let stripButtonID: A11yID? = .tabsDataToggle
    private let datasets: DatasetsController

    init(datasets: DatasetsController) { self.datasets = datasets }

    func makeView(context: RightPanelModuleContext) -> AnyView {
        AnyView(DatasetPanelView(controller: datasets))
    }
}

enum DatasetPanelMetrics {
    static let rowHeight = DS.Space.s6 + DS.Space.s1
    static let headerRow = DS.Space.s6
    static let numberColumn: CGFloat = 64
    static let maxColumns = 3
    static let maxRows = 50
    static let chartHeight = DS.Space.s8
    static let stripe: CGFloat = 2
    /// Linha que chegou há menos disso fica destacada de leve.
    static let freshFor: TimeInterval = 8
}

struct DatasetPanelView: View {
    let controller: DatasetsController

    var body: some View {
        Group {
            if let summary = controller.panelSummary {
                DatasetPanelContent(controller: controller, model: controller.model(for: summary.dataset.id), summary: summary)
                    .id(summary.dataset.id)
            } else {
                VStack(spacing: DS.Space.s2) {
                    Image(systemName: "tablecells").font(.system(size: DS.Space.s6)).foregroundStyle(DS.Color.textQuaternary)
                    Text("No data in this session yet", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                    Text("Tables that subagents collect show up here as rows arrive.", bundle: .module)
                        .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).multilineTextAlignment(.center)
                }
                .padding(DS.Space.s6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .a11y(.rightPanelDataEmpty, kind: "text")
            }
        }
        .background(DS.Color.canvas)
        .a11y(.rightPanelData, kind: "container")
    }
}

private struct DatasetPanelContent: View {
    let controller: DatasetsController
    let model: DatasetViewModel
    let summary: DatasetSummary

    private var columns: [PanelColumn] {
        summary.dataset.columns.enumerated().prefix(DatasetPanelMetrics.maxColumns).map { PanelColumn(index: $0.offset, column: $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let snapshot = model.snapshot {
                numbers(snapshot)
                chart(snapshot)
                table(snapshot)
            } else {
                Spacer(minLength: 0)
            }
        }
        .onAppear { controller.noteVisible(model.id, true) }
        .onDisappear { controller.noteVisible(model.id, false) }
    }

    // MARK: Cabeçalho

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                pickerOrName
                Spacer(minLength: DS.Space.s1)
                DSButton(
                    .datasetOpen, id: .rightPanelDataOpen, "Open table", variant: .outline, size: .xs, symbol: "arrow.up.right",
                    argument: .select("\(summary.dataset.id)|panel"))
            }
            HStack(spacing: DS.Space.s2) {
                CollectionStatus(
                    collecting: controller.isCollecting(summary), computers: model.snapshot?.stats.computers ?? 0,
                    lastRow: model.snapshot?.stats.lastSeen.map { controller.relative($0) })
                if let source = sourceLine {
                    Text(verbatim: source).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.top, DS.Space.s2_5)
        .padding(.bottom, DS.Space.s2)
    }

    @ViewBuilder private var pickerOrName: some View {
        let list = controller.sessionSummaries
        if list.count > 1 {
            DSCombobox(
                id: .rightPanelDataPick, selection: summary.dataset.id,
                entries: list.map { .item(DSMenuItem($0.dataset.id, $0.dataset.name, detail: $0.rowCount.formatted(), detailMono: true)) },
                action: .rightPanelDataPick, height: DSMetrics.fieldHeightComposer - DS.Space.s1)
                .fixedSize()
        } else {
            Text(verbatim: summary.dataset.name).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
        }
    }

    /// "books.toscrape.com · Codex 1, Codex 2": o site e quem está coletando.
    private var sourceLine: String? {
        guard let facets = model.snapshot?.facets else { return nil }
        let hosts = (facets[.source] ?? []).map(\.value).filter { !$0.isEmpty }
        let agents = (facets[.computer] ?? []).map { controller.computerLabel($0.value) ?? $0.value }
        var parts: [String] = []
        if let host = hosts.first { parts.append(hosts.count == 1 ? host : String(localized: "\(hosts.count) sites", bundle: .module)) }
        if !agents.isEmpty { parts.append(agents.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Números

    private func numbers(_ snapshot: DatasetPageSnapshot) -> some View {
        let s = snapshot.stats
        let valid = s.rows == 0 ? 0 : Double(s.rows - s.invalid) / Double(s.rows)
        return HStack(spacing: 0) {
            number(String(localized: "Rows", bundle: .module), s.rows.formatted(),
                   s.recent > 0 ? String(localized: "+\(s.recent.formatted()) in 5 min", bundle: .module) : nil, tone: DS.Color.dataValid)
            number(String(localized: "Rate", bundle: .module), String(localized: "\(snapshot.perMinute)/min", bundle: .module), nil)
            number(String(localized: "Valid", bundle: .module), Self.percent(valid),
                   s.invalid > 0 ? String(localized: "\(s.invalid.formatted()) invalid", bundle: .module) : nil, tone: DS.Color.warning)
            number(String(localized: "Complete", bundle: .module), Self.percent(s.filled),
                   s.weakestColumn.map { String(localized: "\($0.name) low", bundle: .module) }, tone: DS.Color.warning)
        }
        .padding(.vertical, DS.Space.s2)
        .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .a11y(.rightPanelDataStats, kind: "group", value: "\(s.rows)")
    }

    static func percent(_ value: Double) -> String { value >= 1 ? "100%" : value.formatted(.percent.precision(.fractionLength(0))) }

    private func number(_ label: String, _ value: String, _ detail: String?, tone: Color = DS.Color.textTertiary) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(verbatim: label).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary)
            Text(verbatim: value).dsFont(DS.Font.bodyStrong).monospacedDigit().foregroundStyle(DS.Color.textPrimary)
                .contentTransition(.numericText())
            Text(verbatim: detail ?? " ").dsFont(DS.Font.micro).foregroundStyle(tone).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, DS.Space.s3)
    }

    // MARK: Gráfico

    private func chart(_ snapshot: DatasetPageSnapshot) -> some View {
        let values = snapshot.activity.map { (valid: $0.valid, invalid: $0.invalid) }
        let peak = CGFloat(max(values.map { $0.valid + $0.invalid }.max() ?? 0, 1))
        return Canvas { context, size in
            guard !values.isEmpty else { return }
            let gap: CGFloat = 1
            let width = max((size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count), 1)
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * (width + gap)
                let valid = size.height * CGFloat(value.valid) / peak
                let invalid = value.invalid == 0 ? 0 : max(size.height * CGFloat(value.invalid) / peak, 2)
                if valid + invalid == 0 {
                    context.fill(Path(CGRect(x: x, y: size.height - 1, width: width, height: 1)), with: .color(DS.Color.border))
                    continue
                }
                context.fill(Path(CGRect(x: x, y: size.height - valid, width: width, height: valid)), with: .color(DS.Color.dataValid.opacity(0.7)))
                if invalid > 0 {
                    context.fill(Path(CGRect(x: x, y: size.height - valid - invalid, width: width, height: invalid)), with: .color(DS.Color.warning))
                }
            }
        }
        .frame(height: DatasetPanelMetrics.chartHeight)
        .padding(.horizontal, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
        .accessibilityHidden(true)
    }

    // MARK: Tabela

    private func table(_ snapshot: DatasetPageSnapshot) -> some View {
        VStack(spacing: 0) {
            tableHeader
            if snapshot.rows.isEmpty {
                Text("No rows yet.", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.rows.prefix(DatasetPanelMetrics.maxRows)) { row in
                            PanelRow(row: row, columns: columns, datasetID: summary.dataset.id)
                        }
                    }
                }
                footer(snapshot)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: DS.Space.s2) {
            Color.clear.frame(width: DatasetPanelMetrics.stripe)
            ForEach(columns) { entry in
                Text(verbatim: entry.column.name).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                    .frame(width: entry.isFirst ? nil : DatasetPanelMetrics.numberColumn, alignment: entry.isNumeric ? .trailing : .leading)
                    .frame(maxWidth: entry.isFirst ? .infinity : nil, alignment: .leading)
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: DatasetPanelMetrics.headerRow)
        .background(DS.Color.chrome)
        .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func footer(_ snapshot: DatasetPageSnapshot) -> some View {
        let shown = min(snapshot.rows.count, DatasetPanelMetrics.maxRows)
        return Text(verbatim: String(localized: "Latest \(shown) of \(snapshot.stats.rows.formatted()) rows", bundle: .module))
            .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s3)
            .frame(height: DatasetPanelMetrics.headerRow)
            .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }
}

private struct PanelColumn: Identifiable {
    let index: Int
    let column: DatasetColumn
    var id: Int { index }
    var isFirst: Bool { index == .zero }
    var isNumeric: Bool { DatasetMetrics.isNumeric(column.type) }
}

/// Uma linha compacta: faixa de estado, a primeira coluna (texto) e as outras à direita. Linha recém-chegada fica destacada de leve
/// por alguns segundos; o clique abre a tabela inteira.
private struct PanelRow: View {
    let row: DatasetDisplayRow
    let columns: [PanelColumn]
    let datasetID: String
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fresh = context.date.timeIntervalSince(row.row.firstSeen) < DatasetPanelMetrics.freshFor
            ActionButton(.datasetOpen, id: .rightPanelDataRow(row.id), argument: .select("\(datasetID)|panel")) {
                HStack(spacing: DS.Space.s2) {
                    RoundedRectangle(cornerRadius: DatasetPanelMetrics.stripe / 2)
                        .fill(row.row.valid ? DS.Color.dataValid.opacity(0.8) : DS.Color.warning)
                        .frame(width: DatasetPanelMetrics.stripe, height: DS.Space.s3)
                    ForEach(columns) { entry in cell(entry) }
                }
                .padding(.horizontal, DS.Space.s3)
                .frame(height: DatasetPanelMetrics.rowHeight)
                .background(fresh ? DS.Color.dataValid.opacity(0.08) : (hovering ? DS.Color.hoverAgentRow : Color.clear))
                .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
                .contentShape(Rectangle())
                .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.panel), value: fresh)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }

    private func cell(_ entry: PanelColumn) -> some View {
        let text = entry.index < row.cells.count ? row.cells[entry.index] : ""
        let problem = entry.index < row.problems.count ? row.problems[entry.index] : nil
        return Text(verbatim: problem ?? (text.isEmpty ? "–" : GridRowText.short(text)))
            .dsFont(entry.isNumeric || problem != nil ? DS.Font.monoCell : DS.Font.cell)
            .foregroundStyle(problem != nil ? DS.Color.warning : (entry.isFirst ? DS.Color.textPrimary : DS.Color.textSecondary))
            .lineLimit(1).truncationMode(.tail)
            .frame(width: entry.isFirst ? nil : DatasetPanelMetrics.numberColumn, alignment: entry.isNumeric ? .trailing : .leading)
            .frame(maxWidth: entry.isFirst ? .infinity : nil, alignment: .leading)
    }
}
