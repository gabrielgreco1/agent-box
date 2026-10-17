# S-08: `mcpServers` inline por subagente e `agent_id` nos hooks (07 S1)

Data: 2026-10-17. Claude Code 2.1.302. Custo: ≈ US$ 0,01 (uma execução `--model haiku`).

## Pergunta

Na versão instalada, `--agents` aceita `mcpServers` inline por subagente? O servidor MCP de cada filho é distinguível? Os hooks trazem `agent_id`/identificação do subagente?

## Método

Servidor MCP stdio mínimo (`mcp_whoami.py <ident>`, sem SDK) com uma ferramenta `whoami` que devolve `I_AM_<ident>` e registra start/chamadas (pid, ppid) em arquivo. Dois subagentes `child-a` e `child-b` (haiku), cada um com seu servidor inline e `tools` restrito à ferramenta do seu servidor (`agents.json`). Hooks por `--settings` (mesmo logger do S-05).

```
claude -p --model haiku --agents "$(cat agents.json)" --settings settings-hooks.json \
  --output-format stream-json --verbose --include-hook-events --permission-mode acceptEdits \
  --allowedTools "Agent,mcp__whoami-a__whoami,mcp__whoami-b__whoami" --max-budget-usd 0.3 \
  "Launch the subagents child-a and child-b using the Agent tool (one call each, in the same turn, subagent_type child-a and child-b). Then reply with the two replies on one line."
```

Primeira tentativa: `mcpServers` como objeto `{nome:{…}}` foi **recusado** ("expected array, received object"). O formato aceito é **array**; cada item é `{ "<nome>": {command,args} }` (ou, pelo que a mensagem sugere, o nome de um servidor já configurado; não testado).

## Resultado (fixtures: `subagent-hook-payloads.json`, `mcp-server-process-log.json`, `agents.json`)

- **Funciona na 2.1.302.** Resposta final `I_AM_A I_AM_B`; custo US$ 0,0098.
- **Um processo MCP por filho**, filhos diretos do processo `claude` (mesmo ppid), iniciados quando o subagente sobe; ao final nenhum sobra. A ferramenta aparece como `mcp__<servidor>__<ferramenta>`.
- **Isolamento**: os servidores inline **não** aparecem em `mcp_servers`/`tools` do evento `init` da sessão-pai; só o filho dono os usa.
- **Hooks trazem identidade do filho**:
  - `SubagentStart`: `agent_id` (ex. `a9d32b813be6acccc`), `agent_type` (`child-a`).
  - `PreToolUse`/`PostToolUse` **dentro do filho**: `agent_id`, `agent_type` e, para ferramentas MCP, `mcp_server: {name:"whoami-a", source:"agent"}`.
  - `PreToolUse`/`PostToolUse` do pai (ferramenta `Agent`) **não** têm `agent_id`; têm `tool_use_id`.
  - `SubagentStop`: `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message` (`I_AM_A`), `stop_hook_active`, `permission_mode`, `effort`.
  - `Stop` do pai: `last_assistant_message: "I_AM_A I_AM_B"`.
- **Dois filhos distinguíveis**: os pares (`agent_id`, `agent_type`, `mcp_server.name`, resposta `I_AM_A`/`I_AM_B`) são coerentes de ponta a ponta; as chamadas simultâneas não se misturaram.
- **O que o processo MCP vê**: o ambiente herdado do `claude` (sem variável com `agent_id`) e o `argv` da própria definição. Portanto a identidade no servidor MCP vem da **configuração por filho** (argv/env do `mcpServers` inline, p.ex. `agentbox mcp --child <id> --capability …`), não do protocolo. O `agent_id` do hook só existe no lado do hook.

## Conclusão

O modelo de identidade de 07 (§ identidade do chamador) é viável como escrito: (1) processo MCP por filho com configuração própria; (2) `agent_id` + `agent_type` (+ `mcp_server.name`) no `PreToolUse` como correlação. O `agent_id` é gerado pelo Claude por execução, então só serve de correlação; o vínculo "este `agent_id` = este processo MCP" precisa ser feito pelo app (p.ex. o servidor MCP registra a capability no app; o hook `SubagentStart`/`PreToolUse` com `mcp_server.name` casa o nome do servidor, que o app define único por filho).

## Recomendação

- Definir o subagente com `mcpServers` como **array** e nome de servidor único por filho (`agentbox-<runId>-<n>`), e `tools` do filho limitado a `mcp__<nome>__*`.
- Correlacionar no app: `PreToolUse.mcp_server.name` → filho; `SubagentStart.agent_id` → contador de filhos vivos (06 §3.3).
- Não fiar em `agent_id` como autenticação (07 já trata nome como dica).
- Teste pendente (barato, Fatia 3): filho tentando chamar a ferramenta do irmão (`tools` deveria impedir), `--resume` com `--agents` regenerado, e `agents` vindos de plugin/arquivo em vez de `--agents`.

## Texto proposto para a spec (não editado)

**07, identidade do chamador, item (1) e (2):** "Verificado em 2.1.302 (S-08, `docs/evidence/spikes/S-08/`): `--agents` aceita `mcpServers` inline por subagente, **como array** de `{<nome>: {command,args}}` (objeto é recusado); um processo MCP por filho, filho do `claude`, invisível à sessão-pai; as ferramentas ganham o prefixo `mcp__<nome>__`. Os hooks dentro do filho trazem `agent_id`, `agent_type` e `mcp_server{name,source:\"agent\"}`; os do pai não trazem `agent_id`. `SubagentStop` traz `last_assistant_message` e `agent_transcript_path`."

**06 §3.3, `SubagentStart/SubagentStop`:** "campos confirmados: `agent_id`, `agent_type`, `last_assistant_message` (Stop), `agent_transcript_path`."

## Arquivos

`agents.json`, `mcp_whoami.py`, `subagent-hook-payloads.json`, `mcp-server-process-log.json`.
