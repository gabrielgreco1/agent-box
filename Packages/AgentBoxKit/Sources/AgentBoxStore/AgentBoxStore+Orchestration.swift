import Foundation
import GRDB

// Árvore pai -> filhos da orquestração (`v6_agent_tree`, T3-04, 07 §4.3), mensagens do pai aos filhos (P12, CS-307) e o espelho dos
// computadores com a fila persistente (`computer`, `computer_queue` de `v3_computers`, CS-131).

public enum OrchestrationChildState: String, Sendable, Codable, CaseIterable {
    /// Slot de worker do pai sem computador.
    case idle
    /// Computador reservado para o slot; o filho ainda não reivindicou (`box_claim`).
    case reserved
    case claimed
    case released
    /// O `SubagentStop` do filho chegou.
    case ended
    /// Reserva nunca reivindicada, liberada pelo tempo (CS-302).
    case expired

    /// Ainda conta como filho ativo do pai (segura `waitingOnSubagents`).
    public var isActive: Bool { self == .reserved || self == .claimed }
}

public struct OrchestrationChild: Sendable, Equatable, Identifiable {
    /// Identidade MCP do filho (`agentbox mcp --child <id>`).
    public var id: String
    /// Identidade MCP do pai (a execução do terminal pai).
    public var parentID: String
    public var parentRunID: UUID?
    public var slot: Int
    /// `subagent_type` do worker (`agentbox-worker-3`).
    public var agentType: String
    public var computerName: String?
    public var batchID: String?
    /// `agent_run` do filho nativo, preenchido quando o hook revela o `agent_id` (correlação por `mcp_server.name`, S-08).
    public var runID: UUID?
    public var providerAgentID: String?
    public var state: OrchestrationChildState
    public var createdAt: Date
    public var reservedAt: Date?
    public var claimedAt: Date?
    public var releasedAt: Date?
    public var endedAt: Date?

    public init(
        id: String, parentID: String, parentRunID: UUID? = nil, slot: Int, agentType: String, computerName: String? = nil, batchID: String? = nil,
        runID: UUID? = nil, providerAgentID: String? = nil, state: OrchestrationChildState = .idle, createdAt: Date = Date(),
        reservedAt: Date? = nil, claimedAt: Date? = nil, releasedAt: Date? = nil, endedAt: Date? = nil
    ) {
        self.id = id; self.parentID = parentID; self.parentRunID = parentRunID; self.slot = slot; self.agentType = agentType
        self.computerName = computerName; self.batchID = batchID; self.runID = runID; self.providerAgentID = providerAgentID
        self.state = state; self.createdAt = createdAt; self.reservedAt = reservedAt; self.claimedAt = claimedAt
        self.releasedAt = releasedAt; self.endedAt = endedAt
    }
}

public enum AgentMessageDelivery: String, Sendable, Codable {
    /// Worker com PTY (v1.1): colado com bracketed paste e Enter.
    case pty
    /// Filho nativo: vai para a inbox e sai no próximo `box_status` como `parent_messages`.
    case inbox
    case queued
}

public struct StoredAgentMessage: Sendable, Equatable, Identifiable {
    public var id: String
    public var parentID: String
    public var childID: String
    public var text: String
    public var delivery: AgentMessageDelivery
    public var createdAt: Date
    public var deliveredAt: Date?

    public init(id: String, parentID: String, childID: String, text: String, delivery: AgentMessageDelivery, createdAt: Date, deliveredAt: Date? = nil) {
        self.id = id; self.parentID = parentID; self.childID = childID; self.text = text; self.delivery = delivery
        self.createdAt = createdAt; self.deliveredAt = deliveredAt
    }
}

/// Computador espelhado no SQLite (estado e fila sobrevivem a reiniciar o app).
public struct ComputerStateRow: Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var display: String
    public var state: String
    public var ownerParentID: String?
    public var createdAt: Date

    public init(id: UUID, name: String, display: String, state: String, ownerParentID: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.display = display; self.state = state; self.ownerParentID = ownerParentID; self.createdAt = createdAt
    }
}

public struct ComputerQueueRow: Sendable, Equatable {
    public var computerID: UUID
    public var position: Int
    public var requestedAt: Date
    public var reason: String
    public init(computerID: UUID, position: Int, requestedAt: Date, reason: String = "memory") {
        self.computerID = computerID; self.position = position; self.requestedAt = requestedAt; self.reason = reason
    }
}

extension OrchestrationChild {
    fileprivate init(row: Row) throws {
        let state = row["state"] as String
        guard let parsed = OrchestrationChildState(rawValue: state) else { throw StoreError.invalidRow(table: "orchestration_child", detail: "bad state \(state)") }
        self.init(
            id: row["id"], parentID: row["parent_id"], parentRunID: (row["parent_run_id"] as String?).flatMap(UUID.init(uuidString:)), slot: row["slot"],
            agentType: row["agent_type"], computerName: row["computer_name"], batchID: row["batch_id"],
            runID: (row["run_id"] as String?).flatMap(UUID.init(uuidString:)), providerAgentID: row["provider_agent_id"], state: parsed,
            createdAt: RowCodec.date(row["created_at"] as Int64), reservedAt: RowCodec.date(row["reserved_at"] as Int64?),
            claimedAt: RowCodec.date(row["claimed_at"] as Int64?), releasedAt: RowCodec.date(row["released_at"] as Int64?),
            endedAt: RowCodec.date(row["ended_at"] as Int64?))
    }
}

extension StoredAgentMessage {
    fileprivate init(row: Row) throws {
        let delivery = row["delivery"] as String
        guard let parsed = AgentMessageDelivery(rawValue: delivery) else { throw StoreError.invalidRow(table: "agent_message", detail: "bad delivery \(delivery)") }
        self.init(
            id: row["id"], parentID: row["parent_id"], childID: row["child_id"], text: row["text"], delivery: parsed,
            createdAt: RowCodec.date(row["created_at"] as Int64), deliveredAt: RowCodec.date(row["delivered_at"] as Int64?))
    }
}

extension AgentBoxStore {
    // MARK: Árvore

    /// Cria o slot ou atualiza os campos de identidade; o estado e os vínculos existentes só mudam por `updateOrchestrationChild`.
    public func registerOrchestrationChild(_ child: OrchestrationChild) async throws {
        try await write { db in
            try db.execute(
                sql: """
                INSERT INTO orchestration_child (id, parent_id, parent_run_id, slot, agent_type, state, created_at)
                VALUES (?, ?, ?, ?, ?, 'idle', ?)
                ON CONFLICT(id) DO UPDATE SET parent_run_id = COALESCE(excluded.parent_run_id, parent_run_id), agent_type = excluded.agent_type
                """,
                arguments: [child.id, child.parentID, child.parentRunID?.uuidString, child.slot, child.agentType, RowCodec.ms(child.createdAt) as Int64])
        }
    }

    public func orchestrationChild(id: String) async throws -> OrchestrationChild? {
        try await read { db in try Row.fetchOne(db, sql: "SELECT * FROM orchestration_child WHERE id = ?", arguments: [id]).map { try OrchestrationChild(row: $0) } }
    }

    /// Filhos do pai por ordem de slot.
    public func orchestrationChildren(parentID: String) async throws -> [OrchestrationChild] {
        try await read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM orchestration_child WHERE parent_id = ? ORDER BY slot", arguments: [parentID]).map { try OrchestrationChild(row: $0) }
        }
    }

    public func orchestrationChild(parentID: String, computerName: String) async throws -> OrchestrationChild? {
        try await read { db in
            try Row.fetchOne(
                db, sql: "SELECT * FROM orchestration_child WHERE parent_id = ? AND computer_name = ? AND state IN ('reserved','claimed') ORDER BY slot LIMIT 1",
                arguments: [parentID, computerName]).map { try OrchestrationChild(row: $0) }
        }
    }

    /// Transição de estado (e vínculo com o computador) de um filho. Os carimbos de tempo acompanham o estado.
    public func updateOrchestrationChild(id: String, state: OrchestrationChildState, computerName: String?? = nil, batchID: String?? = nil, at: Date = Date()) async throws {
        let ms = RowCodec.ms(at)
        try await write { db in
            switch state {
            case .reserved: try db.execute(sql: "UPDATE orchestration_child SET state = ?, reserved_at = ? WHERE id = ?", arguments: [state.rawValue, ms, id])
            case .claimed: try db.execute(sql: "UPDATE orchestration_child SET state = ?, claimed_at = ? WHERE id = ?", arguments: [state.rawValue, ms, id])
            case .released, .expired: try db.execute(sql: "UPDATE orchestration_child SET state = ?, released_at = ? WHERE id = ?", arguments: [state.rawValue, ms, id])
            case .ended: try db.execute(sql: "UPDATE orchestration_child SET state = ?, ended_at = ? WHERE id = ?", arguments: [state.rawValue, ms, id])
            case .idle: try db.execute(sql: "UPDATE orchestration_child SET state = ?, computer_name = NULL, batch_id = NULL, run_id = NULL, provider_agent_id = NULL WHERE id = ?", arguments: [state.rawValue, id])
            }
            if let computerName { try db.execute(sql: "UPDATE orchestration_child SET computer_name = ? WHERE id = ?", arguments: [computerName, id]) }
            if let batchID { try db.execute(sql: "UPDATE orchestration_child SET batch_id = ? WHERE id = ?", arguments: [batchID, id]) }
        }
    }

    /// Correlação com o filho nativo: o hook trouxe `agent_id` e `mcp_server.name` (S-08). O `agent_run` do filho é opcional.
    public func linkOrchestrationChild(id: String, runID: UUID?, providerAgentID: String) async throws {
        try await write { db in
            try db.execute(sql: "UPDATE orchestration_child SET run_id = COALESCE(?, run_id), provider_agent_id = ? WHERE id = ?", arguments: [runID?.uuidString, providerAgentID, id])
        }
    }

    // MARK: Mensagens do pai (P12)

    public func appendAgentMessage(id: String = UUID().uuidString.lowercased(), parentID: String, childID: String, text: String, delivery: AgentMessageDelivery, at: Date = Date()) async throws -> StoredAgentMessage {
        guard !text.isEmpty, text.count <= 16_000 else { throw StoreError.invalidModel("agent message must have 1...16000 characters") }
        let ms = RowCodec.ms(at)
        try await write { db in
            try db.execute(
                sql: "INSERT INTO agent_message (id, parent_id, child_id, text, delivery, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [id, parentID, childID, text, delivery.rawValue, ms])
        }
        return StoredAgentMessage(id: id, parentID: parentID, childID: childID, text: text, delivery: delivery, createdAt: at, deliveredAt: nil)
    }

    public func pendingAgentMessages(childID: String) async throws -> [StoredAgentMessage] {
        try await read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM agent_message WHERE child_id = ? AND delivered_at IS NULL ORDER BY created_at, rowid", arguments: [childID]).map { try StoredAgentMessage(row: $0) }
        }
    }

    public func agentMessages(childID: String) async throws -> [StoredAgentMessage] {
        try await read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM agent_message WHERE child_id = ? ORDER BY created_at, rowid", arguments: [childID]).map { try StoredAgentMessage(row: $0) }
        }
    }

    public func markAgentMessagesDelivered(_ ids: [String], at: Date = Date()) async throws {
        guard !ids.isEmpty else { return }
        let ms = RowCodec.ms(at)
        try await write { db in
            for id in ids { try db.execute(sql: "UPDATE agent_message SET delivered_at = ? WHERE id = ? AND delivered_at IS NULL", arguments: [ms, id]) }
        }
    }

    // MARK: Computadores e fila

    public func saveComputerState(_ row: ComputerStateRow) async throws {
        let allowed: Set<String> = ["queued", "provisioning", "ready", "in_use", "stopped", "failed", "removing", "removed", "orphan"]
        guard allowed.contains(row.state) else { throw StoreError.invalidModel("computer state \(row.state)") }
        try await write { db in
            try db.execute(
                sql: """
                INSERT INTO computer (id, owner_run_id, name, display, state, created_at) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET state = excluded.state, display = excluded.display, last_used_at = ?
                """,
                arguments: [row.id.uuidString, row.ownerParentID, row.name, row.display, row.state, RowCodec.ms(row.createdAt) as Int64, RowCodec.ms(Date()) as Int64])
        }
    }

    public func computerStates() async throws -> [ComputerStateRow] {
        try await read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, display, state, owner_run_id, created_at FROM computer ORDER BY created_at, name").compactMap { row in
                guard let id = UUID(uuidString: row["id"] as String) else { return nil }
                return ComputerStateRow(
                    id: id, name: row["name"], display: row["display"], state: row["state"], ownerParentID: row["owner_run_id"],
                    createdAt: RowCodec.date(row["created_at"] as Int64))
            }
        }
    }

    /// Substitui a fila persistente (FIFO por `position`, a partir de 1).
    public func replaceComputerQueue(_ rows: [ComputerQueueRow]) async throws {
        try await write { db in
            try db.execute(sql: "DELETE FROM computer_queue")
            for row in rows {
                try db.execute(
                    sql: "INSERT INTO computer_queue (id, computer_id, position, requested_at, reason) VALUES (?, ?, ?, ?, ?)",
                    arguments: [UUID().uuidString.lowercased(), row.computerID.uuidString, row.position, RowCodec.ms(row.requestedAt) as Int64, row.reason])
            }
        }
    }

    public func computerQueue() async throws -> [ComputerQueueRow] {
        try await read { db in
            try Row.fetchAll(db, sql: "SELECT computer_id, position, requested_at, reason FROM computer_queue ORDER BY position").compactMap { row in
                guard let id = UUID(uuidString: row["computer_id"] as String) else { return nil }
                return ComputerQueueRow(computerID: id, position: row["position"], requestedAt: RowCodec.date(row["requested_at"] as Int64), reason: row["reason"])
            }
        }
    }
}
