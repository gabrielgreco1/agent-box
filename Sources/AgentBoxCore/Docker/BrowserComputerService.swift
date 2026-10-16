import Darwin
import Foundation
import LocalAuthentication
import Security

public enum BrowserComputerError: Error, LocalizedError, Equatable {
    case creationDisabled, networkDisabled, insufficientMemory
    case resourceLimit, duplicateComputer, missingComputer, unmanagedContainer
    case missingToken, tokenAuthorizationRequired, tokenAuthorizationDenied, keychainTimedOut
    case invalidDockerResponse, invalidPort, notReady, commandFailed(String)
    case computerRunning, imageUnavailable, updateRecoveryRequired

    public var errorDescription: String? {
        switch self {
        case .creationDisabled: return "A política efetiva impede criar computadores."
        case .networkDisabled: return "A política efetiva desativa a rede necessária para o browser."
        case .insufficientMemory: return "O browser precisa de pelo menos 2048 MiB dentro do limite efetivo."
        case .resourceLimit: return "O limite de computadores ativos foi atingido."
        case .duplicateComputer: return "Mais de um browser gerenciado usa este terminal."
        case .missingComputer: return "Computador browser não encontrado."
        case .unmanagedContainer: return "O container não pertence a este computador do Agent Box."
        case .missingToken: return "O token local deste computador não está disponível no Keychain."
        case .tokenAuthorizationRequired: return "O Keychain exige autorização. Use ‘Autorizar acesso ao token’ para tentar novamente."
        case .tokenAuthorizationDenied: return "A autorização do Keychain foi recusada ou cancelada. O computador foi preservado."
        case .keychainTimedOut: return "O Keychain não respondeu no prazo. O computador foi preservado; tente novamente após resolver o acesso ao Keychain."
        case .invalidDockerResponse: return "Docker devolveu dados inesperados."
        case .invalidPort: return "O browser não publicou uma porta local segura."
        case .notReady: return "O browser ainda não ficou pronto."
        case .commandFailed(let detail): return "Docker: \(detail)"
        case .computerRunning: return "Pare o computador antes de atualizar sua imagem."
        case .imageUnavailable: return "A imagem local configurada não está disponível."
        case .updateRecoveryRequired: return "A atualização foi interrompida; recupere o computador antes de continuar."
        }
    }
}

public protocol BrowserComputerTokenStoring {
    func put(computerID: UUID, value: String) throws
    func read(computerID: UUID) throws -> String
    func readInteractively(computerID: UUID) throws -> String
    func delete(computerID: UUID) throws
}

public extension BrowserComputerTokenStoring {
    func readInteractively(computerID: UUID) throws -> String { try read(computerID: computerID) }
}

/// A timed-out SecurityServer call may keep its worker occupied. Never queue another one behind it.
final class KeychainReadGate {
    static let shared = KeychainReadGate()
    private let lock = NSLock()
    private var inFlight = false

    func execute(timeout: TimeInterval, onTimeout: @escaping () -> Void = {},
                 _ operation: @escaping () throws -> String) throws -> String {
        lock.lock()
        guard !inFlight else { lock.unlock(); throw BrowserComputerError.keychainTimedOut }
        inFlight = true
        lock.unlock()
        let result = ResultBox()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try operation() }
            self.lock.lock()
            self.inFlight = false
            self.lock.unlock()
            result.complete(outcome)
        }
        guard result.wait(timeout: timeout) else {
            onTimeout()
            throw BrowserComputerError.keychainTimedOut
        }
        return try result.value().get()
    }

    private final class ResultBox {
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var outcome: Result<String, Error>?
        func complete(_ result: Result<String, Error>) {
            lock.lock(); outcome = result; lock.unlock()
            semaphore.signal()
        }
        func wait(timeout: TimeInterval) -> Bool {
            semaphore.wait(timeout: .now() + timeout) == .success
        }
        func value() -> Result<String, Error> {
            lock.lock(); defer { lock.unlock() }
            return outcome!
        }
    }
}

/// Separate Keychain namespace from user-imported credentials.
public struct KeychainBrowserComputerTokenStore: BrowserComputerTokenStoring {
    public init() {}
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.agentbox.browser-token.v1",
         kSecAttrAccount as String: id.uuidString]
    }
    public func put(computerID: UUID, value: String) throws {
        var attributes = query(computerID)
        attributes[kSecValueData as String] = Data(value.utf8)
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw BrowserComputerError.missingToken }
    }
    public func read(computerID: UUID) throws -> String {
        try read(computerID: computerID, interactive: false)
    }
    public func readInteractively(computerID: UUID) throws -> String {
        try read(computerID: computerID, interactive: true)
    }
    private func read(computerID: UUID, interactive: Bool) throws -> String {
        var attributes = query(computerID)
        attributes[kSecReturnData as String] = kCFBooleanTrue
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = !interactive
        attributes[kSecUseAuthenticationContext as String] = context
        return try KeychainReadGate.shared.execute(timeout: interactive ? 60 : 8,
                                                   onTimeout: { context.invalidate() }) {
            var result: CFTypeRef?
            // Existing macOS login-keychain items use the legacy backend, which
            // does not honor LAContext.interactionNotAllowed. Suppress optional
            // UI there too, and restore the process preference on every exit.
            let status: OSStatus
            if interactive {
                status = SecItemCopyMatching(attributes as CFDictionary, &result)
            } else {
                status = try LegacyKeychainInteraction.withoutUI {
                    SecItemCopyMatching(attributes as CFDictionary, &result)
                }
            }
            switch status {
            case errSecSuccess:
                guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
                    throw BrowserComputerError.missingToken
                }
                return text
            case errSecInteractionNotAllowed:
                throw BrowserComputerError.tokenAuthorizationRequired
            case errSecAuthFailed where !interactive:
                throw BrowserComputerError.tokenAuthorizationRequired
            case errSecUserCanceled, errSecAuthFailed:
                throw BrowserComputerError.tokenAuthorizationDenied
            default:
                throw BrowserComputerError.missingToken
            }
        }
    }
    public func delete(computerID: UUID) throws {
        let status = SecItemDelete(query(computerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BrowserComputerError.missingToken }
    }
}

public struct BrowserManagedComputer: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let terminalID: UUID
    public let containerID: String
    public let name: String
    public let volumeName: String
    public let running: Bool
}

public struct BrowserComputerMetadata: Codable, Equatable, Sendable {
    public let computerID: UUID
    public let terminalID: UUID
    public let containerID: String
    public let volumeName: String
    public let createdAt: Date
}

public struct BrowserComputerImageUpdateStatus: Equatable, Sendable {
    public let computerID: UUID
    public let currentImageID: String
    public let availableImageID: String
    public var updateAvailable: Bool { currentImageID != availableImageID }
}

public struct PendingBrowserImageUpdate: Equatable, Sendable {
    public let computerID: UUID
    public let terminalID: UUID
}

private struct BrowserImageUpdateJournal: Codable {
    let computerID: UUID
    let terminalID: UUID
    let volumeName: String
    let oldContainerID: String
    var newContainerID: String?
    let temporaryName: String
    let backupName: String
    let targetImageID: String
}

public struct BrowserComputerMetadataStore {
    public let url: URL
    public init(url: URL = AppPaths.applicationSupport.appendingPathComponent("browser-computers.json")) { self.url = url }
    public func load() throws -> [BrowserComputerMetadata] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([BrowserComputerMetadata].self, from: Data(contentsOf: url))
    }
    public func save(_ records: [BrowserComputerMetadata]) throws {
        guard Set(records.map(\.computerID)).count == records.count,
              Set(records.map(\.terminalID)).count == records.count else { throw BrowserComputerError.duplicateComputer }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let file = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard file >= 0 else { throw BrowserComputerError.updateRecoveryRequired }
        defer { _ = Darwin.close(file) }
        guard fsync(file) == 0 else { throw BrowserComputerError.updateRecoveryRequired }
        let directory = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw BrowserComputerError.updateRecoveryRequired }
        defer { _ = Darwin.close(directory) }
        guard fsync(directory) == 0 else { throw BrowserComputerError.updateRecoveryRequired }
    }
}

/// Docker lifecycle for the browser image. Runner is injected so the selected Docker context
/// comes from the caller; this service never changes the user's global Docker context.
public struct BrowserComputerService<Runner: DockerCommandRunning, Tokens: BrowserComputerTokenStoring> {
    public static var image: String { "agentbox-browser:ab019-dev" }
    public static var ownerLabel: String { "com.agentbox.browser-managed" }
    public static var computerLabel: String { "com.agentbox.browser-computer-id" }
    public static var terminalLabel: String { "com.agentbox.browser-terminal-id" }
    public let runner: Runner
    public let tokens: Tokens
    public let policyStore: ComputerPolicyStore
    public let metadataStore: BrowserComputerMetadataStore

    public init(runner: Runner, tokens: Tokens, policyStore: ComputerPolicyStore = ComputerPolicyStore(),
                metadataStore: BrowserComputerMetadataStore = BrowserComputerMetadataStore()) {
        self.runner = runner; self.tokens = tokens; self.policyStore = policyStore; self.metadataStore = metadataStore
    }

    public func list() throws -> [BrowserManagedComputer] {
        let ids = try checked(["ps", "-a", "-q", "--filter", "label=\(Self.ownerLabel)=true"], timeout: 8)
            .stdout.split(whereSeparator: \.isNewline).map(String.init)
        let computers = try ids.compactMap { try inspectOwned($0) }
        guard Set(computers.map(\.id)).count == computers.count,
              Set(computers.map(\.terminalID)).count == computers.count else { throw BrowserComputerError.duplicateComputer }
        return computers
    }

    public func computer(for terminalID: UUID) throws -> BrowserManagedComputer? {
        try list().first(where: { $0.terminalID == terminalID })
    }

    /// Rebuilds missing metadata from owned Docker labels after an app reinstall or file loss.
    /// A contradictory record is never silently replaced.
    @discardableResult
    public func recoverMetadata() throws -> [BrowserComputerMetadata] {
        ComputerCreationLock.lock.lock(); defer { ComputerCreationLock.lock.unlock() }
        guard try loadImageUpdateJournal() == nil else {
            throw BrowserComputerError.updateRecoveryRequired
        }
        let live = try list()
        var records = try metadataStore.load()
        for computer in live {
            if let existing = records.first(where: { $0.computerID == computer.id || $0.terminalID == computer.terminalID }) {
                guard existing.computerID == computer.id, existing.terminalID == computer.terminalID,
                      existing.containerID == computer.containerID, existing.volumeName == computer.volumeName else {
                    throw BrowserComputerError.duplicateComputer
                }
            } else {
                records.append(BrowserComputerMetadata(computerID: computer.id, terminalID: computer.terminalID,
                                                       containerID: computer.containerID,
                                                       volumeName: computer.volumeName, createdAt: Date()))
            }
        }
        try metadataStore.save(records)
        return records
    }

    public func createAndStart(for terminalID: UUID, context: ComputerPolicyContext? = nil) throws -> BrowserManagedComputer {
        ComputerCreationLock.lock.lock(); defer { ComputerCreationLock.lock.unlock() }
        guard try loadImageUpdateJournal() == nil else { throw BrowserComputerError.updateRecoveryRequired }
        let context = context ?? ComputerPolicyContext(terminalID: terminalID)
        guard context.terminalID == terminalID else { throw ComputerPolicyError.invalidScope }
        let policy = try policyStore.load().effective(for: context)
        guard policy.creation != .disabled else { throw BrowserComputerError.creationDisabled }
        guard policy.networkAllowed else { throw BrowserComputerError.networkDisabled }
        guard policy.limits.memoryMiB >= 2048 else { throw BrowserComputerError.insufficientMemory }
        if let existing = try computer(for: terminalID) {
            if existing.running { return existing }
            try checkCapacity(policy)
            try start(existing)
            guard let restarted = try computer(for: terminalID), restarted.running else {
                throw BrowserComputerError.notReady
            }
            return restarted
        }
        try checkCapacity(policy)
        let id = UUID()
        let name = "agentbox-browser-\(id.uuidString.lowercased())"
        let volume = "agentbox-browser-data-\(id.uuidString.lowercased())"
        let token = try randomToken()
        try tokens.put(computerID: id, value: token)
        var createdContainer: String?
        var createdVolume = false
        do {
            // Never treat a pre-existing volume as ours, even if Docker's create would reuse it.
            let priorVolume = try runner.run(["volume", "inspect", volume], timeout: 8)
            guard priorVolume.exitCode != 0 else { throw BrowserComputerError.duplicateComputer }
            _ = try checked(["volume", "create", "--label", "\(Self.ownerLabel)=true",
                             "--label", "\(Self.computerLabel)=\(id.uuidString.lowercased())", volume], timeout: 30)
            createdVolume = true
            let environmentFile = try temporaryEnvironmentFile(computerID: id, token: token)
            defer { try? FileManager.default.removeItem(at: environmentFile) }
            let result = try checked(createArguments(name: name, computerID: id,
                terminalID: terminalID, volume: volume, policy: policy,
                environmentFile: environmentFile, image: Self.image), timeout: 120)
            let containerID = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (12...64).contains(containerID.count),
                  containerID.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                throw BrowserComputerError.invalidDockerResponse
            }
            createdContainer = containerID
            try FileManager.default.removeItem(at: environmentFile)
            guard let computer = try inspectOwned(containerID), computer.id == id,
                  computer.terminalID == terminalID else { throw BrowserComputerError.unmanagedContainer }
            var metadata = try metadataStore.load()
            metadata.append(BrowserComputerMetadata(computerID: id, terminalID: terminalID,
                                                    containerID: containerID, volumeName: volume, createdAt: Date()))
            try metadataStore.save(metadata)
            try start(computer)
            guard let running = try inspectOwned(containerID), running.running else {
                throw BrowserComputerError.notReady
            }
            return running
        } catch {
            if let createdContainer { _ = try? runner.run(["rm", "--force", createdContainer], timeout: 20) }
            if createdVolume { _ = try? runner.run(["volume", "rm", volume], timeout: 20) }
            try? tokens.delete(computerID: id)
            if var metadata = try? metadataStore.load() {
                metadata.removeAll(where: { $0.computerID == id })
                try? metadataStore.save(metadata)
            }
            throw error
        }
    }

    public func stop(computerID: UUID) throws {
        ComputerCreationLock.lock.lock(); defer { ComputerCreationLock.lock.unlock() }
        guard let computer = try list().first(where: { $0.id == computerID }) else { throw BrowserComputerError.missingComputer }
        guard computer.running else { return }
        guard try inspectOwned(computer.containerID)?.id == computerID else { throw BrowserComputerError.unmanagedContainer }
        _ = try checked(["stop", "--time", "10", computer.containerID], timeout: 20)
    }

    /// Compare the stopped box's pinned image with the configured image already on this Docker host.
    /// This reads local Docker state only; it never pulls or mutates a container.
    public func imageUpdateStatus(computerID: UUID) throws -> BrowserComputerImageUpdateStatus {
        ComputerCreationLock.lock.lock(); defer { ComputerCreationLock.lock.unlock() }
        guard try loadImageUpdateJournal() == nil else {
            throw BrowserComputerError.updateRecoveryRequired
        }
        guard let computer = try list().first(where: { $0.id == computerID }) else {
            throw BrowserComputerError.missingComputer
        }
        try verifyMetadata(computer)
        try verifyOwnedVolume(computer.containerID, computer: computer)
        return BrowserComputerImageUpdateStatus(computerID: computerID,
            currentImageID: try containerImageID(computer.containerID),
            availableImageID: try configuredImageID())
    }

    /// Replace only a stopped container. The durable journal makes an interrupted
    /// rename/metadata sequence recoverable without discarding its volume or token.
    public func updateStoppedImage(computerID: UUID, context: ComputerPolicyContext? = nil,
                                   interactiveAuthorization: Bool = false) throws -> BrowserManagedComputer {
        ComputerCreationLock.lock.lock(); defer { ComputerCreationLock.lock.unlock() }
        try recoverInterruptedImageUpdate()
        guard let old = try list().first(where: { $0.id == computerID }) else {
            throw BrowserComputerError.missingComputer
        }
        guard !old.running else { throw BrowserComputerError.computerRunning }
        let context = context ?? ComputerPolicyContext(terminalID: old.terminalID)
        guard context.terminalID == old.terminalID else { throw ComputerPolicyError.invalidScope }
        let policy = try policyStore.load().effective(for: context)
        guard policy.creation != .disabled else { throw BrowserComputerError.creationDisabled }
        guard policy.networkAllowed else { throw BrowserComputerError.networkDisabled }
        guard policy.limits.memoryMiB >= 2048 else { throw BrowserComputerError.insufficientMemory }
        try verifyMetadata(old)
        try verifyOwnedVolume(old.containerID, computer: old)
        let targetImageID = try configuredImageID()
        if try containerImageID(old.containerID) == targetImageID { return old }
        let token = try interactiveAuthorization
            ? tokens.readInteractively(computerID: computerID) : tokens.read(computerID: computerID)
        let nonce = UUID().uuidString.lowercased()
        var journal = BrowserImageUpdateJournal(computerID: computerID, terminalID: old.terminalID,
            volumeName: old.volumeName, oldContainerID: old.containerID, newContainerID: nil,
            temporaryName: "agentbox-updating-\(nonce)", backupName: "agentbox-backup-\(nonce)",
            targetImageID: targetImageID)
        guard try inspectIfPresent(journal.temporaryName) == nil,
              try inspectIfPresent(journal.backupName) == nil else {
            throw BrowserComputerError.duplicateComputer
        }
        try saveImageUpdateJournal(journal)
        do {
            let environmentFile = try temporaryEnvironmentFile(computerID: computerID, token: token)
            defer { try? FileManager.default.removeItem(at: environmentFile) }
            let created = try checked(createArguments(name: journal.temporaryName, computerID: computerID,
                terminalID: old.terminalID, volume: old.volumeName, policy: policy,
                environmentFile: environmentFile, image: targetImageID), timeout: 120)
            let newID = created.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.validContainerID(newID) else { throw BrowserComputerError.invalidDockerResponse }
            journal.newContainerID = newID
            try saveImageUpdateJournal(journal)
            guard let candidate = try inspectOwned(newID, expectedName: journal.temporaryName),
                  candidate.id == old.id, candidate.terminalID == old.terminalID,
                  !candidate.running, candidate.volumeName == old.volumeName else {
                throw BrowserComputerError.unmanagedContainer
            }
            try verifyOwnedVolume(newID, computer: candidate)
            guard try containerImageID(newID) == targetImageID else { throw BrowserComputerError.invalidDockerResponse }
            guard let stillOld = try inspectOwned(old.containerID), !stillOld.running,
                  stillOld == old else { throw BrowserComputerError.computerRunning }
            _ = try checked(["rename", old.containerID, journal.backupName], timeout: 20)
            _ = try checked(["rename", newID, old.name], timeout: 20)
            var records = try metadataStore.load()
            guard let index = records.firstIndex(where: { $0.computerID == computerID }),
                  records[index].containerID == old.containerID else { throw BrowserComputerError.duplicateComputer }
            let previous = records[index]
            records[index] = BrowserComputerMetadata(computerID: previous.computerID,
                terminalID: previous.terminalID, containerID: newID,
                volumeName: previous.volumeName, createdAt: previous.createdAt)
            try metadataStore.save(records)
            // A failed remove is recoverable; the new canonical box is already durable.
            if (try? checked(["rm", old.containerID], timeout: 20)) != nil {
                try? removeImageUpdateJournal()
            }
            guard let updated = try inspectOwned(newID), !updated.running else {
                throw BrowserComputerError.updateRecoveryRequired
            }
            return updated
        } catch {
            do { try recoverInterruptedImageUpdate() }
            catch { throw BrowserComputerError.updateRecoveryRequired }
            throw error
        }
    }

    /// Explicitly finish or roll back a previously interrupted stopped-box update.
    public func recoverStoppedImageUpdate() throws {
        ComputerCreationLock.lock.lock(); defer { ComputerCreationLock.lock.unlock() }
        try recoverInterruptedImageUpdate()
    }

    public func pendingImageUpdate() throws -> PendingBrowserImageUpdate? {
        ComputerCreationLock.lock.lock(); defer { ComputerCreationLock.lock.unlock() }
        guard let journal = try loadImageUpdateJournal() else { return nil }
        return PendingBrowserImageUpdate(computerID: journal.computerID, terminalID: journal.terminalID)
    }

    public func imageUpdateRecoveryPending() throws -> Bool { try pendingImageUpdate() != nil }

    public func start(computerID: UUID, context: ComputerPolicyContext? = nil) throws -> BrowserManagedComputer {
        ComputerCreationLock.lock.lock(); defer { ComputerCreationLock.lock.unlock() }
        guard try loadImageUpdateJournal() == nil else { throw BrowserComputerError.updateRecoveryRequired }
        guard let computer = try list().first(where: { $0.id == computerID }) else { throw BrowserComputerError.missingComputer }
        if computer.running { return computer }
        let context = context ?? ComputerPolicyContext(terminalID: computer.terminalID)
        guard context.terminalID == computer.terminalID else { throw ComputerPolicyError.invalidScope }
        let policy = try policyStore.load().effective(for: context)
        guard policy.creation != .disabled else { throw BrowserComputerError.creationDisabled }
        guard policy.networkAllowed else { throw BrowserComputerError.networkDisabled }
        guard policy.limits.memoryMiB >= 2048 else { throw BrowserComputerError.insufficientMemory }
        try checkCapacity(policy)
        try start(computer)
        guard let running = try inspectOwned(computer.containerID), running.running else {
            throw BrowserComputerError.notReady
        }
        return running
    }

    /// Returns a capability only when the authenticated runtime confirms identity and readiness.
    public func reconnectEndpoint(computerID: UUID, session: URLSession? = nil,
                                  interactiveAuthorization: Bool = false) async throws -> BrowserRuntimeEndpoint {
        _ = try recoverMetadata()
        guard let computer = try list().first(where: { $0.id == computerID }), computer.running else {
            throw BrowserComputerError.missingComputer
        }
        let token = try interactiveAuthorization
            ? tokens.readInteractively(computerID: computerID) : tokens.read(computerID: computerID)
        let portText = try checked(["port", computer.containerID, "8765/tcp"], timeout: 8).stdout
        let port = try parseLoopbackPort(portText)
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/health"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let configuredSession: URLSession
        if let session { configuredSession = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuredSession = URLSession(configuration: configuration)
        }
        defer { if session == nil { configuredSession.invalidateAndCancel() } }
        let (data, response) = try await configuredSession.data(for: request, delegate: BrowserHealthRedirectRejector())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let health = try? JSONDecoder().decode(BrowserRuntimeHealth.self, from: data),
              health.computerID == computerID else { throw BrowserComputerError.notReady }
        return try BrowserRuntimeEndpoint(baseURL: baseURL, apiToken: token,
                                          computerID: computerID, generation: health.generation)
    }

    private func start(_ computer: BrowserManagedComputer) throws {
        guard try inspectOwned(computer.containerID)?.id == computer.id else { throw BrowserComputerError.unmanagedContainer }
        _ = try checked(["start", computer.containerID], timeout: 30)
    }

    private func inspectOwned(_ id: String, expectedName: String? = nil) throws -> BrowserManagedComputer? {
        let output = try checked(["inspect", "--format", "{{json .}}", id], timeout: 8).stdout
        guard let data = output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = json["Config"] as? [String: Any],
              let labels = config["Labels"] as? [String: String],
              let state = json["State"] as? [String: Any],
              let running = state["Running"] as? Bool,
              let containerID = json["Id"] as? String,
              let rawName = json["Name"] as? String,
              labels[Self.ownerLabel] == "true",
              let rawComputer = labels[Self.computerLabel], let computerID = UUID(uuidString: rawComputer),
              let rawTerminal = labels[Self.terminalLabel], let terminalID = UUID(uuidString: rawTerminal) else {
            throw BrowserComputerError.invalidDockerResponse
        }
        let volume = "agentbox-browser-data-\(computerID.uuidString.lowercased())"
        guard rawName == "/\(expectedName ?? "agentbox-browser-\(computerID.uuidString.lowercased())")" else { return nil }
        return BrowserManagedComputer(id: computerID, terminalID: terminalID,
                                      containerID: containerID, name: String(rawName.dropFirst()),
                                      volumeName: volume, running: running)
    }

    private static func validContainerID(_ value: String) -> Bool {
        (12...64).contains(value.count) && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func validImageID(_ value: String) -> Bool {
        value.hasPrefix("sha256:") && value.count == 71 &&
            value.dropFirst(7).allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private func configuredImageID() throws -> String {
        guard let result = try? runner.run(["image", "inspect", "--format", "{{.Id}}", Self.image], timeout: 8),
              result.exitCode == 0 else { throw BrowserComputerError.imageUnavailable }
        let id = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validImageID(id) else { throw BrowserComputerError.imageUnavailable }
        return id
    }

    private func containerImageID(_ id: String) throws -> String {
        let value = try checked(["inspect", "--format", "{{.Image}}", id], timeout: 8)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validImageID(value) else { throw BrowserComputerError.invalidDockerResponse }
        return value
    }

    private func inspectIfPresent(_ reference: String) throws -> String? {
        let result = try runner.run(["inspect", "--format", "{{.Id}}", reference], timeout: 8)
        guard result.exitCode == 0 else {
            let detail = (result.stderr.isEmpty ? result.stdout : result.stderr).lowercased()
            if detail.contains("no such object") || detail.contains("no such container") { return nil }
            throw BrowserComputerError.commandFailed(detail.isEmpty ? "inspect falhou" : detail)
        }
        let id = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validContainerID(id) else { throw BrowserComputerError.invalidDockerResponse }
        return id
    }

    private func verifyOwnedVolume(_ id: String, computer: BrowserManagedComputer) throws {
        let output = try checked(["inspect", "--format", "{{json .Mounts}}", id], timeout: 8).stdout
        guard let data = output.data(using: .utf8),
              let mounts = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              mounts.count == 1,
              mounts[0]["Type"] as? String == "volume",
              mounts[0]["Name"] as? String == computer.volumeName,
              mounts[0]["Destination"] as? String == "/data" else {
            throw BrowserComputerError.unmanagedContainer
        }
        let volume = try checked(["volume", "inspect", "--format", "{{json .Labels}}", computer.volumeName], timeout: 8).stdout
        guard let volumeData = volume.data(using: .utf8),
              let labels = try JSONSerialization.jsonObject(with: volumeData) as? [String: String],
              labels[Self.ownerLabel] == "true",
              labels[Self.computerLabel] == computer.id.uuidString.lowercased() else {
            throw BrowserComputerError.unmanagedContainer
        }
    }

    private func verifyMetadata(_ computer: BrowserManagedComputer) throws {
        let records = try metadataStore.load()
        guard records.count(where: { $0.computerID == computer.id || $0.terminalID == computer.terminalID }) == 1,
              let record = records.first(where: { $0.computerID == computer.id }),
              record.terminalID == computer.terminalID,
              record.containerID == computer.containerID,
              record.volumeName == computer.volumeName else { throw BrowserComputerError.duplicateComputer }
    }

    private func createArguments(name: String, computerID: UUID, terminalID: UUID, volume: String,
                                 policy: EffectiveComputerPolicy, environmentFile: URL,
                                 image: String) -> [String] {
        ["create", "--name", name,
         "--label", "\(Self.ownerLabel)=true",
         "--label", "\(Self.computerLabel)=\(computerID.uuidString.lowercased())",
         "--label", "\(Self.terminalLabel)=\(terminalID.uuidString.lowercased())",
         "--cpus", String(policy.limits.cpus), "--memory", "\(policy.limits.memoryMiB)m",
         "--pids-limit", "256", "--shm-size", "256m",
         "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
         "--read-only", "--tmpfs", "/tmp:rw,nosuid,nodev,size=256m",
         "--tmpfs", "/home/agentbox:rw,nosuid,nodev,size=32m,uid=10001,gid=10001",
         "--network", "bridge", "--publish", "127.0.0.1::8765",
         "--mount", "type=volume,source=\(volume),target=/data",
         "--env-file", environmentFile.path, "--init", image]
    }

    private var imageUpdateJournalURL: URL {
        metadataStore.url.appendingPathExtension("image-update.json")
    }

    private func loadImageUpdateJournal() throws -> BrowserImageUpdateJournal? {
        let path = imageUpdateJournalURL.path
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw BrowserComputerError.updateRecoveryRequired
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_size < 16_384 else { throw BrowserComputerError.updateRecoveryRequired }
        let journal: BrowserImageUpdateJournal
        do {
            journal = try JSONDecoder().decode(BrowserImageUpdateJournal.self, from: Data(contentsOf: imageUpdateJournalURL))
        } catch { throw BrowserComputerError.updateRecoveryRequired }
        let temporaryPrefix = "agentbox-updating-"
        let backupPrefix = "agentbox-backup-"
        guard Self.validContainerID(journal.oldContainerID),
              journal.newContainerID.map(Self.validContainerID) ?? true,
              journal.newContainerID != journal.oldContainerID,
              Self.validImageID(journal.targetImageID),
              journal.volumeName == "agentbox-browser-data-\(journal.computerID.uuidString.lowercased())",
              journal.temporaryName.hasPrefix(temporaryPrefix),
              journal.backupName.hasPrefix(backupPrefix),
              let temporaryNonce = UUID(uuidString: String(journal.temporaryName.dropFirst(temporaryPrefix.count))),
              let backupNonce = UUID(uuidString: String(journal.backupName.dropFirst(backupPrefix.count))),
              temporaryNonce == backupNonce,
              journal.temporaryName == temporaryPrefix + temporaryNonce.uuidString.lowercased(),
              journal.backupName == backupPrefix + backupNonce.uuidString.lowercased() else {
            throw BrowserComputerError.updateRecoveryRequired
        }
        return journal
    }

    private func saveImageUpdateJournal(_ journal: BrowserImageUpdateJournal) throws {
        let url = imageUpdateJournalURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let template = url.path + ".XXXXXX"
        var bytes = Array(template.utf8CString)
        let fd = bytes.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { throw BrowserComputerError.updateRecoveryRequired }
        let temporary = String(cString: bytes)
        var closed = false
        defer {
            if !closed { _ = Darwin.close(fd) }
            _ = Darwin.unlink(temporary)
        }
        let data = try JSONEncoder().encode(journal)
        guard fchmod(fd, 0o600) == 0 else { throw BrowserComputerError.updateRecoveryRequired }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw BrowserComputerError.updateRecoveryRequired }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw BrowserComputerError.updateRecoveryRequired }
        _ = Darwin.close(fd); closed = true
        var existing = stat()
        if lstat(url.path, &existing) == 0 {
            guard existing.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  existing.st_uid == getuid() else { throw BrowserComputerError.updateRecoveryRequired }
        } else if errno != ENOENT { throw BrowserComputerError.updateRecoveryRequired }
        guard Darwin.rename(temporary, url.path) == 0 else { throw BrowserComputerError.updateRecoveryRequired }
        try syncImageUpdateJournalDirectory()
    }

    private func removeImageUpdateJournal() throws {
        guard try loadImageUpdateJournal() != nil else { return }
        guard Darwin.unlink(imageUpdateJournalURL.path) == 0 else { throw BrowserComputerError.updateRecoveryRequired }
        try syncImageUpdateJournalDirectory()
    }

    private func syncImageUpdateJournalDirectory() throws {
        let fd = Darwin.open(imageUpdateJournalURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw BrowserComputerError.updateRecoveryRequired }
        defer { _ = Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw BrowserComputerError.updateRecoveryRequired }
    }

    private func recoverInterruptedImageUpdate() throws {
        guard let journal = try loadImageUpdateJournal() else { return }
        guard let record = try metadataStore.load().first(where: { $0.computerID == journal.computerID }),
              record.terminalID == journal.terminalID,
              record.volumeName == journal.volumeName else { throw BrowserComputerError.updateRecoveryRequired }
        let canonicalName = "agentbox-browser-\(journal.computerID.uuidString.lowercased())"
        guard try inspectIfPresent(journal.oldContainerID) == journal.oldContainerID else {
            // Only a committed update may have already removed the backup.
            guard let newID = journal.newContainerID, record.containerID == newID,
                  let new = try inspectOwned(newID), !new.running,
                  new.id == journal.computerID, new.terminalID == journal.terminalID else {
                throw BrowserComputerError.updateRecoveryRequired
            }
            try verifyOwnedVolume(newID, computer: new)
            guard try containerImageID(newID) == journal.targetImageID else {
                throw BrowserComputerError.updateRecoveryRequired
            }
            try metadataStore.save(try metadataStore.load())
            try removeImageUpdateJournal()
            return
        }
        let oldCanonical = try inspectOwned(journal.oldContainerID)
        let oldBackup = try inspectOwned(journal.oldContainerID, expectedName: journal.backupName)
        guard let old = oldCanonical ?? oldBackup,
              !old.running, old.id == journal.computerID,
              old.terminalID == journal.terminalID else { throw BrowserComputerError.updateRecoveryRequired }
        try verifyOwnedVolume(journal.oldContainerID, computer: old)
        let foundNewID = try inspectIfPresent(journal.temporaryName)
            ?? journal.newContainerID.flatMap { try inspectIfPresent($0) }
        if let persisted = journal.newContainerID, let foundNewID,
           persisted != foundNewID { throw BrowserComputerError.updateRecoveryRequired }
        // A prior rollback can remove the candidate yet fail to unlink the
        // journal (for example when its directory becomes temporarily read-only).
        let newID = foundNewID
        var newCanonical: BrowserManagedComputer?
        var newTemporary: BrowserManagedComputer?
        if let newID {
            newCanonical = try inspectOwned(newID, expectedName: canonicalName)
            newTemporary = try inspectOwned(newID, expectedName: journal.temporaryName)
            guard let new = newCanonical ?? newTemporary,
                  !new.running, new.id == journal.computerID,
                  new.terminalID == journal.terminalID,
                  new.volumeName == journal.volumeName,
                  try containerImageID(newID) == journal.targetImageID else {
                throw BrowserComputerError.updateRecoveryRequired
            }
            try verifyOwnedVolume(newID, computer: new)
        }
        if record.containerID == journal.oldContainerID {
            // Metadata has not committed: return to the original canonical box.
            if let newID, newCanonical != nil {
                _ = try checked(["rename", newID, journal.temporaryName], timeout: 20)
            }
            if oldBackup != nil {
                _ = try checked(["rename", journal.oldContainerID, canonicalName], timeout: 20)
            }
            if let newID { _ = try checked(["rm", newID], timeout: 20) }
            try removeImageUpdateJournal()
        } else if let newID, record.containerID == newID {
            // Metadata committed: never roll back the new canonical container.
            guard newCanonical != nil, oldBackup != nil else { throw BrowserComputerError.updateRecoveryRequired }
            // The JSON rename may have succeeded even if its subsequent fsync failed.
            // Do not discard the backup until the committed record is durable.
            try metadataStore.save(try metadataStore.load())
            _ = try checked(["rm", journal.oldContainerID], timeout: 20)
            try removeImageUpdateJournal()
        } else {
            throw BrowserComputerError.updateRecoveryRequired
        }
    }

    private func checkCapacity(_ policy: EffectiveComputerPolicy) throws {
        let browser = try checked(["ps", "-q", "--filter", "label=\(Self.ownerLabel)=true"], timeout: 8)
            .stdout.split(whereSeparator: \.isNewline)
        let legacy = try checked(["ps", "-q", "--filter", "label=\(DockerComputerService<Runner>.ownerLabel)=true"], timeout: 8)
            .stdout.split(whereSeparator: \.isNewline)
        guard browser.count + legacy.count < policy.limits.maxComputers else { throw BrowserComputerError.resourceLimit }
    }

    private func parseLoopbackPort(_ output: String) throws -> Int {
        let entries = output.split(whereSeparator: \.isNewline)
        guard entries.count == 1, entries[0].hasPrefix("127.0.0.1:"),
              let port = Int(entries[0].dropFirst("127.0.0.1:".count)), (1...65535).contains(port) else {
            throw BrowserComputerError.invalidPort
        }
        return port
    }

    private func temporaryEnvironmentFile(computerID: UUID, token: String) throws -> URL {
        let template = FileManager.default.temporaryDirectory.appendingPathComponent("agentbox-browser-env-XXXXXX").path
        var bytes = Array(template.utf8CString)
        let fd = bytes.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { throw BrowserComputerError.commandFailed("Não foi possível criar arquivo temporário.") }
        let url = URL(fileURLWithPath: String(cString: bytes))
        do {
            guard fchmod(fd, 0o600) == 0 else { throw BrowserComputerError.commandFailed("Permissão de arquivo temporário inválida.") }
            let text = "AB_API_TOKEN=\(token)\nAB_COMPUTER_ID=\(computerID.uuidString)\n"
            let data = Data(text.utf8)
            try data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw BrowserComputerError.commandFailed("Falha ao gravar ambiente temporário.") }
                    offset += count
                }
            }
            guard fsync(fd) == 0 else { throw BrowserComputerError.commandFailed("Falha ao sincronizar ambiente temporário.") }
            _ = Darwin.close(fd)
            return url
        } catch {
            _ = Darwin.close(fd); try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw BrowserComputerError.missingToken
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func checked(_ args: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        let result = try runner.run(args, timeout: timeout)
        guard result.exitCode == 0 else {
            let detail = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw BrowserComputerError.commandFailed(detail.isEmpty ? "código \(result.exitCode)" : detail)
        }
        return result
    }
}

private final class BrowserHealthRedirectRejector: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
