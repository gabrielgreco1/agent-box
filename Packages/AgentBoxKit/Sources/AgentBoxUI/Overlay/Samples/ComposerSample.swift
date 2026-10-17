import AgentBoxDesignSystem
import AgentBoxProtocol
import Observation
import SwiftUI

/// Amostra do composer "New Session" (03 §6) para exercitar o `OverlayPanelHost`, o `DSCombobox` e o `PromptEditor`.
/// Só é montada com `AGENTBOX_SCREEN=overlay-demo`; o composer de verdade chega com a tarefa do fluxo de sessão.
@MainActor @Observable
public final class ComposerSampleModel {
    public var project = "otter"
    public var whereValue = "newWorktree"
    public var createFrom = ""
    public var agent = "claude"
    public var profile = "claudeSkip"
    public var prompt = "Fix the ArcGIS pagination: the last page is dropped when resultOffset lands on a multiple of maxRecordCount."
    public var createMore = false

    public init() {}

    public var hasData: Bool { !prompt.isEmpty || !createFrom.isEmpty }
}

struct ComposerSampleContent: View {
    let model: ComposerSampleModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.overlayGap) {
            Text("New Session", bundle: .module)
                .dsFont(DS.Font.composerTitle)
                .foregroundStyle(DS.Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                field("Project") {
                    DSCombobox(
                        id: .overlayComposerProject, selection: model.project, entries: Self.projectEntries, action: .composerSetProject,
                        searchPlaceholder: String(localized: "Search projects…", bundle: .module))
                }
                field("Where") {
                    DSSegmented(
                        [.init("newWorktree", "New Worktree"), .init("existingWorktree", "Existing Worktree"), .init("mainCheckout", "Main Checkout")],
                        selection: model.whereValue, action: .composerSetWhere, id: .overlayComposerWhere, fillWidth: true,
                        height: DSMetrics.segmentedHeightComposer)
                }
            }
            .overlayGroup(0)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                field("Create from", hint: "origin/main") {
                    DSTextField("Branch name, #123 or a PR / issue URL", text: Bindable(model).createFrom, id: .overlayComposerCreateFrom, compact: true)
                }
            }
            .overlayGroup(1)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    field("Agent") {
                        DSCombobox(
                            id: .overlayComposerAgent, selection: model.agent, entries: Self.agentEntries, action: .composerSetAgent,
                            searchPlaceholder: String(localized: "Search agents…", bundle: .module))
                    }
                    field("Profile") {
                        DSCombobox(
                            id: .overlayComposerProfile, selection: model.profile, entries: Self.profileEntries, action: .composerSetProfile,
                            searchPlaceholder: String(localized: "Search profiles…", bundle: .module))
                    }
                }
                field("Prompt") {
                    DSPromptField(
                        String(localized: "Describe the task", bundle: .module), text: Bindable(model).prompt, id: .overlayComposerPrompt,
                        action: .composerSetPrompt, submitAction: .composerSubmit, autofocus: true)
                }
                HStack(spacing: DS.Space.s1_5) {
                    Image(systemName: "chevron.right").font(.system(size: DS.Space.s3))
                    Text("Advanced", bundle: .module)
                }
                .dsFont(DS.Font.label)
                .foregroundStyle(DS.Color.textSecondary)
                summary
                footer
            }
            .overlayGroup(2)
        }
        .padding(DSMetrics.overlayPadding)
    }

    // MARK: Itens

    static var projectEntries: [DSMenuEntry] {
        [
            .item(DSMenuItem("otter", "otter", icon: .symbol("folder"), detail: "~/orca/workspaces/otter", detailMono: true, detailInTrigger: true)),
            .item(DSMenuItem("rti-platform", "rti-platform", icon: .symbol("folder"), detail: "~/orca/workspaces/rti-platform", detailMono: true)),
            .separator("projects"),
            .item(DSMenuItem("none", String(localized: "No Project (Clean Session)", bundle: .module), icon: .symbol("sparkles"))),
            .separator("pinned"),
            .item(DSMenuItem("add", String(localized: "Add a New Project…", bundle: .module), icon: .symbol("plus"), pinned: true, action: .composerSetProject)),
        ]
    }

    static var agentEntries: [DSMenuEntry] {
        [
            .item(DSMenuItem("claude", "Claude Code", icon: .agent(.claude))),
            .item(DSMenuItem("codex", "Codex", icon: .agent(.codex))),
            .item(DSMenuItem("opencode", "OpenCode", icon: .agent(.opencode), disabledReason: String(localized: "Not installed", bundle: .module))),
            .separator("agents"),
            .item(DSMenuItem("shell", String(localized: "Blank Terminal", bundle: .module), icon: .agent(.shell))),
            .separator("pinned"),
            .item(DSMenuItem("manage", String(localized: "Manage Agents…", bundle: .module), icon: .symbol("gearshape"), pinned: true, action: .composerManageAgents)),
        ]
    }

    static var profileEntries: [DSMenuEntry] {
        [
            .item(DSMenuItem("claudeSkip", "Claude · Skip permissions", detail: "--dangerously-skip-permissions", detailMono: true)),
            .item(DSMenuItem("claudeDefault", "Claude · Default")),
            .item(DSMenuItem("claudePlan", "Claude · Plan mode", detail: "--permission-mode plan", detailMono: true)),
            .separator("pinned"),
            .item(DSMenuItem("edit", String(localized: "Edit Profiles…", bundle: .module), icon: .symbol("slider.horizontal.3"), pinned: true, action: .composerEditProfiles)),
        ]
    }

    // MARK: Peças

    private func field(_ title: LocalizedStringKey, hint: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            HStack {
                Text(title, bundle: .module)
                    .dsFont(DS.Font.label)
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer(minLength: DS.Space.s2)
                if let hint {
                    HStack(spacing: DS.Space.s1) {
                        Text(verbatim: hint)
                        Image(systemName: "chevron.down").font(.system(size: DS.Space.s2, weight: .medium))
                    }
                    .dsFont(DS.Font.monoMicro)
                    .foregroundStyle(DS.Color.textTertiary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        Text(verbatim: "claude --dangerously-skip-permissions \"Fix the ArcGIS pagination…\" in ~/orca/workspaces/otter/fix-arcgis-pagination")
            .dsFont(DS.Font.monoMicro)
            .foregroundStyle(DS.Color.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s2) {
            DSSwitch(isOn: model.createMore, action: .composerCreateMore, id: .overlayComposerCreateMore, "Create More", compact: true)
            Spacer(minLength: DS.Space.s2)
            DSButton(.composerCancel, id: .overlayComposerCancel, "Cancel", variant: .outline, size: .compact, keycap: "esc")
            DSButton(.composerSubmit, id: .overlayComposerSubmit, "Create Session", variant: .primary, size: .compact, keycap: "⌘↵")
                .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

public extension OverlaySpec {
    static func composerSample(_ model: ComposerSampleModel) -> OverlaySpec {
        OverlaySpec(
            name: "composer", id: .overlayComposer, width: DS.Layout.composerWidth, cancelAction: .composerCancel,
            dismissOnScrim: { !model.hasData },
            content: { AnyView(ComposerSampleContent(model: model)) })
    }
}
