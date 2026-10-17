import AgentBoxProtocol
import Foundation
import GRDB

/// Registro de uma execução de importador (08 AR-340, tabela `import_run`).
public struct ImportRun: Sendable, Equatable, Identifiable {
    public enum Source: String, Sendable, CaseIterable { case agentboxJSON = "agentbox_json", orca, agentboxCLI = "agentbox_cli" }

    public var id: UUID
    public var source: Source
    public var sourcePath: String
    public var sourceFingerprint: String?
    public var dryRun: Bool
    public var status: String
    public var summaryJSON: String
    public var startedAt: Date
    public var finishedAt: Date?

    public init(id: UUID = .v7(), source: Source, sourcePath: String, sourceFingerprint: String? = nil, dryRun: Bool = false,
                status: String, summaryJSON: String = "{}", startedAt: Date, finishedAt: Date? = nil) {
        self.id = id; self.source = source; self.sourcePath = sourcePath; self.sourceFingerprint = sourceFingerprint
        self.dryRun = dryRun; self.status = status; self.summaryJSON = summaryJSON
        self.startedAt = startedAt; self.finishedAt = finishedAt
    }
}

extension AgentBoxStore {
    public func record(_ run: ImportRun) async throws {
        let finishedDate: Date? = run.finishedAt
        let finished: Int64? = RowCodec.ms(finishedDate)
        let started: Int64 = RowCodec.ms(run.startedAt as Date)
        let args: StatementArguments = [
            run.id.uuidString, run.source.rawValue, run.sourcePath, run.sourceFingerprint, run.dryRun ? 1 : 0, run.status,
            run.summaryJSON, started, finished,
        ]
        try await write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO import_run
                (id, source, source_path, source_fingerprint, dry_run, status, summary_json, started_at, finished_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: args)
        }
    }

    /// Mais recentes primeiro.
    public func importRuns(source: ImportRun.Source) async throws -> [ImportRun] {
        let raw = source.rawValue
        return try await read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM import_run WHERE source = ? ORDER BY started_at DESC", arguments: [raw]).compactMap { row in
                guard let id = UUID(uuidString: row["id"] as String), let src = ImportRun.Source(rawValue: row["source"] as String) else { return nil }
                let started: Int64 = row["started_at"]
                let finished: Int64? = row["finished_at"]
                let dry: Int = row["dry_run"]
                return ImportRun(
                    id: id, source: src, sourcePath: row["source_path"], sourceFingerprint: row["source_fingerprint"],
                    dryRun: dry != 0, status: row["status"], summaryJSON: row["summary_json"],
                    startedAt: RowCodec.date(started), finishedAt: RowCodec.date(finished))
            }
        }
    }
}
