import Foundation
import AgentBoxCore

enum WorkspaceDirectoryAccessError: LocalizedError {
    case unreadableBookmarks
    case movedDirectory
    case staleBookmark

    var errorDescription: String? {
        switch self {
        case .unreadableBookmarks: return "As autorizações de pastas salvas não puderam ser lidas. O arquivo foi preservado."
        case .movedDirectory: return "A pasta autorizada mudou de lugar. Escolha novamente a pasta exata antes de iniciar."
        case .staleBookmark: return "A autorização desta pasta expirou. Escolha novamente a pasta antes de iniciar."
        }
    }
}

/// Holds access for active workspace paths, including child processes and background Git probes.
/// A bookmark is only a possible macOS grant; success of a restored CLI still needs live validation.
@MainActor final class WorkspaceDirectoryAccess {
    static let shared = WorkspaceDirectoryAccess()

    private struct Grant: Codable {
        let path: String
        let bookmark: Data
        let securityScoped: Bool
    }
    private struct File: Codable {
        let schemaVersion: Int
        let grants: [Grant]
    }

    private let url = AppPaths.applicationSupport.appendingPathComponent("directory-bookmarks.json")
    private var grants: [Grant] = []
    private var activeScopes: [String: URL] = [:]
    private(set) var loadError: String?

    private init() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
            guard file.schemaVersion == 1,
                  Set(file.grants.map(\.path)).count == file.grants.count else {
                throw WorkspaceDirectoryAccessError.unreadableBookmarks
            }
            grants = file.grants
        } catch { loadError = error.localizedDescription }
    }

    /// Called only for a URL explicitly returned by NSOpenPanel.
    @discardableResult func remember(_ selectedURL: URL) throws -> String {
        guard loadError == nil else { throw WorkspaceDirectoryAccessError.unreadableBookmarks }
        let path = try WorkspaceDirectory.resolve(selectedURL.path)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let didStart = selectedURL.startAccessingSecurityScopedResource()
        defer { if didStart { selectedURL.stopAccessingSecurityScopedResource() } }
        let bookmark: Data
        let scoped: Bool
        do {
            bookmark = try selectedURL.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
            scoped = true
        } catch {
            // Unsandboxed builds may reject security-scoped bookmark creation. A normal
            // bookmark still preserves the chosen path, but does not claim to grant TCC.
            bookmark = try selectedURL.bookmarkData(options: [],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
            scoped = false
        }
        var next = grants.filter { $0.path != directory.resolvingSymlinksInPath().path }
        let canonicalPath = directory.resolvingSymlinksInPath().path
        next.append(Grant(path: canonicalPath, bookmark: bookmark, securityScoped: scoped))
        try save(next)
        grants = next
        if let previous = activeScopes.removeValue(forKey: canonicalPath) {
            previous.stopAccessingSecurityScopedResource()
        }
        _ = try activate(path)
        return path
    }

    /// Returns true only when a stored security scope became active. Paths without a
    /// bookmark remain usable under normal OS permissions; no folder is substituted.
    @discardableResult func activate(_ path: String) throws -> Bool {
        guard loadError == nil else { throw WorkspaceDirectoryAccessError.unreadableBookmarks }
        let canonical = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
        guard let grant = grants.filter({ canonical == $0.path || canonical.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count }) else { return false }
        if activeScopes[grant.path] != nil { return true }
        var stale = false
        let resolved = try URL(resolvingBookmarkData: grant.bookmark,
                               options: grant.securityScoped ? .withSecurityScope : [],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw WorkspaceDirectoryAccessError.staleBookmark }
        guard resolved.resolvingSymlinksInPath().standardizedFileURL.path == grant.path else {
            throw WorkspaceDirectoryAccessError.movedDirectory
        }
        guard grant.securityScoped else { return false }
        if resolved.startAccessingSecurityScopedResource() {
            activeScopes[grant.path] = resolved
            return true
        }
        return false
    }

    func stopAll() {
        for url in activeScopes.values { url.stopAccessingSecurityScopedResource() }
        activeScopes.removeAll()
    }

    private func save(_ next: [Grant]) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        try JSONEncoder().encode(File(schemaVersion: 1, grants: next)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
