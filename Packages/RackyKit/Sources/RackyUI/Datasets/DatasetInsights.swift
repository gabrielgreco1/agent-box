import RackyCore
import RackyDesignSystem
import RackyProtocol
import RackyStore
import SwiftUI

// Topo da página de um dataset: estado da coleta, números que respondem "está chegando? está bom? de onde vem?", o gráfico de volume
// com hover, a barra de filtro com os filtros ativos em chips e as facetas da esquerda. Tudo lê o `DatasetPageSnapshot`; os cliques
// passam pelas ações do registro.

enum InsightMetrics {
    static let metricsHeight: CGFloat = 70
    static let metricMinWidth: CGFloat = 148
    static let sparkHeight = DS.Space.s4
    static let sparkWidth: CGFloat = 64
    static let chartHeight: CGFloat = 104
    static let chartBarGap: CGFloat = 2
    static let chartTooltipWidth: CGFloat = 188
    static let barRadius: CGFloat = 1.5
    static let statusDot: CGFloat = 6
    static let queryHeight = DS.Space.s8
    static let chipHeight = DS.Space.s6
    static let facetHeader: CGFloat = 28
    static let check: CGFloat = 14
}

// MARK: Estado da coleta

/// "● Collecting · 2 computers" enquanto algum computador da sessão roda; senão "Idle · last row 4h ago".
struct CollectionStatus: View {
    let collecting: Bool
    let computers: Int
    let lastRow: String?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: DS.Space.s1_5) {
            ZStack {
                if collecting {
                    Circle().fill(DS.Color.dataValid.opacity(0.35))
                        .frame(width: InsightMetrics.statusDot, height: InsightMetrics.statusDot)
                        .scaleEffect(pulse ? 2.2 : 1)
                        .opacity(pulse ? 0 : 1)
                }
                Circle().fill(collecting ? DS.Color.dataValid : DS.Color.textQuaternary)
                    .frame(width: InsightMetrics.statusDot, height: InsightMetrics.statusDot)
            }
            Text(verbatim: text).dsFont(DS.Font.label).foregroundStyle(collecting ? DS.Color.dataValid : DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Space.s2)
        .frame(height: InsightMetrics.chipHeight)
        .background(Capsule().fill(collecting ? DS.Color.dataValid.opacity(0.1) : DS.Color.secondary))
        .fixedSize()
        .onAppear {
            guard collecting, let animation = MotionPolicy.shared.animation(MotionTokens.Easing.standard, MotionTokens.Duration.attention) else { return }
            withAnimation(animation.repeatForever(autoreverses: false)) { pulse = true }
        }
        .a11y(.datasetStatus, kind: "text", label: text)
    }

    private var text: String {
        if collecting {
            return computers == 1
                ? String(localized: "Collecting · 1 computer", bundle: .module)
                : String(localized: "Collecting · \(computers) computers", bundle: .module)
        }
        guard let lastRow else { return String(localized: "Waiting for rows", bundle: .module) }
        return String(localized: "Idle · last row \(lastRow)", bundle: .module)
    }
}

// MARK: Números

/// Uma célula da faixa de números: rótulo, valor grande e uma linha de contexto (que pode ter cor de alerta).
struct MetricCell<Accessory: View>: View {
    let label: String
    let value: String
    let detail: String
    var detailTone: Color = DS.Color.textTertiary
    var help: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s0_5) {
            Text(verbatim: label).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            HStack(alignment: .lastTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: value).dsFont(DS.Font.metric).foregroundStyle(DS.Color.textPrimary)
                    .contentTransition(.numericText())
                    .fixedSize()
                accessory()
            }
            .fixedSize()
            Text(verbatim: detail).dsFont(DS.Font.small).foregroundStyle(detailTone).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(minWidth: InsightMetrics.metricMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
        .help(help ?? "")
        .accessibilityElement(children: .combine)
    }
}

extension MetricCell where Accessory == EmptyView {
    init(label: String, value: String, detail: String, detailTone: Color = DS.Color.textTertiary, help: String? = nil) {
        self.init(label: label, value: value, detail: detail, detailTone: detailTone, help: help) { EmptyView() }
    }
}

/// Mini barras do ritmo (as últimas faixas do gráfico).
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let peak = CGFloat(max(values.max() ?? 0, 1))
            let gap: CGFloat = 1
            let width = max((size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count), 1)
            for (index, value) in values.enumerated() {
                let height = value == 0 ? 1 : max(size.height * CGFloat(value) / peak, 2)
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: size.height - height, width: width, height: height)
                context.fill(Path(rect), with: .color(value == 0 ? DS.Color.borderStrong : DS.Color.dataValid.opacity(0.8)))
            }
        }
        .frame(width: InsightMetrics.sparkWidth, height: InsightMetrics.sparkHeight)
        .accessibilityHidden(true)
    }
}

/// A faixa de números da página: volume, ritmo, qualidade, preenchimento, requisições, origem e duplicatas.
struct MetricsStrip: View {
    let snapshot: DatasetPageSnapshot
    let controller: DatasetsController

    var body: some View {
        let s = snapshot.stats
        // Em área estreita as células do fim somem; volume, ritmo e qualidade ficam sempre.
        ViewThatFits(in: .horizontal) {
            cells(s, count: 7)
            cells(s, count: 5)
            cells(s, count: 3)
        }
        .frame(height: InsightMetrics.metricsHeight)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .a11y(.datasetStats, kind: "group", value: "\(s.rows)")
    }

    private func cells(_ s: DatasetStats, count: Int) -> some View {
        HStack(spacing: 0) {
            MetricCell(label: String(localized: "Rows", bundle: .module), value: s.rows.formatted(), detail: rowsDetail(s),
                       detailTone: s.recent > 0 ? DS.Color.dataValid : DS.Color.textTertiary)
            MetricCell(label: String(localized: "Rate", bundle: .module), value: String(localized: "\(snapshot.perMinute)/min", bundle: .module),
                       detail: peakDetail) {
                Sparkline(values: snapshot.activity.suffix(16).map { $0.valid + $0.invalid })
            }
            MetricCell(label: String(localized: "Valid", bundle: .module), value: percent(validShare(s)),
                       detail: s.invalid == 0 ? String(localized: "No invalid rows", bundle: .module) : String(localized: "\(s.invalid.formatted()) invalid", bundle: .module),
                       detailTone: s.invalid > 0 ? DS.Color.warning : DS.Color.textTertiary,
                       help: String(localized: "Rows that match the column types and required fields.", bundle: .module))
            if count >= 5 {
                MetricCell(label: String(localized: "Complete", bundle: .module), value: percent(s.filled), detail: completeDetail(s),
                           detailTone: (s.weakestColumn?.fill ?? 1) < 0.9 ? DS.Color.warning : DS.Color.textTertiary,
                           help: String(localized: "Share of cells with a value, across every column.", bundle: .module))
                MetricCell(label: String(localized: "Requests", bundle: .module), value: s.requests == 0 ? "–" : s.requests.formatted(), detail: requestsDetail(s),
                           detailTone: s.failedRequests > 0 ? DS.Color.warning : DS.Color.textTertiary,
                           help: String(localized: "Network requests that produced rows, from the computers' request logs.", bundle: .module))
            }
            if count >= 7 {
                MetricCell(label: String(localized: "Sources", bundle: .module), value: sourcesValue(s), detail: sourcesDetail(s))
                MetricCell(label: String(localized: "Duplicates", bundle: .module), value: s.duplicatesMerged.formatted(), detail: duplicatesDetail,
                           help: String(localized: "Rows that arrived again and were merged by the key.", bundle: .module))
            }
        }
    }

    private func percent(_ value: Double) -> String {
        value >= 1 ? "100%" : value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func validShare(_ s: DatasetStats) -> Double { s.rows == 0 ? 0 : Double(s.rows - s.invalid) / Double(s.rows) }

    private func rowsDetail(_ s: DatasetStats) -> String {
        if s.recent > 0 { return String(localized: "+\(s.recent.formatted()) in 5 min", bundle: .module) }
        guard let last = s.lastSeen else { return String(localized: "No rows yet", bundle: .module) }
        return String(localized: "Last row \(controller.relative(last))", bundle: .module)
    }

    /// Pico por minuto entre as faixas do gráfico.
    private var peakDetail: String {
        let counts = snapshot.activity.map { $0.valid + $0.invalid }
        guard (counts.max() ?? 0) > 0 else { return String(localized: "Nothing arrived in this period", bundle: .module) }
        // Faixas menores que 1 min: soma uma janela de 1 min (senão 30 linhas num segundo viram "1.800/min").
        let window = max(Int((60 / snapshot.bucketSeconds).rounded(.up)), 1)
        let perMinute: Int
        if window > 1 {
            perMinute = counts.indices.map { counts[$0..<min($0 + window, counts.count)].reduce(0, +) }.max() ?? 0
        } else {
            perMinute = Int((Double(counts.max() ?? 0) / (snapshot.bucketSeconds / 60)).rounded())
        }
        return String(localized: "Peak \(perMinute.formatted())/min", bundle: .module)
    }

    private func completeDetail(_ s: DatasetStats) -> String {
        guard let weakest = s.weakestColumn else { return String(localized: "Every column filled", bundle: .module) }
        return String(localized: "\(weakest.name) \(percent(weakest.fill)) filled", bundle: .module)
    }

    private func requestsDetail(_ s: DatasetStats) -> String {
        guard s.requests > 0 else { return String(localized: "No network evidence", bundle: .module) }
        var parts: [String] = []
        if let ms = s.averageRequestMs { parts.append(String(localized: "avg \(ms.formatted()) ms", bundle: .module)) }
        parts.append(s.failedRequests == 0 ? String(localized: "none failed", bundle: .module) : String(localized: "\(s.failedRequests) failed", bundle: .module))
        if s.rows >= s.requests * 2 { parts.append(String(localized: "\((Double(s.rows) / Double(s.requests)).formatted(.number.precision(.fractionLength(0...1)))) rows each", bundle: .module)) }
        return parts.joined(separator: " · ")
    }

    private func sourcesValue(_ s: DatasetStats) -> String {
        s.hosts == 1 ? String(localized: "1 site", bundle: .module) : String(localized: "\(s.hosts) sites", bundle: .module)
    }

    private func sourcesDetail(_ s: DatasetStats) -> String {
        let hosts = (snapshot.facets[.source] ?? []).map(\.value).filter { !$0.isEmpty }
        let computers = s.computers == 1 ? String(localized: "1 computer", bundle: .module) : String(localized: "\(s.computers) computers", bundle: .module)
        guard let first = hosts.first else { return computers }
        return hosts.count == 1 ? "\(first) · \(computers)" : computers
    }

    private var duplicatesDetail: String {
        let key = snapshot.summary.dataset.key
        return key.isEmpty ? String(localized: "No key: every row is kept", bundle: .module) : String(localized: "Key: \(key.joined(separator: ", "))", bundle: .module)
    }
}

// MARK: Gráfico

/// Linhas novas no período, verde válidas e âmbar inválidas. O hover destaca a barra e mostra a faixa de horário com as contagens;
/// as barras crescem ao aparecer e quando chegam linhas.
struct ActivityChart: View {
    let snapshot: DatasetPageSnapshot
    let controller: DatasetsController
    @State private var hover: Int?
    /// Sem movimento (preferência do sistema, testes) as barras já nascem no tamanho certo.
    @State private var grown = MotionPolicy.shared.animation(MotionTokens.Easing.expoOut, MotionTokens.Duration.ripple) == nil

    private var buckets: [DatasetActivityBucket] { snapshot.activity }
    private var peak: Int { max(buckets.map { $0.valid + $0.invalid }.max() ?? 0, 1) }
    private var total: Int { buckets.reduce(0) { $0 + $1.valid + $1.invalid } }
    /// Com filtro, o gráfico mostra só o que casa.
    private var filtered: Bool { snapshot.matching < snapshot.stats.rows }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            HStack(spacing: DS.Space.s3) {
                Text("New rows", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                Text(verbatim: filtered
                    ? String(localized: "\(total.formatted()) matching in this period", bundle: .module)
                    : String(localized: "\(total.formatted()) in this period", bundle: .module))
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                Spacer(minLength: 0)
                legend(DS.Color.dataValid.opacity(0.8), String(localized: "Valid", bundle: .module))
                legend(DS.Color.warning, String(localized: "Invalid", bundle: .module))
            }
            HStack(alignment: .top, spacing: DS.Space.s2) {
                bars
                VStack(alignment: .trailing) {
                    Text(verbatim: peak.formatted()).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textQuaternary)
                    Spacer(minLength: 0)
                    Text(verbatim: "0").dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textQuaternary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            axis
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2_5)
        .frame(height: InsightMetrics.chartHeight + DS.Space.s10)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .onAppear {
            guard let animation = MotionPolicy.shared.animation(MotionTokens.Easing.expoOut, MotionTokens.Duration.ripple) else { grown = true; return }
            withAnimation(animation) { grown = true }
        }
        .a11y(.datasetChart, kind: "chart", value: "\(total)")
    }

    private var bars: some View {
        GeometryReader { geo in
            let count = max(buckets.count, 1)
            let gap = InsightMetrics.chartBarGap
            let width = max((geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 1)
            ZStack(alignment: .bottomLeading) {
                // Linha do pico e a base.
                VStack(spacing: 0) {
                    DS.Color.border.frame(height: ComputersMetrics.separator)
                    Spacer(minLength: 0)
                    DS.Color.borderStrong.frame(height: ComputersMetrics.separator)
                }
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                        bar(bucket, index: index, height: geo.size.height)
                            .frame(width: width)
                    }
                }
                if let hover, hover < buckets.count {
                    tooltip(buckets[hover])
                        .offset(x: tooltipX(index: hover, barWidth: width, gap: gap, total: geo.size.width))
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let index = min(max(Int(point.x / (width + gap)), 0), buckets.count - 1)
                    if hover != index { hover = index }
                case .ended: hover = nil
                }
            }
        }
        .frame(height: InsightMetrics.chartHeight - DS.Space.s6)
    }

    private func bar(_ bucket: DatasetActivityBucket, index: Int, height: CGFloat) -> some View {
        let scale = grown ? 1 : 0
        let valid = height * CGFloat(bucket.valid) / CGFloat(peak) * CGFloat(scale)
        let invalid = bucket.invalid == 0 ? 0 : max(height * CGFloat(bucket.invalid) / CGFloat(peak), 2) * CGFloat(scale)
        let dimmed = hover != nil && hover != index
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            if invalid > 0 {
                UnevenRoundedRectangle(topLeadingRadius: InsightMetrics.barRadius, topTrailingRadius: InsightMetrics.barRadius)
                    .fill(DS.Color.warning).frame(height: invalid)
            }
            if valid > 0 {
                UnevenRoundedRectangle(
                    topLeadingRadius: invalid > 0 ? 0 : InsightMetrics.barRadius, topTrailingRadius: invalid > 0 ? 0 : InsightMetrics.barRadius)
                    .fill(DS.Color.dataValid.opacity(hover == index ? 1 : 0.75)).frame(height: valid)
            }
        }
        .frame(maxHeight: .infinity)
        .background(alignment: .bottom) {
            if hover == index { DS.Color.hoverAgentRow.frame(maxHeight: .infinity) }
        }
        .opacity(dimmed ? 0.55 : 1)
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.expoOut, MotionTokens.Duration.medium), value: bucket.valid + bucket.invalid)
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.hover), value: hover)
    }

    private func tooltipX(index: Int, barWidth: CGFloat, gap: CGFloat, total: CGFloat) -> CGFloat {
        let center = CGFloat(index) * (barWidth + gap) + barWidth / 2
        return min(max(center - InsightMetrics.chartTooltipWidth / 2, 0), max(total - InsightMetrics.chartTooltipWidth, 0))
    }

    private func tooltip(_ bucket: DatasetActivityBucket) -> some View {
        let end = bucket.start.addingTimeInterval(snapshot.bucketSeconds)
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: "\(controller.clock(bucket.start, seconds: snapshot.bucketSeconds < 60)) – \(controller.clock(end, seconds: snapshot.bucketSeconds < 60))")
                .dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
            tooltipLine(DS.Color.dataValid, String(localized: "Valid", bundle: .module), bucket.valid)
            tooltipLine(DS.Color.warning, String(localized: "Invalid", bundle: .module), bucket.invalid)
        }
        .padding(DS.Space.s2)
        .frame(width: InsightMetrics.chartTooltipWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.panel))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.borderStrong))
        .shadow(color: .black.opacity(0.35), radius: DS.Space.s2, y: DS.Space.s1)
    }

    private func tooltipLine(_ color: Color, _ title: String, _ value: Int) -> some View {
        HStack(spacing: DS.Space.s1_5) {
            RoundedRectangle(cornerRadius: DS.Radius.xs).fill(color).frame(width: DS.Space.s2, height: DS.Space.s2)
            Text(verbatim: title).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value.formatted()).dsFont(DS.Font.monoCell).foregroundStyle(value == 0 ? DS.Color.textTertiary : DS.Color.textPrimary)
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: DS.Space.s1) {
            RoundedRectangle(cornerRadius: DS.Radius.xs).fill(color).frame(width: DS.Space.s2, height: DS.Space.s2)
            Text(verbatim: title).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
        }
    }

    /// Cinco marcas de hora de ponta a ponta; a última é `now` quando o gráfico acaba agora.
    private var axis: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                Text(verbatim: label(index)).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textQuaternary)
                if index < 4 { Spacer(minLength: 0) }
            }
        }
        .padding(.trailing, DS.Space.s6)
    }

    private func label(_ index: Int) -> String {
        guard let start = snapshot.activityStart, let end = snapshot.activityEnd else { return "" }
        if index == 4, controller.now().timeIntervalSince(end) < 1 { return String(localized: "now", bundle: .module) }
        return controller.clock(start.addingTimeInterval(end.timeIntervalSince(start) * Double(index) / 4), seconds: false)
    }
}

// MARK: Consulta

/// Busca com lupa, os filtros das facetas em chips (cada um some com o x) e o período.
struct DatasetQueryBar: View {
    let snapshot: DatasetPageSnapshot
    let controller: DatasetsController
    @Bindable var model: DatasetViewModel
    let rangeMenu: AnyView
    @FocusState private var focused: Bool
    @Environment(\.actionRegistry) private var registry

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "magnifyingglass").font(.system(size: DS.Space.s3)).foregroundStyle(DS.Color.textTertiary)
                ZStack(alignment: .leading) {
                    if model.search.isEmpty {
                        Text(verbatim: placeholder).dsFont(DS.Font.inputCompact).foregroundStyle(DS.Color.textQuaternary).lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $model.search)
                        .textFieldStyle(.plain)
                        .dsFont(DS.Font.inputCompact)
                        .foregroundStyle(DS.Color.textPrimary)
                        .focused($focused)
                        .onChange(of: model.search) { _, new in
                            guard let registry else { return }
                            Task { _ = try? await registry.perform(.datasetSearch, .set(new)) }
                        }
                        .a11y(.datasetSearch, kind: "textfield", value: model.search, action: .datasetSearch)
                }
                if !model.search.isEmpty {
                    ActionButton(.datasetSearch, id: .datasetSearchClear, argument: .set(""), tooltip: String(localized: "Clear", bundle: .module)) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: DS.Space.s3)).foregroundStyle(DS.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.s2_5)
            .frame(height: InsightMetrics.queryHeight)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Color.chrome))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .strokeBorder(focused ? DS.Color.textTertiary : DS.Color.borderStrong, lineWidth: ComputersMetrics.separator))
            .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.hover), value: focused)
            rangeMenu
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2_5)
        .padding(.bottom, chips.isEmpty ? DS.Space.s2_5 : DS.Space.s1_5)
        .overlay(alignment: .bottom) { if chips.isEmpty { DS.Color.border.frame(height: ComputersMetrics.separator) } }
        if !chips.isEmpty { chipRow }
    }

    /// Exemplo com as colunas de verdade do dataset (`price:>20 title:love`).
    private var placeholder: String {
        let columns = snapshot.summary.dataset.columns
        let numeric = columns.first { $0.type == .integer || $0.type == .number }
        let text = columns.first { $0.type == .string }
        var example: [String] = []
        if let numeric { example.append("\(numeric.name):>10") }
        if let text { example.append("\(text.name):love") }
        guard !example.isEmpty else { return String(localized: "Search rows", bundle: .module) }
        return String(localized: "Search rows, or filter by column: \(example.joined(separator: " "))", bundle: .module)
    }

    struct Chip: Identifiable {
        var id: String
        var title: String
        var value: String
        var clear: String
    }

    private var chips: [Chip] {
        var out: [Chip] = []
        for facet in DatasetFacet.allCases where facet != .error {
            guard let excluded = model.excluded[facet], !excluded.isEmpty else { continue }
            let all = (snapshot.facets[facet] ?? []).map(\.value)
            let kept = all.filter { !excluded.contains($0) }
            let label = { (value: String) in FacetsPanel.label(facet, value, controller: controller) }
            let value = kept.count == 1 && all.count > 2
                ? label(kept[0])
                : String(localized: "not \(excluded.sorted().map(label).joined(separator: ", "))", bundle: .module)
            out.append(Chip(id: facet.rawValue, title: FacetsPanel.title(facet), value: value, clear: "\(facet.rawValue):*"))
        }
        if !model.errorKinds.isEmpty {
            out.append(Chip(id: "error", title: FacetsPanel.title(.error), value: model.errorKinds.sorted().joined(separator: ", "), clear: "error:*"))
        }
        return out
    }

    private var chipRow: some View {
        HStack(spacing: DS.Space.s1_5) {
            ForEach(chips) { chip in
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: chip.title).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                    Text(verbatim: chip.value).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    ActionButton(.datasetFacet, id: .datasetChipClear(chip.id), argument: .select(chip.clear), tooltip: String(localized: "Remove filter", bundle: .module)) {
                        Image(systemName: "xmark").font(.system(size: DS.Space.s2, weight: .semibold)).foregroundStyle(DS.Color.textTertiary)
                            .frame(width: DS.Space.s4, height: DS.Space.s4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, DS.Space.s2)
                .padding(.trailing, DS.Space.s0_5)
                .frame(height: InsightMetrics.chipHeight)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.secondary))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.border))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if chips.count > 1 {
                ActionButton(.datasetFacetsReset, id: .datasetFacetsReset, argument: .press) {
                    Text("Clear all", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.standard, MotionTokens.Duration.fast), value: chips.map(\.id))
    }
}

// MARK: Facetas

/// Caixa de seleção: vazia = fora; marcada = verde com o visto.
struct CheckSquare: View {
    let on: Bool
    var tint: Color = DS.Color.dataValid

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xs + 1)
            .fill(on ? tint : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xs + 1).strokeBorder(on ? tint : DS.Color.borderStrong, lineWidth: ComputersMetrics.separator))
            .overlay {
                if on {
                    Image(systemName: "checkmark").font(.system(size: DS.Space.s2, weight: .bold)).foregroundStyle(DS.Color.canvas)
                }
            }
            .frame(width: InsightMetrics.check, height: InsightMetrics.check)
    }
}

/// Coluna da esquerda, no jeito do Datadog: cada grupo recolhe; cada valor tem a caixa, a barra da proporção atrás e a contagem; no
/// hover a contagem vira "only" (só esse valor). Erro funciona ao contrário: marcar filtra.
struct FacetsPanel: View {
    let snapshot: DatasetPageSnapshot
    let controller: DatasetsController
    let model: DatasetViewModel
    @State private var collapsed: Set<DatasetFacet> = []
    @State private var hovered: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(DatasetFacet.allCases, id: \.self) { facet in
                    let values = snapshot.facets[facet] ?? []
                    if !values.isEmpty { group(facet, values) }
                }
            }
            .padding(.horizontal, DS.Space.s2)
            .padding(.vertical, DS.Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: DatasetMetrics.facetWidth)
        .background(DS.Color.chrome)
        .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
    }

    private func group(_ facet: DatasetFacet, _ values: [DatasetFacetCount]) -> some View {
        let open = !collapsed.contains(facet)
        let filtered = facet == .error ? !model.errorKinds.isEmpty : !(model.excluded[facet]?.isEmpty ?? true)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s1_5) {
                // lint-ui: allow buttons recolhe o grupo (estado local da coluna, sem ação de registro)
                Button {
                    withAnimation(MotionPolicy.shared.animation(MotionTokens.Easing.standard, MotionTokens.Duration.disclosure)) {
                        if open { collapsed.insert(facet) } else { collapsed.remove(facet) }
                    }
                } label: {
                    HStack(spacing: DS.Space.s1_5) {
                        Image(systemName: "chevron.right").font(.system(size: DS.Space.s2, weight: .semibold))
                            .rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(DS.Color.textTertiary)
                        Text(verbatim: Self.title(facet)).dsFont(DS.Font.sectionLabel).foregroundStyle(DS.Color.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if filtered {
                    ActionButton(.datasetFacet, id: .datasetFacetReset(facet.rawValue), argument: .select("\(facet.rawValue):*")) {
                        Text("Reset", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.dataKey)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.s2)
            .frame(height: InsightMetrics.facetHeader)
            if open {
                ForEach(values) { value in row(facet, value) }
                    .transition(.opacity)
            }
        }
    }

    private func row(_ facet: DatasetFacet, _ value: DatasetFacetCount) -> some View {
        let on = model.isChecked(facet, value.value)
        let key = "\(facet.rawValue):\(value.value)"
        let isHovered = hovered == key
        return HStack(spacing: 0) {
            ActionButton(.datasetFacet, id: .datasetFacet(facet.rawValue, value.value), argument: .select(key)) {
                HStack(spacing: DS.Space.s2) {
                    CheckSquare(on: on)
                    if facet == .status {
                        Circle().fill(value.value == "valid" ? DS.Color.dataValid : DS.Color.warning)
                            .frame(width: DatasetMetrics.facetDot, height: DatasetMetrics.facetDot)
                    }
                    Text(verbatim: Self.label(facet, value.value, controller: controller)).dsFont(DS.Font.cell)
                        .foregroundStyle(on || facet == .error ? DS.Color.textPrimary : DS.Color.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(facet == .computer ? value.value : "")
                    Spacer(minLength: DS.Space.s1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isHovered, facet != .error, (snapshot.facets[facet]?.count ?? 0) > 1 {
                ActionButton(.datasetFacet, id: .datasetFacetOnly(facet.rawValue, value.value), argument: .select("\(facet.rawValue):=\(value.value)")) {
                    Text("only", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.dataKey)
                }
                .buttonStyle(.plain)
            } else {
                Text(verbatim: value.count.formatted()).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.s2)
        .frame(height: DatasetMetrics.facetRow)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(isHovered ? DS.Color.hoverAgentRow : Color.clear))
        .onHover { hovered = $0 ? key : (hovered == key ? nil : hovered) }
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

    /// O computador de um worker leva o nome do agente ("Codex 1 · books-p13-14").
    static func label(_ facet: DatasetFacet, _ value: String, controller: DatasetsController) -> String {
        switch (facet, value) {
        case (.status, "valid"): String(localized: "Valid", bundle: .module)
        case (.status, "invalid"): String(localized: "Invalid", bundle: .module)
        case (.evidence, "observed"): String(localized: "Seen in network", bundle: .module)
        case (.evidence, "reported"): String(localized: "Agent-reported", bundle: .module)
        case (.evidence, "none"): String(localized: "No source", bundle: .module)
        case (.computer, _): controller.computerLabel(value) ?? value
        case (_, ""): String(localized: "None", bundle: .module)
        default: value
        }
    }
}
