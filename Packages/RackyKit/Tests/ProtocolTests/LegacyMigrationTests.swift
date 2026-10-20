import Foundation
import Testing

@testable import RackyProtocol

/// Migração da pasta de dados e das variáveis de ambiente do nome antigo. Só diretórios temporários: nunca a pasta real.
@Suite struct DataFolderMigrationTests {
    private func makeSupport() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("racky-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test func movesTheLegacyFolderAndRenamesTheDatabaseFiles() throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let old = support.appendingPathComponent(LegacyNames.dataFolderName)
        try write("db", to: old.appendingPathComponent("db/\(LegacyNames.databaseFileName)"))
        try write("wal", to: old.appendingPathComponent("db/\(LegacyNames.databaseFileName)-wal"))
        try write("shm", to: old.appendingPathComponent("db/\(LegacyNames.databaseFileName)-shm"))
        try write("log", to: old.appendingPathComponent("logs/app.jsonl"))

        #expect(DataFolderMigration.migrate(supportDirectory: support) == .migrated(renamedDatabaseFiles: 3))

        let new = support.appendingPathComponent("Racky")
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(read(new.appendingPathComponent("db/racky.sqlite")) == "db")
        #expect(read(new.appendingPathComponent("db/racky.sqlite-wal")) == "wal")
        #expect(read(new.appendingPathComponent("db/racky.sqlite-shm")) == "shm")
        #expect(read(new.appendingPathComponent("logs/app.jsonl")) == "log")
        #expect(!FileManager.default.fileExists(atPath: new.appendingPathComponent("db/\(LegacyNames.databaseFileName)").path))
    }

    @Test func isIdempotent() throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        try write("db", to: support.appendingPathComponent("\(LegacyNames.dataFolderName)/db/\(LegacyNames.databaseFileName)"))
        _ = DataFolderMigration.migrate(supportDirectory: support)
        #expect(DataFolderMigration.migrate(supportDirectory: support) == .notNeeded)
        #expect(read(support.appendingPathComponent("Racky/db/racky.sqlite")) == "db")
    }

    @Test func usesTheNewFolderWhenBothExistAndTouchesNothing() throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let old = support.appendingPathComponent(LegacyNames.dataFolderName)
        let new = support.appendingPathComponent("Racky")
        try write("old", to: old.appendingPathComponent("db/\(LegacyNames.databaseFileName)"))
        try write("new", to: new.appendingPathComponent("db/racky.sqlite"))

        #expect(DataFolderMigration.migrate(supportDirectory: support) == .bothExist)
        #expect(read(old.appendingPathComponent("db/\(LegacyNames.databaseFileName)")) == "old")
        #expect(read(new.appendingPathComponent("db/racky.sqlite")) == "new")
    }

    @Test func anEmptyNewFolderDoesNotBlockTheMigration() throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        try write("db", to: support.appendingPathComponent("\(LegacyNames.dataFolderName)/db/\(LegacyNames.databaseFileName)"))
        try FileManager.default.createDirectory(at: support.appendingPathComponent("Racky"), withIntermediateDirectories: true)

        #expect(DataFolderMigration.migrate(supportDirectory: support) == .migrated(renamedDatabaseFiles: 1))
        #expect(read(support.appendingPathComponent("Racky/db/racky.sqlite")) == "db")
    }

    @Test func nothingToDoWithoutAnyFolder() throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        #expect(DataFolderMigration.migrate(supportDirectory: support) == .notNeeded)
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("Racky").path))
    }

    @Test func anIsolatedHomeNeverMigrates() {
        #expect(DataFolderMigration.migrateDefault(environment: ["RACKY_HOME": "/tmp/racky-isolated"]) == .notNeeded)
    }
}

@Suite struct LegacyEnvironmentTests {
    @Test func oldNamesBecomeNewNames() {
        let promoted = LegacyEnvironment.promoted(["AGENTBOX_HOME": "/tmp/h", "AGENT_BOX_HOOK_TOKEN": "t", "PATH": "/bin"])
        #expect(promoted["RACKY_HOME"] == "/tmp/h")
        #expect(promoted["RACKY_HOOK_TOKEN"] == "t")
        #expect(promoted["PATH"] == "/bin")
    }

    @Test func theNewNameAlwaysWins() {
        let promoted = LegacyEnvironment.promoted(["AGENTBOX_HOME": "/old", "RACKY_HOME": "/new"])
        #expect(promoted["RACKY_HOME"] == "/new")
    }

    @Test func unrelatedVariablesAreLeftAlone() {
        #expect(LegacyEnvironment.newName(for: "HOME") == nil)
        #expect(LegacyEnvironment.newName(for: "RACKY_HOME") == nil)
        #expect(LegacyEnvironment.newName(for: "AGENTBOX_APP_SOCK") == "RACKY_APP_SOCK")
    }
}
