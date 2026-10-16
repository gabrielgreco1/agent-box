# Estado de implementação — 16/10/2026

## Entregue neste checkpoint

- Novo target SwiftPM operacional separado de `design/`, SwiftTerm 1.20.0 fixado e app macOS empacotado.
- PTY interativo real; emulador/processo retidos por ID ao remontar panes; início e parada explícitos; encerramento forçado com confirmação.
- Sessões, terminais, nomes, seleção, largura/sidebar recolhida e árvore de splits persistentes.
- Até cinco panes, abas, seletor de CLI/shell e pasta escolhida pelo usuário. Dados restaurados aguardam início manual.
- Primeiro uso reutiliza Configurações. Probes de executável, versão e autenticação via comandos públicos; valores de credenciais não entram na UI.
- Biblioteca com CRUD de definições, memória selecionável, importação de skills como dados, origem/hash e contexto revisável/exportável.
- Política Docker desativada por padrão; probe de CLI/daemon e implementação de create/start/stop de container HTTP com labels e limites.

## Evidência

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`: **23 testes, 0 falhas**.

- 6 Docker: política, argv/timeout, ownership e criação controlada com runner falso.
- 6 biblioteca: persistência, corrupção/schema, isolamento de escopos, referências, tamanho e importação de texto sem execução.
- 5 descoberta/probes: PATH do Finder, override, NVM, diretórios e timeout/output limitado.
- 4 workspace: round-trip, rename/IDs, splits e arquivo corrompido.
- 2 PTY reais: TTY, resize, Ctrl-C, renderer retido e reinício explícito.

Após um ajuste para sinalizar também o grupo foreground do PTY, `swift test --filter ProcessesPTYTests` passou novamente: 2 testes, 0 falhas. O build release gerou `build/Agent Box.app` com assinatura local ad hoc.

Conferência visual: primeiro uso, detecção do Claude autenticado, Docker CLI ausente, criação de sessão/terminal Shell, início com PID real e prompt de zsh visível. Captura: `evidence/native-terminal.png`. A entrada por teclado via automação visual não foi concluída devido à mudança de foco/superfície; a entrada e Ctrl-C foram exercitadas pelos testes PTY.

## Limites reais

- Docker não instalado neste Mac. Nenhuma imagem foi baixada e nenhum container foi criado. A integração com daemon precisa de teste real antes de considerar AC27–AC37 atendidos.
- `codex login status` confirmou login pelo shell local; o probe no app expirou na conferência inicial. UI mostra estado indisponível, sem inventar conexão. Investigar contexto de execução/timeout na próxima correção.
- Claude/Codex TUIs não receberam tarefas de modelo no smoke; shell foi o processo testado. OpenCode ausente e auth não implementada.
- Não há broker/MCP por subagente, computador nativo de cada filho, headless browser, desktop ou streaming/takeover.
- Biblioteca salva e exporta contexto; ativação nativa, histórico automático, revisões históricas completas e scope projeto/tarefa na UI são pendentes.
- Ainda faltam Git/worktrees, descoberta/retomada de conversas externas, listener e evidências, `.env`/Keychain, perfis autenticados e mudança de modelo/harness.
- Fechar janela mantém o processo enquanto o aplicativo vive; quit/crash não preserva PTYs. Serviço persistente é trabalho posterior.
- Os 68 critérios globais continuam requisitos de produto. Passar estes testes não equivale a cumprir toda a spec.

## Próxima ordem

1. Corrigir probe Codex no app e completar smoke interativo de cinco panes/TUIs; registrar foco e teclas.
2. Git/worktree e lançamento de agentes salvos pelo adapter, com memória/skills revisadas.
3. Provar identidade de filhos por harness e pedidos de ferramentas antes de associar boxes automaticamente.
4. Instalar/configurar runtime Docker no fluxo de setup, testar HTTP real e avançar para headless/desktop e streaming.

Tarefas do lote: `tasks/AB-002.md`, `tasks/AB-003.md`, `tasks/AB-004.md`, `tasks/AB-005.md`.
