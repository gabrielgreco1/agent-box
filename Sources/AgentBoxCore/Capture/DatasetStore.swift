import Darwin
import Foundation

public struct DatasetRow: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let values: [String: CaptureScalar]
    public let missingReasons: [String: String]
    public let captureID: UUID
    public let captureRecordID: UUID
    public let evidenceSHA256: String
    public let duplicateCount: Int
    public let sourceURL: String
    public let sourceTimestamp: String
    public let identity: CaptureIdentity
}

public struct Dataset: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let computerID: UUID
    public let name: String
    public let columns: [String]
    public let rows: [DatasetRow]
    public let createdAt: Date
}

public enum DatasetExportFormat: String, Codable, Sendable {
    case csv, json
}

public struct DatasetExport: Equatable, Sendable {
    public let dataURL: URL
    public let manifestURL: URL
    public let format: DatasetExportFormat
    public let rowCount: Int
    public let sha256: String
}

public struct DatasetExportManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let datasetID: UUID
    public let exportedAt: Date
    public let format: DatasetExportFormat
    public let rowCount: Int
    public let dataSHA256: String
    public let evidenceSHA256: [String]
}

public actor DatasetStore {
    private static let reservedCSVColumns = ["capture_id", "capture_record_id", "evidence_sha256",
        "duplicate_count", "source_url", "source_timestamp", "session_id", "terminal_id",
        "owner_run_id", "computer_id"]
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL = AppPaths.applicationSupport.appendingPathComponent("Results", isDirectory: true)) throws {
        self.directory = directory
        try CaptureDisk.ensureDirectory(directory)
    }

    private func file(_ id: UUID) -> URL {
        directory.appendingPathComponent("dataset-\(id.uuidString.lowercased()).json")
    }

    public func create(name: String, columns: [String], from captures: [CaptureRecord]) throws -> Dataset {
        try CaptureDisk.ensureDirectory(directory)
        let existingFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("dataset-") && $0.hasSuffix(".json") }
        guard existingFiles.count < 100 else { throw CaptureError.quotaExceeded }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allHeaders = Self.reservedCSVColumns + columns + columns.map { "\($0)__missing_reason" }
        guard !title.isEmpty, title.utf8.count <= 160, !title.contains("\0"),
              !columns.isEmpty, columns.count <= 64, Set(columns).count == columns.count,
              Set(allHeaders).count == allHeaders.count,
              columns.allSatisfy(CaptureSanitizer.validField), !captures.isEmpty,
              captures.count <= 2_000,
              captures.allSatisfy({ $0.identity.computerID == captures[0].identity.computerID }) else {
            throw CaptureError.invalidColumn
        }
        let rows = captures.map { record -> DatasetRow in
            var values: [String: CaptureScalar] = [:]
            var reasons: [String: String] = [:]
            for field in columns {
                if let value = record.event.bodyJSON?[field] {
                    values[field] = value
                    if value == .null { reasons[field] = "source_null" }
                } else {
                    values[field] = .null
                    reasons[field] = record.event.bodyJSON == nil ? "body_not_captured" : "field_unavailable"
                }
            }
            return DatasetRow(id: UUID(), values: values, missingReasons: reasons,
                captureID: record.captureID, captureRecordID: record.id,
                evidenceSHA256: record.evidenceSHA256, duplicateCount: record.duplicateCount,
                sourceURL: record.event.url, sourceTimestamp: record.event.timestamp,
                identity: record.identity)
        }
        let dataset = Dataset(id: UUID(), computerID: captures[0].identity.computerID,
            name: title, columns: columns, rows: rows, createdAt: Date())
        try CaptureDisk.write(try encoder.encode(dataset), to: file(dataset.id))
        return dataset
    }

    public func load(datasetID: UUID) throws -> Dataset {
        guard let data = try CaptureDisk.read(file(datasetID)) else { throw CaptureError.missingResult }
        guard let dataset = try? decoder.decode(Dataset.self, from: data), dataset.id == datasetID,
              !dataset.rows.isEmpty, dataset.rows.count <= 2_000, dataset.columns.count <= 64,
              dataset.columns.allSatisfy(CaptureSanitizer.validField),
              Set(Self.reservedCSVColumns + dataset.columns +
                  dataset.columns.map { "\($0)__missing_reason" }).count ==
                  Self.reservedCSVColumns.count + dataset.columns.count * 2,
              dataset.rows.allSatisfy({ row in
                  row.values.count == dataset.columns.count &&
                  Set(row.values.keys) == Set(dataset.columns) &&
                  row.evidenceSHA256.count == 64 && row.duplicateCount > 0 &&
                  row.identity.computerID == dataset.computerID
              }) else { throw CaptureError.corruptStore }
        return dataset
    }

    public func list(computerID: UUID) throws -> [Dataset] {
        try CaptureDisk.ensureDirectory(directory)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("dataset-") && $0.hasSuffix(".json") }
        guard files.count <= 100 else { throw CaptureError.quotaExceeded }
        var found: [Dataset] = []
        for filename in files {
            let text = String(filename.dropFirst("dataset-".count).dropLast(".json".count))
            guard let id = UUID(uuidString: text) else { throw CaptureError.corruptStore }
            let dataset = try load(datasetID: id)
            if dataset.computerID == computerID { found.append(dataset) }
        }
        return found.sorted { $0.createdAt > $1.createdAt }
    }

    public func deleteResults(datasetID: UUID) throws { try CaptureDisk.delete(file(datasetID)) }

    /// Export creates a fresh private directory under the selected destination.
    /// It never overwrites an earlier export or capture source.
    public func export(datasetID: UUID, format: DatasetExportFormat, to destination: URL) throws -> DatasetExport {
        let dataset = try load(datasetID: datasetID)
        let output = destination.appendingPathComponent("agentbox-result-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(output.path, 0o700) == 0 else { throw CaptureError.unsafePath }
        try CaptureDisk.ensureDirectory(output)
        let data: Data
        switch format {
        case .json:
            let formatter = JSONEncoder()
            formatter.outputFormatting = [.prettyPrinted, .sortedKeys]
            formatter.dateEncodingStrategy = .iso8601
            data = try formatter.encode(dataset)
        case .csv:
            data = Data(Self.csv(dataset).utf8)
        }
        let dataURL = output.appendingPathComponent("result.\(format.rawValue)")
        let manifestURL = output.appendingPathComponent("manifest.json")
        let hash = CaptureDisk.hash(data)
        let manifest = DatasetExportManifest(schemaVersion: 1, datasetID: datasetID,
            exportedAt: Date(), format: format, rowCount: dataset.rows.count,
            dataSHA256: hash, evidenceSHA256: dataset.rows.map(\.evidenceSHA256))
        try CaptureDisk.writeNew(data, to: dataURL)
        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        manifestEncoder.dateEncodingStrategy = .iso8601
        try CaptureDisk.writeNew(try manifestEncoder.encode(manifest), to: manifestURL)
        return DatasetExport(dataURL: dataURL, manifestURL: manifestURL,
            format: format, rowCount: dataset.rows.count, sha256: hash)
    }

    private static func csv(_ dataset: Dataset) -> String {
        let columns = reservedCSVColumns + dataset.columns + dataset.columns.map { "\($0)__missing_reason" }
        var lines = [columns.map(escape).joined(separator: ",")]
        for row in dataset.rows {
            let values = [row.captureID.uuidString, row.captureRecordID.uuidString,
                row.evidenceSHA256, String(row.duplicateCount), row.sourceURL, row.sourceTimestamp,
                row.identity.sessionID.uuidString, row.identity.terminalID.uuidString,
                row.identity.ownerRunID?.uuidString ?? "", row.identity.computerID.uuidString]
                + dataset.columns.map { field in scalar(row.values[field] ?? .null) }
                + dataset.columns.map { row.missingReasons[$0] ?? "" }
            lines.append(values.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func scalar(_ value: CaptureScalar) -> String {
        switch value {
        case .string(let text): text
        case .number(let number): String(number)
        case .bool(let bool): bool ? "true" : "false"
        case .null: ""
        }
    }

    private static func escape(_ value: String) -> String {
        let firstNonSpace = value.unicodeScalars.first { $0 != " " }
        let dangerous = firstNonSpace.map { "=+-@\t\r\n".unicodeScalars.contains($0) } ?? false
        let safe = dangerous ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
