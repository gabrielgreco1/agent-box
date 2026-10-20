import Foundation
import RackyProtocol

/// Pastas de trabalho padrão do nome antigo (`~/AgentBox/{worktrees,sessions,projects}`).
///
/// - Quem já salvou as configurações tem o caminho gravado por extenso: o decode o mantém (nada muda para essa pessoa, e um
///   caminho personalizado também continua valendo).
/// - Quem nunca salvou nada (sem linha no banco) recebe os padrões novos (`~/Racky/...`), SALVO se a pasta antiga já existe em
///   disco e a nova não: nesse caso o padrão antigo é mantido por extenso, para os worktrees e sessões já criados continuarem
///   dentro da pasta que a configuração aponta.
/// - Nenhuma pasta de trabalho é movida ou apagada. Sessões existentes seguem com o caminho absoluto que o banco guarda.
public enum LegacyDefaultFolders {
    /// `exists`: injetável para teste (padrão: o disco).
    public static func applying(
        to general: AppSettings.General, home: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> AppSettings.General {
        var result = general
        func adjust(_ keyPath: WritableKeyPath<AppSettings.General, String>, _ folder: String) {
            let new = home.appendingPathComponent("Racky/\(folder)", isDirectory: true)
            let old = home.appendingPathComponent("\(LegacyNames.userFolderName)/\(folder)", isDirectory: true)
            if result[keyPath: keyPath] == "~/Racky/\(folder)", exists(old), !exists(new) {
                result[keyPath: keyPath] = "~/\(LegacyNames.userFolderName)/\(folder)"
            }
        }
        adjust(\.worktreeFolder, "worktrees")
        adjust(\.cleanSessionFolder, "sessions")
        adjust(\.projectsFolder, "projects")
        return result
    }
}
