import AgentBoxStore
import Foundation
import Testing
@testable import AgentBoxCore

/// Dry-run contra o Orca REAL da máquina (só com `AGENTBOX_REAL_ORCA=1`). Lê por cópia temporária, usa um Store
/// temporário e grava só contagens e nomes de repositórios/worktrees em `AGENTBOX_REAL_ORCA_OUT` (nenhum valor de
/// configuração, nota, comentário, env ou caminho de usuário).
@Suite struct RealOrcaDryRunTests {
    struct Evidence: Codable {
        var source: String
        var repositories: Int
        var worktreeEntriesInOrca: Int
        var projects: [String: [String]]
        var skippedProjects: [String]
        var sessionsByProject: [String: [String]]
        var sessionsToImport: Int
        var sessionsSkipped: Int
        var worktreesWithoutMeta: Int
        var profiles: [String]
        var envKeysByAgent: [String: [String]]
        var ignoredAgents: [String]
        var notes: [String]
        var originalProfileFilesUntouchedByReader: Bool
        var tempDirectoryEmptyAfterwards: Bool
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AGENTBOX_REAL_ORCA"] == "1"))
    func dryRunAgainstRealOrca() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("orca-dryrun-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let store = try await AgentBoxStore.open(paths: StorePaths(root: tempRoot.appendingPathComponent("home")))
        let importer = OrcaImporter(store: store, tempRoot: tempRoot.appendingPathComponent("copies", isDirectory: true))
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("copies"), withIntermediateDirectories: true)
        let profile = try #require(importer.profiles().first)

        // Metadados dos arquivos do Orca antes e depois (tamanho e mtime): a leitura não pode alterá-los. O Orca está em uso,
        // então a comparação cobre só o intervalo da leitura.
        func fingerprint() -> [String: String] {
            var result: [String: String] = [:]
            for name in ["profile-state.db", "profile-state.db-wal", "profile-state.db-shm", "orca-data.json"] {
                let path = profile.directory.appendingPathComponent(name).path
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                    result[name] = "\(attrs[.size] ?? 0)/\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
                }
            }
            return result
        }
        let before = fingerprint()
        let report = try await importer.dryRun(profile: profile)
        let after = fingerprint()

        var projects: [String: [String]] = [:]
        projects["toImport"] = report.projects.filter { $0.outcome == .imported }.map(\.name)
        var byProject: [String: [String]] = [:]
        for s in report.sessions where s.outcome == .imported { byProject[s.detail ?? "?", default: []].append(s.name) }
        let detection = try importer.detect(profile: profile)
        let evidence = Evidence(
            source: report.source.rawValue, repositories: detection.repositories, worktreeEntriesInOrca: detection.worktreeEntries,
            projects: projects, skippedProjects: report.projects.filter { $0.outcome == .skipped }.map(\.name),
            sessionsByProject: byProject, sessionsToImport: report.sessionsImported,
            sessionsSkipped: report.sessions.filter { $0.outcome == .skipped }.count,
            worktreesWithoutMeta: report.worktreesWithoutMeta, profiles: report.profiles.map(\.name),
            envKeysByAgent: report.envKeys, ignoredAgents: report.ignoredAgents, notes: report.notes,
            originalProfileFilesUntouchedByReader: before == after,
            tempDirectoryEmptyAfterwards: ((try? FileManager.default.contentsOfDirectory(atPath: tempRoot.appendingPathComponent("copies").path)) ?? ["?"]).isEmpty)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(evidence)
        if let out = ProcessInfo.processInfo.environment["AGENTBOX_REAL_ORCA_OUT"] {
            try data.write(to: URL(fileURLWithPath: out))
        }
        #expect(report.dryRun && evidence.tempDirectoryEmptyAfterwards)
        #expect(try await store.projects(includeArchived: true).isEmpty, "dry-run não grava")
    }
}
