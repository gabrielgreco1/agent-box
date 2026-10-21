import RackyCore
import RackyDesignSystem
import RackyProtocol
import RackyStore
import SwiftUI

/// Módulo Data do painel direito: a tabela ao vivo do dataset da sessão aberta, compacta, no lugar dos Insights. Abre sozinho quando
/// os dados começam a entrar; "Open" leva para a tabela inteira numa tab da sessão.
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

    func makeHeaderAccessory(context: RightPanelModuleContext) -> AnyView? {
        guard let summary = datasets.panelSummary, datasets.isCollecting(summary), !context.isCompact else { return nil }
        return AnyView(
            HStack(spacing: DS.Space.s1) {
                Circle().fill(DS.Color.dataValid).frame(width: DatasetPanelMetrics.dot, height: DatasetPanelMetrics.dot)
                Text("Collecting", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.dataValid)
            })
    }
}

enum DatasetPanelMetrics {
    static let dot: CGFloat = 6
    static let stripe: CGFloat = 2
    static let rowHeight = DS.Space.s6 + DS.Space.s1
    static let maxColumns = 3
    static let maxRows = 50
}

struct DatasetPanelView: View {
    let controller: DatasetsController

    var body: some View {
        Group {
            if let summary = controller.panelSummary {
                DatasetPanelTable(controller: controller, model: controller.model(for: summary.dataset.id), summary: summary)
                    .id(summary.dataset.id)
            } else {
                VStack(spacing: DS.Space.s1_5) {
                    Image(systemName: "tablecells").font(.system(size: DS.Space.s4)).foregroundStyle(DS.Color.textTertiary)
                    Text("No data in this session yet", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
                    Text("Tables that subagents collect show up here.", bundle: .module)
                        .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).multilineTextAlignment(.center)
                }
                .padding(DS.Space.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .a11y(.rightPanelDataEmpty, kind: "text")
            }
        }
        .a11y(.rightPanelData, kind: "container")
    }
}

/// A tabela compacta: nome (com troca entre datasets da sessão), números, as primeiras colunas e as linhas mais novas.
private struct DatasetPanelTable: View {
    let controller: DatasetsController
    let model: DatasetViewModel
    let summary: DatasetSummary

    private var columns: [DatasetColumn] { Array(summary.dataset.columns.prefix(DatasetPanelMetrics.maxColumns)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DS.Color.border).frame(height: ComputersMetrics.separator)
            if let snapshot = model.snapshot, !snapshot.rows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.rows.prefix(DatasetPanelMetrics.maxRows)) { row in rowView(row) }
                    }
                }
            } else {
                Text("No rows yet.", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { controller.noteVisible(model.id, true) }
        .onDisappear { controller.noteVisible(model.id, false) }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: .zero) {
                pickerOrName
                let stats = model.snapshot?.stats
                Text(verbatim: statsLine(stats))
                    .dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s1)
            DSButton(.datasetOpen, id: .rightPanelDataOpen, "Open", variant: .outline, size: .xs, argument: .select(summary.dataset.id))
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
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

    private func statsLine(_ stats: DatasetStats?) -> String {
        let rows = stats?.rows ?? summary.rowCount
        var parts = [String(localized: "\(rows.formatted()) rows", bundle: .module)]
        let invalid = stats?.invalid ?? summary.invalidCount
        if invalid > 0 { parts.append(String(localized: "\(invalid.formatted()) invalid", bundle: .module)) }
        if let perMinute = model.snapshot?.perMinute, perMinute > 0 { parts.append(String(localized: "\(perMinute)/min", bundle: .module)) }
        return parts.joined(separator: " · ")
    }

    private func rowView(_ row: DatasetDisplayRow) -> some View {
        HStack(spacing: DS.Space.s2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(row.row.valid ? DS.Color.dataValid.opacity(0.8) : DS.Color.warning)
                .frame(width: DatasetPanelMetrics.stripe, height: DS.Space.s3)
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                let all = summary.dataset.columns
                let i = all.firstIndex { $0.name == column.name } ?? index
                let text = i < row.cells.count ? row.cells[i] : ""
                let problem = i < row.problems.count ? row.problems[i] : nil
                let numeric = column.type == .integer || column.type == .number
                Text(verbatim: problem ?? (text.isEmpty ? "–" : GridRowText.short(text)))
                    .dsFont(numeric || problem != nil ? DS.Font.monoMicro : DS.Font.small)
                    .foregroundStyle(problem != nil ? DS.Color.warning : (index == .zero ? DS.Color.textPrimary : DS.Color.textSecondary))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: index == .zero ? .infinity : nil, alignment: numeric ? .trailing : .leading)
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: DatasetPanelMetrics.rowHeight)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }
}
