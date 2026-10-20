import RackyCore
import RackyDesignSystem
import RackyProtocol
import SwiftUI

/// Settings › Computers (03 §14.2, F12): o padrão de "Subagent computers" das sessões novas e o estado do Docker e das imagens.
struct ComputersSettingsView: View {
    let model: SettingsModel

    private var mode: SubagentComputersMode { model.settings.computers.defaultSubagentMode }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
            SettingsBlock(title: "Subagents") {
                SettingsRow(title: "Subagent computers", help: "Default for new sessions. Sessions you already have keep theirs.") {
                    DSSegmented(
                        SubagentComputersMode.allCases.map { .init($0.rawValue, $0.segmentTitle) }, selection: mode.rawValue,
                        action: .settingsComputersDefaultSubagentMode, id: .settings("computers", "defaultSubagentMode"))
                }
                Text(verbatim: mode.explanation)
                    .dsFont(DS.Font.small)
                    .foregroundStyle(DS.Color.textTertiary)
                    .id(mode)
                    .transition(.opacity)
                    .animation(MotionPolicy.shared.animation(MotionTokens.Easing.standard, MotionTokens.Duration.base), value: mode)
            }
            ProxiesSettingsBlock(model: model)
            SettingsBlock(title: "Docker") {
                SettingsRow(title: "Status", help: "Computers run in containers. The first one builds its images in the background.") {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: model.dockerStatus.text)
                            .dsFont(DS.Font.small)
                            .foregroundStyle(model.dockerStatus.stopped ? DS.Color.warning : DS.Color.textSecondary)
                            .lineLimit(1)
                        if model.dockerStatus.stopped {
                            DSButton(.dockerStart, id: .settings("computers", "openDocker"), "Open Docker", variant: .outline)
                        }
                    }
                }
            }
        }
    }
}

/// O que o Settings mostra do Docker e das imagens (alimentado pelo orquestrador).
struct DockerStatusInfo: Equatable {
    var text = String(localized: "Starts when a subagent needs a computer.", bundle: .module)
    var stopped = false
}
