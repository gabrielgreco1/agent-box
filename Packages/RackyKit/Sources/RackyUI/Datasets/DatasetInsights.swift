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
    static let chartHeight: CGFloat = 96
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

// MARK: Gráfico

/// Linhas novas no período, verde válidas e âmbar inválidas, com eixo de valores, grade leve e o período à direita do título. O hover
/// destaca a faixa e mostra horário e contagens; as barras crescem ao aparecer e quando chegam linhas.
struct ActivityChart: View {
    let snapshot: DatasetPageSnapshot
    let controller: DatasetsController
    let rangeMenu: AnyView
    @State private var hover: Int?
    /// Sem movimento (preferência do sistema, testes) as barras já nascem no tamanho certo.
    @State private var grown = MotionPolicy.shared.animation(MotionTokens.Easing.expoOut, MotionTokens.Duration.ripple) == nil

    private var buckets: [DatasetActivityBucket] { snapshot.activity }
    private var total: Int { buckets.reduce(0) { $0 + $1.valid + $1.invalid } }
    /// Com filtro, o gráfico mostra só o que casa.
    private var filtered: Bool { snapshot.matching < snapshot.stats.rows }
    /// Topo do eixo: o número redondo logo acima do pico.
    private var axisTop: Int {
        let peak = max(buckets.map { $0.valid + $0.invalid }.max() ?? 0, 1)
        var unit = 1
        while unit * 10 <= peak { unit *= 10 }
        // Passos de 2 em 2 marcas: 2, 3, 4, 5, 6, 8, 10 × 10ⁿ (o meio também fica redondo).
        for step in [2, 3, 4, 5, 6, 8, 10] where unit * step >= peak { return unit * step }
        return peak
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Text("Rows over time", bundle: .module).dsFont(DS.Font.sectionLabel).foregroundStyle(DS.Color.textPrimary)
                Text(verbatim: filtered
                    ? String(localized: "\(total.formatted()) matching", bundle: .module)
                    : String(localized: "\(total.formatted()) rows", bundle: .module))
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                Spacer(minLength: DS.Space.s2)
                legend(DS.Color.dataValid, String(localized: "Valid", bundle: .module))
                legend(DS.Color.warning, String(localized: "Invalid", bundle: .module))
                rangeMenu.padding(.leading, DS.Space.s2)
            }
            HStack(alignment: .top, spacing: DS.Space.s2) {
                yAxis
                VStack(spacing: DS.Space.s1) {
                    plot
                    xAxis
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .onAppear {
            guard let animation = MotionPolicy.shared.animation(MotionTokens.Easing.expoOut, MotionTokens.Duration.ripple) else { grown = true; return }
            withAnimation(animation) { grown = true }
        }
        .a11y(.datasetChart, kind: "chart", value: "\(total)")
    }

    private var yAxis: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: axisTop.formatted()).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
            Spacer(minLength: 0)
            Text(verbatim: (axisTop / 2).formatted()).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
            Spacer(minLength: 0)
            Text(verbatim: "0").dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
        }
        .frame(height: InsightMetrics.chartHeight)
        .frame(minWidth: DS.Space.s6, alignment: .trailing)
    }

    private var plot: some View {
        GeometryReader { geo in
            let count = max(buckets.count, 1)
            let gap = InsightMetrics.chartBarGap
            let width = max((geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 1)
            ZStack(alignment: .topLeading) {
                // Grade: topo, meio (tracejadas) e a base.
                VStack(spacing: 0) {
                    gridLine(dashed: true)
                    Spacer(minLength: 0)
                    gridLine(dashed: true)
                    Spacer(minLength: 0)
                    DS.Color.borderStrong.frame(height: ComputersMetrics.separator)
                }
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                        bar(bucket, index: index, height: geo.size.height).frame(width: width)
                    }
                }
                if let hover, hover < buckets.count {
                    tooltip(buckets[hover])
                        .offset(x: tooltipX(index: hover, barWidth: width, gap: gap, total: geo.size.width), y: DS.Space.s1)
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
        .frame(height: InsightMetrics.chartHeight)
    }

    private func gridLine(dashed: Bool) -> some View {
        Line().stroke(DS.Color.border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 3] : []))
            .frame(height: ComputersMetrics.separator)
    }

    private func bar(_ bucket: DatasetActivityBucket, index: Int, height: CGFloat) -> some View {
        let scale: CGFloat = grown ? 1 : 0
        let top = CGFloat(axisTop)
        let valid = height * CGFloat(bucket.valid) / top * scale
        let invalid = bucket.invalid == 0 ? 0 : max(height * CGFloat(bucket.invalid) / top, 2) * scale
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
                    .fill(DS.Color.dataValid.opacity(hover == index ? 1 : 0.8)).frame(height: valid)
            }
        }
        .frame(maxHeight: .infinity)
        .background {
            if hover == index { RoundedRectangle(cornerRadius: InsightMetrics.barRadius).fill(DS.Color.textPrimary.opacity(0.06)) }
        }
        .opacity(dimmed ? 0.6 : 1)
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.expoOut, MotionTokens.Duration.medium), value: bucket.valid + bucket.invalid)
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.hover), value: hover)
    }

    private func tooltipX(index: Int, barWidth: CGFloat, gap: CGFloat, total: CGFloat) -> CGFloat {
        // Ao lado da barra (direita; perto da borda, esquerda), para não cobrir o que está sendo lido.
        let right = CGFloat(index + 1) * (barWidth + gap) + DS.Space.s1
        if right + InsightMetrics.chartTooltipWidth <= total { return right }
        return max(CGFloat(index) * (barWidth + gap) - InsightMetrics.chartTooltipWidth - DS.Space.s1, 0)
    }

    private func tooltip(_ bucket: DatasetActivityBucket) -> some View {
        let end = bucket.start.addingTimeInterval(snapshot.bucketSeconds)
        let seconds = snapshot.bucketSeconds < 60
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: "\(controller.clock(bucket.start, seconds: seconds)) – \(controller.clock(end, seconds: seconds))")
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
    private var xAxis: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                Text(verbatim: label(index)).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary)
                if index < 4 { Spacer(minLength: 0) }
            }
        }
    }

    private func label(_ index: Int) -> String {
        guard let start = snapshot.activityStart, let end = snapshot.activityEnd else { return "" }
        if index == 4, controller.now().timeIntervalSince(end) < 1 { return String(localized: "now", bundle: .module) }
        return controller.clock(start.addingTimeInterval(end.timeIntervalSince(start) * Double(index) / 4), seconds: false)
    }
}

/// Linha horizontal de ponta a ponta (grade do gráfico).
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: Consulta

/// Busca com lupa, os filtros das facetas em chips (cada um some com o x) e o período.
struct DatasetQueryBar: View {
    let snapshot: DatasetPageSnapshot
    let controller: DatasetsController
    @Bindable var model: DatasetViewModel
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
