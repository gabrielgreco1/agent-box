import Foundation
import Testing

@testable import RackyCore

/// `Import from racky CLI…`: o `.env` fica em `~/.racky/.env`; quem ainda tem só a pasta do CLI de antes do rename continua importando.
@Suite struct LegacyCLIEnvFileTests {
    private func makeHome(files: [String]) throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("racky-cli-env-\(UUID().uuidString)", isDirectory: true)
        for file in files {
            let url = home.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("ZYTE_API_KEY=k\n".utf8).write(to: url)
        }
        return home
    }

    @Test func prefersTheNewFolder() throws {
        let home = try makeHome(files: [".racky/.env", ".agentbox/.env"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(ProxyService.defaultCLIEnvFile(home: home).path == home.appendingPathComponent(".racky/.env").path)
    }

    @Test func fallsBackToTheFolderOfTheCLIFromBeforeTheRename() throws {
        let home = try makeHome(files: [".agentbox/.env"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(ProxyService.defaultCLIEnvFile(home: home).path == home.appendingPathComponent(".agentbox/.env").path)
    }

    @Test func pointsAtTheNewFolderWhenNeitherExists() throws {
        let home = try makeHome(files: [])
        #expect(ProxyService.defaultCLIEnvFile(home: home).path == home.appendingPathComponent(".racky/.env").path)
    }
}
