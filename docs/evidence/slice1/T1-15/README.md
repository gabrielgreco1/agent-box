# T1-15: adapters de lançamento e captura do ID nativo

Código: `Packages/AgentBoxKit/Sources/AgentBoxCore/Launch/`. Testes: `Packages/AgentBoxKit/Tests/CoreTests/Launch/`.

- Golden files de argv (32 casos, Fatia 1): `Tests/CoreTests/Launch/Golden/slice1/` (regravar com `AB_UPDATE_GOLDEN=1`, revisar o diff).
- Fixtures reais (`--version`, `--help`, `codex resume --help`, status de login redigido, `opencode session list`, `session_meta` do rollout): `Tests/CoreTests/Launch/Fixtures/`, gravados em 2026-10-17 de Claude 2.1.302, Codex 0.163.0, OpenCode 1.18.34.
- `real-cli-probe.json`: saída de `AB_REAL_CLI=1 AB_EVIDENCE_OUT=... swift test --filter RealCLIProbeTests` (só `--version`, `--help` e comandos de status; nenhum agente com prompt). Confirma que o `--help` instalado é igual ao fixture.

## Decisões e pontos abertos

- Probe de login sem rodar login: `claude auth status --json`, `codex login status`, `opencode providers list` (contagem de credenciais). Autenticação por variável de ambiente resulta em `unknown`.
- Claude: `--` antes do prompt só quando há `--add-dir`/`extraArgs` (opções variádicas engoliriam o prompt). Comportamento do `--` no Claude segue o padrão do commander e NÃO foi exercitado com execução real (proibido executar agente com prompt); conferir em T1-16/E2E.
- Padrões "Claude · Default" e "Codex · Default" pulam permissões (herança do Orca) e sempre geram `skipsPermissions` (ShieldOff).
- ID nativo: Claude `--session-id` (UUID do app, no plano antes do spawn); Codex por varredura de `rollout-*.jsonl` (`session_meta.cwd` igual e `timestamp >= spawn - 2 s`), hook `SessionStart` na Fatia 2; OpenCode por `session list --format json` antes e 5 s depois.
- Codex `--no-daemon` por padrão (piso 0.160.0, S-05); sem a flag, o lançamento segue e há aviso.
- Pendente (depende do daemon, T1-09/T1-16): contador `inputBytesByOrigin` = 0 no PTY. Aqui o plano é puro e não existe caminho que escreva no PTY.
