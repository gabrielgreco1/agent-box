# Agent Box rebuild — decisões fechadas

Fonte de verdade para todos os capítulos da spec. Data: 2026-10-16. Auditoria que embasa: `docs/rebuild/audit/01..10`.

## Decisões do dono (Gabriel)

| # | Decisão |
|---|---|
| P1 | A UI é refeita 100%. Referência visual e de comportamento: Orca (`docs/rebuild/audit/04-orca-reference.md`). Nada da UI atual é preservado. |
| P2 | **Idioma da interface: inglês.** Microcopy pode seguir o Orca. A spec é escrita em português, mas todo texto de UI aparece em inglês. |
| P3 | Primeira abertura **importa do Orca** (somente leitura): projetos, worktrees, args padrão por agente. Nada é escrito no Orca; os dois apps coexistem durante a transição. |
| P4 | **Fechar o app (⌘Q) não mata os agentes.** Um daemon de PTY mantém os terminais vivos; ao reabrir, os panes voltam com scrollback. Ícone na barra de menus indica processos ativos. |
| P5 | Subagente com Docker tem **dois modos**, escolhidos por subagente: **leve** (CLI no Mac, só o computador — browser headless ou desktop GUI — no container, controlado via MCP) e **isolado** (o próprio CLI roda no container, aparece como tab no app, computador no mesmo container). |
| P6 | **Entrega: modo leve na v1, modo isolado na v1.1.** A spec cobre os dois em detalhe. |
| P7 | No modo isolado o CLI **já vem logado**, sem login manual. Recomendação registrada para v1.1: `claude setup-token` uma vez (token de 1 ano no Keychain, entregue à box por arquivo read-only), evoluindo para proxy de credenciais no Mac (agente nunca vê o token). Escolha final na abertura da v1.1. Nunca copiar refresh tokens do Mac nem montar o token do `gh`. |
| P8 | Animações com qualidade de motion design; prototipadas com a skill de motion design do dono (HTML frame a frame + Playwright) e portadas para SwiftUI/Core Animation com tokens compartilhados. Três momentos obrigatórios: abrir telas, agente sendo lançado, agente usando um computador. |
| P9 | Criar sessão abre automaticamente um terminal com o agente escolhido rodando, como no Orca. |
| P10 | Além de sessões ligadas a projeto/repo/worktree, existem **sessões limpas**: sem projeto, sem Git, criadas em um clique (pasta nova gerenciada pelo app, ex. `~/AgentBox/sessions/<nome>`, ou uma pasta escolhida). Aparecem na sidebar numa seção própria, com o mesmo card, estados e agentes, e podem ser promovidas/movidas para um projeto depois. |

## Decisões do dono — rodada de revisão final (2026-10-16)

| # | Decisão |
|---|---|
| P11 | Nome na UI da sessão sem projeto/Git: seção **"Sessions"** na sidebar; ação **"New Clean Session"** (⇧⌘N). "Scratch" não é usado em lugar nenhum. |
| P12 | O agente **pai pode enviar mensagens completas (com Enter) aos subagentes que ele mesmo criou**, registradas na timeline. Para qualquer outro terminal vale T11 (colar só por clique do usuário, sem Enter). |
| P13 | **Proxy não é padronizado em Zyte.** O usuário configura o(s) proxy(s) que quiser (provedor genérico: URL/host, porta, credenciais, tipo HTTP/SOCKS, geo opcional; Zyte é só um exemplo/preset, inclusive o modo API/render se configurado) e escolhe qual dar ao agente/box. **Sem teto de orçamento na v1**: nada de corte automático por box/lote/mês; o app só configura o proxy e mostra uso quando disponível. Remove todo requisito de budget cap. |
| P14 | **Aprovação visual por tela**: toda tarefa visual só fecha com screenshot/gravação do Agent Box lado a lado com a referência do Orca e OK explícito do dono. |
| P15 | Padrões propostos em 01-product §8 adotados: worktrees novas em `~/orca/workspaces/<repo>/` na transição; termo de UI "Computer" ("box" só em ferramentas/logs/pastas); sessões importadas do Orca entram sem processo rodando; primeiro ⌘Q com agentes vivos mostra aviso (overlay, T5) com "Keep Running" como padrão; nome automático de sessão limpa tipo `quiet-harbor`, renomear a sessão não renomeia a pasta; runs do CLI antigo importados na v1.1. |
| P16 | Conflitos técnicos, de nomes, números, IDs e atalhos apontados em `docs/rebuild/review/R1..R3` são resolvidos pela recomendação dos revisores, salvo quando contradizem esta página. |

## Decisões delegadas (dono deu autonomia total em 2026-10-17)

| # | Decisão |
|---|---|
| P17 | Tokens visuais seguem os valores **reais** extraídos do Orca 1.4.219 (`docs/rebuild/reference/orca-1.4.219/tokens/`): paleta Tailwind v4 do Orca, raios, line-heights. Onde 02 divergir, o token extraído vence. |
| P18 | D-Codex-1 = **opção B**: o app passa o trust dos próprios hooks via `-c 'hooks.state=…'` inline (S-05), sem escrever em `~/.codex`. Fallback: rollout com estado `estimated`. Adapter Codex usa `--no-daemon` por padrão. |
| P19 | Desenvolvimento por agentes Haiku 5.5 (tarefas mecânicas/checagens) e Sonnet 5.5 (código), gerenciados pela sessão principal. Gate P14 (OK do dono por tela) passa a ser: comparação lado a lado gerada e revisada pela sessão principal; o dono revisa o conjunto ao fim de cada fatia. |

| P20 | SwiftTerm: adotar **1.99.0 fixado na revisão `2dad6a1`** a partir da T1-09 (S-02: parse 5–11× mais rápido, 0–0,3% de quadros perdidos com 4 panes Metal vs 6–24% na 1.20.0, `feed`/`send` seguros fora do main). Condição: explicar a diferença de `getBufferAsData` no dump ANSI antes de fechar a T1-09; se não explicável, voltar para 1.20.0 com `feed` no main e orçamento AR-406. | **Ratificado na T1-09 (2026-10-17):** a diferença de `getBufferAsData` foi explicada (NUL de continuação de caractere largo e de célula vazia na 1.20.0; metade órfã de caractere largo limpa na 1.99.0; ver `docs/evidence/spikes/S-02/parity/README.md`), então a 1.99.0 fica; sem recuo para a 1.20.0.

| P21 | **Nenhuma dependência nem referência ao Orca no produto.** Worktrees do Agent Box vivem em pasta própria: padrão `~/AgentBox/worktrees/<repo>/<nome>` (revoga a parte de P15 sobre `~/orca/workspaces`). Nenhum texto de UI menciona o Orca (ex.: "same as Orca"), nenhum default aponta para pastas do Orca. O Orca segue só como referência de design na documentação interna. **A importação do Orca é removida por completo** (revoga P3): sai o OrcaImporter, o detector de coexistência, a T2-08 e qualquer menção no onboarding/Settings. |

| P22 | **Painel direito na v1** (spec `10-right-panel.md`): Files em cima (~2/3, árvore dinâmica que segue o cwd do agente + visualizador de código) e Insights embaixo (~1/3: uso de IA Claude/Codex com visualizações próprias, plano, tokens; monitor da máquina e dos computadores Docker; proxy). Tudo redimensionável, minimizável, com troca de posição por arrasto e botões claros na faixa de topo para abrir/fechar cada módulo. |

| P23 | **Permissões do macOS: no máximo uma vez, e só quando o usuário pede a função.** O app nunca dispara diálogo de permissão sozinho (Gravação de Tela, Acessibilidade, Notificações, item de login, Keychain): cada um só aparece no primeiro uso explícito da função que precisa dele, com uma explicação dentro do app antes, e nunca de novo depois de concedido. Assinatura sempre estável (identidade fixa de desenvolvedor) para o macOS reconhecer o mesmo app entre builds e atualizações. Nada de helper privilegiado: o app nunca pede a senha do usuário. Daemon via LaunchAgent do próprio usuário, aprovado uma vez. Lint e teste garantem que nenhum caminho automático chama APIs de pedido de permissão. |

## Decisões técnicas (recomendações dos revisores adotadas)

| # | Decisão |
|---|---|
| T1 | Daemon `agentboxd` próprio (LaunchAgent, socket ativado pelo launchd), daemon único, protocolo versionado com handshake, reattach com ring buffer de bytes. Não usar tmux. |
| T2 | Persistência em SQLite (GRDB 7) com migrações e backup; importador do JSON atual. Corrupção nunca desabilita a UI. |
| T3 | Swift 6 estrito, actors; UI no MainActor; zero lógica de domínio em views. macOS mínimo **15**. |
| T4 | Projeto Xcode gerado (para XCUITest) + pacotes SPM. Assinatura estável com certificado local + `install.sh` (sem Sparkle por ora). |
| T5 | Janela: `fullSizeContentView` + titlebar transparente, conteúdo na linha dos semáforos, sem `NSToolbar`; sidebar e tabs desenhadas à mão; modais como overlays dentro da janela (tirando foco do terminal), nunca `.sheet` do sistema. |
| T6 | Terminal: SwiftTerm com renderer Metal ligado e leitura do PTY fora do main thread. Nunca responder a pedidos de leitura de clipboard (OSC 52 read). |
| T7 | Docker via Engine API (com eventos), suportando o contexto ativo (Docker Desktop, OrbStack, Colima). Imagem versionada por digest (GHCR) com build local como fallback; o app constrói/baixa. |
| T8 | Viewer de desktop: noVNC em WKWebView na v1. |
| T9 | Egress sidecar por box desde a v1: proxy, reqlog e bloqueio de SSRF fora do alcance do agente. Token da box nunca em env do container. Proxy: ver P13. |
| T10 | Estado de atividade do agente (working / needs input / done / failed / waiting on subagents) vindo de hooks do Claude e do Codex, configurados **por lançamento**, nunca em config global. |
| T11 | O app pode colar (bracketed paste, sem Enter) no prompt de um agente somente por clique explícito do usuário. Prompt inicial vai como argumento do CLI. |
| T12 | Ferramentas do CLI `agentbox` antigo (exec, curl_cffi, reqlog com bodies, proxy configurável (P13), render (quando o proxy configurado suportar), diário PLAN/DOING/FOUND/BLOCKED, timeline) são portadas para o runtime novo e expostas via MCP. O app detecta a skill global `agentbox` concorrente e oferece desativar/redirecionar. |
| T13 | Canal de automação opt-in (`agentbox ctl`) + `accessibilityIdentifier` em tudo, para agentes e testes dirigirem o app ponta a ponta. |
| T14 | Fora do escopo: Orca Mobile, Automations, Chat UI, SSH remoto, captura/datasets da v1 atual, cerimônia de hash/revisão de lançamento, handoff transacional, sistema de memória próprio. |
