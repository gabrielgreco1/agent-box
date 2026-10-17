# T2-01 · Atividade e spool — evidência

Comandos (DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer): `scripts/bootstrap.sh --fonts`, `scripts/gen.sh`, `scripts/build.sh`, `scripts/lint.sh`, `scripts/lint-ui.sh`, `swift test` em `Packages/AgentBoxKit`.

- `swift-test.log`: suíte inteira, 586 testes em 91 suítes, 0 falhas (inclui os novos de atividade, spool, helper real, migração e injeção).
- `lint.log`, `lint-ui.log`, `build.log`: Swift 6 estrito sem warnings, bundle assinado e verificado.
- `hook-latency.log` (gerado por `hook-latency.py`): `agentbox hook` Release assinado do bundle, 200 execuções por cenário. App fechado (spool): p50 16,9 ms, p95 20,2 ms. App aberto (socket com ack): p50 15,5 ms, p95 20,3 ms. App travado: desiste em ~220 ms e grava no spool. AR-707 (p95 ≤ 30 ms) atendido; baseline de `fork+exec` de `/usr/bin/true` na mesma máquina: p95 9,1 ms.

## O que entrou

| Peça | Onde |
|---|---|
| Subcomando `agentbox hook --provider <claude\|codex> --event <Evento>` | `Sources/agentbox/Hook/HookCommand.swift` |
| Envelope, limites, redução do payload, saneamento da última mensagem | `Sources/AgentBoxProtocol/Hooks/` |
| Spool (`flock` + rename), transporte com prazo de 200 ms (`poll`), observador kqueue | `Sources/AgentBoxPlatform/Hooks/` |
| Redutor de eventos → atividade (puro), projeção em `agent_run`, agregação, idle de 30 min | `Sources/AgentBoxCore/Activity/ActivityReducer.swift` |
| Serviço de ingestão (socket + spool + reconcile + retenção), serviço `hook` de `app.sock` | `Sources/AgentBoxCore/Activity/ActivityService.swift` |
| `AppSockHub`: `hook` e `ctl` no mesmo `app.sock` (handshake de serviço de AR-106) | `Sources/AgentBoxCore/Control/AppSockHub.swift` |
| Migração `v2_activity` e API do Store | `Sources/AgentBoxStore/Schema.swift`, `AgentBoxStore+Activity.swift` |
| Settings de hooks do Claude por lançamento e `-c hooks…` + trust inline do Codex (funções puras) | `Sources/AgentBoxCore/Launch/HookInjection.swift` |

## Mapa AC e requisitos

| Requisito | Teste |
|---|---|
| TA-301 (máquina de estados com fixtures reais, agregação) | `ReducerRealPayloadTests`, `ReducerSyntheticTests`, `ActivityAggregationTests` (payloads de S-05 e S-08 lidos direto de `docs/evidence/spikes/`) |
| TA-302 (app fechado: o turno termina, ao reabrir a sessão mostra `done` com a última mensagem e o horário certo) | `SpoolIngestionTests.appClosedTurnIsRecoveredOnOpen`, `HookCLITests.appClosedEventGoesToTheSpool…` (helper real) |
| TA-303 (helper inerte sem `AGENTBOX_RUN_ID`; nada em `~/.claude`) | `HookCLITests.withoutRunIDTheHelperIsInertAndSilent`; `ClaudeHookSettingsTests` (só gera dados, não escreve) |
| TA-304 (`waitingOnSubagents` até o último `SubagentStop`) | `parentStopWithLiveChildrenWaitsUntilTheLastSubagentStop` (payloads reais com o `Stop` movido), `ActivityServiceTests.stopBeforeSubagentStops…` |
| TA-305 (`needsInput` permissão e pergunta) | `permissionRequestIsNeedsInputPermission…`, `askUserQuestionIsNeedsInputQuestion…`, `notificationTypesMapPerSpec` |
| TA-306 (última mensagem saneada, ≤ 500) | `HookTextSanitizerTests`, `ActivityServiceTests.realClaudeTurnProjectsIntoRunAndTerminal` (`terminal.last_message == "DONE"`) |
| TA-307 (parte pura: `-c hooks…`, `hooks.state={…}` inline, sem `--dangerously-bypass-hook-trust`) | `CodexHookConfigTests` (hashes do fixture real `codex-hooks-list-sessionflags.json`) |
| TA-313 (retenção; linha inválida não trava) | `AgentEventStoreTests.retentionKeeps…`, `SpoolIngestionTests.corruptedLinesNeverBlock…` |
| AC-201 (dado de entrada: mensagem do `Stop` → `terminal.last_message`) | `ActivityServiceTests.realClaudeTurn…` (a renderização na sidebar é de tarefa de UI) |
| AC-202 (parte do app: `Stop` chega pelos hooks por lançamento) | `HookCLITests.liveAppReceivesTheEvent…` (helper real → app.sock → banco); Claude/Codex reais ficam para T2-02/T2-03 |
| AC-T24 / AR-540 (sem `python3`, `node`, `jq`) | `HookCLITests.noPythonNodeOrJQIsNeededOrTouched` (PATH reduzido, interpretadores falsos que falham e registram chamada) |
| AR-707 (p95 ≤ 30 ms) | `hook-latency.log` (Release). `HookCLITests.helperLatency…` só impõe um teto grosso (400 ms) no build Debug com `Process` do Foundation |
| Timeout 200 ms / nunca bloqueia | `HookTransportTests.appThatAcceptsButNeverAnswers…`, `HookCLITests.hungAppDoesNotBlock…` |
| Ordem fora de sequência | `outOfOrderArrivalProducesTheSameState…`, `ActivityServiceTests.outOfOrderArrivalConverges…`, `spoolAndLiveEventsInterleavedOutOfOrderConverge` |
| Idempotência | `replayingTheSameEventsIsIdempotent`, `AgentEventStoreTests.eventsAreIdempotent…`, `drainingFileLeftByACrashIsReprocessedIdempotently`, `HookTransportTests` (`duplicate: true`) |
| Migração `v2_activity` (AR-323) | `V2ActivityMigrationTests` (banco da Fatia 1 com dados migra, backup pré-migração), `MigrationTests` |
| Spool: 4 MiB com marcador `truncated`, `0600`, escrita concorrente sem perda | `HookSpoolTests` |

## Decisões e divergências

- **Spool sem cursor em disco**: o leitor renomeia o arquivo sob `flock` (`.draining`) e o apaga depois de processar; o escritor reabre se o inode mudou. Equivalente ao "cursor avança mesmo em linha inválida" e sem estado extra. Registrado em 06 §3.2.
- **`agent_event` com `event_id` e `at_ns`** (08 §3.2 atualizado): `event_id` é a chave de idempotência por execução (o mesmo evento chega pelo socket e pelo spool); `at_ns` é a hora de ocorrência medida no helper e define a ordem. O estado é projeção dos eventos reaplicados nessa ordem: evento atrasado refaz o estado em vez de corromper.
- **`v2_activity` cria todas as tabelas listadas em 08 §3.2** (`attention`, `inbox_event`, `catalog_item`, `secret`, `secret_binding`, `import_run`, `metric` além de `agent_run`/`agent_event`), porque a migração publicada nunca é editada; só `agent_run` e `agent_event` têm API nesta tarefa.
- **`AgentRun`/`AgentRunKind`** (Protocol) ganharam os campos de `agent_run`; eram só um tipo da Fatia 1.
- Payload reduzido **no helper** (nunca leva o prompt, `tool_input` completo nem `tool_response`); alvo curto (comando, nome do arquivo) só para "Running Bash" e "Wants to run: …".
- Filho sem `SubagentStart` visto (evento só de ferramenta) é **implícito** e não segura o pai em `waitingOnSubagents` (se o `SubagentStop` se perder o pai não espera para sempre).
- Execução de um terminal só atualiza `terminal.last_message`/ID nativo se `current_run_id` é nulo ou igual (evento atrasado de run antigo não sobrescreve).
- `AGENTBOX_HOOK_TIMEOUT_MS` (só teste, 08 §0.2 atualizado) permite prazo maior nos testes funcionais do helper: com a suíte inteira em paralelo o app de teste não responde em 200 ms de forma confiável. Os testes do prazo de 200 ms usam o padrão e medem dentro da thread do helper.
- Eventos sintéticos `ProcessExit` (código de saída) e `PtyLost` entram em `agent_event`; o app chama `recordProcessExit`/`recordPtyLost` (ligação com o daemon é da integração de lançamento, T2-02).
- Payloads de `Notification` e `StopFailure` **não têm fixture real** (S-05 não conseguiu provocá-los; V13 aberto): os testes usam payloads sintéticos com os campos documentados (`notification_type`, `message`; erro lido de `error`/`error_message`/`stop_reason`). Codex só tem `SessionStart` e `UserPromptSubmit` reais; `PreToolUse`/`PostToolUse`/`Stop` do Codex seguem pendentes (cota até 22/10/2026), então o mapeamento do Codex é o mesmo do Claude, não verificado além desses dois.

- Lição de teste: bloquear o pool do GCD com `waitUntilExit` em paralelo impede o `Process` de notificar o término (a suíte travou); os testes usam threads próprias para trabalho bloqueante.

## Não feito (fora do escopo de T2-01)

- **Ligar o hub ao app**: `AppEnvironment` ainda não abre o Store, então `AppSockHub` + `ActivityService` + `HookServiceProvider` existem e são testados sobre socket real, mas não são iniciados pela UI (depende do bootstrap do Store no app, T2-02/T2-04). O `CtlServer` isolado segue como está.
- Injeção no argv (`--settings`, `-c hooks…`) e a sonda `hooks/list` do Codex (T2-02/T2-03); o rollout `estimated` do Codex (T2-03).
- Notificações, unread, Inbox, badge, "Next Needing Attention" (T2-04); a linha da sidebar com a última mensagem (UI).
- Janela de silêncio dos hooks → `unknown` (01 §6.3 cita "a janela de 06", que não define o valor; um agente pode ficar minutos sem hook num turno longo, então não inventei um prazo). `stalled` é v1.1.
- Diagnostics "Activity tracking unavailable" (mostra o motivo quando a injeção falha).
