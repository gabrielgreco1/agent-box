# AB-043 — Identidade da chamada e computador de cada filho

## Contrato

Sessão contém terminais; o harness de um terminal cria subagentes nativos. Cada filho observado pode ter um computador independente. O identificador do terminal continua sendo o do pai: nenhum PTY, sessão ou processo fictício é criado para representar um filho.

O MCP é compartilhado pelo harness. Só fornecer uma conexão com a box do terminal não distingue chamadas do pai das chamadas de seus filhos. Uma chamada sem identidade verificada não pode operar o computador do pai por conveniência.

## Implementação desta etapa

- `BrowserComputerOwner` distingue terminal de filho nativo observado. O filho usa o ID permanente de seu registro de execução, junto do terminal pai real.
- Docker labels, metadados, busca, recuperação e troca de imagem preservam o dono. Registros antigos sem `agentRunID` continuam sendo computadores de terminais. Label de filho malformada é erro, não fallback para o pai.
- O painel do filho cria/reinicia somente enquanto o filho e o pai estão ativos e o PID observado corresponde ao PTY atual. Após awaits, revalida atividade e tenta parar a box caso o filho tenha terminado. O painel mostra se essa parada não pôde ser confirmada.
- O usuário pode consultar/parar uma box histórica. Transferir uma box do pai para um filho exige operação de transferência própria e não está implementado.
- O hook `PreToolUse` assina a identidade nativa da chamada, execução, sessão, ferramenta, argumentos, timestamp e nonce. Substitui qualquer token fornecido pelo modelo. Não concede permissões do harness.
- O app mantém um verificador por invocação: recusa alteração de argumentos, execução errada, validade expirada e replay. Valida o `SessionStart` autenticado antes de aceitar o pai. Não usa texto do terminal para atribuir identidade.
- Lançamentos com MCP exigem os hooks revisados; falha de ativação encerra o processo recém-iniciado. Templates antigos precisam ser preparados novamente quando o contrato dos hooks muda.

## Limite explícito

Nesta etapa, a chamada autenticada de um filho ainda recebe erro indicando que o acesso à box própria está pendente. Ela **não** cai na box do pai. O painel pode gerenciar a box separada, mas isso não comprova que o filho já a controla. Falta integrar o despacho por dono, concessão de controle ao filho, criação sob a política automática e liberação no fim do filho.

## Prova do mecanismo nativo

Um probe descartável com Claude Code 2.1.301 em modo `-p` produziu uma chamada MCP do pai e outra de um filho real. O `agent_id` da segunda chamada coincidiu com `SubagentStart`; ambos compartilharam a sessão e tiveram IDs de chamada distintos. `PreToolUse.updatedInput` chegou ao servidor MCP, sem definir `permissionDecision`. A fixture não acessou Docker, credenciais de sites nem a skill pessoal.

Essa evidência comprova o transporte nativo do identificador e dos argumentos atualizados. Não comprova a experiência de permissões na TUI nem o fluxo completo filho → box → controle humano. Ver `evidence/ab043-native-routing-probe.json`.

## Aceites restantes

1. Dois filhos ativos navegam em boxes diferentes sem aceitar o computador um do outro.
2. O pai continua usando sua própria box.
3. Criação automática ocorre somente sob política compatível e respeita tetos de recurso.
4. Terminar filho/pai revoga apenas as concessões correspondentes; não apaga perfis.
5. Takeover em uma box não pausa outra. Devolver controle retoma somente o alvo certo.
6. Sessão renovada, hook ausente, erro de assinatura e geração antiga não aceitam comandos.
7. Validação na TUI real e inspeção visual do painel, além dos testes de módulo.

Fontes primárias: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [subagentes](https://code.claude.com/docs/en/sub-agents) e [MCP tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools).
