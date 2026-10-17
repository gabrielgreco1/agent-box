import Foundation
import Synchronization

/// `agentboxd` como processo filho do app ou do bench (06 §1.2, "modo degradado e testes"): mesmo binário e protocolo,
/// `AGENTBOX_HOME` próprio, `bind` em `<home>/run/ptyd-v1.sock`. O launchd o substitui na T1-24.
public final class ChildDaemon: Sendable {
    public let home: URL
    public var socketPath: String { home.appendingPathComponent("run/ptyd-v1.sock").path }
    private let process = Mutex<Process?>(nil)

    /// - Parameter home: raiz do daemon; criada com `0700` se não existir (o caminho do socket precisa caber em 104 bytes).
    public init(home: URL) {
        self.home = home
    }

    /// Diretório temporário curto, no formato que os testes usam.
    public static func temporaryHome(prefix: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(prefix)-\(UInt32.random(in: 0 ... 0xFFFFFF))", isDirectory: true)
    }

    public var pid: Int32 { process.withLock { $0?.processIdentifier ?? 0 } }

    /// Executável padrão: `agentboxd` ao lado do binário em execução (bundle do app ou diretório de build).
    public static func defaultExecutable(relativeTo executable: URL? = Bundle.main.executableURL) -> URL? {
        executable?.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("agentboxd")
    }

    public func start(executable: URL, idleExitSeconds: Int = 0) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let child = Process()
        child.executableURL = executable
        child.arguments = ["--idle-exit", "\(idleExitSeconds)", "--home", home.path]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        process.withLock { $0 = child }
    }

    public func terminate() {
        process.withLock { child in
            if let child, child.isRunning { child.terminate() }
            child = nil
        }
    }

    public func removeHome() {
        try? FileManager.default.removeItem(at: home)
    }
}
