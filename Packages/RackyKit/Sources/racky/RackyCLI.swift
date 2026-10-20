// Helper `racky` (subcomandos `ctl`, `hook` e `mcp`).
import RackyPlatform
import RackyProtocol
import ArgumentParser

@main
struct RackyCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "racky",
        abstract: "Racky helper (mcp, hook, ctl).",
        subcommands: [CtlCommand.self, HookCommand.self, HookGuardCommand.self, McpCommand.self]
    )

    /// Sessões de agente iniciadas por uma versão anterior herdam `AGENTBOX_*`: promove para `RACKY_*` antes de qualquer subcomando.
    static func main() async {
        LegacyEnvironment.promoteProcessEnvironment()
        await main(nil)
    }
}
