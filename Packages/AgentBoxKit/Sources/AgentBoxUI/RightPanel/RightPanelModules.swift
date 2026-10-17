import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxProtocol
import SwiftUI

/// Registro dos módulos do painel direito (10-right-panel). Um módulo novo implementa `RightPanelModule` e entra aqui.
@MainActor
enum RightPanelModules {
    static func registerAll(into controller: RightPanelController, env: AppEnvironment) {
        controller.register(FilesModule(controller: env.files))
        controller.register(makeInsightsModule(env: env))
        controller.register(ComputersModule(controller: env.computers))
    }

    /// PONTO DE TROCA: o módulo Insights (uso de IA e máquina) substitui o placeholder aqui. Mantém `id == .insights`,
    /// `toggleAction == .rightPanelToggleInsights` e `stripButtonID == .tabsInsightsToggle` para o botão da faixa de topo.
    static func makeInsightsModule(env: AppEnvironment) -> any RightPanelModule {
        InsightsPlaceholderModule()
    }
}

/// Placeholder do Insights até o módulo real chegar: título, ícone e botão da faixa já funcionam.
@MainActor
final class InsightsPlaceholderModule: RightPanelModule {
    let id = PanelModuleID.insights
    let title = String(localized: "Insights", bundle: .module)
    let icon = "chart.xyaxis.line"
    let toggleAction: ActionID? = .rightPanelToggleInsights
    let stripButtonID: A11yID? = .tabsInsightsToggle

    func makeView(context: RightPanelModuleContext) -> AnyView {
        AnyView(InsightsPlaceholderView(compact: context.isCompact))
    }
}

private struct InsightsPlaceholderView: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: DS.Space.s6, weight: .regular))
                .foregroundStyle(DS.Color.textTertiary)
            if !compact {
                Text("Usage and machine insights will appear here.", bundle: .module)
                    .font(DS.Font.small.font)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .a11y(.rightPanelInsightsEmpty, kind: "text")
    }
}

/// Computers da sessão (03 §10.4) como módulo do painel; abre por ⇧⌘C e não tem botão na faixa de topo.
@MainActor
final class ComputersModule: RightPanelModule {
    let id = PanelModuleID.computers
    let title = String(localized: "Computers", bundle: .module)
    let icon = "display"
    private let controller: ComputersController

    init(controller: ComputersController) { self.controller = controller }

    func makeView(context: RightPanelModuleContext) -> AnyView {
        AnyView(ComputersPanelView(controller: controller))
    }

    func makeHeaderAccessory(context: RightPanelModuleContext) -> AnyView? {
        guard !context.isCompact else { return nil }
        return AnyView(
            Text(verbatim: controller.model.summaryText)
                .font(DS.Font.small.font)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1))
    }
}
