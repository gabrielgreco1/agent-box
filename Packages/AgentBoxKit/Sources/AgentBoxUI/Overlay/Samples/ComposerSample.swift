import AgentBoxDesignSystem
import AgentBoxProtocol
import Observation
import SwiftUI

/// Amostra do composer "New Session" (03 §6) para exercitar o `OverlayPanelHost` e comparar M-101 com o protótipo.
/// Só é montada com `AGENTBOX_SCREEN=overlay-demo`; o composer de verdade chega com a tarefa do fluxo de sessão.
/// Os seletores (Project, Agent, Profile) são fachadas estáticas até o `DSCombobox` (T1-12).
@MainActor @Observable
public final class ComposerSampleModel {
    public var whereValue = "newWorktree"
    public var createFrom = ""
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
                field("Project") { fauxSelect(symbol: "folder", text: "otter", detail: "~/orca/workspaces/otter") }
                field("Where") {
                    DSSegmented(
                        [.init("newWorktree", "New Worktree"), .init("existingWorktree", "Existing Worktree"), .init("mainCheckout", "Main Checkout")],
                        selection: model.whereValue, action: .composerSetWhere, id: .overlayComposerWhere)
                }
            }
            .overlayGroup(0)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                field("Create from") {
                    DSTextField("Branch name, #123 or a PR / issue URL", text: Bindable(model).createFrom, id: .overlayComposerCreateFrom)
                }
            }
            .overlayGroup(1)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    field("Agent") { fauxSelect(symbol: nil, provider: .claude, text: "Claude Code", detail: nil) }
                    field("Profile") { fauxSelect(symbol: nil, text: "Claude · Skip permissions", detail: nil) }
                }
                field("Prompt") {
                    DSTextField(
                        "Describe the task", text: Bindable(model).prompt, id: .overlayComposerPrompt, action: .composerSetPrompt,
                        multiline: true, autofocus: true)
                }
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: "chevron.right").font(.system(size: DS.Space.s3))
                    Text("Advanced", bundle: .module)
                }
                .dsFont(DS.Font.label)
                .foregroundStyle(DS.Color.textSecondary)
                footer
            }
            .overlayGroup(2)
        }
        .padding(DSMetrics.overlayPadding)
    }

    private func field(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
            Text(title, bundle: .module)
                .dsFont(DS.Font.label)
                .foregroundStyle(DS.Color.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fauxSelect(symbol: String?, provider: TerminalProvider? = nil, text: String, detail: String?) -> some View {
        HStack(spacing: DS.Space.s2) {
            if let provider { DSAgentLogo(provider, size: DS.Space.s3 + DS.Space.s0_5) }
            if let symbol { Image(systemName: symbol).font(.system(size: DS.Space.s3 + DS.Space.s0_5)).foregroundStyle(DS.Color.textSecondary) }
            Text(verbatim: text).dsFont(DS.Font.input).foregroundStyle(DS.Color.textPrimary)
            if let detail { Text(verbatim: detail).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary) }
            Spacer(minLength: .zero)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: DS.Space.s3 + DS.Space.s0_5)).foregroundStyle(DS.Color.textSecondary)
        }
        .dsFieldChrome()
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s2) {
            DSSwitch(isOn: model.createMore, action: .composerCreateMore, id: .overlayComposerCreateMore, "Create More")
            Spacer(minLength: DS.Space.s2)
            DSButton(.composerCancel, id: .overlayComposerCancel, "Cancel", variant: .outline, size: .sm, keycap: "⎋")
            DSButton(.composerSubmit, id: .overlayComposerSubmit, "Create Session", variant: .primary, size: .sm, keycap: "⌘↵")
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
