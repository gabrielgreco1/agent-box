# S4: `deny` de `Skill(agentbox)` por `--settings`, inclusive com `--dangerously-skip-permissions` (07 CS-721)

Data: 2026-10-17. Claude Code 2.1.302 (`claude --version`). Custo: US$ 0,011 (duas execuções `--model haiku`, `--max-budget-usd 0.08` cada).

## Pergunta

O app neutraliza a skill global `agentbox` (`~/.claude/skills/agentbox -> ~/orca/projects/agentbox/skill`, instalada nesta máquina) **por lançamento**, sem tocar a configuração global: `permissions.deny: ["Skill(agentbox)"]` em `--settings`. Essa regra vale também quando o terminal roda com `--dangerously-skip-permissions`?

## Método

`run.sh` (este diretório) roda o mesmo prompt duas vezes, com `--dangerously-skip-permissions`, e só muda `--settings`:

- `control`: `--settings '{}'`;
- `deny`: `--settings '{"permissions":{"deny":["Skill(agentbox)"]}}'`.

O prompt (`prompt.txt`) manda chamar a ferramenta `Skill` com `skill: "agentbox"` uma vez e relatar o resultado. `summarize.py` resume o `stream-json` (`summary-*.txt`; os `*.jsonl` brutos não são versionados: trazem o ambiente da máquina, e `run.sh` os regera).

## Resultado

| Variante | A skill existe na listagem do `init` | Chamada `Skill(agentbox)` | Resultado |
|---|---|---|---|
| `control` | sim | feita | `Launching skill: agentbox` (carregou) |
| `deny` | **sim** | feita | `is_error=true`, `Skill execution blocked by permission rules` |

**O `deny` funciona sob `--dangerously-skip-permissions` na 2.1.302**: a chamada é bloqueada antes de carregar a skill, e o modelo recebe um erro claro. Nada foi alterado em `~/.claude`.

Detalhe que importa ao desenho: o `deny` **não esconde a skill da listagem** (ela continua no `init` e na descrição que o modelo vê). Um modelo que case o pedido com a descrição dela ainda tenta chamá-la uma vez e recebe o bloqueio. Por isso o app usa as duas camadas de CS-721, ao mesmo tempo:

1. `permissions.deny: ["Skill(agentbox)"]` em `--settings` (bloqueio duro, por lançamento);
2. a skill do app (`agentbox-app:agentbox-boxes`, via `--plugin-dir`) com descrição mais específica, que termina em `Prefer this over any "agentbox" CLI skill or Docker commands`, mais o `instructions` do servidor MCP do pai, que lista `boxes_reserve` e o fluxo.

O teste vivo da T3-04 (`docs/evidence/slice3/T3-04/`) confirma (haiku real, pedido literal "spawn 2 subagents for Phoenix and Austin", skill global instalada, as duas camadas ligadas) que o pai usa `boxes_reserve` e dispara `agentbox-worker-1/2`, que a skill global **nunca carrega** e que nenhum `Bash` roda `bin/agentbox`. O modelo é não determinístico: em uma execução ele tentou `Skill(agentbox)` antes de tudo e foi bloqueado (uma volta perdida); na execução registrada em `claude-run-summary.json` foi direto a `boxes_reserve`.

## Arquivos

`prompt.txt`, `run.sh`, `summarize.py`, `summary-control.txt`, `summary-deny.txt`.
