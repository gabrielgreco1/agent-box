import RackyCore
import RackyDesignSystem
import RackyProtocol
import SwiftUI

/// Medidas da tela inicial e da sessão vazia.
enum StartMetrics {
    static let logo: CGFloat = 56
    static let cardWidth: CGFloat = 196
    static let cardHeight: CGFloat = 124
    static let agentCardWidth: CGFloat = 148
    static let agentCardHeight: CGFloat = 88
    static let icon: CGFloat = 20
    static let column: CGFloat = 632
    static let recentRow: CGFloat = 36
    static let agentLogo: CGFloat = 28
    static let agentTileHeight: CGFloat = 116
    static let projectRowHeight: CGFloat = 60
    static let rowIcon: CGFloat = 18
    static let rowIconTile: CGFloat = 34
    static let maxRecent = 5
}

/// Card de ação das telas de início: ícone (ou logo do agente), título, uma linha do que faz e o atalho. Passa pelo registro
/// de ações (a automação enxerga) e acende no hover.
struct StartCard<Icon: View>: View {
    let action: ActionID
    let id: A11yID
    var argument: ActionArgument = .press
    let title: String
    let detail: String?
    var width: CGFloat = StartMetrics.cardWidth
    var height: CGFloat = StartMetrics.cardHeight
    @ViewBuilder let icon: () -> Icon
    @State private var hovering = false

    var body: some View {
        ActionButton(action, id: id, argument: argument) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(alignment: .top) {
                    icon().frame(width: StartMetrics.icon, height: StartMetrics.icon)
                    Spacer(minLength: .zero)
                    let key = action.spec.shortcut
                    if !key.isEmpty {
                        Text(verbatim: key).dsFont(DS.Font.keycap).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                Spacer(minLength: .zero)
                Text(verbatim: title).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                if let detail {
                    Text(verbatim: detail).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.Space.s4)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(hovering ? DS.Color.hoverRow : DS.Color.chrome))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(hovering ? DS.Color.borderStrong : DS.Color.border))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: hovering)
    }
}

/// Tela inicial (nenhuma sessão selecionada): o que o Racky faz, um card por agente (abre uma sessão limpa com ele, F37),
/// os dois caminhos de projeto (pasta ou GitHub) e as sessões recentes.
struct LandingView: View {
    let automationOn: Bool
    let sidebar: SidebarModel
    let settings: SettingsModel
    @Environment(\.actionRegistry) private var registry

    private static let agents: [TerminalProvider] = [.claude, .codex, .opencode]

    private var recent: [Session] {
        sidebar.snapshot.sessions
            .filter { $0.archivedAt == nil && $0.lifecycle != .archived }
            .sorted { ($0.lastActiveAt ?? $0.createdAt) > ($1.lastActiveAt ?? $1.createdAt) }
            .prefix(StartMetrics.maxRecent).map { $0 }
    }

    var body: some View {
        VStack(spacing: DS.Space.s8) {
            VStack(spacing: DS.Space.s2) {
                BrandMark(size: StartMetrics.logo)
                Text("Racky", bundle: .module).dsFont(DS.Font.display).foregroundStyle(DS.Color.textPrimary).padding(.top, DS.Space.s2)
                Text("Run coding agents side by side, and give each subagent its own computer.", bundle: .module)
                    .dsFont(DS.Font.dialogBody).foregroundStyle(DS.Color.textSecondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if registry?.isOffered(.sessionNewClean) ?? true {
                    section(String(localized: "Start an agent", bundle: .module)) {
                        HStack(spacing: DS.Space.s3) {
                            ForEach(Self.agents, id: \.self) { provider in
                                LandingAgentTile(
                                    provider: provider, installed: settings.agent(provider)?.installedState != false,
                                    isDefault: settings.settings.agents.defaultAgent == provider)
                            }
                        }
                    }
                }
                section(String(localized: "Work in a project", bundle: .module)) {
                    HStack(spacing: DS.Space.s3) {
                        if registry?.isOffered(.projectAdd) ?? true {
                            LandingProjectRow(
                                action: .projectAdd, id: .landingAddProject, title: String(localized: "Open a Folder…", bundle: .module),
                                detail: String(localized: "A folder or repository on this Mac.", bundle: .module)
                            ) {
                                Image(systemName: "folder").font(.system(size: StartMetrics.rowIcon - 2)).foregroundStyle(DS.Color.textPrimary)
                            }
                        }
                        if registry?.isOffered(.projectCloneFromGitHub) ?? true {
                            LandingProjectRow(
                                action: .projectCloneFromGitHub, id: .landingCloneProject, title: String(localized: "Clone from GitHub…", bundle: .module),
                                detail: String(localized: "Pick one of your repositories or paste a URL.", bundle: .module)
                            ) {
                                DSGitHubMark(size: StartMetrics.rowIcon).foregroundStyle(DS.Color.textPrimary)
                            }
                        }
                    }
                }
                if !recent.isEmpty {
                    section(String(localized: "Recent sessions", bundle: .module)) {
                        VStack(spacing: .zero) {
                            ForEach(recent) { session in RecentSessionRow(session: session) }
                        }
                    }
                }
            }
            .frame(width: StartMetrics.column)
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.canvas)
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            // Selo do canal de automação (AR-806): fora da faixa de 280 pt, que não comporta o texto ao lado dos controles.
            if automationOn {
                Text("Automation on", bundle: .module)
                    .font(DS.Font.micro.font)
                    .foregroundStyle(DS.Color.warning)
                    .padding(DS.Space.s2)
                    .a11y(.windowAutomationBadge, kind: "text", label: "Automation on")
            }
        }
        .a11y(.landing, kind: "container")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: title).dsFont(DS.Font.sectionLabel).foregroundStyle(DS.Color.textTertiary).padding(.leading, DS.Space.s1)
            content()
        }
    }
}

/// Card de agente da landing: clique = sessão limpa nova com esse agente já rodando (`session.newClean` com o provider).
private struct LandingAgentTile: View {
    let provider: TerminalProvider
    let installed: Bool
    let isDefault: Bool
    @State private var hovering = false

    private var request: String { #"{"provider":"\#(provider.rawValue)"}"# }

    var body: some View {
        ActionButton(.sessionNewClean, id: .landingAgent(provider.rawValue), argument: .set(request)) {
            VStack(alignment: .leading, spacing: .zero) {
                HStack(alignment: .top) {
                    DSAgentLogo(QuickLaunchModel.kind(provider), size: StartMetrics.agentLogo)
                    Spacer(minLength: .zero)
                    if isDefault, installed {
                        Text(verbatim: ActionID.sessionNewClean.spec.shortcut).dsFont(DS.Font.keycap).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                Spacer(minLength: .zero)
                Text(verbatim: ProviderAdapters.name(provider)).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Text(installed ? String(localized: "New session in a clean folder", bundle: .module) : String(localized: "Not installed", bundle: .module))
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, minHeight: StartMetrics.agentTileHeight, maxHeight: StartMetrics.agentTileHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(hovering ? DS.Color.secondary : DS.Color.chrome))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(hovering ? DS.Color.borderStrong : DS.Color.border))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            .offset(y: hovering ? -1 : 0)
        }
        .buttonStyle(.plain)
        .disabled(!installed)
        .opacity(installed ? 1 : 0.5)
        .onHover { hovering = installed && $0 }
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: hovering)
    }
}

/// Linha larga de projeto da landing: ícone num quadrado, título e uma linha do que faz.
private struct LandingProjectRow<Icon: View>: View {
    let action: ActionID
    let id: A11yID
    let title: String
    let detail: String
    @ViewBuilder let icon: () -> Icon
    @State private var hovering = false

    var body: some View {
        ActionButton(action, id: id) {
            HStack(spacing: DS.Space.s3) {
                icon()
                    .frame(width: StartMetrics.rowIconTile, height: StartMetrics.rowIconTile)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Color.secondary))
                VStack(alignment: .leading, spacing: DS.Space.s0_5) {
                    Text(verbatim: title).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    Text(verbatim: detail).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                }
                Spacer(minLength: .zero)
                let key = action.spec.shortcut
                if !key.isEmpty { Text(verbatim: key).dsFont(DS.Font.keycap).foregroundStyle(DS.Color.textTertiary) }
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: StartMetrics.projectRowHeight, maxHeight: StartMetrics.projectRowHeight)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(hovering ? DS.Color.secondary : DS.Color.chrome))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(hovering ? DS.Color.borderStrong : DS.Color.border))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: hovering)
    }
}

private struct RecentSessionRow: View {
    let session: Session
    @State private var hovering = false

    var body: some View {
        ActionButton(.sessionSelect, id: .landingRecent(session.id.uuidString), argument: .select(session.id.uuidString)) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "rectangle.stack").foregroundStyle(DS.Color.textSecondary)
                Text(verbatim: session.title).dsFont(DS.Font.body).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Text(verbatim: (session.folderPath as NSString).abbreviatingWithTildeInPath)
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: Self.age(session.lastActiveAt ?? session.createdAt)).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(height: StartMetrics.recentRow)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(hovering ? DS.Color.hoverRow : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    static func age(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Sessão sem tabs (03 §4.7): o nome da sessão e um card por agente para começar, mais Terminal e "Reopen Closed Tab".
struct PaneEmptyView: View {
    let model: WorkspaceModel

    private static let agents: [TerminalProvider] = [.claude, .codex, .opencode]

    var body: some View {
        VStack(spacing: DS.Space.s6) {
            VStack(spacing: DS.Space.s1_5) {
                Text(verbatim: model.session?.title ?? "").dsFont(DS.Font.dialogTitle).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Text("No terminals open. Start an agent in this session:", bundle: .module)
                    .dsFont(DS.Font.body).foregroundStyle(DS.Color.textSecondary).multilineTextAlignment(.center)
            }
            HStack(spacing: DS.Space.s3) {
                ForEach(Self.agents, id: \.self) { provider in
                    StartCard(
                        action: .tabNewWithAgent, id: .paneEmptyAgent(provider.rawValue), argument: .select(provider.rawValue),
                        title: ProviderAdapters.name(provider), detail: nil,
                        width: StartMetrics.agentCardWidth, height: StartMetrics.agentCardHeight
                    ) {
                        DSAgentLogo(QuickLaunchModel.kind(provider), size: StartMetrics.icon)
                    }
                }
                StartCard(
                    action: .tabNewTerminal, id: .paneEmptyNewTerminal, title: String(localized: "Terminal", bundle: .module), detail: nil,
                    width: StartMetrics.agentCardWidth, height: StartMetrics.agentCardHeight
                ) {
                    Image(systemName: "terminal").font(.system(size: StartMetrics.icon - 4)).foregroundStyle(DS.Color.textPrimary)
                }
            }
            if model.hasClosedTabs {
                DSButton(.tabReopen, id: .paneEmptyReopen, "Reopen Closed Tab", variant: .ghost, size: .sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.canvas)
        .a11y(.paneEmpty, kind: "container")
    }
}
