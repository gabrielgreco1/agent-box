import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxProtocol
import SwiftUI

/// Medidas do chrome do pane (03 §4, DS §12.23).
enum PaneMetrics {
    static let headerHeight = DS.Layout.paneHeaderHeight
    static let headerPaddingH = DS.Space.s2
    static let buttonGap: CGFloat = 0
    static let banner = DS.Space.s8
    static let cardWidth: CGFloat = 360
    static let dividerHit = PaneLayout.dividerThickness + 2 * DS.Layout.paneDividerHitSlop
    static let separator: CGFloat = 1
    static let logo = DS.Space.s3
}

/// Dados que o container do pane entrega às views SwiftUI do chrome (cabeçalho, botões, banners).
@MainActor
@Observable
final class PaneChromeModel {
    var terminalID = UUID()
    var title = ""
    var provider: TerminalProvider = .shell
    var glyph: DSIndicatorGlyph = .none
    var focused = false
    var expanded = false
    var hovering = false
    var state: PaneRunState = .running
    var errorDetail = ""

    var id: String { terminalID.uuidString }
    var agentName: String { provider.isAgent ? ProviderAdapters.name(provider) : String(localized: "Terminal", bundle: .module) }
}

/// Cabeçalho do pane (03 §4.2): 24 de altura, sobreposto ao topo, separador inferior `white/6`.
struct PaneHeaderView: View {
    let model: PaneChromeModel

    var body: some View {
        HStack(spacing: DS.Space.s1_5) {
            if model.glyph != .none { DSAgentIndicator(model.glyph, size: .sm).a11y(.paneStatus(model.id), kind: "status") }
            DSAgentLogo(model.provider, size: PaneMetrics.logo)
            Text(verbatim: model.title)
                .dsFont(DS.Font.monoPane)
                .foregroundStyle(model.focused ? DS.Color.paneTitleInput : DS.Color.paneTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: DS.Space.s2)
            PaneButtons(model: model)
        }
        .padding(.horizontal, PaneMetrics.headerPaddingH)
        .frame(height: PaneMetrics.headerHeight)
        .background(DS.Color.terminalBackground)
        .overlay(alignment: .bottom) { DS.Color.paneTitleSeparator.frame(height: PaneMetrics.separator) }
        .a11y(.paneHeader(model.id), kind: "container", label: model.title)
    }
}

/// Botões de ação do pane (split à direita e abaixo, expandir, fechar). Split: no pane ativo ou no hover; fechar: só no hover (fade 120 ms).
struct PaneButtons: View {
    let model: PaneChromeModel

    var body: some View {
        let arg = ActionArgument.select(model.id)
        let showSplit = model.focused || model.hovering
        HStack(spacing: PaneMetrics.buttonGap) {
            ActionButton(.paneSplitRight, id: .paneSplitRight(model.id), argument: arg, tooltip: String(localized: "Split Right", bundle: .module)) {
                Image(systemName: "square.split.2x1")
            }
            .buttonStyle(DSIconButtonStyle(.pane))
            .opacity(showSplit ? 1 : 0)
            ActionButton(.paneSplitDown, id: .paneSplitDown(model.id), argument: arg, tooltip: String(localized: "Split Down", bundle: .module)) {
                Image(systemName: "square.split.1x2")
            }
            .buttonStyle(DSIconButtonStyle(.pane))
            .opacity(showSplit ? 1 : 0)
            ActionButton(
                .paneToggleExpand, id: .paneExpand(model.id), argument: arg,
                tooltip: model.expanded ? String(localized: "Collapse Pane", bundle: .module) : String(localized: "Expand Pane", bundle: .module)
            ) {
                Image(systemName: model.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(DSIconButtonStyle(.pane))
            .opacity(showSplit ? 1 : 0)
            ActionButton(.paneClose, id: .paneClose(model.id), argument: arg, tooltip: String(localized: "Close Pane", bundle: .module)) {
                Image(systemName: "xmark")
            }
            .buttonStyle(DSIconButtonStyle(.pane))
            .opacity(model.hovering ? 1 : 0)
        }
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.hover), value: showSplit)
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.hover), value: model.hovering)
    }
}

/// Variante chromeless (1 pane): só os botões no canto superior direito, visíveis no hover.
struct PaneFloatingButtons: View {
    let model: PaneChromeModel

    var body: some View {
        PaneButtons(model: model)
            .opacity(model.hovering ? 1 : 0)
            .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.hover), value: model.hovering)
    }
}

/// Banner no topo do pane (processo saiu, interrompido, "The process didn't exit.").
struct PaneBannerView: View {
    let model: PaneChromeModel

    var body: some View {
        let arg = ActionArgument.select(model.id)
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: text)
                .dsFont(DS.Font.small)
                .foregroundStyle(isWarning ? DS.Color.warning : DS.Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            switch model.state {
            case .closing:
                DSButton(.terminalForceQuit, id: .paneClosingForceQuit(model.id), "Force Quit", variant: .outline, size: .xs, argument: arg)
                DSButton(.terminalCancelClose, "Cancel", variant: .ghost, size: .xs, argument: arg)
            default:
                DSButton(.terminalRestart, "Restart", variant: .outline, size: .xs, argument: arg)
                DSButton(.paneClose, "Close", variant: .ghost, size: .xs, argument: arg)
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: PaneMetrics.banner)
        .background(DS.Color.chrome)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: PaneMetrics.separator) }
        .a11y(bannerID, kind: "banner", label: text)
    }

    private var isWarning: Bool { if case .closing = model.state { true } else { false } }

    private var bannerID: A11yID {
        switch model.state {
        case .interrupted: .paneInterrupted(model.id)
        default: .paneExitBanner(model.id)
        }
    }

    private var text: String {
        switch model.state {
        case .closing: String(localized: "The process didn't exit.", bundle: .module)
        case .interrupted: String(localized: "This terminal stopped unexpectedly.", bundle: .module)
        default:
            model.provider.isAgent
                ? String(localized: "\(model.agentName) exited.", bundle: .module) : String(localized: "pane.exited.shell", bundle: .module)
        }
    }
}

/// Cartão central do pane: saída com erro (`Terminal exited`) e "Couldn't start" (03 §4.6).
struct PaneCardView: View {
    let model: PaneChromeModel

    var body: some View {
        let arg = ActionArgument.select(model.id)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            switch model.state {
            case .failed(let detail):
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(DS.Color.destructive)
                    Text(String(localized: "Couldn't start \(model.agentName)", bundle: .module))
                        .dsFont(DS.Font.dialogTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                }
                Text(verbatim: detail)
                    .dsFont(DS.Font.monoPane)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(6)
                HStack(spacing: DS.Space.s2) {
                    Spacer(minLength: 0)
                    DSButton(.terminalCopyStartError, "Copy Details", variant: .ghost, size: .sm, argument: arg)
                    DSButton(.terminalRetryStart, "Try Again", variant: .primary, size: .sm, argument: arg)
                }
            case .exited(let code, let signal):
                Text("Terminal exited", bundle: .module)
                    .dsFont(DS.Font.dialogTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(verbatim: exitText(code: code, signal: signal))
                    .dsFont(DS.Font.dialogBody)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s2) {
                    Spacer(minLength: 0)
                    DSButton(.paneClose, id: .paneExitOverlayClose(model.id), "Close", variant: .outline, size: .sm, argument: arg)
                    DSButton(.terminalRestart, id: .paneExitOverlayRestart(model.id), "Restart", variant: .primary, size: .sm, argument: arg)
                }
            default:
                EmptyView()
            }
        }
        .padding(DS.Space.s4)
        .frame(width: PaneMetrics.cardWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Color.chrome))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Color.border))
        .a11y(cardID, kind: "overlay")
    }

    private var cardID: A11yID {
        if case .failed = model.state { .paneStartError(model.id) } else { .paneExitOverlay(model.id) }
    }

    private func exitText(code: Int?, signal: Int?) -> String {
        if let signal { return String(localized: "The process was killed (signal \(signal)). Its output is preserved.", bundle: .module) }
        return String(localized: "The process ended with exit code \(code ?? 0). Its output is preserved.", bundle: .module)
    }
}

/// Sessão sem tabs (03 §4.7): coluna de 320 centralizada.
struct PaneEmptyView: View {
    let model: WorkspaceModel

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            Text(String(localized: "No terminals open in \(model.session?.title ?? "")", bundle: .module))
                .dsFont(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: DS.Space.s2) {
                DSButton(.tabNewAgent, id: .paneEmptyNewAgent, "New Claude Code Tab", variant: .secondary, size: .sm, keycap: nil)
                DSButton(.tabNewTerminal, id: .paneEmptyNewTerminal, "New Terminal", variant: .ghost, size: .sm)
                if model.hasClosedTabs {
                    DSButton(.tabReopen, id: .paneEmptyReopen, "Reopen Closed Tab", variant: .ghost, size: .sm)
                }
            }
        }
        .frame(width: DSMetrics.emptyStateMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.canvas)
        .a11y(.paneEmpty, kind: "container")
    }
}

extension ProviderAdapters {
    /// Nome do agente na UI ("Claude Code").
    static func name(_ provider: TerminalProvider) -> String { adapter(for: provider).displayName }
}
