import RackyCore
import RackyDesignSystem
import RackyProtocol
import SwiftUI

/// Medidas da tela inicial e da sessão vazia.
enum StartMetrics {
    static let logo: CGFloat = 36
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
    static let actionRow: CGFloat = 32
    static let tableRow: CGFloat = 32
    static let actionsWidth: CGFloat = 260
    static let columnGap: CGFloat = 40
    static let blockGap: CGFloat = 32
    static let contentMax: CGFloat = 960
    static let margin: CGFloat = 48
    static let top: CGFloat = 72
    static let nameColumn: CGFloat = 140
    static let ageColumn: CGFloat = 56
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

/// Tela inicial (nenhuma sessão selecionada), no tom de ferramenta profissional: tudo alinhado à esquerda, ações em linhas
/// com o atalho à direita (um agente = sessão limpa nova com ele, F37), sessões recentes em tabela e o ambiente (agentes
/// instalados, versão) num bloco de chave e valor.
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
        ScrollView {
            VStack(alignment: .leading, spacing: StartMetrics.blockGap) {
                header
                HStack(alignment: .top, spacing: StartMetrics.columnGap) {
                    VStack(alignment: .leading, spacing: StartMetrics.blockGap) {
                        if registry?.isOffered(.sessionNewClean) ?? true {
                            LandingBlock(String(localized: "New session", bundle: .module)) {
                                ForEach(Self.agents, id: \.self) { provider in
                                    let info = settings.agent(provider)
                                    LandingActionRow(
                                        action: .sessionNewClean, id: .landingAgent(provider.rawValue),
                                        argument: .set(#"{"provider":"\#(provider.rawValue)"}"#),
                                        title: ProviderAdapters.name(provider),
                                        shortcut: settings.settings.agents.defaultAgent == provider ? ActionID.sessionNewClean.spec.shortcut : "",
                                        enabled: info?.installedState != false
                                    ) { DSAgentLogo(QuickLaunchModel.kind(provider), size: StartMetrics.rowIcon) }
                                }
                            }
                        }
                        LandingBlock(String(localized: "Project", bundle: .module)) {
                            if registry?.isOffered(.projectAdd) ?? true {
                                LandingActionRow(
                                    action: .projectAdd, id: .landingAddProject, title: String(localized: "Open a Folder…", bundle: .module),
                                    shortcut: ActionID.projectAdd.spec.shortcut
                                ) { Image(systemName: "folder").font(.system(size: StartMetrics.rowIcon - 4)).foregroundStyle(DS.Color.textSecondary) }
                            }
                            if registry?.isOffered(.projectCloneFromGitHub) ?? true {
                                LandingActionRow(
                                    action: .projectCloneFromGitHub, id: .landingCloneProject,
                                    title: String(localized: "Clone from GitHub…", bundle: .module),
                                    shortcut: ActionID.projectCloneFromGitHub.spec.shortcut
                                ) { DSGitHubMark(size: StartMetrics.rowIcon - 3).foregroundStyle(DS.Color.textSecondary) }
                            }
                        }
                    }
                    .frame(width: StartMetrics.actionsWidth)
                    VStack(alignment: .leading, spacing: StartMetrics.blockGap) {
                        LandingBlock(String(localized: "Recent sessions", bundle: .module)) {
                            LandingTableHeader(columns: [
                                String(localized: "Name", bundle: .module), String(localized: "Folder", bundle: .module),
                                String(localized: "Active", bundle: .module),
                            ])
                            if recent.isEmpty {
                                Text("No sessions yet. Start one on the left.", bundle: .module)
                                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                                    .frame(maxWidth: .infinity, minHeight: StartMetrics.tableRow, alignment: .leading)
                                    .padding(.horizontal, DS.Space.s2)
                            } else {
                                ForEach(recent) { session in RecentSessionRow(session: session) }
                            }
                        }
                        LandingBlock(String(localized: "Environment", bundle: .module)) {
                            ForEach(Self.agents, id: \.self) { provider in
                                LandingKeyValue(key: ProviderAdapters.name(provider), value: Self.state(settings.agent(provider)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: StartMetrics.contentMax, alignment: .leading)
            .padding(.horizontal, StartMetrics.margin)
            .padding(.top, StartMetrics.top)
            .padding(.bottom, StartMetrics.margin)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
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

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            BrandMark(size: StartMetrics.logo)
            VStack(alignment: .leading, spacing: .zero) {
                Text("Racky", bundle: .module).dsFont(DS.Font.dialogTitle).foregroundStyle(DS.Color.textPrimary)
                Text("Coding agents with their own computers.", bundle: .module)
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    /// Estado de um agente para o bloco de ambiente: versão quando instalado.
    static func state(_ info: AgentInfo?) -> (text: String, tone: AgentInfo.Tone) {
        switch info?.phase {
        case .installed(_, let version, _)?:
            (version.map { String(localized: "Installed · \($0)", bundle: .module) } ?? String(localized: "Installed", bundle: .module), .success)
        case .notInstalled?: (String(localized: "Not installed", bundle: .module), .warning)
        case .checking?, nil: (String(localized: "Checking…", bundle: .module), .neutral)
        }
    }
}

/// Bloco da landing: rótulo pequeno em caixa alta e o conteúdo logo abaixo, separado por uma linha fina.
private struct LandingBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(verbatim: title.uppercased()).dsFont(DS.Font.micro).tracking(0.6).foregroundStyle(DS.Color.textTertiary)
                .padding(.horizontal, DS.Space.s2).padding(.bottom, DS.Space.s2)
            Rectangle().fill(DS.Color.border).frame(height: DSMetrics.hairline)
            VStack(alignment: .leading, spacing: .zero) { content() }.padding(.top, DS.Space.s1)
        }
    }
}

/// Linha de ação: ícone pequeno, título e o atalho à direita; fundo só no hover.
private struct LandingActionRow<Icon: View>: View {
    let action: ActionID
    let id: A11yID
    var argument: ActionArgument = .press
    let title: String
    var shortcut: String = ""
    var enabled = true
    @ViewBuilder let icon: () -> Icon
    @State private var hovering = false

    var body: some View {
        ActionButton(action, id: id, argument: argument) {
            HStack(spacing: DS.Space.s2_5) {
                icon().frame(width: StartMetrics.rowIcon, height: StartMetrics.rowIcon)
                Text(verbatim: title).dsFont(DS.Font.body).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if !enabled {
                    Text("Not installed", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                } else if !shortcut.isEmpty {
                    Text(verbatim: shortcut).dsFont(DS.Font.keycap).foregroundStyle(DS.Color.textTertiary)
                }
            }
            .padding(.horizontal, DS.Space.s2)
            .frame(height: StartMetrics.actionRow)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(hovering ? DS.Color.secondary : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .onHover { hovering = enabled && $0 }
    }
}

/// Cabeçalho da tabela de sessões; as larguras batem com `RecentSessionRow`.
private struct LandingTableHeader: View {
    let columns: [String]

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: columns[0]).frame(width: StartMetrics.nameColumn, alignment: .leading)
            Text(verbatim: columns[1]).frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: columns[2]).frame(width: StartMetrics.ageColumn, alignment: .trailing)
        }
        .lineLimit(1)
        .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
        .padding(.horizontal, DS.Space.s2)
        .frame(maxWidth: .infinity, minHeight: StartMetrics.tableRow, maxHeight: StartMetrics.tableRow)
    }
}

private struct RecentSessionRow: View {
    let session: Session
    @State private var hovering = false

    var body: some View {
        ActionButton(.sessionSelect, id: .landingRecent(session.id.uuidString), argument: .select(session.id.uuidString)) {
            HStack(spacing: DS.Space.s3) {
                Text(verbatim: session.title).dsFont(DS.Font.body).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    .frame(width: StartMetrics.nameColumn, alignment: .leading)
                Text(verbatim: (session.folderPath as NSString).abbreviatingWithTildeInPath)
                    .dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textSecondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: Self.age(session.lastActiveAt ?? session.createdAt)).dsFont(DS.Font.microNumeric)
                    .foregroundStyle(DS.Color.textSecondary).frame(width: StartMetrics.ageColumn, alignment: .trailing)
            }
            .padding(.horizontal, DS.Space.s2)
            .frame(height: StartMetrics.tableRow)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(hovering ? DS.Color.secondary : Color.clear))
            .overlay(alignment: .top) { Rectangle().fill(DS.Color.fg5).frame(height: DSMetrics.hairline) }
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

/// Linha de chave e valor do bloco de ambiente; o valor ganha um ponto com a cor do estado.
private struct LandingKeyValue: View {
    let key: String
    let value: (text: String, tone: AgentInfo.Tone)

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: key).dsFont(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                .frame(width: StartMetrics.nameColumn, alignment: .leading)
            Circle().fill(color).frame(width: DS.Space.s1_5, height: DS.Space.s1_5)
            Text(verbatim: value.text).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
            Spacer(minLength: .zero)
        }
        .padding(.horizontal, DS.Space.s2)
        .frame(height: StartMetrics.tableRow)
    }

    private var color: Color {
        switch value.tone {
        case .success: DS.Color.success
        case .warning: DS.Color.warning
        case .neutral: DS.Color.textTertiary
        }
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
