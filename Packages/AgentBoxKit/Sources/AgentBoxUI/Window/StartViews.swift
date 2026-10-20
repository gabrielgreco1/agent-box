import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxProtocol
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
    static let recentRow: CGFloat = 40
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

/// Tela inicial (nenhuma sessão selecionada): o que o Racky faz, as três formas de começar e as sessões recentes.
struct LandingView: View {
    let automationOn: Bool
    let sidebar: SidebarModel
    @Environment(\.actionRegistry) private var registry

    private var recent: [Session] {
        sidebar.snapshot.sessions
            .filter { $0.archivedAt == nil && $0.lifecycle != .archived }
            .sorted { ($0.lastActiveAt ?? $0.createdAt) > ($1.lastActiveAt ?? $1.createdAt) }
            .prefix(StartMetrics.maxRecent).map { $0 }
    }

    var body: some View {
        VStack(spacing: DS.Space.s6) {
            VStack(spacing: DS.Space.s2) {
                BrandMark(size: StartMetrics.logo)
                Text("Racky", bundle: .module).dsFont(DS.Font.display).foregroundStyle(DS.Color.textPrimary)
                Text("Run coding agents side by side, and give each subagent its own computer.", bundle: .module)
                    .dsFont(DS.Font.dialogBody).foregroundStyle(DS.Color.textSecondary).multilineTextAlignment(.center)
            }
            HStack(spacing: DS.Space.s3) {
                if registry?.isOffered(.projectAdd) ?? true {
                    StartCard(action: .projectAdd, id: .landingAddProject, title: String(localized: "Add Project…", bundle: .module),
                              detail: String(localized: "Work in a folder or repository you already have.", bundle: .module)) {
                        Image(systemName: "folder.badge.plus").font(.system(size: StartMetrics.icon - 4)).foregroundStyle(DS.Color.textPrimary)
                    }
                }
                if registry?.isOffered(.projectCloneFromGitHub) ?? true {
                    StartCard(action: .projectCloneFromGitHub, id: .landingCloneProject, title: String(localized: "Clone from GitHub…", bundle: .module),
                              detail: String(localized: "Pick one of your repositories or paste a URL.", bundle: .module)) {
                        Image(systemName: "arrow.down.circle").font(.system(size: StartMetrics.icon - 4)).foregroundStyle(DS.Color.textPrimary)
                    }
                }
                if registry?.isOffered(.sessionNewClean) ?? true {
                    StartCard(action: .sessionNewClean, id: .landingNewCleanSession, title: String(localized: "New Clean Session", bundle: .module),
                              detail: String(localized: "An empty folder, ready for an agent in one click.", bundle: .module)) {
                        Image(systemName: "sparkles").font(.system(size: StartMetrics.icon - 4)).foregroundStyle(DS.Color.textPrimary)
                    }
                }
            }
            if !recent.isEmpty { recentList }
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

    private var recentList: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Recent sessions", bundle: .module).dsFont(DS.Font.sectionLabel).foregroundStyle(DS.Color.textTertiary)
                .padding(.horizontal, DS.Space.s3).padding(.bottom, DS.Space.s1)
            ForEach(recent) { session in
                RecentSessionRow(session: session)
            }
        }
        .frame(width: StartMetrics.column)
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
