# AB-016 · Identidade observada de agentes

## Contrato entregue

`AgentRunRegistry` guarda JSON durável de runs com `terminalID`, PID observado, provedor, horários e estado. `recordTerminalStart` deve ser chamado apenas depois do estado `.running(pid:)` do runtime; salvar uma definição ou materializar contexto não cria run. Um filho nativo tem `parentRunID` e `parentTerminalID`, sem PID ou terminal próprios inventados. A persistência é atômica e o arquivo recebe permissão `0600`.

`NativeAgentHookEvent.parse` aceita somente JSON estruturado com `hook_event_name`, `session_id`, `agent_id` e `agent_type` onde aplicáveis. `recordHookEvent` exige uma sessão pai previamente correlacionada via `SessionStart`, mesmo provedor e run pai ativo. Texto do PTY não entra nesse contrato. `SubagentStart` repetido com o mesmo ID retorna a identidade existente; `SubagentStop` só encerra um filho previamente observado. O registro não controla processos/filhos nem os apresenta como terminais independentes.

`AgentIdentityCapability.current(for:)` diferencia PID de PTY observado, hooks de subagente documentados, captura ao vivo e terminal independente. Para Claude e Codex, hooks estão documentados, porém `liveSubagentCapture=false`: não há transporte de hooks instalado ou validado no app. OpenCode e shell não têm contrato de subagente verificado. Um caller não deve mostrar filhos reais na UI até integrar transporte confiável e testar eventos de uma sessão real autorizada.

## Fontes e lacunas

- [Claude Code hooks](https://code.claude.com/docs/en/hooks): `SubagentStart` traz `session_id`, `agent_id`, `agent_type`; `SubagentStop` inclui os mesmos identificadores. A documentação alerta que `SubagentStop` também pode vir de agentes internos. Por isso, o registro exige `SubagentStart` prévio.
- [Codex hooks](https://learn.chatgpt.com/docs/hooks): `SubagentStart` e `SubagentStop` também incluem `agent_id`/`agent_type` e `session_id` comum. Hooks não gerenciados requerem revisão de confiança; nenhum foi instalado pelo projeto.
- [Codex app-server](https://learn.chatgpt.com/docs/app-server): `thread/list` possui fontes `subAgent` e filtros experimentais `parentThreadId`/`ancestorThreadId`. Isso não significa que o PTY Codex comum do Agent Box esteja inscrito nesse servidor.

Falta provar em execução real: identificação inequívoca do run pai no transporte de hook, entrega/ordem dos eventos em uma TUI lançada pelo app, semântica de resume e cobertura de agentes internos, reconciliação após quit/crash, e compatibilidade com as versões efetivamente instaladas. Não foram enviados prompts pagos nem iniciados agentes nativos para este lote.

## Verificação

`AgentRegistryTests` usa fixtures de formato documentado, exige correlação de sessão, confirma persistência/permissão e rejeita texto de terminal e evento de filho não correlacionado. `swiftc -typecheck` passou para o Core isolado. O integrador executa o pacote completo serialmente.

## Integração posterior — AB-040

Monitor de runtime e sidebar estão ligados ao registry. Claude Code real produziu início/fim de um subagente com assinaturas válidas no smoke; resultado sanitizado em `../evidence/claude-native-hooks-2026-10-16.json`. O teste visual de TUI → árvore de filhos no app ainda está pendente. Ver `AB-040-native-agent-tree.md` para separar evidência de transporte, PTY e UI.
