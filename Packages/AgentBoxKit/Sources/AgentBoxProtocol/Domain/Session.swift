import Foundation

/// 08 §0.4: `worktree` · `checkout` · `folder` · `clean`.
public enum SessionKind: String, Codable, Sendable, CaseIterable {
    case worktree, checkout, folder, clean
    /// `worktree` e `checkout` exigem `worktreeID`.
    public var requiresWorktree: Bool { self == .worktree || self == .checkout }
}

/// Ciclo de vida da sessão (01 §6.1). `sleeping` é v1.1 e fica fora da Fatia 1.
/// Só `active` e `archived` são persistidos; os demais vivem em memória.
public enum SessionLifecycle: String, Codable, Sendable, CaseIterable {
    case creating, failedToCreate, active, archived, missing, deleted
    public var isPersistable: Bool { self == .active || self == .archived }
}

public struct StatusNote: Codable, Hashable, Sendable {
    public var text: String
    public var author: String
    public var at: Date
    public init(text: String, author: String, at: Date = Date()) {
        self.text = text; self.author = author; self.at = at
    }
}

/// Unidade de trabalho da sidebar: diretório + terminais (01 §5.3).
public struct Session: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: SessionKind
    public var projectID: UUID?
    public var worktreeID: UUID?
    public var folderPath: String
    public var managedFolder: Bool
    public var title: String
    public var statusNote: StatusNote?
    public var unread: Bool
    public var lastViewedAt: Date?
    public var lifecycle: SessionLifecycle
    public var sortIndex: Int
    public var createdAt: Date
    public var lastActiveAt: Date?
    public var archivedAt: Date?

    public init(
        id: UUID = .v7(), kind: SessionKind, projectID: UUID? = nil, worktreeID: UUID? = nil,
        folderPath: String, managedFolder: Bool = false, title: String, statusNote: StatusNote? = nil,
        unread: Bool = false, lastViewedAt: Date? = nil, lifecycle: SessionLifecycle = .active,
        sortIndex: Int = 0, createdAt: Date = Date(), lastActiveAt: Date? = nil, archivedAt: Date? = nil
    ) {
        self.id = id; self.kind = kind; self.projectID = projectID; self.worktreeID = worktreeID
        self.folderPath = folderPath; self.managedFolder = managedFolder; self.title = title
        self.statusNote = statusNote; self.unread = unread; self.lastViewedAt = lastViewedAt
        self.lifecycle = lifecycle; self.sortIndex = sortIndex; self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt; self.archivedAt = archivedAt
    }

    /// Mesma regra do CHECK do schema (R1 K-81); validada antes de gravar.
    public var isStructurallyValid: Bool {
        (kind.requiresWorktree == (worktreeID != nil)) && ((kind == .clean) == (projectID == nil))
    }
}
