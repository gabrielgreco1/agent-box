import Darwin
import Foundation

// Detector de "worktree também aberta no Orca" (06 §6.4; 03 §16.5; AC-T10). Só leitura: usa o mesmo `OrcaReader`
// (cópia temporária do estado) e nunca escreve no Orca.
//
// Heurística documentada:
//  1. `listedInOrca`: o caminho canônico do worktree aparece em `worktreeMeta` (chave `<repoId>::<caminho>`), ou seja, o
//     Orca ainda registra esse worktree. É o gatilho do aviso "This worktree is also open in Orca.".
//  2. `openTabsInOrca`: o worktree tem abas em `workspaceSession.tabsByWorktree` (em uso na janela do Orca). Informativo.
//  3. `orcaRunning`: o Orca está de pé. O Chromium/Electron do Orca mantém o symlink `SingletonLock` na pasta de dados com
//     alvo `<host>-<pid>`; o pid precisa estar vivo e o processo precisa se chamar "Orca". Injetável (`isOrcaRunning`) para
//     teste; o equivalente manual é `pgrep -x Orca`. Quando o Orca roda, a variante do aviso é "Orca is open.".
//
// A lista de caminhos vem do estado lido por `refresh()`; sem Orca instalado, nunca há aviso.

public struct OrcaCoexistenceStatus: Sendable, Equatable {
    public var listedInOrca: Bool
    public var openTabsInOrca: Bool
    public var orcaRunning: Bool

    /// Linha `warning` do diálogo de remoção; nil quando não há o que avisar.
    public var warning: String? {
        guard listedInOrca else { return nil }
        return orcaRunning ? "Orca is open." : "This worktree is also open in Orca."
    }
}

public struct OrcaCoexistence: Sendable {
    public typealias RunningProbe = @Sendable (_ dataDirectory: URL) -> Bool

    public let listedPaths: Set<String>
    public let pathsWithOpenTabs: Set<String>
    public let orcaRunning: Bool

    public init(listedPaths: Set<String> = [], pathsWithOpenTabs: Set<String> = [], orcaRunning: Bool = false) {
        self.listedPaths = listedPaths; self.pathsWithOpenTabs = pathsWithOpenTabs; self.orcaRunning = orcaRunning
    }

    /// Lê o estado atual do Orca (cópia temporária) e o estado de execução. Falha de leitura vira "nada listado".
    public static func refresh(
        locator: OrcaLocator = OrcaLocator(), tempRoot: URL = FileManager.default.temporaryDirectory,
        isOrcaRunning: RunningProbe = OrcaCoexistence.defaultRunningProbe
    ) -> OrcaCoexistence {
        let reader = OrcaReader(tempRoot: tempRoot)
        var listed = Set<String>(), tabs = Set<String>(), running = false
        for profile in locator.profiles() {
            running = running || isOrcaRunning(locator.dataDirectory(of: profile))
            guard let snapshot = try? reader.read(profile) else { continue }
            for meta in snapshot.worktreeMeta { listed.insert(OrcaImporter.canonical(meta.path)) }
            for key in snapshot.worktreesWithOpenTabs {
                if let split = key.range(of: "::") { tabs.insert(OrcaImporter.canonical(String(key[split.upperBound...]))) }
            }
        }
        return OrcaCoexistence(listedPaths: listed, pathsWithOpenTabs: tabs, orcaRunning: running)
    }

    public func status(forWorktreePath path: String) -> OrcaCoexistenceStatus {
        let canonical = OrcaImporter.canonical(path)
        return OrcaCoexistenceStatus(
            listedInOrca: listedPaths.contains(canonical), openTabsInOrca: pathsWithOpenTabs.contains(canonical),
            orcaRunning: orcaRunning)
    }

    /// `SingletonLock` (symlink `<host>-<pid>`) com pid vivo cujo executável se chama "Orca".
    public static let defaultRunningProbe: RunningProbe = { dataDirectory in
        let lock = dataDirectory.appendingPathComponent("SingletonLock").path
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: lock),
              let pidText = target.split(separator: "-").last, let pid = Int32(pidText), pid > 0 else { return false }
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var name = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return false }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).lowercased().hasPrefix("orca")
    }
}
