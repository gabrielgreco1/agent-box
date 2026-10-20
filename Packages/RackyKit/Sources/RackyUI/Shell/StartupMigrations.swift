import Foundation
import RackyPlatform
import RackyProtocol
import RackyStore

/// Migrações do nome antigo que precisam rodar ANTES de qualquer outra coisa do app (antes do lock de instância e do banco).
/// Chamado uma vez por `App/main.swift`. Tudo é idempotente e não apaga nada. Com `RACKY_HOME` próprio (testes, evidência) só a
/// promoção de variáveis de ambiente roda: nunca se toca na pasta nem nos defaults reais do usuário.
public enum StartupMigrations {
    @discardableResult
    public static func run() -> Report {
        LegacyEnvironment.promoteProcessEnvironment()
        let environment = ProcessInfo.processInfo.environment
        let log = LogFacade(.app, category: "migration")
        let folder = DataFolderMigration.migrateDefault(environment: environment)
        switch folder {
        case .migrated: log.publicInfo("data folder migrated to the new name")
        case .bothExist: log.publicInfo("both the old and the new data folder exist: using the new one, leaving the old one untouched")
        case .failed(let reason): log.error("data folder migration failed: \(reason)")
        case .notNeeded: break
        }
        var defaults = 0
        if environment["RACKY_HOME"].map({ $0.isEmpty }) ?? true { defaults = LegacyDefaultsMigration.migrate() }
        return Report(dataFolder: folder, defaultsCopied: defaults)
    }

    public struct Report: Sendable, Equatable {
        public var dataFolder: DataFolderMigration.Outcome
        public var defaultsCopied: Int
    }
}
