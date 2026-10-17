import AgentBoxPlatform
import Darwin
import Foundation

/// `agentboxd`: daemon de PTY (06 §1). Nesta fase roda como processo filho do app e faz `bind` no socket canônico
/// (`AB/run/ptyd-v1.sock`; `$AGENTBOX_HOME/run/ptyd-v1.sock` nos testes). Ativação por launchd é a T1-24.
///
/// Opções: `--socket <caminho>`, `--home <diretório>`, `--idle-exit <segundos>` (0 desliga; padrão 60), `--build <texto>`.
@main
struct AgentBoxD {
    static func main() async {
        signal(SIGPIPE, SIG_IGN)
        var socket: String?
        var home: String?
        var idleExit = 60
        var build = "1.0 (dev)"
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--socket": socket = arguments.next()
            case "--home": home = arguments.next()
            case "--idle-exit": idleExit = Int(arguments.next() ?? "") ?? idleExit
            case "--build": build = arguments.next() ?? build
            default:
                FileHandle.standardError.write(Data("agentboxd: unknown option \(argument)\n".utf8))
                Darwin.exit(64)
            }
        }
        let paths = DaemonPaths.resolve(environment: ProcessInfo.processInfo.environment, socketOverride: socket, homeOverride: home)
        let configuration = DaemonConfiguration(paths: paths, build: build, idleExit: idleExit > 0 ? .seconds(idleExit) : nil)
        do {
            try await DaemonServer(configuration: configuration).run()
        } catch {
            FileHandle.standardError.write(Data("agentboxd: \(error)\n".utf8))
            Darwin.exit(1)
        }
    }
}
