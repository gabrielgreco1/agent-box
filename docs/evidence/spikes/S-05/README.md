# S-05: hooks por lançamento (Claude `--settings`, Codex `-c hooks`, daemon do Codex)

Data: 2026-10-17. Claude Code 2.1.302, Codex CLI 0.160.0, macOS (Orca 1.4.219 instalado, com hooks globais do Orca em `~/.claude/settings.json` e `~/.codex/hooks.json`). Custo: Claude ≈ US$ 0,03 (3 execuções com `--model haiku`); Codex US$ 0 (a conta ficou sem cota: "usage limit", ver limitações).

## Perguntas

- (a) Os hooks de `claude --settings <arquivo>` disparam, somam aos globais (Orca) ou os substituem, e quais são os payloads?
- (b) `codex -c hooks…` funciona? Exige trust por hash em `~/.codex/config.toml`? O hash é estável? Há alternativa sem tocar a config global?
- (c) O que é o app-server daemon do Codex e ele interfere (`--no-daemon`)?

## Método e comandos exatos

Tudo em diretório temporário fora do repo (`<scratchpad>/spikes/s05`). Logger: `logger.sh <tag>` (cópia aqui) lê o stdin do hook, anexa `{tag,payload}` em `$SPIKE_LOG` e devolve `{}`. Nenhum arquivo global foi editado; `sha256` de `~/.codex/config.toml` e `hooks.json` conferido antes e depois das execuções `exec`/app-server (idêntico). Nunca usado `--dangerously-bypass-hook-trust`.

Claude (a):

```
claude -p --model haiku --session-id <uuid> --settings settings-hooks.json \
  --debug-file a1.debug --output-format stream-json --verbose --include-hook-events \
  --permission-mode acceptEdits --allowedTools Bash --max-budget-usd 0.15 \
  "Run the shell command 'echo spike-ok' with the Bash tool, then reply with exactly: DONE"
```

`settings-hooks.json` registra o logger em SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Notification, Stop, StopFailure, SubagentStart, SubagentStop, SessionEnd. O cwd tinha ainda `.claude/settings.json` de projeto com um logger em UserPromptSubmit. Segunda execução: `--permission-mode default` pedindo um `Write` (negado em `-p`) para provocar `PermissionRequest`.

Codex (b, c):

- `hooks_list_probe.py` / `codex_trusted_run.py`: sobem `codex app-server --listen stdio://` com 5 `-c hooks.<Evento>=[{hooks=[{type="command",command="<logger> <Evento>",timeout=5}]}]` e chamam o método JSON-RPC `hooks/list`, que devolve por hook `source`, `key`, `currentHash` e `trustStatus` (esquema obtido com `codex app-server generate-json-schema`).
- `codex exec --skip-git-repo-check -m gpt-5.6-luna -c model_reasoning_effort=low -s read-only <-c hooks…> [-c hooks.state={…}] --json "<prompt>"`.
- `tui_probe.py`: TUI interativa (`codex …`, com e sem `--no-daemon`) num PTY, em projeto já confiável, digita um prompt e anota processos e hooks.
- (c): `codex app-server daemon start|version|stop`.

## Resultados

### (a) Claude `--settings`

1. **Os hooks por lançamento disparam**: todos os eventos registrados rodaram (fixture `claude-settings-hooks-payloads.json`).
2. **Somam, não substituem.** Em `claude-hook-sources-additive.json`: `UserPromptSubmit` rodou 3 hooks (global do Orca + projeto + `--settings`); `PreToolUse`/`PostToolUse`/`Stop` rodaram 2 (Orca global + `--settings`); `SessionStart` 5 (global, `--settings` e 3 de plugins). O `--debug-file` lista o comando do Orca (`claude-hook.sh`) em cada evento. Isto confirma o V1 de 08 §11.2: hooks de várias fontes rodam todos. Sem as variáveis `ORCA_*` o script do Orca sai em silêncio (só imprime `{}`).
3. **Payloads** (campos observados, todos os eventos trazem `session_id`, `transcript_path`, `cwd`, `hook_event_name`):
   - `SessionStart`: `source` (`startup`).
   - `UserPromptSubmit`: `prompt_id`, `permission_mode`, `prompt`.
   - `PreToolUse`: `prompt_id`, `permission_mode`, `effort{level}`, `tool_name`, `tool_input`, `tool_use_id`.
   - `PostToolUse`: idem + `tool_response`, `duration_ms`.
   - `PermissionRequest`: dispara em `-p` depois do `PreToolUse` (`tool_name`).
   - `Stop`: `stop_hook_active`, **`last_assistant_message`** (ex.: `"DONE"`), `background_tasks`, `session_crons`.
   - `SessionEnd`: `reason` (`other` em `-p`).
   - `SubagentStart`/`SubagentStop`: ver S-08.
4. **`Notification` não foi observado**: em `-p` não dispara; provocá-lo exige a TUI, e a TUI do Claude pede "trust this folder", que grava em `~/.claude.json` (config global). Ficou sem verificar (V13 continua aberto; Orca já tem fixture de 2026-10-16 em `docs/evidence/claude-native-hooks-2026-10-16.json`).
5. `--include-hook-events` no `stream-json` devolve `hook_started`/`hook_response` (com `exit_code`/`outcome`) por hook: útil para o contrato de testes, não para o adapter.

### (b) Codex `-c hooks…`

1. **Descobertos, mas `untrusted`.** `hooks/list` mostra os hooks de `-c` com `source: "sessionFlags"`, `key: "/<session-flags>/config.toml:<evento>:<i>:<j>"` e `trustStatus: "untrusted"` (`codex-hooks-list-sessionflags.json`). Execução `codex exec` nessas condições: **zero** invocações do logger. Os hooks do `~/.codex/hooks.json` do Orca aparecem como `trusted` (hash gravado em `[hooks.state."<arquivo>:<evento>:i:j"]`).
2. **Hash estável quando o conteúdo é estável** (`codex-hash-stability.json`): mesma definição repetida, em outro cwd ou em `/tmp` dá o mesmo `currentHash`; mudar `timeout` ou o texto do comando muda o hash. A chave (`/<session-flags>/config.toml:stop:0:0`) não depende de caminho por execução. Portanto uma aprovação gravada pelo Codex valeria para sempre **se** o comando do helper e o `timeout` forem constantes (sem run id/pane no comando; correlação só por env).
3. **Achado novo: o trust pode ser passado no próprio lançamento, sem escrever nada em `~/.codex`.** A forma pontilhada (`-c 'hooks.state."<key>".trusted_hash="…"'`) é ignorada, mas a forma de tabela inline funciona:
   `-c 'hooks.state={"/<session-flags>/config.toml:stop:0:0"={trusted_hash="sha256:…"}}'` muda o `trustStatus` para `trusted`. Com isso, `codex exec` e a TUI dispararam `SessionStart` e `UserPromptSubmit` (`codex-hook-payloads.json`). O hash vem de `hooks/list` (um app-server de sonda por lançamento, ~0,3 s) ou de recomputo se o algoritmo for descoberto. Isto **não** é `--dangerously-bypass-hook-trust` (vale só para os hooks listados, por hash) e **não** grava no config, mas é auto-confiança do app: contorna o modelo de trust do Codex. É zona cinzenta e vai para o dono (D-Codex-1, abaixo).
4. **Payloads Codex capturados** (`codex-hook-payloads.json`):
   - `SessionStart`: `session_id`, `transcript_path` (o rollout `~/.codex/sessions/AAAA/MM/DD/rollout-…jsonl`, **já no primeiro evento**: dá o ID nativo e o arquivo para o tail), `cwd`, `hook_event_name`, `model`, `permission_mode`, `source` (`startup`).
   - `UserPromptSubmit`: os mesmos + `turn_id`, `prompt`.
   - `permission_mode` veio `bypassPermissions` mesmo com `-s read-only` (campo não confiável para o estado).
5. **Limitação: não foi possível capturar `PreToolUse`, `PostToolUse`, `Stop`/`last_assistant_message`.** Todos os turnos do Codex falharam com "You've hit your usage limit" (a conta só volta em 22/10/2026; é o `turn.failed` que o app mapearia para `failed(reason)`). O que fica pendente: payloads de `PreToolUse`/`PostToolUse`/`Stop`, `SubagentStart/Stop` do Codex e `last_assistant_message` no `Stop`. Reexecutar `codex_trusted_run.py` depois de 22/10 (ou com outra conta).
6. **Alternativas sem hook, sem tocar o config** (não exercitadas além da leitura): `-c notify=[…]` por lançamento (só fim de turno; o `notify` global do Computer Use é substituído, não encadeado, a menos que o helper o chame), tail do rollout (o caminho vem no `SessionStart` se hooks rodarem, ou por §2.5), app-server JSON-RPC (`hooks/list`, `thread/*`; viável para sonda, mas contra P9 como transporte do agente).
7. **Efeito colateral observado no config global (não causado por hooks)**: depois das execuções da TUI Codex, `~/.codex/config.toml` mudou de mtime; o diff contra `config.toml.bak` mostra a TUI mantendo `[tui] screen_reader_detection_done` e contadores `[tui.model_availability_nux]`. Nenhuma entrada `hooks.state` nova foi criada. Ou seja, **a própria TUI do Codex escreve estado de UI no config do usuário a cada lançamento**, independente do Agent Box; vale citar em T10/§3.3.1 (a regra "o app não escreve em `~/.codex`" está certa; "o Codex nunca altera" não é verificável). `exec` e `app-server` não alteraram o arquivo (sha conferido).

### (c) App-server daemon × `--no-daemon`

- `codex app-server daemon start` instala `~/.codex/packages/app-server-daemon/` e sobe `codex app-server --listen unix:// --managed-daemon` (+ `daemon pid-update-loop`) com **ppid 1 e pgid próprio**, socket em `~/.codex/app-server-control/app-server-control.sock` (symlink para `/private/tmp/codex-daemon-501/<hash>`). Sem o daemon rodando, nenhum processo de daemon existia antes do teste (nem o `codex exec` nem a TUI o iniciaram nas execuções feitas; `daemon_auto_start=true` fica registrado na feature list mas só observei o `start` explícito).
- `codex exec` com o daemon rodando: o hook disparou no próprio processo (exec não delega).
- TUI com o daemon rodando, com e sem `--no-daemon`: processo único `codex …` no pgid do PTY, hooks `-c` dispararam nos dois casos (`SessionStart`, `UserPromptSubmit`) e nenhum processo-filho do daemon apareceu. Não consegui provar, com os turnos falhando, em qual processo a thread vive. Conclusão prudente: o daemon é um servidor compartilhado fora do grupo do PTY (matá-lo não é função do pane), e `--no-daemon` é a única forma documentada de garantir que a sessão e a config `-c` pertençam ao processo do pane.
- Estado restaurado: daemon parado com `codex app-server daemon stop`; sobrou `~/.codex/packages/app-server-daemon/` (criado por mim ao instalar o daemon) e o diretório `~/.codex/app-server-control/` (dono: Codex; inerte). Remover à mão se incomodar.

## Conclusão

- (a) **Confirmado** (V1): `--settings` soma com os hooks globais e traz `session_id`, `transcript_path`, `source`, `last_assistant_message`, `prompt_id`. Adapter Claude por lançamento está desbloqueado (T1-15, T2-02). `Notification` segue por verificar.
- (b) **Hooks por `-c` rodam somente se `trusted`**; o hash é estável com comando e timeout constantes; o trust pode ser dado por `-c hooks.state={…}` (sem escrever em `~/.codex`). Sem isso, o baseline de rollout `estimated` continua o único caminho que não mexe em nada.
- (c) O daemon existe e vive fora do PTY; `--no-daemon` é seguro e barato.

## Recomendação

1. Fatia 1: sem hooks de Codex (`unknown`); Claude por `--settings` como em 06 §3.3.
2. Fatia 2: Codex por **tail do rollout `estimated`** como baseline sempre ativo; hooks `-c` só depois de D-Codex-1.
3. Passar `--no-daemon` por padrão no adapter Codex (decide 06 §2.2, linha `--no-daemon`) e registrar a capability.
4. Manter comando e `timeout` dos hooks do helper constantes (`agentbox hook --provider codex --event X`, `timeout=5`) para o hash não mudar entre versões do app apenas por caminho; o hash só muda quando a definição muda.

## Para decisão do dono: D-Codex-1

Opções, da menos para a mais intrusiva: (A) só rollout `estimated` (nada a decidir); (B) hooks por `-c` com **trust inline por lançamento** (`-c hooks.state={…}`, achado deste spike): nenhum arquivo do Codex é escrito pelo app, nenhum clique, mas o app declara confiar nos próprios hooks (o hash é o do próprio hook que ele gera); (C) aprovação na TUI, gravada pelo Codex em `config.toml` (a ideia original de D-Codex-1). Sugestão: B é tecnicamente o mais limpo, porém é um bypass funcional do modelo de segurança de hooks do Codex; só adotar se o dono aceitar isso explicitamente, caso contrário A agora e C como opt-in na Fatia 2.

## Texto proposto para a spec (não editado aqui)

**06 §3.3.1, acrescentar após "O problema":** "Spike S-05 (2026-10-17, Codex 0.160.0): hooks de `-c` entram como `source=sessionFlags`, chave `/<session-flags>/config.toml:<evento>:i:j`, `untrusted`, e **não executam**. O `currentHash` é estável para o mesmo comando e `timeout` (não depende de cwd nem de repetição) e muda se qualquer um deles mudar. O trust pode ser fornecido no próprio lançamento por `-c 'hooks.state={"<chave>"={trusted_hash="<hash>"}}'` (forma de tabela inline; a forma pontilhada é ignorada), sem escrever em `~/.codex/config.toml`; com isso `SessionStart` (traz `transcript_path` do rollout) e `UserPromptSubmit` (traz `turn_id`, `prompt`) dispararam. Isto equivale a auto-confiança e fica sob D-Codex-1. Pendente: payload de `PreToolUse`/`PostToolUse`/`Stop` (cota do Codex esgotada)."

**06 §2.2, linha `--no-daemon`:** "S-05(c): o daemon (`codex app-server daemon`) roda com ppid 1 e pgid próprio, socket em `~/.codex/app-server-control/`. O adapter passa `--no-daemon` por padrão (a sessão e os `-c` por lançamento ficam no processo do pane). Capability `noDaemon` registrada por versão. O Codex TUI atualiza `[tui]` no `config.toml` por conta própria (independe do app)."

**06 §3.3 (Claude), V1:** "Confirmado em 2.1.302: hooks de `--settings` somam com os globais e de projeto; payloads em `docs/evidence/spikes/S-05/`. `Notification` não verificado."

## Arquivos

`claude-settings-hooks-payloads.json`, `claude-hook-sources-additive.json`, `claude-permission-request.json`, `codex-hooks-list-sessionflags.json`, `codex-hash-stability.json`, `codex-hook-payloads.json`, scripts `logger.sh`, `hooks_list_probe.py`, `codex_trusted_run.py`, `tui_probe.py`, `settings-hooks.json`.
