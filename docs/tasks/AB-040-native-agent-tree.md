# AB-040 — Sessão → terminais → subagentes observados

## Implementação

A revisão de um agente Claude oferece **Observar subagentes do Claude**, ligada inicialmente. O hook vem empacotado em `Resources/Hooks/claude_event.py`. Preparar o plano congela script e configuração; materializar grava os bytes protegidos, e restaurar verifica hashes. Nenhuma configuração global do Claude é modificada.

Cada início de processo, inclusive reinício de um mesmo terminal/contexto revisado, gera um UUID de execução novo e seu próprio diretório `hook-runs/<runID>`. Token, inbox e settings são privados. A criação é exclusiva: uma colisão de UUID ou link simbólico existente não é sobrescrita nem removida. O binding persistido continua apontando ao template revisado, e o runtime injeta somente as três variáveis específicas do hook no CLI. O segredo não aparece na revisão, argumentos ou histórico.

`NativeAgentMonitor` registra PID observado de cada PTY, admite primeiro o pai no registry, então consome eventos autenticados. Eventos que chegam antes da admissão ficam no inbox. Uma tarefa de observação por execução faz polling, drena eventos finais antes de encerrar a observação do pai, e serializa reinícios rápidos. Ao abrir o app, pais deixados como ativos pelo processo anterior são reconciliados; isso não inventa conclusão dos filhos. A tela distingue um filho ativo com pai observado de um estado antigo “Último evento: iniciado”.

A sidebar permite expandir **sessão → terminal → subagente**. Só mostra filhos do registry autenticado, nunca linhas inferidas de texto do terminal. O detalhe mostra ID nativo, origem, horários e navegação até o pai. Busca inclui tipo e ID nativos. Erros de observação ficam visíveis. Fechar/reabrir uma pane não cria outro agente.

## Evidência

- Suíte integrada: **110 testes, zero falhas**, com Xcode e scratch isolado. Inclui PTYs reais, mesmo contexto iniciado duas vezes com runIDs diferentes, final drain de hook assinado, reconciliação do pai, adulteração de script/token e preservação de diretórios existentes.
- Teste real do **Claude Code instalado** em diretório temporário próprio: um único subagente `box-verification`, sem ferramentas, respondeu `HOOK_OK`. O processo terminou com sucesso em duas rodadas. Vieram `SessionStart`, `SubagentStart` e `SubagentStop`, com HMAC válido e mesmo runID. Sem leitura de arquivos pessoais ou navegação. Custo reportado pelo CLI: US$ 0,035543; teto de execução configurado: US$ 0,50. Resultado sanitizado em `../evidence/claude-native-hooks-2026-10-16.json`.
- Build release e assinatura ad hoc passaram com hook e helper MCP empacotados.

## Limites restantes

O smoke real comprova o transporte de eventos pelo CLI, mas não substitui a conferência da sidebar com uma TUI lançada pelo app: o Mac ficou bloqueado antes dessa etapa. Não houve teste de subagente nativo do Codex/OpenCode. O campo conservador de capability global não anuncia captura ativa para um terminal sem verificar seu lançamento.

Um subagente nativo não ganha automaticamente PID, PTY ou computador exclusivo. Não há controle individual ou troca de harness desses filhos nesta entrega. A próxima integração precisa conceder computadores por identidade de filho comprovada, sob políticas e limites, e provar duas boxes concorrentes sem cruzar sessões. Resume e `/clear` precisam de tratamento de mudanças de sessão nativa; inbox cheio e histórico longo precisam de rotação/recuperação. Não marcar AB-016 e o aceite global como completos por este checkpoint.

Contrato: [Claude Code hooks](https://code.claude.com/docs/en/hooks), validado também pelo CLI instalado.
