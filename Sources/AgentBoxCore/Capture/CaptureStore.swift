import CryptoKit
import Darwin
import Foundation

/// Private, bounded persistence shared by capture and result stores. Every read
/// validates ownership, type, mode, size and schema; corruption never becomes an
/// empty successful result. Callers supply a dedicated directory per store.
enum CaptureDisk {
    static let maximumFileBytes = 12 * 1_048_576

    static func ensureDirectory(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch { throw CaptureError.unsafePath }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else {
            throw CaptureError.unsafePath
        }
    }

    static func read(_ url: URL) throws -> Data? {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw CaptureError.unsafePath
        }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
              info.st_size >= 0, info.st_size <= maximumFileBytes else { throw CaptureError.unsafePath }
        let length = Int(info.st_size)
        var data = Data(count: length)
        let received = data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var total = 0
            while total < length {
                let count = Darwin.read(fd, base.advanced(by: total), length - total)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { return -1 }
                total += count
            }
            return total
        }
        guard received == length else { throw CaptureError.corruptStore }
        return data
    }

    static func write(_ data: Data, to url: URL) throws {
        guard data.count <= maximumFileBytes else { throw CaptureError.quotaExceeded }
        try ensureDirectory(url.deletingLastPathComponent())
        // A private directory makes rename atomic without another user's race.
        _ = try read(url)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CaptureError.unsafePath }
        var completed = false
        defer {
            _ = Darwin.close(fd)
            if !completed { _ = unlink(temporary.path) }
        }
        let written = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return data.isEmpty }
            var total = 0
            while total < data.count {
                let count = Darwin.write(fd, base.advanced(by: total), data.count - total)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { return false }
                total += count
            }
            return true
        }
        guard written, fsync(fd) == 0, rename(temporary.path, url.path) == 0 else {
            throw CaptureError.unsafePath
        }
        completed = true
        let directoryFD = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if directoryFD >= 0 { _ = fsync(directoryFD); _ = Darwin.close(directoryFD) }
    }

    static func writeNew(_ data: Data, to url: URL) throws {
        guard data.count <= maximumFileBytes else { throw CaptureError.quotaExceeded }
        try ensureDirectory(url.deletingLastPathComponent())
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CaptureError.unsafePath }
        var completed = false
        defer {
            _ = Darwin.close(fd)
            if !completed { _ = unlink(url.path) }
        }
        let written = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return data.isEmpty }
            var total = 0
            while total < data.count {
                let count = Darwin.write(fd, base.advanced(by: total), data.count - total)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { return false }
                total += count
            }
            return true
        }
        guard written, fsync(fd) == 0 else { throw CaptureError.unsafePath }
        completed = true
    }

    static func delete(_ url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        guard try read(url) != nil else { return }
        guard unlink(url.path) == 0 else { throw CaptureError.unsafePath }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public actor CaptureStore {
    private struct Archive: Codable {
        let schemaVersion: Int
        let computerID: UUID
        var records: [CaptureRecord]
        var coverage: [String]
        var gaps: [String]
        var reportedDroppedByCaptureID: [String: Int]
        var localDropped: Int
    }

    private let directory: URL
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    public init(directory: URL = AppPaths.applicationSupport.appendingPathComponent("Captures", isDirectory: true),
                now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.directory = directory
        self.now = now
        try CaptureDisk.ensureDirectory(directory)
    }

    private func file(_ computerID: UUID) -> URL {
        directory.appendingPathComponent("capture-\(computerID.uuidString.lowercased()).json")
    }

    private func load(_ computerID: UUID) throws -> Archive {
        guard let data = try CaptureDisk.read(file(computerID)) else {
            return Archive(schemaVersion: 1, computerID: computerID, records: [], coverage: [], gaps: [],
                reportedDroppedByCaptureID: [:], localDropped: 0)
        }
        guard let archive = try? decoder.decode(Archive.self, from: data), archive.schemaVersion == 1,
              archive.computerID == computerID, archive.records.count <= 2_000,
              archive.records.allSatisfy({ $0.identity.computerID == computerID &&
                  $0.duplicateCount > 0 && $0.evidenceSHA256.count == 64 &&
                  $0.expiresAt >= $0.firstObservedAt }),
              archive.reportedDroppedByCaptureID.count <= 1_000,
              archive.reportedDroppedByCaptureID.values.allSatisfy({ $0 >= 0 }),
              archive.localDropped >= 0 else {
            throw CaptureError.corruptStore
        }
        for record in archive.records {
            let evidence = Evidence(captureID: record.captureID, identity: record.identity, event: record.event)
            guard CaptureDisk.hash(try encoder.encode(evidence)) == record.evidenceSHA256 else {
                throw CaptureError.corruptStore
            }
        }
        return archive
    }

    private func pruneExpired(_ archive: inout Archive) {
        let instant = now()
        archive.records.removeAll { $0.expiresAt <= instant }
    }

    private func readCurrent(_ computerID: UUID) throws -> Archive {
        var archive = try load(computerID)
        let before = archive.records.count
        pruneExpired(&archive)
        if archive.records.count != before {
            try CaptureDisk.write(try encoder.encode(archive), to: file(computerID))
        }
        return archive
    }

    private func trimToFileLimit(_ archive: inout Archive) throws -> Int {
        guard try encoder.encode(archive).count > CaptureDisk.maximumFileBytes else { return 0 }
        let ordered = archive.records.enumerated().sorted { left, right in
            left.element.firstObservedAt == right.element.firstObservedAt
                ? left.offset < right.offset
                : left.element.firstObservedAt < right.element.firstObservedAt
        }.map(\.element)
        var lower = 1, upper = ordered.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            archive.records = Array(ordered.dropFirst(middle))
            if try encoder.encode(archive).count <= CaptureDisk.maximumFileBytes {
                upper = middle
            } else { lower = middle + 1 }
        }
        archive.records = Array(ordered.dropFirst(lower))
        guard try encoder.encode(archive).count <= CaptureDisk.maximumFileBytes else {
            throw CaptureError.quotaExceeded
        }
        return lower
    }

    public func append(batch: CaptureBatch, identity: CaptureIdentity,
                       configuration: CaptureConfiguration) throws -> CaptureAppendResult {
        let config = try configuration.validated()
        guard batch.schemaVersion == 1, UUID(uuidString: batch.computerID) == identity.computerID,
              batch.coverageVersion.utf8.count <= 64, batch.nextCursor >= 0, batch.dropped >= 0,
              batch.events.count <= config.maxEvents, batch.coverage.count <= 32, batch.gaps.count <= 32,
              (batch.coverage + batch.gaps).allSatisfy({ $0.utf8.count <= 128 && !$0.contains("\0") }) else {
            throw CaptureError.invalidWireData
        }
        guard config.enabled, batch.enabled else {
            return CaptureAppendResult(inserted: 0, duplicates: 0, reportedDropped: batch.dropped, localDropped: 0)
        }
        var archive = try readCurrent(identity.computerID)
        let instant = now()
        var insertedIDs = Set<UUID>()
        var duplicates = 0, localDropped = 0
        for raw in batch.events {
            let event = try CaptureSanitizer.sanitized(raw, configuration: config)
            let evidence = Evidence(captureID: batch.captureID, identity: identity, event: event)
            let hash = CaptureDisk.hash(try encoder.encode(evidence))
            if archive.records.contains(where: { $0.evidenceSHA256 == hash }) {
                // Polling the same cursor again is a replay, not another network request.
                duplicates += 1
            } else {
                let recordID = UUID()
                archive.records.append(CaptureRecord(id: recordID, captureID: batch.captureID,
                    identity: identity, event: event, evidenceSHA256: hash,
                    duplicateCount: 1, firstObservedAt: instant, lastObservedAt: instant,
                    expiresAt: instant.addingTimeInterval(Double(config.retentionSeconds))))
                insertedIDs.insert(recordID)
            }
        }
        if archive.records.count > config.maxEvents {
            localDropped += archive.records.count - config.maxEvents
            archive.records = Array(archive.records.suffix(config.maxEvents))
        }
        archive.coverage = Array(Set(archive.coverage + batch.coverage)).sorted().prefix(32).map { $0 }
        archive.gaps = Array(Set(archive.gaps + batch.gaps)).sorted().prefix(32).map { $0 }
        let captureKey = batch.captureID.uuidString.lowercased()
        archive.reportedDroppedByCaptureID[captureKey] = max(
            archive.reportedDroppedByCaptureID[captureKey] ?? 0, batch.dropped)
        guard archive.reportedDroppedByCaptureID.count <= 1_000 else { throw CaptureError.quotaExceeded }
        localDropped += try trimToFileLimit(&archive)
        archive.localDropped = min(Int.max - localDropped, archive.localDropped) + localDropped
        let extraDrops = try trimToFileLimit(&archive)
        localDropped += extraDrops
        archive.localDropped = min(Int.max - extraDrops, archive.localDropped) + extraDrops
        try CaptureDisk.write(try encoder.encode(archive), to: file(identity.computerID))
        return CaptureAppendResult(inserted: archive.records.filter { insertedIDs.contains($0.id) }.count,
            duplicates: duplicates,
            reportedDropped: batch.dropped, localDropped: localDropped)
    }

    public func records(computerID: UUID) throws -> [CaptureRecord] { try readCurrent(computerID).records }

    public func status(computerID: UUID) throws -> CaptureStatus {
        let archive = try readCurrent(computerID)
        let reported = archive.reportedDroppedByCaptureID.values.reduce(0) { total, value in
            total > Int.max - value ? Int.max : total + value
        }
        return CaptureStatus(coverage: archive.coverage, gaps: archive.gaps,
            reportedDropped: reported, localDropped: archive.localDropped,
            retainedEvents: archive.records.count)
    }

    public func deleteCaptures(computerID: UUID) throws { try CaptureDisk.delete(file(computerID)) }
}

private struct Evidence: Encodable {
    let captureID: UUID
    let identity: CaptureIdentity
    let event: CaptureEvent
}
