import Foundation

public enum SplitAxis: String, Codable, Equatable, Sendable {
    case horizontal, vertical
}

public indirect enum WorkspaceNode: Codable, Equatable, Sendable {
    case terminal(UUID)
    case split(id: UUID, axis: SplitAxis, fraction: Double, first: WorkspaceNode, second: WorkspaceNode)

    public var terminalIDs: [UUID] {
        switch self {
        case .terminal(let id): return [id]
        case .split(_, _, _, let first, let second): return first.terminalIDs + second.terminalIDs
        }
    }

    public func inserting(_ terminalID: UUID, beside targetID: UUID, axis: SplitAxis) -> WorkspaceNode {
        switch self {
        case .terminal(let id) where id == targetID:
            return .split(id: UUID(), axis: axis, fraction: 0.5, first: self, second: .terminal(terminalID))
        case .terminal: return self
        case .split(let id, let existingAxis, let fraction, let first, let second):
            return .split(id: id, axis: existingAxis, fraction: fraction,
                          first: first.inserting(terminalID, beside: targetID, axis: axis),
                          second: second.inserting(terminalID, beside: targetID, axis: axis))
        }
    }

    public func removing(_ terminalID: UUID) -> WorkspaceNode? {
        switch self {
        case .terminal(let id): return id == terminalID ? nil : self
        case .split(let id, let axis, let fraction, let first, let second):
            let left = first.removing(terminalID)
            let right = second.removing(terminalID)
            switch (left, right) {
            case (nil, nil): return nil
            case (let node?, nil), (nil, let node?): return node
            case (let left?, let right?):
                return .split(id: id, axis: axis, fraction: fraction, first: left, second: right)
            }
        }
    }

    public func replacing(_ oldID: UUID, with newID: UUID) -> WorkspaceNode {
        switch self {
        case .terminal(let id): return .terminal(id == oldID ? newID : id)
        case .split(let id, let axis, let fraction, let first, let second):
            return .split(id: id, axis: axis, fraction: fraction,
                          first: first.replacing(oldID, with: newID),
                          second: second.replacing(oldID, with: newID))
        }
    }

    public func settingFraction(_ value: Double, for splitID: UUID) -> WorkspaceNode {
        switch self {
        case .terminal: return self
        case .split(let id, let axis, let fraction, let first, let second):
            return .split(id: id, axis: axis, fraction: id == splitID ? min(0.8, max(0.2, value)) : fraction,
                          first: first.settingFraction(value, for: splitID),
                          second: second.settingFraction(value, for: splitID))
        }
    }

    public func retaining(_ validIDs: Set<UUID>, seen: inout Set<UUID>) -> WorkspaceNode? {
        switch self {
        case .terminal(let id):
            guard validIDs.contains(id), seen.insert(id).inserted else { return nil }
            return self
        case .split(let id, let axis, let fraction, let first, let second):
            let left = first.retaining(validIDs, seen: &seen)
            let right = second.retaining(validIDs, seen: &seen)
            switch (left, right) {
            case (nil, nil): return nil
            case (let node?, nil), (nil, let node?): return node
            case (let left?, let right?):
                return .split(id: id, axis: axis, fraction: min(0.8, max(0.2, fraction)), first: left, second: right)
            }
        }
    }
}

public struct WorkspaceLayout: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var root: WorkspaceNode?
    public var focusedTerminalID: UUID?

    public init(sessionID: UUID, root: WorkspaceNode? = nil, focusedTerminalID: UUID? = nil) {
        self.sessionID = sessionID
        self.root = root
        self.focusedTerminalID = focusedTerminalID
    }

    public var visibleTerminalIDs: [UUID] { root?.terminalIDs ?? [] }

    public mutating func focus(_ terminalID: UUID) {
        focusedTerminalID = terminalID
        if root == nil { root = .terminal(terminalID) }
    }

    public mutating func show(_ terminalID: UUID) {
        if let root, !root.terminalIDs.contains(terminalID),
           let oldID = focusedTerminalID.flatMap({ root.terminalIDs.contains($0) ? $0 : nil }) ?? root.terminalIDs.first {
            self.root = root.replacing(oldID, with: terminalID)
        } else if root == nil {
            root = .terminal(terminalID)
        }
        focusedTerminalID = terminalID
    }

    public mutating func split(_ terminalID: UUID, beside targetID: UUID, axis: SplitAxis) {
        guard !visibleTerminalIDs.contains(terminalID), visibleTerminalIDs.count < 5 else { return }
        guard let existing = root else { root = .terminal(terminalID); focusedTerminalID = terminalID; return }
        guard existing.terminalIDs.contains(targetID) else { return }
        root = existing.inserting(terminalID, beside: targetID, axis: axis)
        focusedTerminalID = terminalID
    }

    public mutating func closePane(_ terminalID: UUID) {
        root = root?.removing(terminalID)
        if focusedTerminalID == terminalID { focusedTerminalID = root?.terminalIDs.first }
    }

    public mutating func normalize(terminals: [TerminalRecord]) {
        var seen = Set<UUID>()
        root = root?.retaining(Set(terminals.map(\.id)), seen: &seen)
        if let focusedTerminalID, root?.terminalIDs.contains(focusedTerminalID) != true {
            self.focusedTerminalID = root?.terminalIDs.first
        }
    }
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public var sessions: [WorkspaceSession]
    public var layouts: [WorkspaceLayout]
    public var selectedSessionID: UUID?
    public var sidebarWidth: Double
    public var sidebarCollapsed: Bool

    public init(sessions: [WorkspaceSession] = [], layouts: [WorkspaceLayout] = [],
                selectedSessionID: UUID? = nil, sidebarWidth: Double = 288, sidebarCollapsed: Bool = false) {
        self.sessions = sessions
        self.layouts = layouts
        self.selectedSessionID = selectedSessionID
        self.sidebarWidth = sidebarWidth
        self.sidebarCollapsed = sidebarCollapsed
    }

    public mutating func normalize() {
        sidebarWidth = sidebarWidth.isFinite ? min(480, max(224, sidebarWidth)) : 288
        var seenSessions = Set<UUID>()
        sessions = sessions.filter { seenSessions.insert($0.id).inserted }
        var seenTerminals = Set<UUID>()
        for index in sessions.indices {
            sessions[index].terminals = sessions[index].terminals.filter { seenTerminals.insert($0.id).inserted }
        }
        let knownSessions = Set(sessions.map(\.id))
        var seenLayouts = Set<UUID>()
        layouts = layouts.filter { knownSessions.contains($0.sessionID) && seenLayouts.insert($0.sessionID).inserted }
        for index in layouts.indices {
            if let session = sessions.first(where: { $0.id == layouts[index].sessionID }) {
                layouts[index].normalize(terminals: session.terminals)
            }
        }
        if let selectedSessionID, !knownSessions.contains(selectedSessionID) {
            self.selectedSessionID = sessions.first?.id
        } else if selectedSessionID == nil {
            selectedSessionID = sessions.first?.id
        }
    }

    public mutating func updateLayout(for sessionID: UUID, _ update: (inout WorkspaceLayout) -> Void) {
        let index = layouts.firstIndex(where: { $0.sessionID == sessionID })
        var layout = index.map { layouts[$0] } ?? WorkspaceLayout(sessionID: sessionID)
        update(&layout)
        if let index { layouts[index] = layout } else { layouts.append(layout) }
    }
}

public struct WorkspaceRepository {
    public let url: URL

    public init(url: URL = AppPaths.applicationSupport.appendingPathComponent("workspace.json")) {
        self.url = url
    }

    public func load() throws -> WorkspaceSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return WorkspaceSnapshot() }
        var snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(contentsOf: url))
        snapshot.normalize()
        return snapshot
    }

    public func save(_ snapshot: WorkspaceSnapshot) throws {
        var normalized = snapshot
        normalized.normalize()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(normalized)
        try data.write(to: url, options: .atomic)
    }
}

public enum WorkspaceDirectoryError: Error, Equatable {
    case missingOrNotDirectory
}

public enum WorkspaceDirectory {
    public static func resolve(_ path: String) throws -> String {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { throw WorkspaceDirectoryError.missingOrNotDirectory }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceDirectoryError.missingOrNotDirectory
        }
        return url.path
    }
}
