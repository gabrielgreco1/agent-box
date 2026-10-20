# 10 · Revisão: um dia de uso real (jornadas)

Data: 16/10/2026 · Rodada 2 da auditoria · Lente: produto e uso diário.
Entrada: relatórios 01 a 06 desta pasta, o código do Orca (só leitura) e sinais de uso real colhidos na máquina do Gabriel (lista abaixo). Nenhum código foi alterado.

O objetivo é rodar o dia do Gabriel, passo a passo, contra o app atual e contra o que os relatórios já propõem, e achar o que ainda falta. Cada requisito novo leva um ID `Rj.n` e prioridade P0 (sem isso a jornada não fecha), P1 (a jornada fecha, mas mal) ou P2 (melhoria). Quando um requisito estende algo dos relatórios, a referência vem entre parênteses.

---

## 0. Sinais de uso real

Os relatórios 01 a 06 descrevem o app e o Orca. Faltava olhar como o Gabriel trabalha de fato. Os dados abaixo foram lidos em modo leitura (sem conteúdo de credenciais) e mudam algumas prioridades.

| Sinal | Onde | O que muda |
|---|---|---|
| Orca com **6 repositórios e 103 worktrees** registrados; worktrees em `~/orca/workspaces/<repo>/<nome>` (rti-platform tem 6, arizona-data-request 3) | `~/Library/Application Support/orca/profiles/local-default/orca-data.json` (só contagens) | Worktree por tarefa é o hábito central. Importar isso do Orca no primeiro uso vale muito. |
| `agentDefaultArgs.claude = "--dangerously-skip-permissions"` | mesmo arquivo, `settings` | Ele roda Claude sem prompts de permissão. "Precisa de você" vem quase sempre de **fim de turno ou pergunta**, raramente de permissão. O perfil padrão do Racky deve herdar isso, com indicador visível. |
| `automations: 0`, `sshTargets: 0`, `experimentalMobile/NativeChat/AgentHibernation/Activity: false`, `keepComputerAwakeWhileAgentsRun: false` | idem | Automations, SSH, Chat UI, hibernação e feed não são usados. Corta-se da v1 sem perda. |
| 1 aparelho pareado em `orca-devices.json`, mas Mobile experimental desligado | idem | Mobile foi testado e não ficou. Não entra na v1 (ver §11). |
| Checklist do onboarding do Orca: `reviewedDiff: false`, `openedPr: false`, `triedCmdJ: false` | idem | Sinal fraco (o checklist pode parar de contar depois de fechado), mas sugere que diff e PR são feitos pelo agente e pelo `gh`, não pela UI do Orca. A v1 precisa de **visibilidade** de PR/checks, não de um painel de source control completo. |
| Orca instala hooks globais em `~/.claude/settings.json` (13 eventos) e em `~/.codex/hooks.json` (Stop, PermissionRequest, SubagentStart/Stop, SessionStart…), todos condicionados a `ORCA_AGENT_HOOK_PORT` / `ORCA_PANE_KEY` | arquivos de config | (a) O Racky vai conviver com esses hooks. (b) **O Codex já tem hooks de estado e de subagente** nesta versão, ao contrário do que o relatório 05 assume (só `notify`). |
| `notify` do Codex aponta para o Codex Computer Use | `~/.codex/config.toml:1` | O único slot `notify` está ocupado. O Racky não pode sobrescrevê-lo. |
| Statusline do Claude é um script do usuário que lê `rate_limits.five_hour/seven_day` | `~/.claude/statusline-command.sh` | Fonte pronta para medir uso. Não pode ser substituída, só encadeada. |
| Último rollout do Codex mostra `rate_limits.primary.used_percent = 100` (janela de 300 min) | `~/.codex/sessions/2026/10/…` | Ele bate no limite. A troca Claude ↔ Codex (J7) tem gatilho real. |
| CLI antigo `~/orca/projects/racky`: 34 runs, incluindo `pp-phoenix-az` e `pp-austin-tx`; **15 boxes `pp-*` criadas em 12 minutos** no dia 13/10; runs de até 391 MB; 1,3 GB no total | `runs/` | A jornada 4 já aconteceu, em escala de 15 boxes, com o CLI antigo. O app novo precisa aguentar esse lote e não pode regredir em relação a ele. |
| Skill global `~/.claude/skills/racky` com descrição que casa literalmente com "spawn 2 subagents for Phoenix and Austin" | SKILL.md | Dentro do Racky, o Claude vai escolher essa skill (o CLI antigo) em vez das ferramentas do app, a menos que o conflito seja resolvido. |
| Máquina: 48 GB de RAM, 14 núcleos, 98 GB livres em disco; Docker Desktop instalado com daemon parado; Colima ausente | `sysctl`, `df`, relatório 05 | 15 boxes em modo desktop a 2 GB cada não cabem na VM padrão do Docker Desktop. Capacidade e fila deixam de ser detalhe. |
| `claude --session-id <uuid>`, `--name`, `--bg`, `--remote-control` existem na 2.1.302 | `claude --help` | Captura de ID sem hook (já citado no 05) e uma alternativa barata ao Mobile (`--remote-control`). |

---

## 1. Decisões de modelo que as jornadas forçam

Antes das jornadas, quatro escolhas aparecem em quase todas. Sem elas, os requisitos ficam ambíguos.

1. **Projeto → Sessão → Terminais → Filhos.** O 05 propõe Projeto → Worktree → Terminal. O SPEC1 diz que sessão funciona sem Git. As jornadas pedem as duas coisas: a J3 é worktree, a J4 (lote de scraping) é pasta comum. Proposta: **uma sessão está ligada a um diretório** (worktree nova, checkout existente ou pasta) e pertence a um projeto (repositório ou pasta raiz). A sidebar fica igual à do Orca (projeto → card da sessão → linhas de agente), e a palavra "Sessão" continua.
2. **"Digitar no PTY" por ação explícita.** A regra J6 do SPEC1 ("nenhuma API digita texto num PTY já ativo") bloqueia "mandar falhas dos checks ao agente", handoff, resposta rápida pela notificação e relançar filhos. Proposta: o app pode **colar** (bracketed paste, sem Enter) no prompt do agente quando o usuário clica num botão que diz isso. Nada automático. Ver R5.1.
3. **Modos de subagente.** A decisão já tomada é ter dois modos: (A) CLI dentro do container e (B) CLI no Mac com só o computador no container. As jornadas mostram que B cobre o caso de scraping de ponta a ponta, desde que a box tenha shell (exec), reqlog e proxy, como o CLI antigo. A traz isolamento do próprio CLI e terminal digitável do filho, mas exige credencial dentro do container (ver R4.6). Proposta: **B na v1, A na v1.1**.
4. **Runtime da box.** O CLI antigo (bash + Python, `exec`, `browser`, `reqlog`, `proxy`, `render`, `note`, `timeline`) é o que foi usado em 34 runs. O runtime Swift/Python atual tem takeover e hardening melhores, mas menos ferramentas de trabalho (01 §2, 05 b). Proposta: **portar as ferramentas do CLI antigo para dentro do runtime novo** (separação control/work do 05) e expor as duas coisas por MCP. Não reescrever a escada de escalonamento do zero.

---

## J1. Primeira abertura e onboarding

### Roteiro ideal
1. O Gabriel abre o app. A janela já tem o visual final (sidebar vazia, titlebar Orca). Um overlay de onboarding (não sheet) mostra a checklist "Preparar o Racky", e todas as detecções rodam em paralelo, com resultado em 2–3 s:
   - Claude 2.1.302 logado, Codex 0.160.0 logado, OpenCode 1.18.34 ("login não verificável"). Cada CLI deslogado tem "Abrir login", que abre um terminal com o comando oficial.
   - `gh` 2.93.0 logado como `gabrielgreco1`, com escopos `repo` e `workflow`.
   - Docker: "Docker Desktop instalado, parado" → **Iniciar** (abre o Docker e espera o socket). Imagem da box ausente → **Construir em segundo plano** (tamanho e tempo estimados), sem travar o onboarding. A VM tem X GB de RAM, o que dá "≈ N boxes headless ou M desktop".
   - Notificações: pede permissão com uma frase do porquê.
   - Agentes em segundo plano: "Manter agentes rodando quando fechar o app" pede aprovação do item de login/LaunchAgent.
2. **Importar**: "Encontrei 6 repositórios e 103 worktrees no Orca, 13 agentes Claude, 12 agentes Codex, ~160 skills e 34 runs do racky CLI". Toggles por grupo. Projetos e worktrees viram projetos e sessões sem mover arquivos. Agentes e skills são indexados por referência.
3. **Padrões**: agente padrão Claude com `--dangerously-skip-permissions` (herdado do Orca, com aviso); modo de subagente B; orçamento Zyte US$ 1 por box; chave Zyte lida de `~/orca/projects/racky/.env` e guardada como segredo.
4. **Conflitos detectados**: hooks globais do Orca (inofensivos, apenas informa); `notify` do Codex ocupado (não será tocado); skill global `racky` que concorre com o app (oferece desativar ou redirecionar).
5. Termina no composer de nova sessão com o último projeto do Orca pré-selecionado.

### Onde falha hoje
- A sheet de primeiro uso joga a `AppSettingsView` inteira no usuário (03, tela 2).
- Os defaults da política (`creation = disabled`, 768 MiB) quebram o recurso principal (02 #1).
- O contexto Docker está fixo em Colima, que não existe nesta máquina (02 §5). O app não inicia o Docker nem constrói a imagem (05 b).
- Não há detecção de `gh`. Skills entram uma por vez, por seletor de arquivo (05 e).

### Já proposto nos relatórios
Onboarding em passos no estilo Orca (04 §5.8, 06 A2), preparar Docker e imagem pelo app (05 b, P0), catálogo das fontes nativas (05 e, P1).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R1.1 | P0 | Onboarding como **checklist de diagnóstico não bloqueante**: cada item tem estado, motivo e uma ação de um clique; nada de formulário de política no primeiro uso. A mesma checklist fica em Configurações › Diagnóstico, para rodar de novo. | "Tudo que eu clico parece que não funciona" começa no primeiro minuto. |
| R1.2 | P0 | Usar o **contexto Docker ativo** (hoje `desktop-linux`) e só sugerir Colima/OrbStack quando não houver runtime. Ler a memória da VM (`docker info`) e mostrar a capacidade em boxes. | Os testes e o código fixam `colima-racky-dev` (02); a capacidade decide o tamanho do lote (J4). |
| R1.3 | P0 | **Importar do Orca** (leitura): repositórios, worktrees ativos e args padrão por agente, a partir de `orca-data.json` e de `~/orca/workspaces`. Nada é movido nem gravado no Orca. | 103 worktrees. Sem isso, o primeiro dia começa vazio e ele volta para o Orca. |
| R1.4 | P1 | Importar o **CLI racky antigo**: runs como histórico só-leitura de boxes (result.json, journal, reqlog) e a chave Zyte do `.env` como segredo. | São os dados de trabalho dele; a J4 consulta runs anteriores ("o que já sabemos de Phoenix"). |
| R1.5 | P0 | **Nunca sobrescrever configuração global** dos CLIs: `statusLine`, `notify`, hooks e skills globais ficam intocados. Tudo do Racky vai por lançamento (`--settings`, `--mcp-config`, `--plugin-dir`, `-c`). Quando um recurso só existe em config global (hooks do Codex), usar o padrão do Orca: entrada global condicionada a uma variável de ambiente do Racky, com aviso e remoção limpa. | Há três donos disputando os mesmos arquivos (Orca, Codex Computer Use, o próprio usuário). |
| R1.6 | P0 | Detectar a skill global `racky` (e outras cuja descrição concorra com as ferramentas do app) e oferecer: desativar, manter, ou deixar o app servir de backend dos mesmos comandos. | Sem isso, a frase da J4 aciona o CLI antigo dentro do app novo. |
| R1.7 | P1 | Detectar `gh` e escopos; sem login, "Abrir terminal com `gh auth login`". Mostrar qual fonte de auth GitHub está ativa. | GitHub integrado é pedido explícito; hoje nada detecta o `gh`. |
| R1.8 | P1 | Pedir a aprovação do item de login (SMAppService) só quando ele ativar "continuar em segundo plano", com texto explicando o que roda. | O daemon de PTY (05 c) depende disso no macOS atual. |
| R1.9 | P2 | Reprobe automático quando a versão de um CLI muda, com "o que mudou" (flags e hooks suportados). | Os adapters dependem de versão (02, 05). |

---

## J2. Começar o dia

### Roteiro ideal
1. 9h. O app está aberto desde ontem, ou o daemon segurou os processos. A sidebar mostra cada sessão com o estado agregado e a última frase do agente:
   - `rti-platform / stacktax-pr-bronze` · Claude · concluído há 7 h · "Abri o PR #412; 2 checks falhando".
   - `arizona / sandperch` · Codex · **esperando você** · "Qual tabela usar, permits_2024 ou permits_v2?".
   - `permits-oct` · 2 boxes paradas · US$ 0,31 de Zyte ontem.
2. O sino (ou ⌘⇧I) abre "Desde ontem": eventos por sessão (turnos concluídos, perguntas, PR mudou de estado, checks falharam, boxes que pararam, gasto). Clicar leva ao pane certo com rim flash.
3. Se o Mac reiniciou, os panes voltam com o último scrollback esmaecido e um botão **Retomar**. "Retomar sessão" relança todos os agentes da sessão com `--resume` do ID capturado; nada retoma sozinho.
4. Cada sessão tem uma nota curta de objetivo e status, que o agente também atualiza ("reproduzi o bug; testando fix").

### Onde falha hoje
O quit mata tudo (05 c). Terminais voltam `idle` com "Sessões restauradas aguardam início manual" (03, tela 17). O ID da conversa nativa não é capturado num terminal comum (05 a). Não há estado de agente, última mensagem, feed nem estado de PR.

### Já proposto
Daemon de PTY (05 c, P0), estado semântico via hooks (05 c, P0; 06 E0/E1), sino e feed no estilo Orca (04 §5.4), captura do ID (05 a, **P1**), notas por sessão (01 sugestão 22).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R2.1 | P0 | **Última mensagem do agente** por terminal: uma linha na sidebar, o texto completo no hover. Fonte: hook `Stop` do Claude (campo de última mensagem, se a versão expõe; senão a última entrada do `transcript_path`), `notify`/hook `Stop` do Codex (`last-assistant-message`). | Um ponto colorido sem contexto obriga a abrir 10 panes para saber o que aconteceu. |
| R2.2 | P0 | **Subir a captura do ID nativo para P0** (no 05 está P1): todo terminal Claude nasce com `--session-id` gerado pelo app; Codex e OpenCode por hook/rollout/`session list`. | A J8 (reboot) e a retomada em lote dependem disso. |
| R2.3 | P1 | **Inbox "Desde a última vez"**, separado dos pedidos de ajuda: eventos de agente, PR/checks, boxes e gasto, agrupados por sessão, com "marcar lido". | O sino do Orca resolve notificação; falta o resumo de quem passou horas fora. |
| R2.4 | P1 | **Nota de status da sessão** editável pelo usuário e pelo agente (ferramenta MCP `session_set_status`), mostrada na linha 2 do card. | Equivale aos worktree checkpoints do Orca; substitui a entidade Tarefa da v0.4 sem a cerimônia. |
| R2.5 | P1 | **Retomada em lote com custo à vista**: "Retomar 6 agentes" lista cada um (CLI, modelo, última mensagem) com checkbox. Nunca automática depois de reboot. | Cada retomada consome janela de uso. |
| R2.6 | P2 | Filtros da sidebar: "precisa de você", "trabalhando", "dormindo", esconder sessões paradas há mais de N dias. | 103 worktrees não cabem numa lista plana. |

---

## J3. Nova sessão num repo, com worktree nova e Claude já rodando com prompt

### Roteiro ideal
1. ⌘N abre o composer em overlay. Projeto pré-selecionado (o da sessão atual).
2. "Criar a partir de": `origin/main` por padrão; aceita branch, `#123` ou URL de PR/issue.
3. Agente: Claude, perfil "Opus · sem permissões" (padrão herdado).
4. Prompt em várias linhas. O nome da sessão e da branch saem do prompt (`gabrielgreco1/fix-arcgis-pagination`) se ele não digitar nada.
5. "Onde": worktree nova (padrão), checkout existente, pasta, ou **pasta nova sem Git** (para lote de scraping).
6. ⌘↵. O overlay fecha na hora. A sidebar mostra a linha pendente; `fetch` e `worktree add` rodam em segundo plano; `.env` e arquivos ignorados são copiados; o script de setup roda numa aba própria.
7. A aba abre com `claude --session-id <uuid> --dangerously-skip-permissions "<prompt>"` no cwd do worktree. A ignição (06 E2) aparece só se o start demorar mais de 300 ms.
8. Se algo falha (branch existe, fetch sem rede), o erro aparece no card pendente com "Tentar de novo" e "Usar branch existente".

### Onde falha hoje
Nova sessão pede só o nome e cai na tela vazia; o novo terminal vem com Shell e não inicia (03, bugs 2 e 3). O worktree não sugere destino e abre um terminal parado (03, tela 22).

### Já proposto
Composer do Orca (04 §5.2, §7), lançador de um passo e perfis (05 a, P0), worktree por tarefa (05 d, P0 parcial), ignição (06 E2).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R3.1 | P0 | O **prompt inicial vai como argumento do CLI** (`claude "<prompt>"`, `codex "<prompt>"`, `opencode --prompt`), nunca digitado no PTY. Prompt longo vai por arquivo referenciado no argumento. | Cumpre a regra J6 sem gambiarra e é o que faz "já rodando com prompt" funcionar. |
| R3.2 | P0 | **Diretório gerenciado e nomes**: raiz de worktrees configurável (padrão compatível com `~/orca/workspaces/<repo>/<nome>` durante a transição), prefixo de branch do usuário Git, nome automático e tratamento de colisão. | O composer sem convenção vira formulário de 6 campos de novo. |
| R3.3 | P0 | O composer aceita **sessão sem Git**: pasta existente ou pasta nova em `~/Racky/scratch/<nome>`. | Lotes de scraping não são repositórios; o composer do Orca é centrado em worktree. |
| R3.4 | P1 | **Arquivos ignorados na worktree nova**: ler `.worktreeinclude` e `orca.yaml` (`scripts.setup`, `worktree.sharedDirectories`) quando existirem, e oferecer "copiar `.env*`" por projeto. | Sem `.env`, o agente falha nos primeiros minutos da worktree nova. Reaproveitar o formato do Orca evita configurar duas vezes. |
| R3.5 | P1 | Script de setup com política "esperar" ou "iniciar o agente já", com a saída numa aba "Setup". | `pnpm install` e similares atrasam o agente sem feedback. |
| R3.6 | P2 | Anexar imagem ou arquivo ao prompt do composer (o app salva e passa o caminho). | Uso comum no Claude Code. |
| R3.7 | P2 | "Mesma tarefa em N agentes" (Claude e Codex em worktrees irmãs) a partir do composer. | Fluxo central do Orca; útil, mas não é o dia dele hoje. |

---

## J4. "Spawn 2 subagentes para Phoenix e Austin"

A jornada que justifica o app. O Gabriel já fez isso com o CLI antigo, em lote de 15 cidades.

### Roteiro ideal (modo B: CLI no Mac, computador no container)
1. **Sessão** `permits-oct` (pasta sem Git). Claude pai lançado pelo Racky, portanto já com o MCP do app e a skill de orquestração do app, injetados por lançamento.
2. Ele digita: "spawn 2 subagentes para Phoenix e Austin; levantar sistemas de permits (zoning, building), endpoints e cobertura; saída result.json".
3. O pai consulta runs anteriores (`runs/pp-phoenix-az/result.json` importado) e monta o brief de cada filho com tarefa, o que já se sabe e spec de saída.
4. O pai chama `boxes_reserve(["phoenix-az", "austin-tx"], mode: headless)`. O app checa capacidade e orçamento, cria as duas boxes em paralelo e responde logo, sem esperar o Chromium. Na sidebar, embaixo do terminal pai, nascem duas linhas filhas com o glifo de provisionamento (06 E3).
5. O pai dispara dois subagentes nativos em background, cada um com o brief e o nome da box. Na primeira chamada, o filho reivindica a box pelo nome; a linha da sidebar passa a mostrar o filho e a box juntos.
6. **Ver ao vivo**: a sessão ganha uma faixa "Computadores" com duas miniaturas (URL atual, última nota do diário, gasto). Hover amplia; clique abre o viewer como pane ao lado dos terminais, a 15–30 fps.
7. **Captcha em Phoenix**: o filho chama `computer_request_help(kind: captcha, reason: "hCaptcha na busca do Accela")`. A chamada volta na hora com um `request_id`, e o filho fica em `computer_wait_help`. Notificação: "Phoenix precisa de você · captcha em aca-prod.accela.com". O clique abre o viewer com **Assumir** em destaque.
8. Ele assume. Phoenix fica pausado; Austin segue. Resolve o captcha e clica **Devolver** (⌘⇧R), com uma nota opcional ("resolvido, sessão logada"). O filho recebe URL atual, abas e a nota, e continua.
9. **Evidências**: cada linha filha abre abas Rede (reqlog com filtro XHR/erros, corpo completo, "copiar como curl"), Diário (PLAN/DOING/FOUND/BLOCKED), Comandos, Arquivos (`/work`) e Timeline.
10. **Resultado volta ao pai**: o subagente nativo devolve a resposta final ao pai, como já faz o Claude. Além disso, o app copia `/work/result.json` e os logs para `~/Racky/runs/permits-oct/phoenix-az/`, e o pai chama `box_collect("phoenix-az")` para receber a timeline e conferir cada afirmação contra os IDs de request. Afirmação sem evidência aparece marcada na UI.
11. **Fim**: as boxes param sozinhas quando o filho termina e os perfis ficam. O card da sessão mostra "Phoenix US$ 0,12 · Austin US$ 0,00 · 18 min". "Arquivar lote" remove containers e mantém runs e perfis.

### Onde falha hoje
- Computador e MCP só no caminho Biblioteca → plano revisado → Claude, e o filho só ganha box se o pai foi lançado com `webscraping-expert` (02 #5, 05 b).
- Criação desativada e memória de 768 MiB por padrão (02 #1). Imagem não construída (05).
- Sem exec, `curl_cffi`, POST, reqlog com corpos lido pelo agente, proxy, render, diário e timeline (01 §2: regressão em relação ao CLI antigo).
- Headless sem interação (02 #13). Viewer MJPEG a 4 fps. Motivo do pedido de ajuda descartado (02 #18). Timeout de 60 s no handler MCP (02 #9).
- Containers e volumes nunca são removidos (02 #2). O fluxo pela TUI nunca foi conferido visualmente (01 §3.2).

### Já proposto
Docker e imagem pelo app, computador em qualquer terminal Claude, viewer com fps decente, shell com separação control/work, listener MITM (05 b, P0). Proxy com orçamento, painel global, miniaturas, ferramentas por seletor, timeline (05 b, P1). Borda viva, handoff de controle e banner de ajuda (06 E3, E4).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R4.1 | P0 | **Skill de orquestração do app**, entregue por lançamento ao pai: passos (reservar boxes, brief por filho, diário obrigatório, coletar, conferir evidências), template do brief e regras de escalonamento, migrados do SKILL0 e do `subagent-prompt.md`. | Sem instrução, o pai não sabe usar as ferramentas novas; com a skill antiga, usa o CLI antigo (R1.6). |
| R4.2 | P0 | **Reserva de box por nome e reivindicação pelo filho**: o pai cria boxes com rótulo humano; o primeiro filho que chamar `computer_acquire(box: "phoenix-az")` fica dono; a sidebar mostra o vínculo. Sobe a "reserva antecipada" do SPEC (K8) de P2 (05) para P0. | É assim que o fluxo real funciona (orquestrador cria a box antes do filho). Também resolve a identidade sem depender do caso "scraping". |
| R4.3 | P0 | **Pedido de ajuda assíncrono**: `request_help` retorna na hora; `wait_help` faz long-poll com progresso e pode ser repetido sem duplicar o pedido. O tipo e o motivo vão para a notificação. | Captcha leva minutos; nenhuma chamada MCP pode ficar bloqueada além do timeout do cliente. |
| R4.4 | P0 | **Takeover sem perder a página**: o browser das boxes de scraping roda headed em Xvfb mesmo quando ninguém assiste ("headless" = sem stream). Assumir não troca de modo nem reabre o browser. Se o modo tiver de mudar, a URL, os cookies e o storage são preservados e a página é reaberta. | Hoje a troca headless → desktop reinicia o browser; a sessão do captcha se perde. |
| R4.5 | P0 | **Resultado e logs no host** por sessão e box (`runs/<sessão>/<box>/`), visíveis no app, mais a ferramenta `box_collect` para o pai receber timeline e result. Afirmações sem ID de request marcadas como "não verificado". | É o passo 5 do SKILL0 e o que dá confiança ao resultado. Hoje nada volta ao host. |
| R4.6 | P1 | **Modo A (CLI no container)**: PTY do container anexado como terminal filho digitável; skills montadas só-leitura; `agent_spawn`/`agent_wait` para o pai. Exige decisão registrada sobre credencial (token de `claude setup-token`, API key ou auth do Codex por env, com escopo da box), porque contraria a regra U9 do SPEC1 ("o app não copia token para o container"). | Decisão já tomada pelo Gabriel; os relatórios só dizem "decidir". |
| R4.7 | P0 | **Capacidade e fila visíveis**: antes de criar, checar RAM e CPU da VM Docker contra o modo pedido; o que não cabe entra numa fila exibida ("3 de 15 aguardando memória"), e a ferramenta devolve esse estado ao pai. Lotes usam headless por padrão. | 15 boxes em 12 minutos é o uso real. A fila do SPEC (L10, L11) está pendente e nenhum relatório a prioriza. |
| R4.8 | P1 | Faixa "Computadores" da sessão com URL atual, última nota do diário e gasto por box, ordenada por "precisa de você" (estende 05 b, miniaturas). | Com 15 boxes, miniatura sem texto não diz nada. |
| R4.9 | P1 | **Nota humana ao devolver** o controle, entregue ao agente junto com o estado reconciliado (estende SPEC O3). | "Já loguei, pode seguir da página 3" economiza um ciclo. |
| R4.10 | P1 | **Detector de filho travado**: sem chamadas de ferramenta nem nota de diário há N minutos → estado "parado?" na linha e no inbox. | O CLI antigo dependia de o Gabriel olhar; com 15 filhos, alguém trava sem avisar. |
| R4.11 | P1 | Mandar mensagem a um filho específico: no modo A, digitando no terminal dele; no modo B, via pai ("pedir ao pai para orientar Phoenix") com R5.1. | Steering por filho (SPEC K11) não existe; subagente nativo não recebe input direto. |

---

## J5. Revisar diffs, abrir PR e ver checks

### Roteiro ideal
1. O card da sessão mostra branch, ↑3, ponto de alterações e, depois do push, o chip `#412` com o estado dos checks.
2. ⌘⇧G abre o painel direito "Alterações": arquivos mudados contra a base, diff em linha, só leitura. "Abrir em…" leva ao editor dele, ao Finder ou ao GitHub.
3. Na maioria das vezes ele pede ao agente: "commita e abre o PR". O app só observa e atualiza o chip.
4. Quando prefere fazer pelo app: **Criar PR** faz push (com o agente SSH do usuário) e abre o `gh pr create` pré-preenchido, com confirmação.
5. Checks falham → notificação "2 checks falhando em #412" → **Mandar falhas ao agente** cola no prompt do agente os nomes dos checks e o trecho do log (`gh run view --log-failed`). Ele revisa e aperta Enter.

### Onde falha hoje
Nenhuma chamada ao GitHub. A allowlist de env remove `SSH_AUTH_SOCK`, então `git push` por SSH quebra dentro do agente (02 #3). O popover de Git é só texto (03, tela 13).

### Já proposto
PR, checks e review via `gh` (05 d, P1), diff viewer (05 d, P2), herança do env (05 a, P0), painel direito com Source Control (04 §2.4).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R5.1 | P0 | **Colar no prompt do agente como ação explícita**: bracketed paste, sem Enter por padrão, sempre por clique com rótulo claro ("Colar no Claude"). Revisa a regra J6 do SPEC1. | Habilita "Fix checks", handoff, relançar filhos e resposta rápida. Sem isso, cada um desses vira "copie e cole você mesmo". |
| R5.2 | P0 | **"Abrir em…"** por sessão e worktree: editor configurado (Cursor, VS Code, Zed), Finder, terminal externo, GitHub. | Válvula de escape barata. Enquanto o diff do app não existe, é como ele revisa. |
| R5.3 | P1 | **Diff só leitura** contra a base do worktree, sobe de P2 (05) para P1. Staging, commit e merge pelo app ficam fora. | Revisar é parte do dia; montar commit pela UI ele não faz nem no Orca. |
| R5.4 | P1 | Mudanças de PR e checks (falhou, aprovado, mergeado) viram eventos do inbox e notificações, com o polling respeitando a cota compartilhada com o `gh` e os agentes. | O chip sozinho exige olhar a sidebar. |
| R5.5 | P1 | **Mandar falhas ao agente** (nomes, links, trecho do log) via R5.1. | "Fix broken checks" do Orca; fecha o ciclo sem sair do app. |
| R5.6 | P2 | Comentários por linha no diff, enviados em lote ao agente (Annotate AI Diff do Orca). | Bom, mas depende do diff viewer completo. |

---

## J6. Dez ou mais sessões em paralelo

### Roteiro ideal
1. Sidebar densa: cada card agrega o pior estado (precisa de você > falhou > trabalhando > concluído não lido > ocioso). Não lido em negrito. Linhas de agente com a última frase e o tempo.
2. Ele está focado em `rti-platform`. Uma notificação do sistema avisa que `arizona/sandperch` fez uma pergunta. Notificação suprimida se ele já está olhando aquele pane.
3. ⌘⇧A ("próximo que precisa de você") percorre a fila em ordem de espera, com rim flash no pane. ⌘J lista tudo, com "precisa de você" no topo. ⌘1…9 trocam de sessão; ⌃Tab volta à anterior.
4. Dock com badge do número de pendências. Item na barra de menus com a lista e "ir para".
5. Captcha de box tem prioridade sobre fim de turno. Se ninguém atende em 3 minutos, um único lembrete.
6. Com 12 agentes trabalhando e 6 boxes, o app continua leve: só os panes visíveis renderizam.

### Onde falha hoje
Sem estado de agente; notificação só para pedido de box (05 c). Atalhos registrados em itens de `Menu`, sem `.commands` (03 #11). Tudo abre em sheet.

### Já proposto
Estado via hooks e notificação (05 c, P0), atalhos e notificações do Orca (04 §5.4, §6), indicadores com fase sincronizada (06 E1), menu bar (SPEC P10, 05 c).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R6.1 | P0 | **Estado do pai considera os filhos**: um pai que terminou o turno mas tem subagentes em background fica "aguardando subagentes", não "concluído". O mesmo vale para boxes com pedido aberto. | O `Stop` do Claude dispara com filhos ainda rodando; o ponto verde mentiria no meio do lote. |
| R6.2 | P0 | **"Próximo que precisa de você"** (atalho e botão no sino), em ordem de espera. | Triagem de 10+ sessões é um laço; a palette ajuda a achar, não a esvaziar a fila. |
| R6.3 | P0 | **Orçamento de desempenho** medido: 15 terminais com TUI ativa e 6 boxes com miniatura. Panes ocultos só bufferizam, não desenham; miniaturas fora da tela param. Meta de CPU do app em repouso definida e checada no Instruments. | O 06 cobre o custo do motion; ninguém mediu o custo de 15 SwiftTerm vivos. |
| R6.4 | P1 | **Prioridade por tipo de pedido**: captcha/login de box > pergunta ou permissão > fim de turno. Um lembrete único para pedidos de box não atendidos (ajusta a regra "um som por request_id", SPEC P4). Modo foco: "só pedidos de box". | Sessão de site expira; fim de turno pode esperar. |
| R6.5 | P1 | Item na barra de menus **com ações**: lista do que espera, ir para, assumir box. | Estende SPEC P10, que só fala em indicador. |
| R6.6 | P1 | **Dormir sessão**: para os processos, para as boxes e guarda os IDs para retomar. Fixar sessões no topo. | Com 100+ worktrees, a lista viva precisa ser curta. Hibernação automática fica para depois. |
| R6.7 | P2 | Responder pela notificação ("continue", "sim") via R5.1. | Atalho útil quando só falta confirmar. |

---

## J7. Trocar de Claude para Codex no meio (handoff)

### Roteiro ideal
1. A status bar mostra Claude 5 h em 96 %. O Claude bate no limite; um banner no pane diz "Limite de 5 h atingido (volta às 14:20). Continuar no Codex?".
2. **Continuar em… Codex** monta um brief editável: objetivo (nota da sessão e primeiro prompt), últimos pedidos do usuário, última resposta, `git status` e diff resumido, pendências (lista de tarefas do transcript), filhos e boxes ativos.
3. Ele revisa o "recibo" e confirma. Uma aba nova abre o Codex no mesmo worktree, com o brief salvo em `.racky/handoff.md` e passado no prompt inicial, e com o MCP do Racky configurado por `-c mcp_servers`.
4. A aba do Claude continua lá, marcada "passou para Codex". As boxes do Claude só mudam de dono se ele marcar.
5. Às 14:20, "Voltar ao Claude" retoma a conversa original com um resumo do que o Codex mudou desde o handoff.

### Onde falha hoje
Nada existe (01 X1–X6). Codex é só export no lançamento de agente (02 #4). Computador e MCP são exclusivos do Claude.

### Já proposto
Handoff transacional com checkpoint e rollback (SPEC1 X2–X5), MCP para Codex (05 b, P1).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R7.1 | P1 | **Handoff leve** em vez do transacional do SPEC1: nova aba, origem mantida, brief gerado do transcript e do Git, editável antes de lançar. Rollback = fechar a aba nova. | O transacional (pausar, checkpoint, revogar, associar, validar) é caro e não muda o resultado para um usuário só. |
| R7.2 | P1 | **Detecção de limite**: `rate_limits` do statusline do Claude e do rollout do Codex alimentam um banner com a hora de reset e a oferta de troca. | O último rollout dele está em 100 %. |
| R7.3 | P1 | **Transferir box** entre terminais como ação explícita (SPEC L17, pendente). | Sem isso, o Codex começa sem o browser logado. |
| R7.4 | P1 | **Paridade mínima do Codex** na v1.1: MCP do Racky por `-c`, estado e subagentes pelos hooks que o Codex já tem (`Stop`, `PermissionRequest`, `SubagentStart/Stop`), ID pelo rollout. Corrige o 05, que trata o Codex como "só notify". Conferir por versão. | O Codex é o segundo agente do dia, não um extra. |
| R7.5 | P2 | "Voltar ao agente original" com o diff desde o handoff. | Fecha o ciclo quando o limite reseta. |
| R7.6 | P2 | Troca de conta Claude/Codex (como o hot-swap do Orca), com uso por conta. | Há duas contas Codex registradas no Orca e um registro de créditos de reset. |

---

## J8. Fechar o app, reiniciar o Mac e voltar

### Roteiro ideal
1. ⌘Q: "4 agentes trabalhando e 2 boxes ativas continuam em segundo plano. [Continuar] [Encerrar tudo]". O item da barra de menus mostra o que segue rodando.
2. Reabrir: panes reaparecem com os processos vivos e o scrollback, inclusive o que saiu com o app fechado.
3. Atualização do Mac e reboot. Ao abrir: layout e último scrollback voltam esmaecidos; cada pane tem **Retomar**, que relança com o ID capturado **e as mesmas flags, MCP, hooks e skills** do lançamento original.
4. Subagentes que estavam rodando aparecem como "interrompidos no reboot", com a última nota do diário de cada um, e o botão "Pedir ao pai para relançar" (cola um pedido no prompt via R5.1).
5. Docker parado: o app oferece iniciar quando algo precisar de box; boxes voltam com o perfil (logins mantidos), sem reiniciar sozinhas.
6. Com agentes trabalhando, o Mac não dorme (opcional, com indicador e aviso na bateria).

### Onde falha hoje
O quit mata tudo com SIGTERM e SIGKILL (05 c). O `restore` exige argv idêntico, e os diretórios de lançamento acumulam sem regeneração (02 #16, §2.7). Subagentes de execuções encerradas ficam `running` para sempre no registry (02 §2.8).

### Já proposto
Daemon de PTY e reanexação (05 c, P0), restauração de buffer (05 c, P1), retomada com as flags originais (05 a, técnico).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R8.1 | P0 | **Lançamento declarativo e regenerável**: o app persiste "o que foi pedido" (CLI, perfil, agente, skills, MCP, cwd, ID) e regera `--settings`, `--mcp-config` e `--plugin-dir` na retomada. Nada depende de um diretório temporário sobreviver ao reboot. | O Claude não restaura essas flags no `--resume`; sem elas, o agente volta sem box e sem hooks. |
| R8.2 | P0 | **Reconciliação de filhos e boxes** depois de reboot ou crash: filhos viram "interrompido", boxes órfãs são listadas, pedidos de ajuda abertos continuam visíveis. | Hoje ficam `running` para sempre. |
| R8.3 | P1 | Docker depois do reboot: detectar runtime parado, iniciar sob demanda, nunca subir boxes em massa sozinho. | 15 boxes subindo juntas no boot travariam a máquina. |
| R8.4 | P1 | **Manter acordado** enquanto há agente trabalhando (asserção de energia), opcional, com indicador e aviso na bateria. | Lote de scraping noturno para quando a tampa fecha. O Orca tem a opção; ele deixa desligada, então o padrão é desligado. |
| R8.5 | P1 | Modo A: a sessão do CLI dentro do container fica no volume da box, para retomar depois que o container reinicia. | Senão o filho do modo A perde a conversa em todo reboot. |
| R8.6 | P2 | Abrir no login. | Conveniência. |

---

## J9. Biblioteca: criar agente, editar skill, ativar só numa sessão

### Roteiro ideal
1. ⌘⇧L abre a Biblioteca no painel direito, com abas Agentes, Skills e Instruções e as fontes com contagem: `~/.claude/agents` (13), `~/.codex/agents` (12), `~/.claude/skills` (133), `~/.agents/skills` (~30), plugins, `.claude/` do projeto.
2. **Criar agente** "permit-portal-scout": nome, descrição, modelo, ferramentas, skills (`webscraping-expert`), MCP (`racky` computer). Escopo: usuário, projeto ou "só no app". Grava `~/.claude/agents/permit-portal-scout.md` e, se ele marcar, o `.toml` espelho do Codex.
3. **Editar skill**: abre o `SKILL.md` num editor simples ou no editor externo. O app avisa "usada por 3 sessões ativas; vale a partir do próximo lançamento" e guarda backup antes de salvar.
4. **Ativar só nesta sessão**: na aba "Contexto" da sessão, ele liga a skill `arcgis-playbook` e o agente "permit-portal-scout" só para esta sessão. O app aplica no próximo lançamento (ou oferece "relançar com resume"). Skills globais aparecem como "sempre ativas", diferenciadas das adicionadas na sessão.

### Onde falha hoje
A Biblioteca é um mundo paralelo num JSON, importa uma skill por vez, cola a skill inteira no system prompt e no plugin ao mesmo tempo (02 #6), e Codex/OpenCode são só export (05 e). A sheet não fecha (03 #1).

### Já proposto
Catálogo das fontes nativas, ativação nativa no Claude (`--agents`, `--agent`), acesso rápido, editor de `CLAUDE.md`/`AGENTS.md` (05 e, P1). Conversor entre clientes (P2).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R9.1 | P1 | **Escopo de ativação explícito**: global (sempre ativo, vem dos arquivos do CLI), sessão (aditivo, por lançamento) e "só no app" (guardado fora das pastas globais e injetado por lançamento). Mover uma skill de global para "só no app" é uma ação com backup. Conferir se a versão instalada do Claude permite desligar uma skill global por lançamento; se não permitir, a UI diz isso em vez de prometer. | "Ativar só numa sessão" não existe para skills globais, porque o Claude carrega todas. |
| R9.2 | P1 | **Quando a mudança vale**: cada edição mostra "próximo lançamento" ou "relançar agora com resume", e quais sessões ativas usam o item. | Editar uma skill e não ver efeito é outro "não funciona". |
| R9.3 | P1 | Agente da biblioteca pode declarar o computador do Racky em `mcpServers` e skills em `skills`; isso substitui o preset "Web scraping" fixo no código (02 #5). | Tira o caso pessoal do Core sem perder o atalho. |
| R9.4 | P1 | **Backup e histórico** de toda escrita em `~/.claude` e `~/.codex` (diff e reverter). | Escrever ali afeta todos os terminais, inclusive os do Orca. |
| R9.5 | P2 | Lint da biblioteca: frontmatter inválido, skill referenciada que não existe, `.md` e `.toml` divergentes. | Ele mantém os espelhos à mão (13 contra 12). |
| R9.6 | — | **Recomendação**: tirar a memória própria do app da v1. Memória fica nos formatos nativos (`CLAUDE.md`, `AGENTS.md`, memória automática do Claude). | O 05 já pede para avaliar; nenhuma jornada precisou dela. |

---

## J10. Custos, uso e limites

### Roteiro ideal
1. Status bar de 24 pt. À esquerda: "Claude 5 h 62 % (14:20) · 7 d 31 %" e "Codex 5 h 100 % (16:05)" em vermelho. À direita: "3 boxes · 6,1 GB · Zyte US$ 0,42 hoje · runs 1,3 GB".
2. Clique em cada item abre o detalhe: por sessão e terminal, tokens e custo estimado; por box, gasto Zyte contra orçamento, CPU, RAM e disco do volume.
3. Orçamento Zyte em três níveis: box (US$ 1), sessão ou lote (ex.: US$ 5) e dia. Em 80 %, aviso. Em 100 %, o proxy recusa (402) e vira pedido humano "aumentar orçamento?" com +US$ 1 em um clique.
4. "Limpar": volumes de boxes paradas há mais de N dias, runs grandes (pp-dallas-tx tem 391 MB), imagens antigas, com tamanho e confirmação.

### Onde falha hoje
Nada é medido. Proxy e orçamento não existem (01 T1–T4).

### Já proposto
Proxy com orçamento por box (05 b, P1), painel de computadores com CPU/RAM (05 b, P1), custo por execução (01 sugestão 13), limpeza de worktrees e volumes (01 sugestão 7).

### Requisitos novos
| ID | P | Requisito | Por quê |
|---|---|---|---|
| R10.1 | P1 | **Medidores de janela de uso**: Claude via um statusline de lançamento que encadeia o script do usuário (repassa o mesmo JSON e devolve a mesma saída), Codex via `rate_limits` dos rollouts. Nada global é alterado (R1.5). | É o dado que decide a J7; o Orca já mostra. |
| R10.2 | P1 | Custo e tokens por terminal e por sessão, rotulados "estimado" (campo de custo do statusline do Claude, se a versão expõe; `token_count` do Codex). | Saber o que um lote custou em tokens. |
| R10.3 | P1 | **Orçamento Zyte hierárquico** (box ⊂ sessão ⊂ dia) aplicado no broker, com reserva e reconciliação; estouro vira pedido humano com aumento de um clique. | O CLI antigo só tinha por box; com 15 boxes, US$ 1 cada vira US$ 15 sem ninguém decidir. |
| R10.4 | P1 | Recursos Docker ao vivo (por box e total da VM) ligados à capacidade da R4.7, e assistente de limpeza com tamanhos. | 98 GB livres e runs de centenas de MB por cidade. |
| R10.5 | P2 | Histórico de gasto por dia e projeto, exportável. | Prestar contas de um projeto de dados. |

---

## 11. O que o Orca tem e o Racky não

A coluna "Uso" vem dos sinais do §0.

| Recurso do Orca | Uso pelo Gabriel | Entra? | Motivo |
|---|---|---|---|
| Worktree por tarefa, composer, base ref | Alto (103 worktrees) | **v1** | Centro do dia (J3). |
| Daemon de PTY e restore de sessão | Implícito (usa todo dia) | **v1** | J2 e J8. |
| Estado de agente, notificações, sino, badge | Notificações ligadas | **v1** | J6. |
| Feed de agentes (Activity) | Desligado | v1 em versão simples (inbox R2.3) | O resumo "desde ontem" é útil mesmo sem o feed. |
| Histórico de sessões com Resume | Provável | **v1** (P1 no 05) | "Continuar conversa" (05 a). |
| Status bar com uso e limites | Provável (statusline própria lê `rate_limits`) | **v1** | J10 e J7. |
| PR e checks na sidebar, "Fix broken checks" | Não usa a UI | v1: chip e estado; v1.1: Fix checks | Visibilidade sem painel completo. |
| Source Control (stage, commit, push, AI commit) | Sinal de não uso | Fora | O agente faz. Só "Abrir em…" e diff só leitura. |
| Annotate AI Diff, atribuição de linhas | Não | Mais tarde | Depende de diff completo. |
| Tasks (issues GitHub/Linear/Jira) | `defaultTaskSource: github`, uso incerto | Só "criar a partir de #issue/URL" no composer | Página de tarefas é um produto à parte. |
| Automations (prompts agendados) | 0 automações | Mais tarde | Se vier, como "lote de scraping agendado" (SPEC v0.4 A12). |
| Mobile companion | Testou, desligado | Fora | Alternativa barata: toggle `claude --remote-control` por terminal (P2), usando o app oficial do Claude. |
| Chat UI sobre o terminal | Desligado | Fora | O princípio é preservar a TUI original. |
| Navegador embutido e design mode | Não | Fora | As boxes Docker cumprem o papel com isolamento. |
| Computer use de apps macOS | Não pelo Orca (Codex Computer Use já instalado) | Fora | Fora do foco. |
| SSH, servidores remotos, VMs por workspace | 0 alvos | Fora | Runtime remoto já estava fora do escopo v1 (SPEC A10). |
| Hibernação de agentes | Desligada | Mais tarde | "Dormir sessão" manual (R6.6) cobre. |
| Troca de conta Claude/Codex | 2 contas Codex registradas | Mais tarde (R7.6) | Útil com limites, não é bloqueante. |
| Quick Commands | Sem sinal | Mais tarde | Podem virar "briefs salvos" para lotes. |
| `orca.yaml`, `.worktreeinclude` | Provável nos repos | v1.1, leitura compatível (R3.4) | Evita configurar duas vezes. |
| Worktree comment atualizado pelo agente | — | **v1** (R2.4) | Barato e útil para retomar. |
| Caffeinate | Desligado | v1.1, desligado por padrão (R8.4) | Lote noturno. |
| Orchestration (runs, tasks, dispatch) | Não | Fora | O Racky tem a própria orquestração (boxes e filhos); copiar a do Orca duplicaria. |
| Editor Monaco, explorer, Quick Open ⌘P | — | Fora | "Abrir em…" resolve. |

O que o Racky tem e o Orca não: computador Docker por subagente, takeover com pausa só do filho afetado, reqlog e diário como evidência, orçamento de proxy, dois modos de subagente. É isso que justifica sair do Orca, e é a parte que a v1 não pode entregar pela metade.

---

## 12. Requisitos transversais que apareceram em várias jornadas

| ID | P | Requisito | Jornadas |
|---|---|---|---|
| RT.1 | P0 | **Convivência com o Orca durante a transição**: os dois apps rodam juntos por semanas. Hooks condicionados por variável de ambiente, nenhum arquivo do Orca é escrito, worktrees compartilhados não são apagados por um app sem o outro saber (avisar se o worktree também está aberto no Orca). | J1, J3, J9 |
| RT.2 | P0 | **Roteiro de aceite "um dia"**: a v1 só é dada como pronta quando o Gabriel roda as jornadas J2, J3, J4, J6 e J8 num dia real, numa build assinada de forma estável, com gravação de tela. Substitui os 68 ACs `planned` como critério de pronto. | todas |
| RT.3 | P1 | Cada ação longa (worktree, box, imagem, retomada em lote) tem estado visível no próprio lugar onde foi pedida e termina em sucesso ou erro com ação. Nada de spinner sem fim nem erro em alert genérico ("Erro no workspace", 03 #14). | J1, J3, J4, J8 |

---

## 13. Proposta de escopo da v1 do rebuild

Critério: a v1 precisa **substituir o Orca no dia a dia** e **fazer o lote de scraping melhor que o CLI antigo**. Se só fizer um dos dois, ele continua usando dois apps.

### Entra na v1 (em quatro fatias, cada uma termina com um dia de uso real)

**Fatia 1 · Casca e terminais** (troca o Orca para trabalho sem boxes)
- Janela, sidebar, tabs, splits, overlays e tokens de motion P0 (04, 06).
- Projeto → Sessão → Terminais; apagar e arquivar; "Abrir em…" (R5.2).
- Composer ⌘N com worktree, checkout, pasta ou pasta nova; agente e prompt já rodando (R3.1–R3.3).
- Perfis de lançamento Claude, Codex e shell; env do shell de login; padrão sem permissões, herdado do Orca.
- Daemon de PTY (quit e crash), captura de ID, retomada com flags regeneradas, retomada em lote (R2.2, R2.5, R8.1).
- Importar do Orca (R1.3); convivência (RT.1).

**Fatia 2 · Atenção e GitHub**
- Estado de agente via hooks (Claude completo; Codex pelo que os hooks dele dão), estado do pai com filhos (R6.1), última mensagem (R2.1).
- Notificações, sino e inbox simples, Dock badge, "próximo que precisa de você" (R6.2), ⌘J, ⌘1…9.
- Chip de PR e estado dos checks via `gh`, "Criar PR" com `gh pr create`, nota da sessão (R2.4).
- Colar no prompt por ação explícita (R5.1).
- Orçamento de desempenho medido (R6.3).

**Fatia 3 · Boxes, modo B** (supera o CLI antigo)
- Onboarding de Docker e imagem, contexto ativo, capacidade (R1.1, R1.2, R4.7).
- MCP do computador em qualquer terminal Claude; skill de orquestração do app; conflito com a skill antiga resolvido (R4.1, R1.6).
- Reserva e reivindicação por nome (R4.2); browser headed em Xvfb (R4.4); pedido de ajuda assíncrono (R4.3).
- Runtime com as ferramentas do CLI antigo: exec, `curl_cffi`, browser por seletor, reqlog com corpos de browser, curl e Python, diário, proxy Zyte com orçamento por box, render.
- Viewer a 15–30 fps com assumir e devolver; faixa de computadores da sessão.
- Resultado e logs no host e `box_collect` (R4.5); remoção e arquivamento de boxes.

**Fatia 4 · Uso e biblioteca mínima**
- Status bar com janelas Claude e Codex, boxes, RAM e Zyte do dia (R10.1, parte da R10.4).
- Biblioteca só leitura das fontes nativas, ativação por sessão aditiva (parte da R9.1), "abrir no editor".

### Fica para a v1.1
Modo A (R4.6, R8.5); handoff leve, detecção de limite e transferência de box (R7.1–R7.4); diff só leitura e "Fix checks" (R5.3–R5.5); criar e editar agentes com backup (R9.2–R9.4); inbox "desde ontem" completo (R2.3); orçamento hierárquico e custos por terminal (R10.2, R10.3); dormir sessão, menu bar com ações, prioridade de pedidos (R6.4–R6.6); manter acordado (R8.4); `.worktreeinclude`/`orca.yaml` (R3.4, R3.5); importar runs antigos (R1.4).

### Mais tarde
Automations e lotes agendados; `--remote-control` como "mobile"; hibernação automática; troca de contas; Annotate diff; página de tarefas; OpenCode com paridade; conversor de agentes; XLSX; biblioteca de perfis de browser e backup/restore; modo privado; WebRTC.

### Sai do plano (do SPEC1 atual)
- Cerimônia de lançamento com plano, hash, revisão e binding (02 §2.7).
- Handoff transacional (substituído pelo leve).
- Memória própria do app (R9.6).
- Painel "Capturas e dados" e datasets (substituídos por reqlog, diário e resultado com evidência).
- Tela de grants de credencial por UUID (substituída por segredos por projeto injetados no env).
- `ControlBroker` persistido e journal de atualização de imagem (02 §7).

### Decisões que precisam do Gabriel antes da spec
1. Sessão ligada a um diretório, com projeto acima (§1.1)?
2. Liberar "colar no prompt" por ação explícita (R5.1), revisando a regra J6?
3. Credencial dentro do container no modo A: qual mecanismo e com que escopo (R4.6)?
4. Browser das boxes sempre headed em Xvfb, aceitando o custo de RAM (R4.4)?
5. Portar o runtime do CLI antigo para dentro do runtime novo (§1.4) em vez de evoluir só o atual?
6. Onde ficam worktrees e runs na transição: `~/orca/workspaces` compartilhado ou pasta própria (R3.2)?
7. Aposentar a skill global `racky` quando a fatia 3 estiver pronta (R1.6)?
