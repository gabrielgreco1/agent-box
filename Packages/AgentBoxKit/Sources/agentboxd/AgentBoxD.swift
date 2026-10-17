import AgentBoxPlatform
import Darwin
import Foundation

/// `agentboxd`: daemon de PTY (06 §1). Nesta fase roda como processo filho do app e faz `bind` no socket canônico
/// (`AB/run/ptyd-v1.sock`; `$AGENTBOX_HOME/run/ptyd-v1.sock` nos testes). Ativação por launchd é a T1-24.
///
/// Opções: `--socket <caminho>`, `--home <diretório>`, `--idle-exit <segundos>` (0 desliga; padrão 60), `--build <texto>`.
/// Configuração explícita de build do modo ad-hoc de desenvolvimento (S-03): `-Xswiftc -DAGENTBOX_ALLOW_ADHOC_PEERS`.
/// Nunca por variável de ambiente nem argumento. Só tem efeito se o próprio daemon estiver assinado ad-hoc.
#if AGENTBOX_ALLOW_ADHOC_PEERS
    private let allowAdhocPeersBuild = true
#else
    private let allowAdhocPeersBuild = false
#endif

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
        let policy = PeerAuthPolicy.resolve(daemon: CodeIdentity.ofCurrentProcess(), allowAdhocDevelopment: allowAdhocPeersBuild)
        let configuration = DaemonConfiguration(
            paths: paths, build: build, idleExit: idleExit > 0 ? .seconds(idleExit) : nil,
            peerAuthenticator: PeerAuthenticator(policy: policy))
        do {
            try await DaemonServer(configuration: configuration).run()
        } catch {
            FileHandle.standardError.write(Data("agentboxd: \(error)\n".utf8))
            Darwin.exit(1)
        }
    }
}
