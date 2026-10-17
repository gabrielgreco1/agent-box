import AgentBoxCore
import AgentBoxDesignSystem
import SwiftUI

/// Raiz do módulo Insights do painel direito. `compact` força o modo compacto; abaixo de `InsightsMetrics.compactWidth`
/// ele também liga sozinho (só os números principais, abas só com ícone).
public struct InsightsModuleView: View {
    @Bindable private var model: InsightsModel
    private let forceCompact: Bool
    @Namespace private var tabNamespace

    public init(model: InsightsModel, compact: Bool = false) {
        self.model = model
        self.forceCompact = compact
    }

    public var body: some View {
        GeometryReader { proxy in
            let compact = forceCompact || proxy.size.width < InsightsMetrics.compactWidth
            VStack(spacing: .zero) {
                tabStrip(compact: compact)
                    .padding(.horizontal, compact ? DS.Space.s2 : DS.Space.s3)
                    .padding(.vertical, DS.Space.s2)
                ScrollView {
                    pane(compact: compact)
                        .padding(.horizontal, compact ? DS.Space.s2 : DS.Space.s3)
                        .padding(.bottom, DS.Space.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(DS.Color.panel)
        .onAppear { model.viewDidAppear() }
        .onDisappear { model.viewDidDisappear() }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func pane(compact: Bool) -> some View {
        switch model.tab {
        case .claude: InsightsProviderPane(summary: model.snapshot.claude, now: model.now, compact: compact, scanning: model.snapshot.scanning)
        case .codex: InsightsProviderPane(summary: model.snapshot.codex, now: model.now, compact: compact, scanning: model.snapshot.scanning)
        case .machine:
            InsightsMachinePane(snapshot: model.snapshot, history: model.history, sortByMemory: $model.appsSortedByMemory, compact: compact)
        case .proxy: InsightsProxyPane(proxies: model.snapshot.proxies, compact: compact)
        }
    }

    private func tabStrip(compact: Bool) -> some View {
        HStack(spacing: .zero) {
            ForEach(InsightsTab.allCases) { tab in
                let active = tab == model.tab
                // lint-ui: allow buttons seletor de aba local do módulo; não é uma ação do app
                Button { model.tab = tab } label: { tabLabel(tab, compact: compact) }
                    .buttonStyle(DSSegmentStyle(active: active, fillWidth: true))
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.accent)
                                .matchedGeometryEffect(id: "insights-tab", in: tabNamespace)
                        }
                    }
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityLabel(Text(tab.title, bundle: .module))
            }
        }
        .padding(DSMetrics.segmentedPadding)
        .frame(height: DSMetrics.segmentedHeight)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Color.secondary))
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: model.tab)
    }

    @ViewBuilder private func tabLabel(_ tab: InsightsTab, compact: Bool) -> some View {
        if compact {
            switch tab {
            case .claude: DSAgentLogo(DSAgentKind.claude, size: DS.Space.s3)
            case .codex: DSAgentLogo(DSAgentKind.codex, size: DS.Space.s3)
            case .machine: Image(systemName: "gauge.with.dots.needle.bottom.50percent").font(.system(size: DS.Space.s3))
            case .proxy: Image(systemName: "network").font(.system(size: DS.Space.s3))
            }
        } else {
            Text(tab.title, bundle: .module)
        }
    }
}

extension InsightsTab {
    var title: LocalizedStringKey {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .machine: "Machine"
        case .proxy: "Proxy"
        }
    }
}
