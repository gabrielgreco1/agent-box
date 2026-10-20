import Foundation
import Testing

@testable import RackyCore

/// Pastas padrão do nome antigo: configurações salvas valem como estão; quem nunca salvou mantém `~/AgentBox/...` só se a pasta
/// antiga já existe e a nova não. Nada é movido.
@Suite struct LegacyDefaultFoldersTests {
    private let home = URL(fileURLWithPath: "/Users/x", isDirectory: true)

    @Test func newInstallsGetTheNewDefaults() {
        let general = LegacyDefaultFolders.applying(to: AppSettings.General(), home: home, exists: { _ in false })
        #expect(general.worktreeFolder == "~/Racky/worktrees")
        #expect(general.cleanSessionFolder == "~/Racky/sessions")
        #expect(general.projectsFolder == "~/Racky/projects")
    }

    @Test func anExistingOldFolderKeepsTheOldDefaultForThatFolderOnly() {
        let general = LegacyDefaultFolders.applying(
            to: AppSettings.General(), home: home, exists: { $0.path == "/Users/x/AgentBox/worktrees" })
        #expect(general.worktreeFolder == "~/AgentBox/worktrees")
        #expect(general.cleanSessionFolder == "~/Racky/sessions")
    }

    @Test func ifTheNewFolderAlreadyExistsTheNewDefaultStays() {
        let general = LegacyDefaultFolders.applying(to: AppSettings.General(), home: home, exists: { _ in true })
        #expect(general.worktreeFolder == "~/Racky/worktrees")
    }

    @Test func aCustomPathIsNeverTouched() {
        var general = AppSettings.General()
        general.worktreeFolder = "~/code/trees"
        let result = LegacyDefaultFolders.applying(to: general, home: home, exists: { _ in true })
        #expect(result.worktreeFolder == "~/code/trees")
    }

    @Test func aSavedLegacyPathSurvivesDecoding() throws {
        let json = #"{"general":{"worktreeFolder":"~/AgentBox/worktrees","cleanSessionFolder":"/Volumes/work/sessions"}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.general.worktreeFolder == "~/AgentBox/worktrees")
        #expect(settings.general.cleanSessionFolder == "/Volumes/work/sessions")
        #expect(settings.general.projectsFolder == "~/Racky/projects", "o que nunca foi salvo recebe o padrão novo")
    }
}
