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
        if let conversations = env.conversations { controller.register(ConversationsModule(controller: conversations)) }
        if env.flags.isEnabled(.slice2) {
            controller.register(SourceControlModule(controller: env.github))
            controller.register(ChecksModule(controller: env.github))
        }
        if env.flags.offersSlice4 { controller.register(ContextModule(controller: env.context)) }
    }

    static func makeInsightsModule(env: AppEnvironment) -> any RightPanelModule {
        InsightsModule(model: env.insights)
    }
}

/// Insights (uso de IA e máquina) como módulo do painel; mantém o botão da faixa de topo.
@MainActor
final class InsightsModule: RightPanelModule {
    let id = PanelModuleID.insights
    let title = String(localized: "Insights", bundle: .module)
    let icon = "chart.xyaxis.line"
    let toggleAction: ActionID? = .rightPanelToggleInsights
    let stripButtonID: A11yID? = .tabsInsightsToggle
    private let model: InsightsModel

    init(model: InsightsModel) { self.model = model }

    func makeView(context: RightPanelModuleContext) -> AnyView {
        AnyView(InsightsModuleView(model: model, compact: context.isCompact))
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

/// Conversations (03 §10.5) como módulo do painel; abre por ⇧⌘H e não tem botão na faixa de topo.
@MainActor
final class ConversationsModule: RightPanelModule {
    let id = PanelModuleID.conversations
    let title = String(localized: "Conversations", bundle: .module)
    let icon = "clock.arrow.circlepath"
    private let controller: ConversationsController

    init(controller: ConversationsController) { self.controller = controller }

    func makeView(context: RightPanelModuleContext) -> AnyView {
        AnyView(ConversationsView(controller: controller))
    }
}
