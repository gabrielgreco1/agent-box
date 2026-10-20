import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxProtocol
import SwiftUI

/// Settings › General, só com o que a Fatia 1 usa (03 §14.2): background, confirmações, pastas e prefixo de branch.
struct GeneralSettingsView: View {
    let model: SettingsModel

    private var general: AppSettings.General { model.settings.general }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
            SettingsBlock(title: "Background") {
                switchRow("Keep agents running when you quit", help: "Terminals keep running and come back when you reopen Racky.",
                          key: "keepAgentsRunning", isOn: general.keepAgentsRunning, action: .settingsGeneralKeepAgentsRunning)
                if model.backgroundNeedsApproval {
                    SettingsRow(
                        title: "Background agents need approval",
                        help: "Allow Racky in Login Items so your agents keep running after you quit. Until then they keep running only while this Mac session lasts.") {
                        DSButton(
                            .settingsGeneralAllowLoginItems, id: .settings("general", "allowLoginItems"), "Allow in Login Items", variant: .outline)
                    }
                }
                switchRow("Ask before quitting with running agents", help: nil,
                          key: "askBeforeQuit", isOn: general.askBeforeQuit, action: .settingsGeneralAskBeforeQuit)
                switchRow("Resume agents automatically when Racky opens",
                          help: "Agents that stopped while Racky was closed or your Mac restarted continue their conversation.",
                          key: "resumeAgentsOnOpen", isOn: general.resumeAgentsOnOpen, action: .settingsGeneralResumeAgentsOnOpen)
            }
            SettingsBlock(title: "Folders") {
                folderRow("Worktree folder", help: "Where new worktrees are created.", key: "worktreeFolder",
                          action: .settingsGeneralWorktreeFolder, saved: general.worktreeFolder)
                folderRow("Projects folder", help: "Where Clone from GitHub puts new projects.", key: "projectsFolder",
                          action: .settingsGeneralProjectsFolder, saved: general.projectsFolder)
                folderRow("Clean session folder", help: "Where sessions without a project live.", key: "cleanSessionFolder",
                          action: .settingsGeneralCleanSessionFolder, saved: general.cleanSessionFolder)
            }
            SettingsBlock(title: "Branches") {
                SettingsRow(title: "Branch prefix", help: "Added to the name of new branches.") {
                    DSSegmented(
                        [.init("gitUser", "Git user"), .init("custom", "Custom"), .init("none", "None")],
                        selection: general.branchPrefix.rawValue, action: .settingsGeneralBranchPrefix,
                        id: .settings("general", "branchPrefix"))
                }
                if general.branchPrefix == .custom {
                    SettingsRow(title: "Custom prefix", help: "For example name/") {
                        SettingsTextField(
                            id: .settings("general", "branchPrefixCustom"), action: .settingsGeneralBranchPrefixCustom,
                            saved: general.branchPrefixCustom, error: model.fieldErrors["general.branchPrefixCustom"], placeholder: "name/", mono: true)
                    }
                }
            }
            SettingsBlock(title: "Confirmations") {
                switchRow("Confirm before closing a running terminal", help: nil,
                          key: "confirmCloseTerminal", isOn: general.confirmCloseTerminal, action: .settingsGeneralConfirmCloseTerminal)
                switchRow("Confirm before deleting a session", help: nil,
                          key: "confirmDeleteSession", isOn: general.confirmDeleteSession, action: .settingsGeneralConfirmDeleteSession)
                SettingsRow(title: "Reset \"Don't ask again\" choices", help: "Turns every confirmation back on.") {
                    DSButton(.settingsResetConfirmations, id: .settings("general", "resetConfirmations"), "Reset", variant: .outline)
                }
            }
        }
    }

    private func switchRow(_ title: LocalizedStringKey, help: LocalizedStringKey?, key: String, isOn: Bool, action: ActionID) -> some View {
        SettingsRow(title: title, help: help) {
            DSSwitch(isOn: isOn, action: action, id: .settings("general", key), "")
                .accessibilityLabel(Text(title, bundle: .module))
        }
    }

    private func folderRow(_ title: LocalizedStringKey, help: LocalizedStringKey, key: String, action: ActionID, saved: String) -> some View {
        SettingsRow(title: title, help: help) {
            HStack(spacing: DS.Space.s2) {
                SettingsTextField(
                    id: .settings("general", key), action: action, saved: saved, error: model.fieldErrors["general.\(key)"], mono: true)
                DSButton(.settingsPickPath, id: .settings("general", "\(key)Change"), "Change…", variant: .outline, argument: .select(key))
            }
        }
    }
}
