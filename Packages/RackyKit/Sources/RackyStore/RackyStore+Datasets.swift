import Foundation
import GRDB

// Datasets v1 (`v10_datasets`): tabelas nomeadas que os subagentes de uma sessão preenchem. O store só guarda e deduplica; validação,
// coerção de tipos e hash da chave moram em RackyCore (`DatasetEngine`), que entrega as linhas já prontas (`DatasetRowInput`).

public enum DatasetColumnType: String, Sendable, Codable, CaseIterable {
    case string, integer, number, boolean, date, datetime, url, json
}

public struct DatasetColumn: Sendable, Codable, Equatable, Hashable {
    public var name: String
    public var type: DatasetColumnType
    public var required: Bool
    public init(name: String, type: DatasetColumnType = .string, required: Bool = false) {
        self.name = name; self.type = type; self.required = required
    }
}

public struct Dataset: Sendable, Equatable, Identifiable {
    /// ULID.
    public var id: String
    public var sessionID: UUID
    public var name: String
    public var columns: [DatasetColumn]
    /// Nomes das colunas da chave; vazio = a linha inteira é a chave.
    public var key: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: String, sessionID: UUID, name: String, columns: [DatasetColumn], key: [String], createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id; self.sessionID = sessionID; self.name = name; self.columns = columns; self.key = key
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }
}

/// Confiança da origem da linha: `observed` (o egress viu a página), `reported` (o agente disse) ou `none` (sem request id).
public enum DatasetTrust: String, Sendable, Codable, CaseIterable {
    case observed, reported, none
}

/// Linha pronta para o upsert (o core já validou e calculou `rowKey`).
public struct DatasetRowInput: Sendable, Equatable {
    public var rowKey: String
    /// Objeto JSON só com as colunas do dataset.
    public var data: String
    public var valid: Bool
    public var error: String?
    public var computer: String?
    public var runID: String?
    public var requestID: String?
    public var sourceURL: String?
    public var trust: DatasetTrust

    public init(
        rowKey: String, data: String, valid: Bool = true, error: String? = nil, computer: String? = nil, runID: String? = nil,
        requestID: String? = nil, sourceURL: String? = nil, trust: DatasetTrust = .none
    ) {
        self.rowKey = rowKey; self.data = data; self.valid = valid; self.error = error; self.computer = computer; self.runID = runID
        self.requestID = requestID; self.sourceURL = sourceURL; self.trust = trust
    }
}

public struct DatasetRow: Sendable, Equatable, Identifiable {
    public var id: String { rowKey }
    public var rowKey: String
    public var data: String
    public var valid: Bool
    public var error: String?
    public var computer: String?
    public var runID: String?
    public var requestID: String?
    public var sourceURL: String?
    public var trust: DatasetTrust
    public var firstSeen: Date
    public var lastSeen: Date
    public var seenCount: Int

    public init(
        rowKey: String, data: String, valid: Bool = true, error: String? = nil, computer: String? = nil, runID: String? = nil, requestID: String? = nil,
        sourceURL: String? = nil, trust: DatasetTrust = .none, firstSeen: Date, lastSeen: Date, seenCount: Int = 1
    ) {
        self.rowKey = rowKey; self.data = data; self.valid = valid; self.error = error; self.computer = computer; self.runID = runID
        self.requestID = requestID; self.sourceURL = sourceURL; self.trust = trust; self.firstSeen = firstSeen; self.lastSeen = lastSeen; self.seenCount = seenCount
    }
}

public struct DatasetUpsertCounts: Sendable, Equatable {
    public var inserted = 0
    public var updated = 0
    public var duplicate = 0
    public init(inserted: Int = 0, updated: Int = 0, duplicate: Int = 0) { self.inserted = inserted; self.updated = updated; self.duplicate = duplicate }
}

/// Uma linha da lista de datasets (contagens vêm de uma consulta só).
public struct DatasetSummary: Sendable, Equatable, Identifiable {
    public var dataset: Dataset
    public var rowCount: Int
    public var invalidCount: Int
    public var id: String { dataset.id }
    public init(dataset: Dataset, rowCount: Int, invalidCount: Int) { self.dataset = dataset; self.rowCount = rowCount; self.invalidCount = invalidCount }
}

public enum DatasetRowFilter: String, Sendable, CaseIterable {
    case all, invalid
}

extension Dataset {
    fileprivate init(row: Row) throws {
        guard let session = UUID(uuidString: row["session_id"] as String) else { throw StoreError.invalidRow(table: "dataset", detail: "bad session id") }
        self.init(
            id: row["id"], sessionID: session, name: row["name"],
            columns: try RowCodec.decode([DatasetColumn].self, row["columns"], table: "dataset"),
            key: try RowCodec.decode([String].self, row["key"], table: "dataset"),
            createdAt: RowCodec.date(row["created_at"] as Int64), updatedAt: RowCodec.date(row["updated_at"] as Int64) as Date)
    }
}

extension DatasetRow {
    fileprivate init(row: Row) throws {
        let trust = row["trust"] as String? ?? "none"
        guard let parsed = DatasetTrust(rawValue: trust) else { throw StoreError.invalidRow(table: "dataset_row", detail: "bad trust \(trust)") }
        self.init(
            rowKey: row["row_key"], data: row["data"], valid: (row["valid"] as Int) == 1, error: row["error"], computer: row["computer"],
            runID: row["run_id"], requestID: row["request_id"], sourceURL: row["source_url"], trust: parsed,
            firstSeen: RowCodec.date(row["first_seen"] as Int64), lastSeen: RowCodec.date(row["last_seen"] as Int64), seenCount: row["seen_count"])
    }
}

/// `LIKE` sem curinga: escapa `%`, `_` e a barra (o `ESCAPE '\\'` vem na consulta).
private func likePattern(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    return "%" + escaped + "%"
}

extension RackyStore {
    // MARK: Esquema

    public func createDataset(_ dataset: Dataset) async throws {
        let columns = try RowCodec.json(dataset.columns), key = try RowCodec.json(dataset.key)
        try await write { db in
            try db.execute(
                sql: "INSERT INTO dataset (id, session_id, name, columns, key, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                arguments: [dataset.id, dataset.sessionID.uuidString, dataset.name, columns, key, RowCodec.ms(dataset.createdAt) as Int64, RowCodec.ms(dataset.updatedAt) as Int64])
        }
    }

    /// Troca colunas e chave (o core decide o que pode mudar; o store só grava).
    public func updateDatasetSchema(id: String, columns: [DatasetColumn], key: [String], at date: Date? = nil) async throws {
        let columns = try RowCodec.json(columns), key = try RowCodec.json(key)
        let ms = RowCodec.ms(date ?? clock()) as Int64
        try await write { db in
            try db.execute(sql: "UPDATE dataset SET columns = ?, key = ?, updated_at = ? WHERE id = ?", arguments: [columns, key, ms, id])
        }
    }

    public func dataset(id: String) async throws -> Dataset? {
        try await read { db in try Row.fetchOne(db, sql: "SELECT * FROM dataset WHERE id = ?", arguments: [id]).map { try Dataset(row: $0) } }
    }

    public func dataset(sessionID: UUID, name: String) async throws -> Dataset? {
        let session = sessionID.uuidString
        return try await read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM dataset WHERE session_id = ? AND name = ?", arguments: [session, name]).map { try Dataset(row: $0) }
        }
    }

    /// Resumos (com contagens) de todos os datasets, ou só os de uma sessão; os mais recentes primeiro.
    public func datasetSummaries(sessionID: UUID? = nil) async throws -> [DatasetSummary] {
        let session = sessionID?.uuidString
        return try await read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT d.*, COUNT(r.row_key) AS row_count, COALESCE(SUM(1 - r.valid), 0) AS invalid_count FROM dataset d
                LEFT JOIN dataset_row r ON r.dataset_id = d.id
                WHERE (?1 IS NULL OR d.session_id = ?1) GROUP BY d.id ORDER BY d.updated_at DESC, d.id DESC
                """, arguments: [session]
            ).map { DatasetSummary(dataset: try Dataset(row: $0), rowCount: $0["row_count"], invalidCount: $0["invalid_count"]) }
        }
    }

    public func datasetSummary(id: String) async throws -> DatasetSummary? {
        try await datasetSummaries().first { $0.dataset.id == id }
    }

    // MARK: Linhas

    /// Upsert por `rowKey` numa transação: igual = `duplicate` (só `last_seen` e `seen_count`), dado diferente = `updated`
    /// (troca dado, validade e proveniência; mantém `first_seen`), chave nova = `inserted`.
    public func upsertDatasetRows(datasetID: String, rows: [DatasetRowInput], at date: Date? = nil) async throws -> DatasetUpsertCounts {
        let now = RowCodec.ms(date ?? clock()) as Int64
        return try await write { db in
            var counts = DatasetUpsertCounts()
            for row in rows {
                let existing = try Row.fetchOne(db, sql: "SELECT data, valid, error FROM dataset_row WHERE dataset_id = ? AND row_key = ?", arguments: [datasetID, row.rowKey])
                if let existing {
                    let same = (existing["data"] as String) == row.data && ((existing["valid"] as Int) == 1) == row.valid
                    if same {
                        try db.execute(
                            sql: "UPDATE dataset_row SET last_seen = ?, seen_count = seen_count + 1 WHERE dataset_id = ? AND row_key = ?", arguments: [now, datasetID, row.rowKey])
                        counts.duplicate += 1
                    } else {
                        try db.execute(
                            sql: """
                            UPDATE dataset_row SET data = ?, valid = ?, error = ?, computer = ?, run_id = ?, request_id = ?, source_url = ?, trust = ?,
                                last_seen = ?, seen_count = seen_count + 1 WHERE dataset_id = ? AND row_key = ?
                            """,
                            arguments: [row.data, row.valid ? 1 : 0, row.error, row.computer, row.runID, row.requestID, row.sourceURL, row.trust.rawValue, now, datasetID, row.rowKey])
                        counts.updated += 1
                    }
                } else {
                    try db.execute(
                        sql: """
                        INSERT INTO dataset_row (dataset_id, row_key, data, valid, error, computer, run_id, request_id, source_url, trust, first_seen, last_seen, seen_count)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                        """,
                        arguments: [datasetID, row.rowKey, row.data, row.valid ? 1 : 0, row.error, row.computer, row.runID, row.requestID, row.sourceURL, row.trust.rawValue, now, now])
                    counts.inserted += 1
                }
            }
            if !rows.isEmpty { try db.execute(sql: "UPDATE dataset SET updated_at = ? WHERE id = ?", arguments: [now, datasetID]) }
            return counts
        }
    }

    /// Linhas por ordem de chegada (`rowid`), com filtro de validade e busca de texto no dado e na URL de origem.
    public func datasetRows(datasetID: String, filter: DatasetRowFilter = .all, search: String? = nil, limit: Int = 1000, offset: Int = 0) async throws -> [DatasetRow] {
        try await read { db in
            var sql = "SELECT * FROM dataset_row WHERE dataset_id = ?"
            var arguments: StatementArguments = [datasetID]
            if filter == .invalid { sql += " AND valid = 0" }
            if let search, !search.isEmpty {
                sql += " AND (data LIKE ? ESCAPE '\\' OR COALESCE(source_url, '') LIKE ? ESCAPE '\\')"
                arguments += [likePattern(search), likePattern(search)]
            }
            sql += " ORDER BY rowid LIMIT ? OFFSET ?"
            arguments += [limit, offset]
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map { try DatasetRow(row: $0) }
        }
    }

    /// Total que casa o filtro e a busca (a paginação da UI e o "n of m").
    public func datasetRowCount(datasetID: String, filter: DatasetRowFilter = .all, search: String? = nil) async throws -> Int {
        try await read { db in
            var sql = "SELECT COUNT(*) FROM dataset_row WHERE dataset_id = ?"
            var arguments: StatementArguments = [datasetID]
            if filter == .invalid { sql += " AND valid = 0" }
            if let search, !search.isEmpty {
                sql += " AND (data LIKE ? ESCAPE '\\' OR COALESCE(source_url, '') LIKE ? ESCAPE '\\')"
                arguments += [likePattern(search), likePattern(search)]
            }
            return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    public func datasetRow(datasetID: String, rowKey: String) async throws -> DatasetRow? {
        try await read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM dataset_row WHERE dataset_id = ? AND row_key = ?", arguments: [datasetID, rowKey]).map { try DatasetRow(row: $0) }
        }
    }

    public func deleteDataset(id: String) async throws {
        try await write { db in try db.execute(sql: "DELETE FROM dataset WHERE id = ?", arguments: [id]) }
    }
}
