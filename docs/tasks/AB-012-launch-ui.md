# AB-012 · Lançamento de agente salvo

## Fluxo implementado

- A biblioteca oferece **Usar…** na definição ativa. A revisão escolhe sessão existente ou nova, pasta, escopos de projeto/tarefa/perfil, memórias e skills. Nenhum terminal ou histórico nasce ao preparar.
- A revisão exibe contexto integral, revisão, proveniência, executável, argumentos, pasta, local do snapshot e SHA-256. Alterar a seleção descarta o plano; iniciar exige confirmação explícita do contexto exibido.
- Claude Code usa `AgentLaunchPlanner.materialize` e `TerminalRuntimeManager.start(materialized)`. Vínculo e workspace são gravados antes do start; se essa gravação falhar, nenhum processo é iniciado. O histórico só é gravado depois que o runtime observa `.running(pid:)`. Falha posterior solicita encerramento e restaura os metadados anteriores; o novo terminal não é publicado na UI.
- O vínculo persistido contém o caminho protegido e digest do snapshot. Após reabrir o app, o terminal fica parado. **Iniciar** chama `AgentLaunchPlanner.restore(binding, terminal:)` antes de iniciar o mesmo snapshot. O runtime bloqueia `start(TerminalRecord)` para registros com `agentDefinitionID`.
- Codex, OpenCode e Shell mostram o motivo de não haver adapter verificado e permitem copiar/exportar o contexto; não criam execução ativa de agente salvo.
- O histórico da biblioteca abre a sessão e seleciona o terminal quando ambos ainda existem.
- O painel de computador recebe o terminal, a sessão, a pasta canônica (raiz Git quando conhecida) e o ID de agente provenientes do workspace.

## Limites e integridade

- Reiniciar o mesmo terminal é retomada explícita do mesmo snapshot revisado, sem autorestart e sem criar uma segunda linha de histórico para o mesmo vínculo.
- Uma falha de leitura do arquivo de vínculos preserva o arquivo e bloqueia novos lançamentos de agentes salvos para evitar sobrescrevê-lo.
- Se a persistência falhar depois que o PTY já começou, o processo recebe SIGTERM. O snapshot protegido não é removido enquanto o processo puder estar lendo o arquivo.
- A revisão bloqueia nova tentativa enquanto um processo lançado mas não registrado ainda estiver encerrando. Se SIGTERM não bastar, oferece encerramento forçado com confirmação explícita.
- Uma interrupção abrupta entre a gravação prévia dos metadados e o start pode deixar um terminal restaurado em estado parado sem linha de histórico. O usuário precisará iniciar esse snapshot explicitamente; a UI nunca o rotula como execução observada.
- Os adapters de Codex e OpenCode continuam como exportação até haver mecanismo verificado de ativação na TUI.

## Verificação

- Revisão estática dos pontos de criação, restauração e persistência feita nesta tarefa.
- Build e testes integrados ficam para o agente raiz, que os executa em série com os demais módulos.
