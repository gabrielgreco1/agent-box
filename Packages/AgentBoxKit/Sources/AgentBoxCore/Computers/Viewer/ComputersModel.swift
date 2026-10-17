import Foundation
import Observation

/// Uma linha da aba Computers e da página Computers (07 CS-403, CS-440).
public struct ComputerRow: Identifiable, Sendable, Equatable {
    public var id: String { snapshot.name }
    public var snapshot: ViewerSnapshot
    /// JPEG da miniatura (≤ 1 fps); decodificado fora do main thread pela UI (audit/09 N13).
    public var thumbnail: Data?
    public var sessionTitle: String?
    public var owner: String?
    public var lastActivity: Date
    public var needsYou: Bool { snapshot.help != nil }
}

/// Item do Inbox para pedidos de ajuda de computador (03 §9.1): um por `request_id`.
public struct InboxItem: Identifiable, Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case needsYou, resolved, declined, cancelled }
    public var id: String
    public var computer: String
    public var summary: HelpSummary
    public var createdAt: Date
    public var read = false
    public var phase: Phase = .needsYou
    /// Linha 2 do item: `<computer> needs you · CAPTCHA on <host>`.
    public var message: String { "\(computer) needs you · \(summary.headline)" }
}

/// Texto da notificação do macOS para um pedido de ajuda (CS-433): sem conteúdo de página nem dado sensível.
public struct HelpNotificationContent: Sendable, Equatable {
    public var title: String
    public var body: String
    public var threadID: String

    public static func make(session: String?, computer: String, summary: HelpSummary) -> HelpNotificationContent {
        HelpNotificationContent(
            title: session.map { "\($0) — \(computer) needs you" } ?? "\(computer) needs you", body: summary.headline, threadID: session ?? computer)
    }
}

/// Diretório dos computadores da UI: linhas ordenadas ("precisa de você" e depois atividade recente), Inbox de pedidos de ajuda,
/// contagem para o Dock e notificação uma vez por `request_id`. O Docker e o hub ficam atrás de `ManagedComputer`.
@MainActor
@Observable
public final class ComputersModel {
    public private(set) var rows: [ComputerRow] = []
    public private(set) var inbox: [InboxItem] = []
    /// Pedidos abertos e não resolvidos: o número do badge do Dock (03 §9.3).
    public var attentionCount: Int { inbox.filter { $0.phase == .needsYou }.count }
    public var sessionTitle: (String) -> String? = { _ in nil }
    @ObservationIgnored public var onHelpRequested: (InboxItem, HelpNotificationContent) -> Void = { _, _ in }
    @ObservationIgnored public var onAttentionChange: (Int) -> Void = { _ in }

    private var computers: [String: ManagedComputer] = [:]
    private var activity: [String: Date] = [:]
    private var notified: Set<String> = []
    private var thumbnails: [String: (data: Data, at: Date)] = [:]
    private var thumbnailInFlight: Set<String> = []

    public init() {}

    public func computer(named name: String) -> ManagedComputer? { computers[name] }

    /// Passa a acompanhar um computador: eventos (pedido de ajuda, controle) chegam aqui.
    public func attach(_ computer: ManagedComputer) async {
        computers[computer.name] = computer
        activity[computer.name] = activity[computer.name] ?? Date()
        let name = computer.name
        await computer.setObserver { [weak self] event in
            Task { @MainActor in self?.ingest(event, computer: name) }
        }
        await refresh()
    }

    public func detach(name: String) {
        computers[name] = nil
        rows.removeAll { $0.id == name }
    }

    // MARK: Eventos

    public func ingest(_ event: ComputerEvent, computer name: String, now: Date = Date()) {
        activity[name] = now
        switch event {
        case .helpRequested(_, let requestID, _):
            Task { await self.recordHelp(requestID, computer: name, now: now) }
        case .helpResolved(_, let requestID, let status):
            guard let index = inbox.firstIndex(where: { $0.id == requestID }) else { return }
            inbox[index].phase = switch status {
            case .declined: .declined
            case .cancelled, .expired: .cancelled
            default: .resolved
            }
            inbox[index].read = true
            onAttentionChange(attentionCount)
        case .control, .doing, .blocked, .released: break
        }
    }

    private func recordHelp(_ requestID: String, computer name: String, now: Date) async {
        guard !notified.contains(requestID), let computer = computers[name] else { return }
        guard let summary = await computer.helpSummary(requestID) else { return }
        notified.insert(requestID)
        let item = InboxItem(id: requestID, computer: name, summary: summary, createdAt: now)
        inbox.insert(item, at: 0)
        onAttentionChange(attentionCount)
        onHelpRequested(item, .make(session: sessionTitle(name), computer: name, summary: summary))
        await refresh()
    }

    public func markRead(_ id: String) { if let i = inbox.firstIndex(where: { $0.id == id }) { inbox[i].read = true } }
    public func markAllRead() { for i in inbox.indices { inbox[i].read = true } }
    public var unreadCount: Int { inbox.filter { !$0.read }.count }

    // MARK: Linhas

    /// Atualiza snapshots (barato) e, no máximo 1 vez por segundo por computador, a miniatura (CS-403).
    public func refresh(now: Date = Date(), withThumbnails: Bool = false) async {
        var next: [ComputerRow] = []
        for (name, computer) in computers {
            let snapshot = await computer.viewerSnapshot()
            if withThumbnails, snapshot.display != "http", snapshot.state == .ready || snapshot.state == .inUse,
               !thumbnailInFlight.contains(name), now.timeIntervalSince(thumbnails[name]?.at ?? .distantPast) >= 1 {
                thumbnailInFlight.insert(name)
                if let data = await computer.thumbnail() { thumbnails[name] = (data, now) }
                thumbnailInFlight.remove(name)
            }
            next.append(ComputerRow(
                snapshot: snapshot, thumbnail: thumbnails[name]?.data, sessionTitle: sessionTitle(name), owner: nil,
                lastActivity: activity[name] ?? .distantPast))
        }
        rows = Self.sorted(next)
    }

    /// "Precisa de você" primeiro, depois atividade recente, depois nome (audit/10 R4.8).
    public static func sorted(_ rows: [ComputerRow]) -> [ComputerRow] {
        rows.sorted {
            if $0.needsYou != $1.needsYou { return $0.needsYou }
            if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
            return $0.id < $1.id
        }
    }

    public var summaryText: String {
        let running = rows.filter { $0.snapshot.state == .ready || $0.snapshot.state == .inUse }.count
        return "\(running) running"
    }
}
