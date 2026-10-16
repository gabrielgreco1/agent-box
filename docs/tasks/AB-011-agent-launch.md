# AB-011 · Plano revisável de lançamento de agente salvo

## Contrato entregue

`AgentLaunchPlanner.prepare(...)` valida a seleção de memória/skills pela `LibraryContext.prepare`, escopo, validade e revisão; resolve o CLI e a pasta; e devolve um `AgentLaunchPlan` sem gravar arquivo ou abrir processo. `plan.review` expõe argv, ambiente adicional, texto integral, SHA-256, revisão do agente, fonte/revisão das memórias e origem/hash das skills selecionadas. O caller apresenta esse review ao usuário.

`planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)` é a etapa explícita após review: cria um diretório por execução e grava `context.md` com permissão `0600`; não inicia CLI. Repetir o mesmo plano falha sem sobrescrever o snapshot. `planner.removeContextFile(for:)` remove o arquivo após saída do processo ou descarte da exportação. `MaterializedAgentLaunch.validateContextFile()` detecta edição após a revisão. O runtime aceita `try runtime.start(materialized)` apenas quando há terminal ativável, valida o hash e usa o executável exato do plano. Nenhuma API envia texto a um PTY já ativo.

Para restart explícito do mesmo snapshot, `materialized.binding` fornece metadados `Codable`; `AgentLaunchPlanner.restore(binding, terminal:)` reconstrói o argv suportado e confere ID da definição, provedor, cwd, caminho do snapshot no diretório do plano, tipo de arquivo, SHA-256 e o executável resolvido atualmente. Isso apenas restitui um `MaterializedAgentLaunch`; não abre processo. `runtime.start(terminal)` recusa registros com `agentDefinitionID`, exigindo o caminho de lançamento revisado. A UI persiste o binding antes de adicionar o terminal ao workspace e nunca relança automaticamente na abertura.

## Capacidade por CLI

- **Claude Code:** `--append-system-prompt-file <context.md>` inicia a TUI original com o prompt padrão preservado. O conteúdo selecionado entra como contexto anexado. O texto de uma skill importada **não** vira skill nativa invocável por slash command nem cria identidade de subagente.
- **Codex, OpenCode e shell:** plano e arquivo podem ser revistos/exportados; `materialized.terminal` é `nil`, e `runtime.start(materialized)` recusa ativação. O usuário ainda pode abrir um terminal normal do CLI separadamente. O Codex instalado aceita prompt inicial via argv, mas colocar memória/skills potencialmente sensíveis e até 200 KB em argv exporia texto na lista de processos e poderia ultrapassar limites do sistema. `model_instructions_file` substitui instruções internas; não é um append seguro para este caso.

Fontes verificadas: `claude --help`, `claude --version` (2.1.301), `codex --help`, `codex --version` (0.162.1), [referência oficial do CLI Claude](https://code.claude.com/docs/en/cli-reference) e [referência oficial de configuração Codex](https://learn.chatgpt.com/docs/config-file/config-reference). Nenhum cliente de modelo foi iniciado durante a verificação.

## Testes e limites

`AgentLaunchTests` cobre plano sem escrita, revisão de fonte/revisão/hash, snapshot protegido, confirmação de digest, duplicação, limpeza, export-only do Codex, rejeição de memória fora do escopo e restauração com adulteração de argv, path, executável e conteúdo. O integrador executará os testes de pacote serialmente.

O arquivo de contexto permanece no disco até limpeza explícita após término. A integração da UI de review e do registro de uso observado pertence ao integrador; salvar definição ou materializar contexto não marca execução como iniciada. A ativação depende da versão do CLI instalado no momento do lançamento; o adapter foi verificado com as versões locais acima e não cria identidade nativa de agente/subagente.
