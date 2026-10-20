import AppKit
import RackyCore
import Darwin
import Foundation
import SwiftUI

struct CapturePanelEvent: Identifiable {
    let id: String
    let source: String
    let status: String
    let url: String
    let time: String
    let hasJSON: Bool
}

struct CapturePanelDataset: Identifiable {
    let id: UUID
    let name: String
    let rowCount: Int
}

private enum SharedCaptureStorage {
    static let captures = Result { try CaptureStore() }
    static let datasets = Result { try DatasetStore() }
    static let configurations = CaptureConfigurationArchive()
}

@MainActor enum CapturePanelRegistry {
    private static var stores: [UUID: CapturePanelStore] = [:]

    static func store(computerID: UUID, owner: BrowserComputerOwner,
                      context: ComputerPolicyContext) -> CapturePanelStore {
        if let existing = stores[computerID], existing.owner == owner,
           existing.context == context { return existing }
        let created = CapturePanelStore(computerID: computerID, owner: owner, context: context)
        stores[computerID] = created
        return created
    }
}

private enum CapturePanelOperationError: LocalizedError {
    case configurationNotSaved
    case configurationNotSavedAndStateUnknown
    case configurationChangedElsewhere

    var errorDescription: String? {
        switch self {
        case .configurationNotSaved:
            return "Os filtros não foram salvos. A captura do runtime foi desativada; revise e aplique novamente."
        case .configurationNotSavedAndStateUnknown:
            return "Os filtros não foram salvos e não foi possível confirmar a desativação da captura. Confira a box antes de continuar."
        case .configurationChangedElsewhere:
            return "Os filtros foram alterados em outro painel. Revise a configuração atual antes de aplicar."
        }
    }
}

/// A separate actor serializes each computer's preferences across open panels.
/// The on-disk preference contains filters only; no endpoint or bearer token.
private actor CaptureConfigurationArchive {
    private struct Stored: Codable {
        let schemaVersion: Int
        let computerID: UUID
        let configuration: CaptureConfiguration
    }
    private let directory: URL

    init(directory: URL = AppPaths.applicationSupport.appendingPathComponent("CapturePreferences", isDirectory: true)) {
        self.directory = directory
    }

    private func file(_ id: UUID) -> URL {
        directory.appendingPathComponent("capture-\(id.uuidString.lowercased()).json")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_mode & 0o077 == 0 else {
            throw CaptureError.unsafePath
        }
    }

    func load(_ id: UUID) throws -> CaptureConfiguration {
        try ensureDirectory()
        let fd = Darwin.open(file(id).path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == ENOENT { return CaptureConfiguration() }
            throw CaptureError.unsafePath
        }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_mode & 0o077 == 0,
              (1...16_384).contains(info.st_size) else { throw CaptureError.unsafePath }
        var bytes = Data(count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            var readCount = 0
            while readCount < buffer.count {
                let next = Darwin.read(fd, base.advanced(by: readCount), buffer.count - readCount)
                if next < 0 && errno == EINTR { continue }
                if next <= 0 { return -1 }
                readCount += next
            }
            return readCount
        }
        guard count == bytes.count,
              let stored = try? JSONDecoder().decode(Stored.self, from: bytes),
              stored.schemaVersion == 1, stored.computerID == id else { throw CaptureError.corruptStore }
        return try stored.configuration.validated()
    }

    func save(_ configuration: CaptureConfiguration, for id: UUID) throws {
        try ensureDirectory()
        let validated = try configuration.validated()
        let payload = try JSONEncoder().encode(Stored(schemaVersion: 1, computerID: id, configuration: validated))
        guard payload.count <= 16_384 else { throw CaptureError.invalidConfiguration }
        // Refuse an unsafe or corrupted existing preference instead of replacing it.
        _ = try load(id)
        let target = file(id)
        let temporary = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CaptureError.unsafePath }
        var completed = false
        defer {
            _ = Darwin.close(fd)
            if !completed { _ = unlink(temporary.path) }
        }
        let wrote = payload.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var count = 0
            while count < buffer.count {
                let next = Darwin.write(fd, base.advanced(by: count), buffer.count - count)
                if next < 0 && errno == EINTR { continue }
                if next <= 0 { return false }
                count += next
            }
            return true
        }
        guard wrote, fsync(fd) == 0, rename(temporary.path, target.path) == 0 else {
            throw CaptureError.unsafePath
        }
        completed = true
        let dirFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dirFD >= 0 else { throw CaptureError.unsafePath }
        defer { _ = Darwin.close(dirFD) }
        guard fsync(dirFD) == 0 else { throw CaptureError.unsafePath }
    }
}

@MainActor final class CapturePanelStore: ObservableObject, Identifiable {
    let id: UUID
    let computerID: UUID
    let owner: BrowserComputerOwner
    let context: ComputerPolicyContext
    @Published private(set) var configuration = CaptureConfiguration()
    @Published private(set) var events: [CapturePanelEvent] = []
    @Published private(set) var datasets: [CapturePanelDataset] = []
    @Published private(set) var coverage: [String] = []
    @Published private(set) var gaps: [String] = []
    @Published private(set) var dropped = 0
    @Published private(set) var captureEnabled = false
    @Published private(set) var runtimeStateKnown = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorText: String?
    @Published private(set) var exportLocation: String?
    @Published private(set) var warningText: String?

    private let service = BrowserComputerService(runner: DockerProcessRunner(),
                                                 tokens: KeychainBrowserComputerTokenStore())
    private let captureStoreOverride: CaptureStore?
    private let datasetStoreOverride: DatasetStore?
    private let configurationArchive: CaptureConfigurationArchive
    private let ownershipProvider: (@MainActor () async throws -> BrowserManagedComputer?)?
    private let endpointProvider: (@MainActor () async throws -> BrowserRuntimeEndpoint)?
    private let clientFactory: (BrowserRuntimeEndpoint) -> BrowserRuntimeClient
    private var configurationLoaded = false
    private var configurationLoadFailed = false
    private var refreshing = false
    private var captureID: UUID?
    private var cursor = 0
    private var backgroundTask: Task<Void, Never>?

    init(computerID: UUID, owner: BrowserComputerOwner, context: ComputerPolicyContext,
         captureStore: CaptureStore? = nil, datasetStore: DatasetStore? = nil,
         configurationDirectory: URL? = nil,
         ownershipProvider: (@MainActor () async throws -> BrowserManagedComputer?)? = nil,
         endpointProvider: (@MainActor () async throws -> BrowserRuntimeEndpoint)? = nil,
         clientFactory: @escaping (BrowserRuntimeEndpoint) -> BrowserRuntimeClient = { BrowserRuntimeClient(endpoint: $0) }) {
        self.id = computerID
        self.computerID = computerID
        self.owner = owner
        self.context = context
        self.captureStoreOverride = captureStore
        self.datasetStoreOverride = datasetStore
        self.configurationArchive = configurationDirectory.map { CaptureConfigurationArchive(directory: $0) } ??
            SharedCaptureStorage.configurations
        self.ownershipProvider = ownershipProvider
        self.endpointProvider = endpointProvider
        self.clientFactory = clientFactory
    }

    func refresh() async {
        guard !isBusy, !refreshing else { return }
        refreshing = true
        isBusy = true
        defer { refreshing = false; isBusy = false }
        do {
            try await loadOffline()
            try await loadConfiguration()
            let currentConfiguration = try await configurationArchive.load(computerID)
            if currentConfiguration != configuration { configuration = currentConfiguration }
            guard try await ownedComputer()?.running == true else {
                captureEnabled = false
                runtimeStateKnown = true
                updateBackgroundPolling()
                return
            }
            let endpoint = try await verifiedEndpoint()
            let client = clientFactory(endpoint)
            _ = try await drain(client)
            updateBackgroundPolling()
            errorText = nil
        } catch {
            captureEnabled = false
            runtimeStateKnown = false
            updateBackgroundPolling()
            errorText = error.localizedDescription
        }
    }

    func apply(_ requested: CaptureConfiguration) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await loadConfiguration()
            guard !configurationLoadFailed else { throw CaptureError.corruptStore }
            let next = try requested.validated()
            let persisted = try await configurationArchive.load(computerID)
            guard persisted == configuration else {
                configuration = persisted
                throw CapturePanelOperationError.configurationChangedElsewhere
            }
            let endpoint = try await verifiedEndpoint()
            let client = clientFactory(endpoint)
            if configuration.enabled && !next.enabled {
                // Privacy wins if local evidence persistence is broken: disabling
                // capture must remain possible even when the final drain fails.
                do { _ = try await drain(client); warningText = nil }
                catch {
                    warningText = "A captura foi desligada, mas eventos pendentes não puderam ser salvos: \(error.localizedDescription)"
                }
            } else {
                _ = try await drain(client)
                warningText = nil
            }
            let batch = try await client.configureCapture(next)
            captureEnabled = batch.enabled
            runtimeStateKnown = true
            do {
                try await configurationArchive.save(next, for: computerID)
            } catch {
                if let disabled = try? await client.configureCapture(CaptureConfiguration()) {
                    captureEnabled = disabled.enabled
                    runtimeStateKnown = true
                    throw CapturePanelOperationError.configurationNotSaved
                }
                captureEnabled = false
                runtimeStateKnown = false
                throw CapturePanelOperationError.configurationNotSavedAndStateUnknown
            }
            configuration = next
            // Idempotent Apply can return requests completed after the preflight
            // drain. Persist the returned batch before advancing its cursor.
            if next.enabled && batch.enabled {
                _ = try await captureStorage().append(batch: batch, identity: captureIdentity(), configuration: next)
            }
            captureID = batch.captureID
            cursor = batch.nextCursor
            try await loadOffline()
            updateBackgroundPolling()
            errorText = nil
        } catch { errorText = error.localizedDescription; updateBackgroundPolling() }
    }

    func createDataset(name: String, columns: [String], eventIDs: Set<String>) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard !columns.isEmpty, Set(columns).isSubset(of: Set(configuration.jsonFields)) else {
                throw CaptureError.invalidColumn
            }
            let records = try await captureStorage().records(computerID: computerID)
            let captures = records.filter { eventIDs.contains($0.id.uuidString) && $0.event.bodyJSON != nil }
            _ = try await datasetStorage().create(name: name, columns: columns, from: captures)
            try await loadOffline()
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    func exportDataset(_ id: UUID, csv: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let store = try datasetStorage()
            let dataset = try await store.load(datasetID: id)
            guard dataset.computerID == computerID else { throw CaptureError.missingResult }
            let panel = NSSavePanel()
            panel.title = "Escolher pasta para exportação"
            panel.nameFieldStringValue = "racky-resultado"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            guard !FileManager.default.fileExists(atPath: chosen.path) else { throw CaptureError.unsafePath }
            try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let result = try await store.export(datasetID: id, format: csv ? .csv : .json, to: chosen)
            exportLocation = result.dataURL.deletingLastPathComponent().path
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    func deleteCaptures() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let endpoint = try await verifiedEndpoint()
            let batch = try await clientFactory(endpoint).clearCaptures()
            try await captureStorage().deleteCaptures(computerID: computerID)
            captureID = batch.captureID
            cursor = batch.nextCursor
            captureEnabled = batch.enabled
            runtimeStateKnown = true
            try await loadOffline()
            errorText = nil
        } catch {
            errorText = "Capturas locais preservadas: a box precisa estar acessível para limpar também o ring do runtime. \(error.localizedDescription)"
        }
    }

    func deleteDataset(_ id: UUID) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let store = try datasetStorage()
            guard try await store.load(datasetID: id).computerID == computerID else {
                throw CaptureError.missingResult
            }
            try await store.deleteResults(datasetID: id)
            try await loadOffline()
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func loadConfiguration() async throws {
        guard !configurationLoadFailed else { throw CaptureError.corruptStore }
        guard !configurationLoaded else { return }
        do {
            configuration = try await configurationArchive.load(computerID)
            configurationLoaded = true
        } catch {
            configurationLoadFailed = true
            configurationLoaded = true
            throw error
        }
    }

    private func loadOffline() async throws {
        let captureStore = try captureStorage()
        let resultStore = try datasetStorage()
        let records = try await captureStore.records(computerID: computerID)
        let status = try await captureStore.status(computerID: computerID)
        let results = try await resultStore.list(computerID: computerID)
        events = records.sorted { $0.firstObservedAt > $1.firstObservedAt }.map { record in
            CapturePanelEvent(id: record.id.uuidString, source: record.event.source,
                status: record.event.status.map(String.init) ?? "—", url: record.event.url,
                time: record.event.timestamp, hasJSON: record.event.bodyJSON != nil)
        }
        datasets = results.map { CapturePanelDataset(id: $0.id, name: $0.name, rowCount: $0.rows.count) }
        coverage = status.coverage
        gaps = status.gaps
        let (sum, overflow) = status.reportedDropped.addingReportingOverflow(status.localDropped)
        dropped = overflow ? Int.max : sum
    }

    @discardableResult
    private func drain(_ client: BrowserRuntimeClient) async throws -> CaptureBatch {
        var batch = try await client.capture(after: cursor)
        if let captureID, captureID != batch.captureID {
            batch = try await client.capture(after: 0)
        }
        if configuration.enabled && batch.enabled {
            _ = try await captureStorage().append(batch: batch, identity: captureIdentity(),
                                              configuration: configuration)
            try await loadOffline()
        }
        // A failed append leaves the old cursor intact for the next poll.
        captureID = batch.captureID
        cursor = batch.nextCursor
        captureEnabled = batch.enabled
        runtimeStateKnown = true
        coverage = Array(Set(coverage + batch.coverage)).sorted()
        gaps = Array(Set(gaps + batch.gaps)).sorted()
        dropped = max(dropped, batch.dropped)
        return batch
    }

    private func updateBackgroundPolling() {
        if configuration.enabled && (!runtimeStateKnown || captureEnabled) {
            guard backgroundTask == nil else { return }
            backgroundTask = Task { [weak self] in
                while !Task.isCancelled {
                    let delay: Duration = self?.runtimeStateKnown == false ? .seconds(15) : .seconds(3)
                    try? await Task.sleep(for: delay)
                    if Task.isCancelled { break }
                    if let store = self { await store.refresh() } else { break }
                }
            }
        } else {
            backgroundTask?.cancel()
            backgroundTask = nil
        }
    }

    private func ownedComputer() async throws -> BrowserManagedComputer? {
        if let ownershipProvider {
            let computer = try await ownershipProvider()
            guard computer == nil || (computer?.id == computerID && computer?.owner == owner) else {
                throw BrowserComputerError.unmanagedContainer
            }
            return computer
        }
        let service = service
        let owner = owner
        let computer = try await Task.detached(priority: .utility) { try service.computer(for: owner) }.value
        guard computer == nil || computer?.id == computerID else { throw BrowserComputerError.unmanagedContainer }
        return computer
    }

    private func verifiedEndpoint() async throws -> BrowserRuntimeEndpoint {
        guard let computer = try await ownedComputer(), computer.running else {
            throw BrowserComputerError.missingComputer
        }
        let endpoint: BrowserRuntimeEndpoint
        if let endpointProvider {
            endpoint = try await endpointProvider()
        } else {
            let service = service
            let id = computerID
            endpoint = try await Task.detached(priority: .utility) {
                try await service.reconnectEndpoint(computerID: id)
            }.value
        }
        guard endpoint.computerID == computerID,
              try await ownedComputer()?.id == computerID else { throw BrowserComputerError.unmanagedContainer }
        return endpoint
    }

    private func captureStorage() throws -> CaptureStore {
        if let captureStoreOverride { return captureStoreOverride }
        return try SharedCaptureStorage.captures.get()
    }

    private func datasetStorage() throws -> DatasetStore {
        if let datasetStoreOverride { return datasetStoreOverride }
        return try SharedCaptureStorage.datasets.get()
    }

    private func captureIdentity() throws -> CaptureIdentity {
        guard let sessionID = context.sessionID, context.terminalID == owner.terminalID else {
            throw CaptureError.identityMismatch
        }
        return CaptureIdentity(sessionID: sessionID, terminalID: owner.terminalID,
                               ownerRunID: owner.agentRunID, computerID: computerID)
    }
}
