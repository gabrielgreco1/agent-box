import Foundation

public struct ReaperReport: Sendable, Equatable {
    public var terminated: [String] = []
    public var kept: [String] = []
    public var failures: [String: String] = [:]
    /// Por que cada um foi encerrado (`expired` ou `orphan`).
    public var reasons: [String: String] = [:]
    public init() {}
}

/// Reaper (estudo 6.1, camada 5): lista PELAS TAGS do dono em cada região habilitada e encerra órfãos e vencidos.
/// Nunca toca em recurso sem `racky:managed=true` + `racky:owner=<este app>`: a listagem já vai filtrada e o resultado é conferido de novo.
public struct HostReaper: Sendable {
    public let provider: any CloudProvider
    public let owner: String
    /// Host sem dono conhecido só vira órfão depois disto (dá tempo de o app registrar a VM que acabou de criar).
    public let orphanGrace: Duration

    public init(provider: any CloudProvider, owner: String, orphanGrace: Duration = .seconds(600)) {
        self.provider = provider; self.owner = owner; self.orphanGrace = orphanGrace
    }

    /// `knownHostIDs`: hosts que o app sabe estar em uso (ids do provedor).
    public func sweep(knownHostIDs: Set<String>, regions: [String], now: Date = Date()) async throws -> ReaperReport {
        var report = ReaperReport()
        let hosts = try await provider.listHosts(tags: RackyTags.filter(owner: owner), regions: regions)
        for host in hosts where host.state.isLive {
            // Defesa em profundidade: um adaptador com filtro frouxo não pode nos fazer apagar o que não é nosso.
            guard let tags = RackyTags(host.tags), tags.owner == owner else { continue }
            let reason: String?
            if tags.expires <= now {
                reason = "expired"
            } else if !knownHostIDs.contains(host.id), now.timeIntervalSince(tags.created) >= Double(orphanGrace.components.seconds) {
                reason = "orphan"
            } else {
                reason = nil
            }
            guard let reason else { report.kept.append(host.id); continue }
            do {
                try await provider.terminateHost(id: host.id, region: host.region)
                report.terminated.append(host.id)
                report.reasons[host.id] = reason
            } catch {
                report.failures[host.id] = "\(error)"
            }
        }
        return report
    }
}
