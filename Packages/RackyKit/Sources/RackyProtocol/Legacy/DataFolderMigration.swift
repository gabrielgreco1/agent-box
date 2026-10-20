import Darwin
import Foundation

/// Migra a pasta de dados do nome antigo para `~/Library/Application Support/Racky` com UM `rename(2)` (atômico no mesmo
/// volume), antes de abrir o banco ou o lock de instância. Nunca apaga nada; nunca mexe nas pastas de trabalho do usuário.
///
/// Regras:
/// - só a antiga existe: renomeia a pasta e depois os arquivos do banco (`db/<antigo>.sqlite{,-wal,-shm}`);
/// - só a nova existe, ou nenhuma: nada a fazer;
/// - as duas existem: usa a nova (a antiga fica intocada) e devolve `.bothExist` para o chamador registrar;
///   uma pasta nova VAZIA (criada por um instalador, por exemplo) é removida e a migração segue.
public enum DataFolderMigration {
    public enum Outcome: Sendable, Equatable {
        case notNeeded
        case migrated(renamedDatabaseFiles: Int)
        case bothExist
        case failed(String)
    }

    private static let databaseSuffixes = ["", "-wal", "-shm"]

    /// `supportDirectory` = `~/Library/Application Support` (ou um temporário nos testes).
    public static func migrate(supportDirectory: URL, fileManager: FileManager = .default) -> Outcome {
        let old = supportDirectory.appendingPathComponent(LegacyNames.dataFolderName, isDirectory: true)
        let new = supportDirectory.appendingPathComponent("Racky", isDirectory: true)
        // Volume case-insensitive: nomes diferentes, então um não é o outro. Ainda assim, nunca renomear para si mesmo.
        guard old.path.lowercased() != new.path.lowercased() else { return .notNeeded }

        var oldIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: old.path, isDirectory: &oldIsDirectory), oldIsDirectory.boolValue else { return .notNeeded }

        if fileManager.fileExists(atPath: new.path) {
            // `rmdir` só remove diretório vazio: a pasta nova com conteúdo nunca é tocada.
            guard rmdir(new.path) == 0 else { return .bothExist }
        }
        guard rename(old.path, new.path) == 0 else {
            let code = errno
            if code == EEXIST || code == ENOTEMPTY { return .bothExist }  // outro processo migrou na frente
            if code == ENOENT, fileManager.fileExists(atPath: new.path) { return .notNeeded }
            return .failed(String(cString: strerror(code)))
        }
        return .migrated(renamedDatabaseFiles: renameDatabaseFiles(in: new.appendingPathComponent("db", isDirectory: true), fileManager: fileManager))
    }

    /// Pasta de dados real do usuário. Com `RACKY_HOME` (testes, evidência, dev isolado) não faz nada.
    @discardableResult
    public static func migrateDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> Outcome {
        if let home = environment["RACKY_HOME"], !home.isEmpty { return .notNeeded }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return .notNeeded }
        return migrate(supportDirectory: support)
    }

    private static func renameDatabaseFiles(in directory: URL, fileManager: FileManager) -> Int {
        var renamed = 0
        for suffix in databaseSuffixes {
            let from = directory.appendingPathComponent(LegacyNames.databaseFileName + suffix)
            let to = directory.appendingPathComponent("racky.sqlite" + suffix)
            guard fileManager.fileExists(atPath: from.path), !fileManager.fileExists(atPath: to.path) else { continue }
            if rename(from.path, to.path) == 0 { renamed += 1 }
        }
        return renamed
    }
}
