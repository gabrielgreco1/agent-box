import AgentBoxDocker
import Foundation
import Security

/// ULID (48 bits de tempo + 80 aleatórios, Crockford): mesmo formato dos ids do reqlog.
public enum ULID {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func generate(nowMs: UInt64? = nil) -> String {
        var random = [UInt8](repeating: 0, count: 10)
        _ = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
        var value: [UInt8] = []  // 16 bytes big-endian: 6 de tempo + 10 aleatórios
        let ts = nowMs ?? UInt64(Date().timeIntervalSince1970 * 1000)
        for shift in stride(from: 40, through: 0, by: -8) { value.append(UInt8((ts >> UInt64(shift)) & 0xFF)) }
        value += random
        var out: [Character] = []
        var bits = 0, buffer = 0
        for byte in value.reversed() {
            buffer |= Int(byte) << bits
            bits += 8
            while bits >= 5 { out.append(alphabet[buffer & 31]); buffer >>= 5; bits -= 5 }
        }
        if bits > 0 { out.append(alphabet[buffer & 31]) }
        return String(out.prefix(26).reversed())
    }
}

public enum BoxState: String, Sendable, Equatable, Codable { case queued, provisioning, ready, inUse = "in_use", stopped, failed }
public enum Lease: String, Sendable, Equatable, Codable { case agent, human }
public enum HelpKind: String, Sendable, Codable, CaseIterable { case captcha, login, mfa, choice, download, permission, other }
public enum HelpStatus: String, Sendable, Codable { case open, takenOver = "taken_over", resolved, declined, cancelled, expired }

public struct HelpRequest: Sendable, Equatable {
    public var id: String
    public var kind: HelpKind
    public var reason: String
    public var url: String?
    public var question: String?
    public var options: [String]
    public var status: HelpStatus
    public var humanNote: String?
    public var choice: String?
    public var declineReason: String?
    public var createdAt: Date
    public var cookieFingerprint: String
    public var downloadsAtRequest: Set<String>
    public var resolvedState: JSON?

    public var isOpen: Bool { status == .open || status == .takenOver }
}

/// Evento para a UI e para o app (Inbox, sidebar, notificação). A UI chega em T3-05.
public enum ComputerEvent: Sendable, Equatable {
    case helpRequested(computer: String, requestID: String, kind: HelpKind)
    case helpResolved(computer: String, requestID: String, status: HelpStatus)
    case doing(computer: String, text: String)
    case blocked(computer: String, text: String)
    case released(computer: String)
    /// Reservado e nunca reivindicado em 10 min (CS-302): `"Unclaimed computer"`.
    case unclaimed(computer: String)
}

/// Um computador no ar: estado, dono (filho que reivindicou), lease, pedidos de ajuda e os logs do run que ficam fora do
/// alcance do agente (07 §3, §2.8). O Docker vem atrás de `ComputerBackend`.
public actor ManagedComputer {
    public nonisolated let name: String
    public nonisolated let run: RunFolder
    public nonisolated let backend: any ComputerBackend
    public nonisolated let profile: String?
    public nonisolated let proxiesAllowed: [String]
    public nonisolated let journal: ChainedLog
    public nonisolated let commands: ChainedLog
    public nonisolated let helpLog: ChainedLog
    public nonisolated let messages: ChainedLog
    public nonisolated let events: ChainedLog

    public private(set) var display: ComputerDisplay
    public private(set) var state: BoxState
    public private(set) var queuePosition: Int?
    public private(set) var owner: String?
    public private(set) var lease: Lease = .agent
    public private(set) var proxy: String
    public private(set) var country: String?
    public private(set) var lastDoing: String?
    public private(set) var openBlocked: String?
    public private(set) var runID = ULID.generate()
    private var previousRun: JSON?
    private var helps: [String: HelpRequest] = [:]
    private var commandNumber = 0
    private var observer: (@Sendable (ComputerEvent) -> Void)?

    public init(name: String, display: ComputerDisplay, run: RunFolder, backend: any ComputerBackend, state: BoxState = .ready,
                proxy: String = "direct", proxiesAllowed: [String] = [], profile: String? = nil) throws {
        self.name = name
        self.display = display
        self.run = run
        self.backend = backend
        self.state = state
        self.proxy = proxy
        self.proxiesAllowed = proxiesAllowed
        self.profile = profile
        try run.ensureLayout()
        journal = ChainedLog(file: run.file("journal.jsonl"))
        commands = ChainedLog(file: run.file("commands.jsonl"))
        helpLog = ChainedLog(file: run.file("help.jsonl"))
        messages = ChainedLog(file: run.file("messages.jsonl"))
        events = ChainedLog(file: run.file("events.jsonl"))
        let numbers = (try? FileManager.default.contentsOfDirectory(atPath: run.commandsDirectory.path)) ?? []
        commandNumber = numbers.compactMap { Int($0.prefix(4)) }.max() ?? 0
    }

    public func setObserver(_ observer: (@Sendable (ComputerEvent) -> Void)?) { self.observer = observer }
    func emit(_ event: ComputerEvent) { observer?(event) }

    // MARK: Estado

    public func setState(_ new: BoxState, position: Int? = nil) {
        state = (new == .ready && owner != nil) ? .inUse : new
        queuePosition = position
    }
    public func setDisplay(_ new: ComputerDisplay) { display = new }
    public func setProxy(_ name: String, country: String?) { proxy = name; self.country = country }

    /// Espera o computador ficar `ready` (long-poll de `box_claim`).
    public func waitUntilReady(timeout: Duration) async -> BoxState {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, state == .queued || state == .provisioning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return state
    }

    // MARK: Dono

    func claim(by child: String) throws {
        if let owner, owner != child {
            throw ToolError(.alreadyClaimed, "computer \(name) is already claimed by another child", details: ["owner": .string(owner)])
        }
        if owner == nil, journal.fileHasContent { previousRun = previousRunSummary() }
        owner = child
        if state == .ready { state = .inUse }
    }

    func release() {
        owner = nil
        if state == .inUse { state = .ready }
    }

    /// `previous_run` de `box_claim` (CS-185): onde o filho anterior parou.
    private func previousRunSummary() -> JSON? {
        let entries = ChainedLog.read(journal.file)
        guard !entries.isEmpty else { return nil }
        var out: [String: JSON] = ["run_id": .string(runID)]
        if let doing = entries.last(where: { $0["kind"]?.string == "DOING" })?["text"] { out["last_doing"] = doing }
        if let blocked = entries.last(where: { $0["kind"]?.string == "BLOCKED" })?["text"] { out["open_blocked"] = blocked }
        return .object(out)
    }

    func takePreviousRun() -> JSON? { defer { previousRun = nil }; return previousRun }

    // MARK: Lease humano (T3-05 liga os botões; aqui só o estado e a regra)

    public func takeOver() { lease = .human; for id in helps.keys where helps[id]?.status == .open { helps[id]?.status = .takenOver } }
    public func handBack() { lease = .agent }

    /// Escritas do agente no computador ficam pausadas durante pedido de ajuda e controle humano (CS-272).
    func pauseReason() -> ToolError? {
        if lease == .human || helps.values.contains(where: { $0.status == .takenOver }) {
            return ToolError(.humanInControl, "a human is controlling this computer; wait for Hand Back", retryAfterS: 5)
        }
        if helps.values.contains(where: { $0.status == .open }) {
            return ToolError(.waitingHelp, "a help request is open; poll help_wait before acting", retryAfterS: 5)
        }
        return nil
    }

    func stateGate() -> ToolError? {
        switch state {
        case .ready, .inUse: nil
        case .queued, .provisioning: ToolError(.queued, "computer \(name) is not ready yet (\(state.rawValue))", retryAfterS: 5)
        case .stopped: ToolError(.boxRestarted, "computer \(name) is stopped; claim it again", retryAfterS: 5)
        case .failed: ToolError(.boxRestarted, "computer \(name) failed to start", retryAfterS: 30)
        }
    }

    // MARK: Diário

    @discardableResult
    func appendJournal(kind: String, text: String, evidence: [String], system: Bool = false) async throws -> [String: JSON] {
        var entry: [String: JSON] = ["id": .string(ULID.generate()), "kind": .string(kind), "text": .string(text), "run_id": .string(runID)]
        if !evidence.isEmpty { entry["evidence"] = .array(evidence.map { .string($0) }) }
        if system { entry["system"] = true }
        let written = try await journal.append(entry)
        if kind == "DOING" { lastDoing = text; emit(.doing(computer: name, text: text)) }
        if kind == "BLOCKED" { openBlocked = text; emit(.blocked(computer: name, text: text)) }
        if kind == "DOING" || kind == "FOUND" { openBlocked = nil }
        return written
    }

    func logEvent(_ kind: String, _ text: String) async {
        _ = try? await events.append(["kind": .string(kind), "text": .string(text)])
    }

    func nextCommandNumber() -> Int { commandNumber += 1; return commandNumber }

    // MARK: Ajuda humana (CS-270..273)

    func requestHelp(kind: HelpKind, reason: String, url: String?, question: String?, options: [String]) async throws -> HelpRequest {
        // Repetir kind + url enquanto há um aberto devolve o mesmo id (nada de pedido, som ou notificação duplicados).
        if let existing = helps.values.first(where: { $0.isOpen && $0.kind == kind && $0.url == url }) { return existing }
        let cookies = await cookieFingerprint()
        let request = HelpRequest(
            id: ULID.generate(), kind: kind, reason: reason, url: url, question: question, options: options, status: .open, createdAt: Date(),
            cookieFingerprint: cookies, downloadsAtRequest: downloads())
        helps[request.id] = request
        var entry: [String: JSON] = ["id": .string(request.id), "event": "requested", "kind": .string(kind.rawValue), "reason": .string(reason)]
        if let url { entry["url"] = .string(url) }
        if let question { entry["question"] = .string(question) }
        _ = try? await helpLog.append(entry)
        emit(.helpRequested(computer: name, requestID: request.id, kind: kind))
        return request
    }

    public func help(_ id: String) -> HelpRequest? { helps[id] }
    public var openHelpID: String? { helps.values.filter(\.isOpen).sorted { $0.createdAt < $1.createdAt }.first?.id }

    /// O humano resolveu (a UI da T3-05 chama; os testes também). Reconcilia o estado do computador para `help_wait`.
    public func resolveHelp(_ id: String, note: String?, choice: String? = nil) async throws {
        guard var request = helps[id], request.isOpen else { throw ToolError(.notFound, "no open help request \(id)") }
        request.status = .resolved
        request.humanNote = note
        request.choice = choice
        request.resolvedState = await reconcile(request)
        helps[id] = request
        lease = .agent
        _ = try? await helpLog.append(["id": .string(id), "event": "resolved", "note": note.map { .string($0) } ?? .null])
        emit(.helpResolved(computer: name, requestID: id, status: .resolved))
    }

    public func declineHelp(_ id: String, reason: String?) async {
        guard var request = helps[id], request.isOpen else { return }
        request.status = .declined
        request.declineReason = reason
        helps[id] = request
        _ = try? await helpLog.append(["id": .string(id), "event": "declined"])
        emit(.helpResolved(computer: name, requestID: id, status: .declined))
    }

    func cancelHelp(_ id: String) async throws -> HelpRequest {
        guard var request = helps[id] else { throw ToolError(.notFound, "no help request \(id)") }
        if request.isOpen {
            request.status = .cancelled
            helps[id] = request
            _ = try? await helpLog.append(["id": .string(id), "event": "cancelled"])
            emit(.helpResolved(computer: name, requestID: id, status: .cancelled))
        }
        return request
    }

    /// Long-poll repetível e idempotente (nunca > 50 s).
    func waitHelp(_ id: String, wait: Duration) async throws -> HelpRequest {
        guard helps[id] != nil else { throw ToolError(.notFound, "no help request \(id)") }
        let deadline = ContinuousClock.now + min(wait, .seconds(50))
        while ContinuousClock.now < deadline, helps[id]?.isOpen == true {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return helps[id]!
    }

    private func cookieFingerprint() async -> String {
        guard display != .http, let out = try? await backend.runtime("cookies", ["action": "get"], timeout: 10),
              let cookies = out["cookies"]?.array else { return "" }
        return cookies.compactMap { c in "\(c["domain"]?.string ?? "")|\(c["name"]?.string ?? "")=\(c["value"]?.string ?? "")" }.sorted().joined(separator: ";")
    }

    private func downloads() -> Set<String> {
        let dir = run.work.appendingPathComponent("downloads")
        return Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    }

    private func reconcile(_ request: HelpRequest) async -> JSON {
        var state: [String: JSON] = [:]
        if display != .http {
            if let status = try? await backend.runtime("status", [:], timeout: 10) {
                state["url"] = status["url"] ?? .null
                state["title"] = status["title"] ?? .null
            }
            if let tabs = try? await backend.runtime("tabs", ["action": "list"], timeout: 10) { state["tabs"] = tabs["tabs"] ?? [] }
        }
        state["cookies_changed"] = .bool(await cookieFingerprint() != request.cookieFingerprint)
        state["new_downloads"] = .array(downloads().subtracting(request.downloadsAtRequest).sorted().map { .string("/work/downloads/" + $0) })
        return .object(state)
    }
}

extension ChainedLog {
    /// Há alguma linha gravada? (leitura barata do tamanho do arquivo; usado só para o `previous_run`).
    nonisolated var fileHasContent: Bool {
        ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.intValue ?? 0 > 0
    }
}
