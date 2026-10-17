# F12/F13 · Subagent computers

Imagens (renderizadas fora da tela por `SubagentSnapshotTests`, sem janela e sem abrir o app): `sessionCard.png` (card com o ícone de computador em Ask, `Restart to apply` fora de uso, linha do agente com chevron, uma linha por subagente com spinner, título, tempo, e o computador reservado na fila), `approvalCard.png` e `spawnApprovalCard.png` (card do modo Ask e do gatilho de spawn), `hoverCard.png` (pré-visualização do computador, nome, URL), `settingsComputers.png`.

Integração real (Docker + `claude -p --model haiku`, `LiveSubagentComputersTests`): `live-full.json`, `live-ask.json`, `live-guard.json` e os `claude-*-summary.json`. Em todos `boxes_reserve` foi chamado, um computador subiu, o worker navegou (reqlog do computador com hits na página) e o título foi devolvido; no Ask o card foi decidido por `Allow`; no `guard` o hook bloqueou o subagente comum e o Claude reservou o computador. Cleanup: 0 recursos e 0 imagens.

Não há captura do app real em execução: a regra do dono proíbe abrir instâncias do app nesta tarefa. O viewer (T3-05) tem evidência própria em `docs/evidence/slice3/`.
