import Darwin
import Foundation
import RackyProtocol
import ServiceManagement

/// O que o launchd diz sobre o LaunchAgent do nome antigo (`LegacyNames.launchAgentLabel`) e o que dá para fazer com ele.
/// Separado de `LaunchdQuerying` para os fakes existentes não precisarem mudar.
public protocol LegacyLaunchdControlling: Sendable {
    func jobState(label: String) async -> LaunchdJobState
    /// pid do daemon do job, quando está rodando.
    func jobPID(label: String) async -> Int32?
    /// Processos filhos diretos do daemon (shells e agentes dos terminais). Não precisa falar com o daemon: o daemon antigo só
    /// aceita o app antigo (peer auth pelo identificador de assinatura), então o app novo não consegue perguntar a ele.
    func childProcessCount(of pid: Int32) async -> Int
    /// `launchctl bootout`. `true` também quando o job já não existe.
    func bootout(label: String) async -> Bool
}

public enum LegacyRetirementOutcome: Sendable, Equatable {
    /// O launchd não conhece o job antigo: nada a fazer.
    case notPresent
    /// Sem terminais vivos: o job antigo foi removido (bootout + unregister).
    case retired
    /// Há terminais vivos no daemon antigo: ele continua intocado até esvaziar. Nova tentativa no próximo `prepare`/`recover`.
    case keptRunning(liveTerminals: Int)
    case failed(String)
}

/// Aposenta o LaunchAgent do nome antigo SÓ quando ele não tem terminais vivos. Com terminais vivos não faz nada: matar o
/// daemon antigo mataria o trabalho dos agentes. O daemon antigo sai sozinho 60 s depois da última sessão (sem clientes).
public struct LegacyDaemonRetirement: Sendable {
    private let launchd: any LegacyLaunchdControlling
    private let unregisterService: @Sendable () -> Void
    private let label: String

    public init(
        launchd: any LegacyLaunchdControlling = SystemLegacyLaunchd(), label: String = LegacyNames.launchAgentLabel,
        unregisterService: @escaping @Sendable () -> Void = LegacyDaemonRetirement.unregisterFromServiceManagement
    ) {
        self.launchd = launchd
        self.label = label
        self.unregisterService = unregisterService
    }

    public func retireIfDrained() async -> LegacyRetirementOutcome {
        let state = await launchd.jobState(label: label)
        if state == .notLoaded { return .notPresent }
        if state == .running {
            guard let pid = await launchd.jobPID(label: label) else { return .keptRunning(liveTerminals: 1) }
            let live = await launchd.childProcessCount(of: pid)
            if live > 0 { return .keptRunning(liveTerminals: live) }
        }
        unregisterService()
        return await launchd.bootout(label: label) ? .retired : .failed("launchctl bootout failed")
    }

    /// Melhor esforço: o plist antigo já não está no bundle novo, então o `SMAppService` pode se recusar. O `bootout` é o que vale.
    @Sendable public static func unregisterFromServiceManagement() {
        try? SMAppService.agent(plistName: LegacyNames.launchAgentLabel + ".plist").unregister()
    }
}

public struct SystemLegacyLaunchd: LegacyLaunchdControlling {
    private let launchctl = URL(fileURLWithPath: "/bin/launchctl")
    private let pgrep = URL(fileURLWithPath: "/usr/bin/pgrep")

    public init() {}

    public func jobState(label: String) async -> LaunchdJobState { await SystemLaunchd().jobState(label: label) }

    public func jobPID(label: String) async -> Int32? {
        guard let output = try? await ProcessRunner.run(
            ProcessRequest(executable: launchctl, arguments: ["print", "gui/\(getuid())/\(label)"], timeout: .seconds(5))),
            output.exitCode == 0
        else { return nil }
        return Self.pid(printOutput: output.stdoutString)
    }

    public func childProcessCount(of pid: Int32) async -> Int {
        guard let output = try? await ProcessRunner.run(ProcessRequest(executable: pgrep, arguments: ["-P", "\(pid)"], timeout: .seconds(5)))
        else { return 1 }  // sem como medir: tratar como ocupado é o lado seguro
        if output.exitCode == 1 { return 0 }  // pgrep: nenhum processo
        guard output.exitCode == 0 else { return 1 }
        return output.stdoutString.split(whereSeparator: \.isNewline).count
    }

    public func bootout(label: String) async -> Bool {
        guard let output = try? await ProcessRunner.run(
            ProcessRequest(executable: launchctl, arguments: ["bootout", "gui/\(getuid())/\(label)"], timeout: .seconds(30)))
        else { return false }
        // 0 = removido; 3 (ESRCH) e 113 = o job já não existe.
        return [0, 3, 113].contains(output.exitCode)
    }

    /// Só a linha do próprio job (um tab de indentação): `pid = N` aninhado pertence aos sockets e processos filhos.
    static func pid(printOutput: String) -> Int32? {
        for line in printOutput.split(separator: "\n", omittingEmptySubsequences: true) where line.hasPrefix("\tpid = ") {
            return Int32(line.dropFirst("\tpid = ".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
