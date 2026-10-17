# T2-02 / T2-03: injecao por lancamento (Fatia 2)

- `LaunchInjection` (helper do `agentbox`, hashes de trust do Codex, MCP e plugin do Claude) so vale com `slice >= .slice2`; na Fatia 1 o segmento `injected` continua vazio (goldens `slice1/` inalterados).
- Claude: `--settings <run/launch/<runID>/settings.json>` sempre; `--mcp-config` e `--plugin-dir` somente com conteudo; prompt protegido por `--` quando ha flag variadica.
- Codex: `-c hooks.<Evento>=...` mais `-c hooks.state={...}` (trust inline, P18) quando ha hashes; `--no-daemon` no segmento `profile`; nunca `--dangerously-bypass-hook-trust`; sem hashes, so as definicoes (fallback `estimated`).
- Arquivos `0600` em diretorio `0700` (subdiretorios do plugin tambem `0700`); `InjectionValidator` agora e aplicado pelo `LaunchPlanner` (`injectionViolation`). Resume regenera flags e arquivos identicos. Nada em `~/.claude` nem `~/.codex`.
- Goldens novos: `Packages/AgentBoxKit/Tests/CoreTests/Launch/Golden/slice2/`.
- Teste real: `AB_REAL_CLI=1 swift test --filter Slice2Real` roda `claude -p --model haiku "reply OK"` com a injecao; o app de teste recebeu Stop (activity `done`) e SessionStart (`providerSessionID` == `--session-id`). Passou em 7,6 s (centavos). Teste real do Codex: skipped (sem cota ate 22/10/2026).
- Suite completa: 848 testes passaram (uma rodada teve 3 falhas de temporizacao de terminal sob carga, nao reproduzidas na seguinte).
