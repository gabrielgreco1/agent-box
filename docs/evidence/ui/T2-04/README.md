# T2-04: atencao e notificacoes

`drive.sh` abre o app em segundo plano (`open -g`, `AGENTBOX_AUTOMATION=1`, `AGENTBOX_SLICE=2`, `AGENTBOX_HOME` isolado, `AGENTBOX_NOTIFICATIONS=fake`, fixture `attention-demo`) e dispara eventos REAIS com `agentbox hook` (payloads S-05 e S-08). Nenhuma notificacao real e pedida ou enviada; o app e encerrado por PID.

| Arquivo | O que mostra |
|---|---|
| `01-sessions-before-hooks` | Antes dos hooks: agentes vivos em "Status unavailable" |
| `02/03-settings-notifications-*` | Permissao nao pedida (cartao + Allow Notifications) e depois de Allow (centro falso concede) |
| `04-cards-states` | Cards: needs input (permissao e pergunta), working (spinner), done nao lido, waiting on 2 subagents, failed, idle; badge 3 no Inbox |
| `05/06-inbox*` | Inbox por grupos (Needs You, Working, Done, Earlier) e filtro Needs You |
| `fake-notifications.jsonl`, `dock-badge.txt` | O que seria entregue ao sistema e o badge do Dock (3) |

Fora da evidencia visual: pane com rim flash e tab (precisam de PTY de agente); cobertos por testes (`AttentionIntegrationTests`, `AttentionProjectionTests`).
