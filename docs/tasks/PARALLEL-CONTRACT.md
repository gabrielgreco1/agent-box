# Contrato do lote 1

Código de design preservado em `design/`. App operacional novo em `Sources/AgentBox`, domínio reutilizável em `Sources/AgentBoxCore`. macOS 14+, Swift 5 language mode, SwiftTerm 1.20.0. Fontes de sistema, logos oficiais, sem fixtures no runtime.

## Propriedade dos arquivos

- PTY agent: `Sources/AgentBox/Terminal/`, `Sources/AgentBoxCore/Processes/`, `Tests/AgentBoxCoreTests/Processes*`, `docs/tasks/AB-002.md`.
- UI agent: `Sources/AgentBox/Workspace/`, `Sources/AgentBoxCore/Workspaces/`, `Tests/AgentBoxCoreTests/Workspace*`, `docs/tasks/AB-003.md`.
- Docker agent: `Sources/AgentBox/Docker/`, `Sources/AgentBoxCore/Docker/`, `Tests/AgentBoxCoreTests/Docker*`, `docs/tasks/AB-004.md`.
- Integrador: entry point, Package.swift, Domain.swift, biblioteca/memória/skills, recursos, build, integração, documentação geral e Git.

Não editar arquivos de outro responsável; comunicar ajustes. Não fazer commit/push, instalar software, iniciar CLI pago, criar container ou alterar credenciais sem instrução específica. Testes usam shells locais descartáveis e runners falsos quando apropriado. Nenhum agente usa cópia de UI falsa para representar estado conectado.

## Interfaces compartilhadas

`AgentBoxCore.Domain.swift` define `CLIProvider`, `TerminalRecord`, `WorkspaceSession` e `AppPaths.applicationSupport`.

PTY: `@MainActor TerminalRuntimeManager: ObservableObject`, `init()`, `start(_ terminal: TerminalRecord)`, `stop(_ id: UUID)`, `shutdown()`, `state(for id: UUID) -> TerminalProcessState`. `TerminalProcessState` expõe `idle`, `starting`, `running(pid: Int32)`, `exited(code: Int32?)`, `failed(String)`. `TerminalSurface(terminal: TerminalRecord, runtime: TerminalRuntimeManager)` é NSViewRepresentable/SwiftUI; criar ou remontar a view NÃO relança processo. O manager guarda emulador/PTY por ID enquanto o app vive; não afirmar sobrevivência ao quit/crash.

UI: `WorkspaceView()` é o ponto de entrada; tem manager compartilhado, sidebar/sessões/panes e lançamento explícito. A biblioteca abre `LibraryView()`. Configurações abrem `AppSettingsView()`. Inspector opcional de computador abre `ComputerPanel(terminalID: UUID)`. Esses três tipos serão implementados por outros responsáveis. Restaurar metadados não dispara comandos automaticamente. Fechar app com processos vivos oferece escolha de cancelar ou encerrar; runtime sobrevivente ao quit fica para serviço posterior.

Docker: `DockerSettingsView()` e `ComputerPanel(terminalID: UUID)` consultam estado real. Primeira entrega pode criar/parar computador HTTP apenas após escolha explícita e política habilitada. Não alegar browser/desktop/stream operacionais. Box lógica sempre ligada a terminal selecionado; native child binding depende do gate M5.

Root: `LibraryView()` entrega CRUD de definições, memória e skills, persistência e exportação de contexto. Ativação nativa só quando verificada; não escrever instruções arbitrariamente num PTY ativo.

## Evidências

Cada agente registra o que funciona, testes executados e limites no seu arquivo de tarefa. Critérios globais continuam planejados até integração, sem marcar entrega parcial como conclusão integral.
