import Foundation

/// Orquestra o ciclo de vida de VMs host do ponto de vista do app: AUP aceito, cota, teto de gasto, criação com tags e cloud-init,
/// encerramento, reaper. É a ÚNICA porta de entrada para criar VM (nada cria recurso sem passar pelo teto de gasto).
public actor CloudHostManager {
    public struct Settings: Sendable {
        public var owner: String
        public var caps: SpendCaps
        public var policy: DeadManPolicy
        public var calendar: Calendar
        public init(owner: String, caps: SpendCaps = SpendCaps(), policy: DeadManPolicy = DeadManPolicy(), calendar: Calendar = .current) {
            self.owner = owner; self.caps = caps; self.policy = policy; self.calendar = calendar
        }
    }

    /// Chaves do host para o cloud-init (geradas pelo app; ver `SSHKeyPair`).
    public struct Access: Sendable {
        public var authorizedKey: String
        public var hostKey: CloudInit.HostKey
        public init(authorizedKey: String, hostKey: CloudInit.HostKey) { self.authorizedKey = authorizedKey; self.hostKey = hostKey }
    }

    public let provider: any CloudProvider
    public var settings: Settings
    public private(set) var ledger = SpendLedger()
    private let clock: @Sendable () -> Date
    private let acceptedAUP: @Sendable (CloudProviderID, String) async -> Bool
    private var hosts: [String: CloudHost] = [:]

    /// `acceptedAUP(provider, versão)`: o usuário já confirmou este AUP? (P27.7)
    public init(provider: any CloudProvider, settings: Settings, clock: @escaping @Sendable () -> Date = { Date() },
                acceptedAUP: @escaping @Sendable (CloudProviderID, String) async -> Bool) {
        self.provider = provider; self.settings = settings; self.clock = clock; self.acceptedAUP = acceptedAUP
    }

    public var activeHosts: [CloudHost] { hosts.values.filter { $0.state.isLive }.sorted { $0.id < $1.id } }
    public func updateCaps(_ caps: SpendCaps) { settings.caps = caps }

    /// Cria um host. Falha ANTES de criar qualquer coisa se: o AUP não foi aceito, falta cota ou o teto de gasto estouraria.
    public func acquireHost(region: String, shape: HostShape, runID: String? = nil, access: Access) async throws -> CloudHost {
        let now = clock()
        let aup = try await provider.acceptableUsePolicy()
        guard await acceptedAUP(provider.id, aup.version) else { throw CloudError.acceptableUseNotAccepted(provider: provider.id, version: aup.version) }
        let quota = try await provider.quota(region: region)
        guard quota.vcpuAvailable >= shape.vcpus else { throw CloudError.quotaExceeded(region: region, needed: shape.vcpus, available: quota.vcpuAvailable) }
        let estimate = try await provider.estimate(shape: shape, region: region)
        let lifetime = settings.policy.maxLifetime
        let expires = now.addingTimeInterval(TimeInterval(lifetime.components.seconds))
        let hostID = UUID().uuidString.lowercased()
        let candidate = SpendRecord(hostID: hostID, startedAt: now, expiresAt: expires, hourlyUSD: estimate.hourlyUSD)
        if let denial = SpendGuard(caps: settings.caps, calendar: settings.calendar).evaluate(newHost: candidate, ledger: ledger, now: now) {
            throw CloudError.spendCapExceeded(denial)
        }
        let tags = RackyTags(owner: settings.owner, host: hostID, run: runID, created: now, expires: expires, provider: provider.id)
        let userData = CloudInit.userData(policy: settings.policy, authorizedKey: access.authorizedKey, hostKey: access.hostKey)
        let host = try await provider.provisionHost(HostRequest(region: region, shape: shape, tags: tags, userData: userData, maxLifetime: lifetime))
        var record = candidate
        record.hostID = host.id
        ledger.open(record)
        hosts[host.id] = host
        return host
    }

    public func releaseHost(id: String) async throws {
        guard let host = hosts[id] else { throw CloudError.notFound(id) }
        try await provider.terminateHost(id: id, region: host.region)
        ledger.close(hostID: id, at: clock())
        hosts[id]?.state = .terminated
    }

    public struct CapEnforcement: Sendable, Equatable {
        public var denial: SpendDenial
        public var terminated: [String]
    }

    /// Durante o uso: se o ACUMULADO passou de um teto, encerra TODOS os hosts. Devolve o motivo e os ids.
    @discardableResult
    public func enforceCaps() async -> CapEnforcement? {
        let now = clock()
        guard let denial = SpendGuard(caps: settings.caps, calendar: settings.calendar).breach(ledger: ledger, now: now) else { return nil }
        var done: [String] = []
        for host in activeHosts {
            if (try? await releaseHost(id: host.id)) != nil { done.append(host.id) }
        }
        return CapEnforcement(denial: denial, terminated: done)
    }

    /// Reaper por tag em `regions`; fecha no livro-caixa o que foi encerrado.
    public func reap(regions: [String]) async throws -> ReaperReport {
        let report = try await HostReaper(provider: provider, owner: settings.owner).sweep(
            knownHostIDs: Set(activeHosts.map(\.id)), regions: regions, now: clock())
        for id in report.terminated {
            ledger.close(hostID: id, at: clock())
            hosts[id]?.state = .terminated
        }
        return report
    }
}
