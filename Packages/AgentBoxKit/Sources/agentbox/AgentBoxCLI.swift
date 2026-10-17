// Helper `agentbox` (subcomandos `ctl` e `hook`; `mcp` em tarefa seguinte).
import AgentBoxPlatform
import AgentBoxProtocol
import ArgumentParser

@main
struct AgentBoxCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentbox",
        abstract: "Agent Box helper (mcp, hook, ctl).",
        subcommands: [CtlCommand.self, HookCommand.self]
    )
}
