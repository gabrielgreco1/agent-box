// Placeholder (T1-01): helper `agentbox` (futuros subcomandos `mcp`, `hook`, `ctl`).
import AgentBoxPlatform
import AgentBoxProtocol
import ArgumentParser

@main
struct AgentBoxCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentbox",
        abstract: "Agent Box helper (mcp, hook, ctl)."
    )

    func run() async throws {
        throw CleanExit.helpRequest(self)
    }
}
