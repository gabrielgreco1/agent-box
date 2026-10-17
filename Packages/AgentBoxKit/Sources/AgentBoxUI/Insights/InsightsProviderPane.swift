import AgentBoxCore
import AgentBoxDesignSystem
import SwiftUI

/// Bloco com título (12/500), hairline acima e conteúdo. Sem card: o painel já é a superfície.
struct InsightsSection<Content: View>: View {
    let title: LocalizedStringKey
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack {
                Text(title, bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                Spacer(minLength: DS.Space.s2)
                if let trailing { Text(verbatim: trailing).dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textTertiary) }
            }
            content
        }
        .padding(.vertical, DS.Space.s3)
        .overlay(alignment: .top) { Rectangle().fill(DS.Color.border).frame(height: DSMetrics.hairline) }
    }
}

/// Rótulo + valor numérico alinhados (valor em dígitos tabulares).
struct InsightsStat: View {
    let label: LocalizedStringKey
    let value: String
    var emphasis = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(label, bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
            Spacer(minLength: DS.Space.s1)
            Text(verbatim: value).dsFont(emphasis ? DS.Font.bodyStrong : DS.Font.body).monospacedDigit()
                .foregroundStyle(DS.Color.textPrimary).lineLimit(1)
        }
    }
}

/// Aba de um provedor (Claude ou Codex): janelas de limite, hoje, tendência, hora do dia, modelos e sessões.
struct InsightsProviderPane: View {
    let summary: ProviderSummary
    let now: Date
    let compact: Bool
    var scanning = false

    var body: some View {
        if !summary.hasData {
            DSEmptyState(summary.provider == .claude
                ? String(localized: "No Claude usage found yet.", bundle: .module)
                : String(localized: "No Codex usage found yet.", bundle: .module))
        } else if compact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: Cheio

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: .zero) {
            header
            windowsSection
            InsightsSection(title: "Today", trailing: nil) { todayBlock }
            InsightsSection(title: "Last 7 days", trailing: InsightsFormat.tokens(summary.week.fresh) + " tokens · " + InsightsFormat.cost(summary.weekCostUSD)) {
                WeekSparkline(days: summary.dailyWeek)
            }
            InsightsSection(title: "By hour of day", trailing: nil) {
                HourHeatmap(values: summary.hourOfDay, currentHour: Calendar.current.component(.hour, from: now))
            }
            if !summary.topModels.isEmpty {
                InsightsSection(title: "Models", trailing: nil) { modelRows }
            }
            if !summary.topSessions.isEmpty {
                InsightsSection(title: "Sessions", trailing: nil) { sessionRows }
            }
            if !summary.unpricedModels.isEmpty {
                Text(verbatim: "Cost estimate leaves out \(summary.unpricedModels.count) model\(summary.unpricedModels.count == 1 ? "" : "s") without a price.")
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                    .padding(.top, DS.Space.s1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s2) {
            DSAgentLogo(summary.provider.agentKind, size: DS.Space.s4)
            Text(verbatim: summary.provider == .claude ? "Claude" : "Codex").dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary)
            if let plan = InsightsFormat.plan(summary.plan?.plan) { DSBadge(plan) }
            Spacer(minLength: .zero)
            if scanning { DSSpinner(size: DS.Space.s3, delayed: true) }
            if let p = summary.plan, !p.loggedIn { DSBadge(String(localized: "Signed out", bundle: .module), variant: .warning) }
        }
        .padding(.bottom, DS.Space.s3)
    }

    private var windowsSection: some View {
        InsightsSection(title: "Usage limits", trailing: nil) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                HStack(alignment: .center, spacing: DS.Space.s4) {
                    RingMeter(fraction: summary.fiveHour?.usedFraction, elapsed: elapsed(summary.fiveHour, length: UsageAggregator.blockLength),
                              estimated: summary.fiveHour?.source == .estimated, caption: "5h")
                    VStack(spacing: DS.Space.s1_5) {
                        InsightsStat(label: "Resets in", value: resetText(summary.fiveHour), emphasis: true)
                        InsightsStat(label: "Cost", value: InsightsFormat.cost(summary.fiveHour?.costUSD ?? 0))
                        InsightsStat(label: "Tokens", value: InsightsFormat.tokens(summary.fiveHour?.counts.fresh ?? 0))
                        InsightsStat(label: "Messages", value: "\(summary.fiveHour?.messages ?? 0)")
                    }
                }
                weekBlock
                if summary.fiveHour?.source == .estimated || summary.sevenDay?.source == .estimated {
                    Text("Estimated against your busiest earlier window. Connect the status line for exact limits.")
                        .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
    }

    private var weekBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            HStack(alignment: .firstTextBaseline) {
                Text("7-day window").dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
                Spacer(minLength: DS.Space.s1)
                if let f = summary.sevenDay?.usedFraction {
                    AnimatedNumber(value: f * 100) { "\(Int($0.rounded()))%" }.dsFont(DS.Font.bodyStrong).foregroundStyle(InsightsTone.color(for: f))
                } else {
                    Text(verbatim: "–").dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textTertiary)
                }
            }
            TickBar(fraction: summary.sevenDay?.usedFraction, elapsed: elapsed(summary.sevenDay, length: UsageAggregator.weekLength),
                    estimated: summary.sevenDay?.source == .estimated)
            HStack {
                Text(verbatim: InsightsFormat.cost(summary.sevenDay?.costUSD ?? 0) + " · " + InsightsFormat.tokens(summary.sevenDay?.counts.fresh ?? 0) + " tokens")
                    .dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textTertiary)
                Spacer(minLength: DS.Space.s1)
                if let r = summary.sevenDay?.resetsAt {
                    Text(verbatim: "resets in " + InsightsFormat.duration(r.timeIntervalSince(now))).dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var todayBlock: some View {
        let t = summary.today
        let reads = Double(t.cacheRead)
        let denominator = reads + Double(t.input + t.cacheWrite)
        return VStack(spacing: DS.Space.s1_5) {
            HStack(alignment: .firstTextBaseline) {
                AnimatedNumber(value: summary.todayCostUSD) { InsightsFormat.cost($0) }
                    .dsFont(DS.Font.pageTitle).foregroundStyle(DS.Color.textPrimary)
                Spacer(minLength: DS.Space.s1)
                AnimatedNumber(value: Double(t.fresh)) { InsightsFormat.tokens(Int($0)) }
                    .dsFont(DS.Font.control).foregroundStyle(DS.Color.textSecondary)
                Text(verbatim: "tokens").dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            }
            InsightsStat(label: "Output", value: InsightsFormat.tokens(t.output))
            InsightsStat(label: "Cache hit", value: denominator > 0 ? InsightsFormat.percent(reads / denominator) : "–")
        }
    }

    private var modelRows: some View {
        VStack(spacing: DS.Space.s2) {
            ForEach(summary.topModels) { m in
                VStack(spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: InsightsFormat.modelName(m.model)).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textPrimary).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: DS.Space.s1)
                        Text(verbatim: InsightsFormat.percent(m.share)).dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textSecondary)
                        Text(verbatim: InsightsFormat.cost(m.costUSD)).dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textPrimary)
                            .frame(minWidth: DS.Space.s10, alignment: .trailing)
                    }
                    ShareBar(fraction: m.share)
                }
            }
        }
    }

    private var sessionRows: some View {
        let top = max(summary.topSessions.first?.costUSD ?? 0, 0.0001)
        return VStack(spacing: DS.Space.s2) {
            ForEach(summary.topSessions) { s in
                VStack(spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s1_5) {
                        Text(verbatim: s.label ?? "Session " + String(s.session.prefix(6))).dsFont(DS.Font.small).foregroundStyle(DS.Color.textPrimary).lineLimit(1).truncationMode(.middle)
                        if s.sidechainMessages > 0 { DSBadge("+\(s.sidechainMessages) sub", variant: .mono) }
                        Spacer(minLength: DS.Space.s1)
                        Text(verbatim: InsightsFormat.tokens(s.counts.fresh)).dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textSecondary)
                        Text(verbatim: InsightsFormat.cost(s.costUSD)).dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textPrimary)
                            .frame(minWidth: DS.Space.s10, alignment: .trailing)
                        Text(verbatim: InsightsFormat.ago(s.lastActive, now: now)).dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textTertiary)
                            .frame(minWidth: DS.Space.s6, alignment: .trailing)
                    }
                    ShareBar(fraction: s.costUSD / top)
                }
            }
        }
    }

    // MARK: Compacto (só os números principais)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                RingMeter(fraction: summary.fiveHour?.usedFraction, elapsed: nil, estimated: summary.fiveHour?.source == .estimated, caption: "5h", compact: true)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s1) {
                        DSAgentLogo(summary.provider.agentKind, size: DS.Space.s3)
                        Text(verbatim: InsightsFormat.plan(summary.plan?.plan) ?? "").dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
                    }
                    Text(verbatim: resetText(summary.fiveHour)).dsFont(DS.Font.microNumeric).foregroundStyle(DS.Color.textTertiary)
                }
            }
            InsightsStat(label: "7-day", value: summary.sevenDay?.usedFraction.map { InsightsFormat.percent($0) } ?? "–", emphasis: true)
            TickBar(fraction: summary.sevenDay?.usedFraction, estimated: summary.sevenDay?.source == .estimated)
            InsightsStat(label: "Today", value: InsightsFormat.cost(summary.todayCostUSD))
            InsightsStat(label: "Tokens", value: InsightsFormat.tokens(summary.today.fresh))
        }
    }

    // MARK: Auxiliares

    private func resetText(_ w: LimitWindow?) -> String {
        guard let r = w?.resetsAt, r > now else { return "No active window" }
        return InsightsFormat.duration(r.timeIntervalSince(now))
    }

    /// Fração do tempo da janela já decorrida, para o cursor de ritmo (só com horário de reset conhecido).
    private func elapsed(_ w: LimitWindow?, length: TimeInterval) -> Double? {
        guard let r = w?.resetsAt, r > now else { return nil }
        return min(1, max(0, 1 - r.timeIntervalSince(now) / length))
    }
}
