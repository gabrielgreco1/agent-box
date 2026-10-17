import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AppKit
import Foundation

/// Tela de teste do `TerminalSurface` (`AGENTBOX_SCREEN=terminal-demo`, só dev e evidência de T1-09): um pane de
/// terminal ocupando o centro da janela, ligado a um `agentboxd` filho do app. Não faz parte do produto: o pane real
/// chega com T1-15. Variáveis:
/// - `AGENTBOX_DEMO_ARGV`: comando (separado por espaços; padrão `/bin/zsh -f -i`).
/// - `AGENTBOX_DEMO_SCRIPT`: arquivo cujo conteúdo é digitado no terminal (origem `ctl`) depois que a sessão sobe.
/// - `AGENTBOX_DEMO_DAEMON`: caminho do `agentboxd` (padrão: ao lado do executável do app).
/// - `AGENTBOX_HOME`: raiz do daemon (padrão: diretório temporário); o estado vai em `<home>/demo.json`.
@MainActor
final class TerminalDemoViewController: NSViewController {
    private let env: AppEnvironment
    private let host: TerminalHostView
    private let daemon: ChildDaemon
    private var client: PTYClient?
    private var binding: TerminalSessionBinding?
    private let log = LogFacade(.app, category: "terminal-demo")
    private var termSource: DispatchSourceSignal?

    init(env: AppEnvironment) {
        self.env = env
        host = TerminalHostView(terminalID: "demo", registry: env.registry, elements: env.elements)
        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["AGENTBOX_HOME"], !configured.isEmpty {
            daemon = ChildDaemon(home: URL(fileURLWithPath: configured, isDirectory: true))
        } else {
            daemon = ChildDaemon(home: ChildDaemon.temporaryHome(prefix: "abdemo"))
        }
        super.init(nibName: nil, bundle: nil)
        view = host
        env.terminalRouter.focus(host)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard binding == nil, client == nil else { return }
        host.focusTerminal()
        Task { await start() }
    }

    private func start() async {
        do {
            let environment = ProcessInfo.processInfo.environment
            let socket = daemon.socketPath
            guard let exe = environment["AGENTBOX_DEMO_DAEMON"].map({ URL(fileURLWithPath: $0) }) ?? ChildDaemon.defaultExecutable() else {
                throw PTYClientError.notConnected
            }
            try daemon.start(executable: exe, idleExitSeconds: 5)
            installTerminationCleanup()

            let client = PTYClient(configuration: PTYClientConfiguration(socketPath: socket, build: "demo"))
            var started = false
            for _ in 0 ..< 100 {
                if (try? await client.start()) != nil {
                    started = true
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard started else { throw PTYClientError.notConnected }
            self.client = client

            let dims = host.surface.terminalDimensions
            let argv = (environment["AGENTBOX_DEMO_ARGV"] ?? "/bin/zsh -f -i").split(separator: " ").map(String.init)
            let sessionEnv = [
                "PATH": environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8",
                "TERM": "xterm-256color", "COLORTERM": "truecolor", "TERM_PROGRAM": "AgentBox", "PROMPT": "%F{green}%n@agentbox%f %F{blue}%~%f %# ",
            ]
            let create = CreateRequest(
                sessionID: SessionID(), argv: argv, cwd: NSHomeDirectory(), env: sessionEnv, cols: UInt16(clamping: dims.cols),
                rows: UInt16(clamping: dims.rows), ringBytes: 4 << 20, coldLog: false, owner: SessionOwner(terminalID: "demo", runID: "demo"))
            let created = try await client.create(create)
            let binding = TerminalSessionBinding(client: client, sessionID: created.session.sessionID, host: host)
            self.binding = binding
            try await binding.start()
            writeStatus(sessionID: created.session.sessionID)
            if let path = environment["AGENTBOX_DEMO_SCRIPT"], let script = try? String(contentsOfFile: path, encoding: .utf8) {
                try await Task.sleep(for: .milliseconds(800))
                binding.send(Array(script.utf8), origin: .ctl)
            }
        } catch {
            log.error("terminal demo failed: \(error)")
        }
    }

    private func writeStatus(sessionID: SessionID) {
        let info: [String: Any] = [
            "windowNumber": view.window?.windowNumber ?? 0, "daemonPID": daemon.pid, "appPID": getpid(),
            "sessionID": sessionID.description, "metal": host.surface.metalEnabled,
            "cols": host.surface.terminalDimensions.cols, "rows": host.surface.terminalDimensions.rows,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: daemon.home.appendingPathComponent("demo.json"))
        }
    }

    /// SIGTERM (fechar por PID) e saída normal derrubam o daemon filho: sem processo órfão.
    private func installTerminationCleanup() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.daemon.terminate()
            exit(0)
        }
        source.resume()
        termSource = source
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.daemon.terminate() }
        }
    }
}
