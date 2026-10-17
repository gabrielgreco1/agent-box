# 08 · Revisão da rodada 2: completude funcional e subagentes

Data: 16/10/2026. Revisor da segunda rodada, com foco em completude funcional e subagentes. Nenhum código foi alterado.

**Lido por completo:** `01-features-requested.md`, `02-core-audit.md`, `05-core-features-gaps.md`; `~/.claude/skills/agentbox/SKILL.md`; `~/orca/projects/agentbox/` (README, `bin/agentbox`, `collect.py`, `image/Dockerfile`, `image/tools/*`, `templates/subagent-prompt.md` e os artefatos de `runs/`, só leitura); `docs/spec/index.html` (convertido para texto); `docs/EXECUTION-PLAN.md`. Das tasks em `docs/tasks/` só li trechos, porque a 01 já as inventariou.

**Verificado na máquina** (só metadados, nenhum segredo foi impresso): `claude --help` 2.1.302, `codex --help` 0.160.0 (`login`, `exec`, `app-server`, `exec-server`, `features list`), Keychain (`security find-generic-password` sem `-w`), as chaves de `~/.codex/auth.json` sem os valores, `gh auth status`, `git config`, `ssh-add -l`, `docker context ls`, `sysctl` e `~/.claude/settings.json`.

**Docs oficiais consultadas:** Claude Code (authentication, env-vars, hooks, sub-agents, agent-teams, cross-session-messaging), Codex (auth, CI/CD auth, hooks, subagents) e Docker Sandboxes (`sbx`). As fontes estão no fim.

Convenção: **(verificar)** marca o que veio de doc ou relato de terceiros e ainda não passou por teste nesta máquina.

---

## 0. Fatos novos do ambiente que mudam decisões

| Fato | Evidência | Por que importa |
|---|---|---|
| Uso real do Gabriel: **15 subagentes em paralelo**, todos iniciados no mesmo segundo, com duração de 5 a 45 min | `runs/pp-*` (13/10/2026): o primeiro evento de `agent.jsonl` de todos é `1791922864…872` | A spec planeja um benchmark de **2 boxes** (SPEC1 cap.08, "teto 2"). A carga real é 7× maior |
| Gasto Zyte somado: **US$ 2,13** em 8 das 15 boxes (a maior gastou US$ 0,53); disco **1,3 GB** em `runs/` (a maior box, 391 MB) | `runs/pp-*/zyte_spend.json`, `du` | Precisa de orçamento **agregado por lote**, não só por box, e de política de retenção |
| Mac com **48 GiB e 14 CPUs** | `sysctl hw.memsize hw.ncpu` | A SPEC1 cap.08 fala em "Mac observado de 24 GiB" |
| Login do Claude no **Keychain** (`Claude Code-credentials`), método `claude.ai`, assinatura **team**; `~/.claude/.credentials.json` **não existe** | `security find-generic-password -s "Claude Code-credentials"`, `claude auth status --json` | Um container Linux não lê o Keychain do Mac. Ver §1 |
| Codex com `auth_mode=chatgpt`, `access_token`/`refresh_token`/`id_token` em **arquivo** (`~/.codex/auth.json`, 0600) | Chaves do JSON (sem valores) | O refresh token roda a cada renovação e é de uso único. Ver §1 |
| Git usa **HTTPS com `gh auth git-credential`** (token no Keychain `gh:github.com`, escopos `repo, workflow, gist, read:org`). O `ssh-agent` não tem chaves | `git config --global`, `gh auth status`, `ssh-add -l` | Corrige 02/05 (ver §6). Dentro do container o git **não tem credencial nenhuma** |
| Orca instala hooks **globais** do Claude em `~/.claude/settings.json` (13 eventos), que só agem quando há `ORCA_AGENT_HOOK_PORT/TOKEN/PANE_KEY` no env | `settings.json` → `hooks` | Esse é o padrão a copiar: hooks sempre instalados, ativados por env do pane. Assim **todo** terminal ganha estado, não só o "lançamento revisado" |
| `tmux` não está instalado. Docker Desktop (`desktop-linux`) existe; Colima não | `which tmux`, `docker context ls` | Afeta a opção "tmux para sobreviver" (05 c) e o modo split-pane de agent teams |

---

## 1. [P0] Login automático do CLI dentro do container (requisito novo do dono)

**Requisito:** no modo isolado, o Claude Code e o Codex sobem **já logados** dentro do container, sem novo login do usuário. Valem também `gh` e `git`.

**Conflito com a spec atual:** a SPEC1 cap.12 ("Login do CLI: gerenciado pelo cliente oficial no host; o app **não copia token para container**") e o AC14 ("nenhum token copiado") proíbem isso explicitamente. A decisão do dono revoga essas regras. A spec nova precisa trocá-las por um modelo de ameaça escrito (§1.6).

### 1.1 Onde cada credencial vive hoje (verificado)

| Cliente | Armazenamento no Mac | Tipo | Renovação |
|---|---|---|---|
| Claude Code 2.1.302 | Keychain do macOS, serviço `Claude Code-credentials` (com `CLAUDE_CONFIG_DIR`, a entrada muda conforme o diretório). Só usa `~/.claude/.credentials.json` 0600 quando o Keychain recusa a escrita. No Linux, sempre o arquivo | OAuth da assinatura (accessToken + refreshToken + expiresAt) | Automática. Avisa 3 dias antes de expirar e falha com "Login expired" quando o refresh falha |
| Codex 0.160 | `~/.codex/auth.json` (`cli_auth_credentials_store` = `file`, `keyring`, `auto` ou `ephemeral`; o padrão aqui é arquivo) | ChatGPT OAuth (id/access/refresh) ou API key | Automática durante o uso. O token novo é gravado de volta no `auth.json` |
| gh 2.93 | Keychain `gh:github.com` | Token OAuth do gh com `repo, workflow, gist, read:org` | Sem expiração |
| git | `credential.https://github.com.helper = !gh auth git-credential` | Usa o token do gh | — |

### 1.2 O que dá errado se o app "só copiar o login"

1. **Corrida de rotação do refresh token.** Os refresh tokens OAuth do Claude e do Codex são de uso único na prática. Com N cópias (Mac + 15 containers), a primeira que renovar invalida as outras. As demais caem com `invalid_grant`, "refresh token already used" ou 401, e podem **derrubar também o login do Mac**. A doc de CI/CD do Codex só aceita copiar o `auth.json` "quando uma única máquina ou fila serializada usa aquela cópia". Para o Claude há relatos públicos do mesmo efeito com sessões concorrentes num só store (anthropics/claude-code #54443, #24317, #21765) (verificar na 2.1.302).
2. **Keychain inacessível.** O container não lê o Keychain do Mac. Seria preciso extrair o segredo com `security … -w` e materializá-lo no container, o que expõe o token em claro.
3. **O agente lê o token.** No modo isolado, o CLI e o shell do agente rodam no mesmo container e com o mesmo usuário. Variável de ambiente, `/proc/<pid>/environ` e arquivo de credencial ficam legíveis. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` tira credenciais do env dos subprocessos (Bash, hooks, MCP), mas é **defesa em profundidade, não fronteira**: o processo `claude` continua tendo o valor. Num cenário de scraping (conteúdo hostil + shell + internet aberta), exfiltração por prompt injection é um risco concreto.
4. **Expiração silenciosa.** Uma sessão de fundo que sobrevive ao login para de progredir e não se recupera sozinha (doc "Renew an expiring login").

### 1.3 Claude Code: opções em ordem de recomendação

**A. Token de longa duração (`claude setup-token`). Recomendado para o P0.**
- Fluxo: no setup, o app abre um pane com `claude setup-token`. O usuário aprova no browser **uma vez**. O app captura o token impresso, guarda no Keychain do app e registra a data (validade de **1 ano**).
- Injeção: arquivo de segredo 0400 montado só-leitura (`/run/secrets/claude_oauth`). O entrypoint faz `export CLAUDE_CODE_OAUTH_TOKEN=$(cat …)` e chama `exec claude`. O token nunca vai em argv nem na imagem. Env-file temporário apagado após o `docker create` também serve (o padrão atual do token da box).
- **Concorrência:** o token não tem refresh nem rotação, então N containers simultâneos não brigam entre si nem com o login do Mac.
- Limites documentados: o token só faz requisições de modelo. **Remote Control e conectores do claude.ai não funcionam.** `--bare` não lê `CLAUDE_CODE_OAUTH_TOKEN`. Exige assinatura Pro, Max, Team ou Enterprise (o dono tem Team) e conta para os mesmos limites de uso da assinatura (§9).
- Itens obrigatórios: alerta 30 dias antes de vencer, ação "Gerar novo token", teste "logado no container?" com `claude auth status --json` dentro de uma box descartável, e revogação explicada (o token só é revogado pela conta, no claude.ai).
- Mitigações de leitura pelo agente: `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, usuário não-root, arquivo de segredo removido do env após o boot (verificar se o Claude relê a variável) e egress controlado. O risco residual fica **declarado na UI**.

**B. Gateway de credenciais no host. Recomendado como P1, é o desenho certo a médio prazo.**
- O container recebe `ANTHROPIC_BASE_URL=http://host.docker.internal:<porta>/box/<id>` e `ANTHROPIC_AUTH_TOKEN=<token efêmero da box>`. Um proxy do app em loopback valida o token da box, troca pela credencial real e repassa (incluindo o streaming SSE).
- É o padrão do Docker Sandboxes (`sbx`): segredos ficam no Keychain do host, o sandbox vê um placeholder e o proxy injeta o valor real. Segundo a doc do Docker, "o proxy cuida do fluxo OAuth, então as credenciais não ficam guardadas no sandbox".
- Ganhos: o agente **nunca vê** a credencial real; dá para revogar por box; dá para medir tokens e custo por box/subagente com **orçamento rígido** e kill switch; dá para impor uma allowlist de modelos.
- Custos documentados: com base URL que não é first-party, o Remote Control desliga e o MCP tool search também (`ENABLE_TOOL_SEARCH=true` reativa). Falta conferir se usar o OAuth da assinatura atrás de um proxy próprio é aceito pelos termos (verificar). Se não for, o gateway serve só com API key.

**C. Não fazer:** copiar a entrada do Keychain ou `.credentials.json` para cada container; usar `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` por container (a mesma corrida); montar `~/.claude` do Mac com escrita (corrida e poluição do histórico do host).

**API key** (`ANTHROPIC_API_KEY`) fica como alternativa explícita para quem quer cobrança por API. Nesse caso existe `--max-budget-usd`, mas só funciona com `-p`.

### 1.4 Codex: opções

O Codex não tem um equivalente ao `setup-token` para a assinatura ChatGPT.
- **A. Identidade dedicada às boxes num volume Docker. Recomendado para o P0 (verificar com teste de carga).** No setup, o app roda uma vez `codex login --device-auth` dentro de um container auxiliar, com `CODEX_HOME` apontando para um volume nomeado `agentbox-codex-home`. Esse login abre uma **cadeia de refresh separada** da do Mac, então o Mac não é afetado. Todas as boxes Codex montam o **mesmo arquivo**: não é cópia, e o arquivo vive dentro da VM do Docker, onde o lock entre containers é coerente. É o mesmo cenário de vários terminais Codex no Mac compartilhando um `auth.json`, que é uso normal. Há sinal de que o Codex relê o disco antes de renovar (commit #11802) (verificar). O teste de aceite (§1.7) tem de provar isso.
- **B.** API key (`codex login --with-api-key` lendo do Keychain do app, com `cli_auth_credentials_store=ephemeral` dentro da box). Cobrança por API, sem corrida.
- **C.** `--with-access-token` vale só para workspaces enterprise. Não se aplica.
- **D. Alternativa arquitetural (P2):** `codex --remote` / `app-server` / `exec-server` (experimentais na 0.160). O Codex roda no Mac, com o login do Mac, e só a execução de comandos vai para um `exec-server` no container. Isso daria um **terceiro modo**, "CLI no Mac com shell na box", sem credencial no container. Vale um spike antes de fechar a arquitetura.
- **Não fazer:** copiar `~/.codex/auth.json` do Mac para N containers. É exatamente o caso que a doc proíbe.

### 1.5 GitHub e git dentro do container

- **Não montar o token do `gh`** do Mac. Ele tem `repo` e `workflow` sobre **todos** os repositórios do dono, e um agente com shell poderia empurrar código ou alterar workflows de qualquer repo.
- **P0, broker de credencial git no host.** Dentro da box, `git config credential.helper "!agentbox-git-credential"`. O helper pergunta ao app (por HTTP com o token da box) e o app só responde para o **remote da sessão** (host, owner e repo conferidos). Cada uso fica registrado, e um push pode exigir confirmação conforme a política. O token entregue vem do `gh auth token` do Mac, mas sai **apenas por operação** e nunca fica no container.
- **P1, `gh` dentro da box.** `GH_TOKEN` com um **fine-grained PAT** limitado ao repo e às permissões mínimas (contents, pull requests), criado uma vez pelo usuário e guardado no Keychain do app. Na alternativa, o broker atende `gh api` também.
- **SSH:** o dono não usa (remotes HTTPS, agent vazio). Se um dia usar, o Docker Desktop expõe `/run/host-services/ssh-auth.sock`. Repassar o agent dá ao container **todas** as chaves para qualquer host, então o melhor é uma deploy key por repo (P2).
- **Identidade de commit:** `user.name`/`user.email` copiados do git do host. Assinatura de commit está desligada hoje (sem `gpgsign`). Registrar o subagente autor no trailer do commit (P2).

### 1.6 Modelo de ameaça a escrever na spec (substitui a SPEC1 cap.12 e o AC14)

"No modo isolado, o CLI do agente tem shell no mesmo container que a credencial que ele usa. O app limita **escopo** (token só de modelo, PAT de um repo, git por broker) e **destino** (egress), e declara que o agente consegue usar e, sem gateway, ler a credencial do modelo. Com o gateway (§1.3 B), a credencial real não entra no container."

### 1.7 Aceite proposto (P0)

1. 15 boxes Claude e 3 boxes Codex simultâneas por 8 h, com renovação forçada (Codex) e o Mac usando os dois CLIs ao mesmo tempo. Nenhum logout no Mac nem nas boxes.
2. `env`, `cat /proc/*/environ` e `find / -name "*credential*"` dentro da box não mostram o token do gh nem o do Mac. Com o gateway ligado, também não mostram o token de modelo.
3. Push para um repo fora da sessão é negado pelo broker, com registro.
4. A UI mostra a validade do token Claude e o estado "logado" por box.

---

## 2. Achados novos (não cobertos ou tratados raso na rodada 1)

Severidade: **P0** bloqueia o uso principal, **P1** necessário para ser bom, **P2** melhoria.

### Orquestração e subagentes

**N1 [P0]. Falta a API de orquestração do próprio app ("spawn" de subagente em box).**
- Evidência: o subagente nativo do Claude (Task/Agent) **sempre roda no processo do pai, no Mac**. Ele não tem como nascer dentro de um container. O modo isolado só existe se **o app** criar o processo filho. Na 01, K6/SC30 ("worker independente") aparece como P2/pendente. Na decisão do dono, porém, ele é o **mecanismo central** do modo isolado.
- Recomendação: ferramentas MCP do app oferecidas ao terminal pai:
  - `agent_spawn {mode: isolado|leve, harness: claude|codex|opencode, agent_def?, brief, box_profile, computer: none|headless|desktop, worktree?}` devolve `child_id`;
  - `agent_status`, `agent_wait {ids, timeout}`, `agent_result` (o `result.json` com evidências), `agent_message {child_id, text}`, `agent_stop`, `agent_list`.
  - Na UI, cada filho isolado é uma **aba de terminal real** pendurada no pai, como a decisão do dono pede.
  - O filho fala com o pai pelo mesmo MCP (`report_progress`, `ask_parent`).

**N2 [P0]. Paralelismo dimensionado errado.**
- Evidência: 15 filhos simultâneos no uso real (§0). O helper MCP aceita até 8 chamadas simultâneas (`LocalMCPChannel`, 02 §2.9), e a 01 SC32 marca isso como "Paralelismo feito". **Isso é concorrência de chamadas, não de subagentes.** A SPEC1 propõe 2 boxes. O Claude permite 20 subagentes simultâneos por sessão (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`). O Codex usa `max_threads` 6 por padrão (verificar).
- Recomendação:
  - Alvo de aceite: **15 boxes headless + 2 desktop** em 48 GiB.
  - Perfis de recurso por modo: headless ~0,5–1 GiB, desktop 2 GiB, isolado + CLI +0,5 GiB (verificar).
  - Fila com preflight, tetos por lote e escalonamento de tela (só N desktops ao vivo).

**N3 [P1]. A árvore precisa de profundidade > 1, de teammates e de filhos de filhos.**
- Evidência: subagentes Claude podem criar subagentes até 3 níveis (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`). Agent teams (experimental) criam *teammates* com caixa de mensagens e lista de tarefas compartilhada (`~/.claude/teams`, `~/.claude/tasks`, hooks `TeammateIdle`/`TaskCreated`/`TaskCompleted`). O Codex tem `max_depth`. A 01 K e o 02 só modelam pai → filho.
- Recomendação: o modelo `AgentRun` ganha `parent_run_id` recursivo, `kind ∈ {native_subagent, teammate, app_worker_isolated, app_worker_light}` e `harness`. A sidebar mostra a árvore com colapso e breadcrumb.

**N4 [P1]. O resultado do filho precisa voltar ao pai e ficar visível no app.**
- Evidência: `SubagentStop` traz `last_assistant_message`, e cada filho tem transcript próprio em `~/.claude/projects/<p>/<session>/subagents/agent-<id>.jsonl`. O CLI antigo precisava de `collect.py` manual para importar o transcript. A 01 K9 diz que "o resultado não é registrado".
- Recomendação: o app indexa (só referência) o transcript do filho e mostra em **tempo real**: mensagens, chamadas de ferramenta e resultados. Isso substitui `collect`. Para workers isolados, o transcript fica no volume da box (N12). O resultado final vira registro estruturado (`agent_result`).

**N5 [P1]. Mensagens entre agentes não atravessam a fronteira do container.**
- Evidência: a doc oficial de cross-session messaging diz que "uma sessão dentro de um container e uma sessão no host não se alcançam". Dentro do mesmo container funciona.
- Recomendação: o app faz a ponte, com `agent_message` (N1) entregue no socket de inbox da sessão destino (`CLAUDE_CODE_MESSAGING_SOCKET` e `CLAUDE_CODE_MESSAGING_TOKEN`, exportados para hooks e Bash) ou como prompt via MCP. Respeitar `crossSessionInbound`. As mensagens chegam marcadas como "de outra sessão" e não aprovam nada.

**N6 [P1]. Steering e controle individual do filho por harness.**
- Evidência: o Claude retoma um subagente com `SendMessage` pelo nome ou ID e tem `claude attach/logs/stop/respawn` para sessões `--bg`. O Codex tem `codex queue` (mensagem para uma sessão existente) e um app-server daemon com `codex agents`. A 01 K11 diz só "pendente".
- Recomendação: tabela de capacidades por harness com {mensagem, parar, retomar, trocar modelo}, verificada na versão instalada, e ações no menu do filho.

**N7 [P1]. Lote (fan-out) como recurso de primeira classe.**
- Evidência: o uso real é "N cidades → N filhos, um brief por filho com tarefa, contexto conhecido e spec de saída" (`templates/subagent-prompt.md`). O Codex tem `spawn_agents_on_csv` (verificar).
- Recomendação: "Novo lote" com tabela de alvos (colar CSV), template de brief com `{{TASK}}/{{CONTEXT}}/{{OUTPUT_SPEC}}`, modo, orçamento por filho e total, e um painel do lote com progresso, gasto, bloqueados e resultados. O lote termina num **consolidado** (`results.jsonl`) com links para as evidências.

**N8 [P1]. Verificação automática das afirmações contra as evidências.**
- Evidência: no skill original, o orquestrador lia `timeline --md` e conferia cada afirmação do `result.json` contra os IDs de request. Isso era manual.
- Recomendação: um validador do app marca cada campo do resultado como "citado e existente" ou "citado e inexistente / não verificado", e mostra a evidência ao lado.

### Capacidades na box (complementam 01 SC e 05 b)

**N9 [P0]. Orçamento e logs não podem ficar ao alcance do agente.**
- Evidência: no runtime antigo, `zyte_spend.json`, `requests.jsonl` e `bodies/` vivem em `/work`, que o agente escreve (`agentlog.py:8-12`). Apagar o arquivo zera o gasto, e logs editados forjam evidência. A `ZYTE_API_KEY` vai no env da box (`bin/agentbox`, `docker run -e ZYTE_API_KEY`), então o agente pode usar a chave fora do túnel e furar o orçamento.
- Recomendação:
  - O proxy, o orçamento e o listener rodam fora do alcance do agente: num sidecar de rede (`--network container:`) ou no host.
  - A chave Zyte fica só no sidecar.
  - Os logs são append-only, gravados pelo sidecar num volume que o agente só lê, com hash encadeado se for barato.
  - Isso é a versão concreta da separação control/work que a 05 b propõe.

**N10 [P1]. Detalhes do proxy que a rodada 1 não registrou.**
- Evidência (`tunnel.py`, `proxy`, `render`):
  1. Trocar de modo **derruba todas as conexões** abertas no modo anterior, para nada sair pelo IP errado.
  2. Uma lista de hosts de ruído (analytics, update do Chrome) é bloqueada para não gastar orçamento.
  3. O `render` custa US$ 0,01 por chamada, mais que um request (US$ 0,002), e marca `blocked` quando o HTML ainda é página anti-bot.
  4. O CA da Zyte é instalado na imagem.
- Recomendação: entram na spec do proxy. O orçamento passa a ter três níveis (box, lote, mês) e o estado aparece na sidebar.

**N11 [P1]. Arquivos de trabalho visíveis ao vivo no host, com arquivamento.**
- Evidência: o skill antigo montava `runs/<box>/` como `/work` por bind mount, e o dono abria os arquivos no Finder/editor durante a execução. `up` com um nome repetido **arquiva** o run anterior (`runs/_archive/<box>-<ts>`) e nunca apaga. O app atual usa um volume nomeado e não oferece navegação (01 L21 lista isso, mas sem prioridade).
- Recomendação: P1. Usar uma pasta de host por run (bind mount no modo leve e para resultados no isolado) com o mesmo arquivamento e retenção configurável (1,3 GB em 3 dias de uso).

### Modo isolado: o que falta além do login

**N12 [P0]. Imagem "agente" e ambiente do CLI dentro do container.**
- Evidência: a imagem atual é Playwright + runtime HTTP, sem nenhum CLI de agente (02 §2.12).
- Recomendação:
  - **CLIs:** Claude, Codex e OpenCode com versão fixada para ARM64, `DISABLE_AUTOUPDATER=1` e `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` opcional. Botão "atualizar CLIs da imagem" com rebuild.
  - **Usuário:** não-root (o Claude recusa `--dangerously-skip-permissions` como root sem `IS_SANDBOX=1`, verificar).
  - **Permissões:** modo de permissão padrão dentro da box é decisão do dono. Sugestão: `acceptEdits`/`auto` no isolado, porque o container é o sandbox. No Codex, `--sandbox danger-full-access` ou bypass, porque bwrap/landlock podem não funcionar no Docker (verificar).
  - **Estado do CLI persistente:** volume `~/.claude` e `~/.codex` **por box** (projects/transcripts, memória automática, sessões). Sem isso não há `--resume` depois de recriar o container, e a memória automática se perde.
  - **"Kit" de configuração:** o app materializa só-leitura dentro da box as skills, agentes, plugins, MCP servers e `CLAUDE.md` escolhidos. O Docker sbx documenta que "sandboxes não pegam `~/.claude` do host". Os hooks globais do Orca não existem lá, então os hooks do app precisam vir no kit.

**N13 [P0]. Repositório: montagem, sincronização e conflito entre N filhos.**
- Evidência: nenhuma doc da rodada 1 trata o assunto.
- Recomendação. As opções:
  - (a) **Worktree por filho** no host, com bind mount rw na box. Simples e as mudanças aparecem na hora. É o padrão do Orca e o `isolation: worktree` do Claude. Custo: virtiofs lento para `node_modules`, mapeamento de UID e escrita direta no disco do host.
  - (b) Repo montado só-leitura e clone gravável dentro do volume da box (o `--clone` do sbx). O resultado volta por `git push` para um remote local (bare no host) ou por `git bundle`. Isola melhor e exige um passo de "trazer mudanças".
  - Sugestão: (a) como padrão para código e (b) para tarefas não confiáveis (scraping). Em ambos: nunca dois filhos no mesmo worktree, e um diff do filho aparece no app antes de mesclar.

**N14 [P0]. Hooks e telemetria de dentro do container até o app.**
- Evidência: hoje os hooks são um `python3` do host gravando em arquivo (02 §2.8, 05 transversal). Dentro do container nada disso existe.
- Recomendação: usar hooks **`type: "http"`**, nativos no Claude 2.1.x, com `headers` e `allowedEnvVars`, apontando para `http://host.docker.internal:<porta>` com token por box, e `onFailure` conforme o evento. O mesmo mecanismo serve o host, elimina a dependência de `python3` e o polling de inbox (resolve 02 bugs #11 e #12 por outro caminho). O Codex tem hooks estáveis na 0.160 (`codex features list`: `hooks stable true`) (verificar quais eventos).

**N15 [P1]. Rede do modo isolado.**
- Evidência: a SPEC1 cap.10 pede separar "internet da tarefa" de "rede local/host". O CLI no container precisa de `api.anthropic.com`/`chatgpt.com`, de `host.docker.internal` (hooks, MCP, gateway, broker git) e da internet (scraping).
- Recomendação: rede Docker própria por lote. Deny para a LAN e para os metadados do Mac, allow para a porta do app no host. Egress da tarefa passa pelo sidecar (proxy, log e orçamento). Opcional: allowlist de destinos por tarefa.

**N16 [P1]. Takeover do terminal do filho, não só do browser.**
- Evidência: no modo isolado o filho tem PTY real (aba), então o humano pode digitar nele e aprovar permissões ali. A rodada 1 só trata takeover de browser (01 O). As permissões de um subagente nativo **em background** aparecem na sessão principal com o nome do filho (doc sub-agents).
- Recomendação: um pedido de permissão vira item na fila de pedidos (01 P6) com origem. Clicar leva à aba certa. O hook `PermissionRequest` alimenta a fila.

**N17 [P1]. Computador GUI no mesmo container do CLI.**
- Evidência: a decisão do dono diz "headless ou GUI no mesmo container". Com o shell do agente no mesmo container do browser, o lease de controle (01 O4) é contornável. O runtime README já admite isso.
- Recomendação: aceitar e declarar no modo isolado (app pessoal), mas manter o **viewer e o input humano** fora do alcance do agente (Xvfb/VNC rodando como outro usuário ou no sidecar). Alternativa: browser no sidecar e CLI no container work, com a mesma rede.

### Modo leve (CLI no Mac, computador via MCP)

**N18 [P1]. Usar `mcpServers` por subagente e `agent_id` dos hooks no lugar do roteamento com token HMAC.**
- Evidência: a definição de subagente aceita `mcpServers` inline, que conecta quando o filho começa e desconecta quando termina. `agent_id` e `agent_type` são campos comuns da entrada dos hooks. O app atual injeta um `route_token` via `PreToolUse.updatedInput` (02 §2.9).
- Recomendação: no lançamento, gerar o subagente "com computador" com `mcpServers: {agentbox: {command, args:["--child", <id>]}}`. Cada filho fala com o próprio processo MCP, e a identidade vem do processo. Validar na 2.1.302. Ressalvas: subagentes de plugin ignoram `mcpServers`, e teammates in-process também.

**N19 [P1]. Ferramentas de computador para shell no modo leve.**
- Evidência: o skill original dava `exec` na box mesmo com o CLI no Mac. A 05 b lista "shell no box" como P0, mas sem dizer como ele chega ao CLI do Mac.
- Recomendação: `computer_exec {argv|shell, cwd, timeout, stdin?}` com log de comando, sem TTY, e `computer_pty` (opcional) que abre uma aba "shell da box" para o humano.

### Persistência, notificações e custo

**N20 [P0]. O modo isolado sobrevive ao quit do app, se o PTY morar no container.**
- Evidência: um container continua rodando quando o app fecha. Se o CLI rodar sob `tmux`/`dtach` **dentro da imagem**, e o app só anexar (`docker exec -it … tmux attach`), o filho isolado sobrevive a quit e crash sem o daemon de PTY que a 05 c coloca como a peça mais difícil.
- Recomendação: incluir `tmux` ou `dtach` na imagem e definir "anexar/desanexar" como contrato do modo isolado. Para o modo leve no Mac, ver a correção C5 (`claude --bg`).

**N21 [P1]. Notificações que faltam na lista da rodada 1.**
- Evidência: a 05 cobre "esperando você" e "terminou". Faltam:
  - token Claude perto de vencer ou login de box inválido;
  - limite de uso da assinatura atingido (`StopFailure`);
  - orçamento de proxy em 80% e em 100%;
  - Docker parado (estado atual da máquina);
  - box morta ou OOM;
  - filho bloqueado (`BLOCKED:` no diário);
  - lote concluído com resumo.
- Recomendação: um centro de notificações único (02 já propõe fundir com HumanRequests) com esses tipos, mais os resumos de lote.

**N22 [P1]. Limites de uso da assinatura compartilhados por N agentes.**
- Evidência: o `setup-token` e o login normal usam a **mesma assinatura** (Team). 15 sessões paralelas consomem a janela de 5 h e o limite semanal juntas, e quando a janela se esgota, todas param.
- Recomendação:
  - medidor por lote (tokens e custo estimado a partir do JSON da statusline, do `result` em `-p` ou do gateway N1/§1.3 B);
  - aviso e pausa de novos spawns quando faltar margem;
  - fallback de modelo por filho (`--fallback-model`);
  - modelo padrão mais barato para os filhos (`CLAUDE_CODE_SUBAGENT_MODEL`).

**N23 [P1]. Diário PLAN/DOING/FOUND/BLOCKED como dado estruturado e estado da UI.**
- Evidência: a 01 SC15 diz só "ausente". No uso real, o diário é o que o dono lia durante a execução (`agent.jsonl`, 9 a 29 notas por box).
- Recomendação: ferramenta MCP `journal {kind, text, evidence_ids[]}`. A última nota DOING vira o subtítulo do filho na sidebar, e BLOCKED vira estado de atenção. A timeline combina diário, comandos, requests e transcript.

### Biblioteca, handoff e GitHub

**N24 [P1]. Biblioteca precisa saber o que cada modo carrega.**
- Evidência: no modo leve, o CLI enxerga `~/.claude` e `~/.agents` inteiros. No isolado, só o kit (N12). Hoje nada mostra isso.
- Recomendação: na tela do agente/lançamento, uma lista "carregado nesta execução" por modo (skills, agentes, MCP, `CLAUDE.md`, plugins), com a fonte.

**N25 [P2]. Handoff entre harnesses ficou mais concreto.**
- Evidência: existe `claude import [source]` ("Import config from another AI coding agent"). O Codex tem `external_agent_memory_import` em desenvolvimento.
- Recomendação: no modo isolado, o handoff é trocar o processo de CLI **na mesma box** (workspace, browser e logs preservados) com um checkpoint em arquivo (`HANDOFF.md`: objetivo, feito, evidências, próximos passos), gerado pelo agente de saída e lido pelo de entrada. É muito mais simples que o handoff transacional da SPEC1. Rebaixar AB-027 para esse desenho.

**N26 [P1]. GitHub por subagente.**
- Evidência: com N filhos em worktrees, cada um pode virar um PR. A 05 d trata PR por worktree do humano.
- Recomendação: o lote de código abre um PR por filho (draft), com checks visíveis e "mandar falha de check ao filho" (a ação "Fix broken checks" do Orca). Usar `claude --from-pr` para retomar no PR. Depende do broker git (§1.5).

### Ciclo de vida e limpeza

**N27 [P1]. Limpeza completa e reconciliação ao abrir.**
- Evidência: a 02 #2 aponta o vazamento de container e volume. Ainda faltam: worktrees de filhos, volumes `~/.claude` por box, `LaunchContexts/`, arquivos de segredo temporários, runs antigos, redes Docker por lote e a entrada de token no Keychain.
- Recomendação: cada recurso tem dono (`run_id`) e TTL. Ao abrir, o app reconcilia por labels e mostra os órfãos com tamanho. Uma ação "limpar lote" remove tudo, menos os resultados e as evidências exportadas.

---

## 3. Lista consolidada definitiva: capacidades de subagente alvo

Modo: **I** = isolado (CLI no container), **L** = leve (CLI no Mac, computador por MCP), **I/L** = ambos. "Ref." aponta para a 01 (SC/K/O…) ou para os achados N desta revisão.

| # | Capacidade | Modo | Prioridade | Ref. |
|---|---|---|---|---|
| **Criação e identidade** |||||
| 1 | Escolher modo por subagente (isolado/leve) no spawn, com padrão por agente salvo e por lote | I/L | P0 | decisão do dono |
| 2 | Spawn pelo app (`agent_spawn`) a partir do pai ou da UI; worker com PTY real em aba | I/L | P0 | N1, K6 |
| 3 | Subagente nativo do harness observado (Claude hooks; Codex hooks/multi_agent) | L | P0 Claude / P1 Codex | K1–K3, C1 |
| 4 | Identidade por filho confiável (processo MCP por filho, `agent_id` do hook) | I/L | P0 | N18, SC2 |
| 5 | Árvore com profundidade > 1, teammates e workers do app | I/L | P1 | N3 |
| 6 | Harness por filho: Claude, Codex, OpenCode | I/L | P0 Claude+Codex / P2 OpenCode | K7 |
| 7 | Modelo e esforço por filho, com padrão mais barato para filhos | I/L | P1 | N22, SC31 |
| **Autenticação e segredos** |||||
| 8 | CLI já logado no container (setup-token / volume Codex dedicado) | I | P0 | §1 |
| 9 | Gateway de credenciais (o agente não vê o token; custo e orçamento por box) | I | P1 | §1.3 B |
| 10 | Git por broker limitado ao repo da sessão; `gh` com PAT fino | I | P0 git / P1 gh | §1.5 |
| 11 | Segredos de tarefa (.env, grants) injetados por box, nunca em argv nem imagem | I/L | P1 | SC25, U4 |
| **Trabalho na box** |||||
| 12 | Shell/exec na box (argv e shell, cwd, timeout, cancel) com log de comandos | I (nativo) / L (`computer_exec`) | P0 | SC3, SC16, N19 |
| 13 | Ferramentas: curl, python3, requests, **curl_cffi**, jq, openpyxl, Playwright | I/L | P0 | SC4 |
| 14 | HTTP arbitrário (POST, headers, cookies, redirects) a partir da box | I/L | P0 | SC8 |
| 15 | Browser persistente com ações por seletor (open/text/html/click/fill/press/eval/cookies/shot/download/upload) | I/L | P0 | SC5, SC6 |
| 16 | Modos http/headless/desktop, com troca pedida pelo agente dentro da política | I/L | P0 | SC7 |
| 17 | Repo/worktree por filho (bind rw ou clone isolado), diff antes de mesclar | I | P0 | N13 |
| 18 | `/work` visível ao vivo no host, arquivamento por run, `/tmp` para rascunho | I/L | P1 | N11, SC19 |
| **Rede, proxy e custos** |||||
| 19 | Listener de **todas** as requests (browser, curl, python), com bodies, falhas e consulta pelo agente (`reqlog --xhr/--errors/--grep/--full`) | I/L | P0 | SC9 |
| 20 | Proxy Zyte on/off/status por box cobrindo o browser; troca derruba conexões antigas; hosts de ruído bloqueados | I/L | P1 | SC10, N10 |
| 21 | Render via Zyte API (`--capture` de XHR, detecção de "blocked") | I/L | P1 | SC11, N10 |
| 22 | Orçamento rígido por box, por lote e por mês, **fora do alcance do agente**, medido e estimado | I/L | P0 (box) / P1 (lote, mês) | N9, T2 |
| 23 | Escada de escalonamento direto → proxy → render → pedir ajuda; nunca contornar login | I/L | P1 | SC12 |
| 24 | Egress controlado: sem LAN/host além das portas do app; allowlist opcional por tarefa | I | P1 | N15 |
| 25 | Medição de tokens e custo de modelo por filho e por lote; aviso de limite da assinatura | I/L | P1 | N22 |
| **Observação humana** |||||
| 26 | Ver a tela ao vivo (viewer bom para takeover; miniaturas para N boxes) | I/L | P0 viewer / P1 grade | 05 b, N2 |
| 27 | Takeover do browser com lease/ACK; irmãos continuam | I/L | P0 | SC13, SC14 |
| 28 | Takeover do **terminal** do filho (digitar e aprovar permissões na aba) | I | P1 | N16 |
| 29 | Pedido de ajuda com motivo real e tipo (login, CAPTCHA, escolha, permissão) | I/L | P0 | P2, 02 #18 |
| 30 | Transcript do filho ao vivo no app (mensagens, ferramentas, resultados) | I/L | P1 | N4 |
| **Diário, evidência e resultado** |||||
| 31 | Diário PLAN/DOING/FOUND/BLOCKED estruturado, refletido na sidebar | I/L | P1 | N23, SC15 |
| 32 | Timeline combinada (diário, comandos, requests, transcript) | I/L | P1 | SC17 |
| 33 | `result.json` com toda afirmação citando request ou arquivo; validador automático | I/L | P1 | SC18, N8 |
| 34 | Logs e evidências append-only, gravados por processo fora do agente | I/L | P1 | N9 |
| **Orquestração** |||||
| 35 | Resultado volta ao pai (`agent_result`, `agent_wait`) | I/L | P0 | N1, N4 |
| 36 | Mensagens pai ↔ filho e filho ↔ filho (ponte host ↔ container) | I/L | P1 | N5 |
| 37 | Parar, retomar e enviar mensagem a um filho individualmente | I/L | P1 | N6 |
| 38 | Lote: N alvos → N filhos com brief templado, painel do lote e consolidado | I/L | P1 | N7 |
| 39 | Paralelismo: 15 headless + 2 desktop simultâneos com fila e preflight | I/L | P0 | N2 |
| 40 | Skills/agentes/MCP materializados no kit do container (webscraping-expert carregado, intake pulado) | I | P0 | N12, SC20 |
| **Ciclo de vida** |||||
| 41 | Sobrevive ao quit/crash do app (isolado: tmux no container; leve: `claude --bg` ou ptyd) | I/L | P0 | N20, C5 |
| 42 | Retomar a conversa do filho depois de recriar a box (volume de estado do CLI) | I | P1 | N12 |
| 43 | Parada e limpeza no fim (box, volume, worktree, rede, segredos temporários), com retenção dos resultados | I/L | P0 | N27, SC28 |
| 44 | Perfil de browser reaproveitado com exclusividade (login humano feito uma vez) | I/L | P1 | SC26, V2 |
| 45 | Handoff de harness na mesma box por `HANDOFF.md` | I | P2 | N25 |
| 46 | PR por filho com checks e "corrigir checks" | I | P1 | N26 |

---

## 4. Correções aos relatórios da rodada 1

| # | Relatório | Afirmação | Correção |
|---|---|---|---|
| C1 | 05 (c) "Como outros resolvem"; 01 K7; 05 P2 n.º 23 | Codex só teria `notify`; filhos Codex sem identidade e "P2" | O Codex 0.160 tem **`hooks` estável** e **`multi_agent` estável** (`codex features list`). A doc oficial lista `SessionStart`, `PreToolUse`, `PostToolUse`, `SubagentStart`, `Stop`, entre outros, em `config.toml`/`hooks.json`, com revisão e confiança dos hooks. Há também `codex queue` e um app-server daemon. Subir os filhos e o estado do Codex para **P1** e refazer o levantamento de eventos na versão instalada |
| C2 | 02 §4.1 item 2, 02 bug #3, 05 (a), 05 (d) "Dependências" | A allowlist de env "quebra `git push` via ssh" | O dono usa **HTTPS + `gh auth git-credential`** (Keychain), e o `ssh-agent` não tem chaves. No host, o push funciona pelo helper independentemente do env (verificar no PTY do app). A allowlist continua sendo bug pelos outros motivos. O problema real de git é **dentro do container**, onde não há credencial nenhuma (§1.5) |
| C3 | 01 SC32 | "Paralelismo de filhos: feito (helper com até 8 chamadas simultâneas)" | Isso é concorrência de chamadas MCP, não paralelismo de subagentes. Com 15 filhos, o limite de 8 vira gargalo. Paralelismo real de subagentes com box é **pendente**, e o alvo é 15 (N2) |
| C4 | 01 L6/U9, SPEC1 cap.12, AC14 | "Login do CLI fica no host; o app não copia token para o container" (regra) | Foi revogado pela decisão do dono. Substituir pelo modelo de §1.6 e pelo aceite §1.7 |
| C5 | 05 (c) "Claude Code … `--bg` … não substitui um daemon do app" | — | É verdade para os três clientes juntos. Para o **Claude**, porém, `--bg` + `attach` + `logs` + `stop` + `respawn` + `agents` dão sobrevivência ao quit, reanexação e listagem nativas. Um terminal Claude do app pode ser `claude attach <id>` dentro do PTY. Isso adianta o P0 de sobrevivência sem esperar o ptyd (verificar a interação com hooks, MCP e `--settings` no `--bg`) |
| C6 | 02 §2.8 ("socket local ou FIFO em vez de arquivo + polling") e 05 transversal ("Python do host exigido") | — | O Claude tem hooks **`type: "http"`** (POST JSON, `headers`, `allowedEnvVars`, `onFailure: block` desde a 2.1.295). É a solução nativa: elimina `python3`, arquivo e polling, e funciona de dentro do container (N14). `agent_id`/`agent_type` em todo evento reduz a necessidade do `route_token` injetado (N18) |
| C7 | 05 (e) "Proposta técnica" (`--agents` com `skills` e `mcpServers` resolve o agente de scraping) | — | Ressalvas documentadas: subagentes de plugin ignoram `mcpServers`; teammates in-process ignoram `mcpServers` e `skills`; com `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, um subagente nomeado vira teammate. O desenho precisa fixar o modo (agent teams desligado nos lançamentos do app, ou tratado) |
| C8 | SPEC1 cap.08 citada na 01 L10 e na 05 | "Mac observado de 24 GiB", benchmark de 2 boxes, "10 pedidos com teto 2" | A máquina tem 48 GiB e 14 CPUs, e o uso real é de 15 filhos simultâneos. Refazer as metas de capacidade (N2) |
| C9 | 01 T1/T2 e 05 (b) "Comparação com o CLI anterior" | Apresentam o proxy/orçamento do skill antigo como referência a migrar | O desenho antigo tem orçamento e logs **burláveis pelo agente** (arquivos em `/work` graváveis; `ZYTE_API_KEY` no env da box). Migrar a funcionalidade, não o desenho (N9) |
| C10 | 01 §2 SC1 | "o orquestrador cria a box antes de criar o filho e entrega o nome dela" como requisito | Era o contorno do skill antigo, porque o Task tool não cria box. No app novo, o spawn pelo app (N1) cria box e filho juntos e entrega a identidade sem depender do modelo copiar o nome da box |
| C11 | 05 (b) Prioridade, P0 "shell no box com separação control/work" | Tratado como requisito único | No modo isolado o shell é nativo (o CLI está no container). A separação control/work vira: sidecar com proxy, listener e orçamento (N9) e viewer fora do alcance (N17). No modo leve continua valendo `computer_exec` (N19) |
| C12 | 02 §2.9 "Se o app fecha, o helper sai … sem reconexão" | Correto, mas incompleto | No modo isolado com hooks e MCP via HTTP para o host, a queda do app também derruba hooks e ferramentas dos filhos que seguem vivos no container. É preciso definir o comportamento: filas no sidecar e reentrega ao reabrir, ou falha explícita para o agente com "app indisponível, aguarde" |

---

## 5. Fontes externas

- Claude Code: [authentication](https://code.claude.com/docs/en/authentication) · [env-vars](https://code.claude.com/docs/en/env-vars) · [hooks](https://code.claude.com/docs/en/hooks) · [sub-agents](https://code.claude.com/docs/en/sub-agents) · [agent-teams](https://code.claude.com/docs/en/agent-teams) · [cross-session-messaging](https://code.claude.com/docs/en/cross-session-messaging) · [devcontainer](https://code.claude.com/docs/en/devcontainer)
- Relatos de corrida de refresh (não oficiais): [anthropics/claude-code#54443](https://github.com/anthropics/claude-code/issues/54443) · [#21765 (espelho)](https://claudeissues.com/issue/21765-oauth-refresh-token-not-used-when-credentials-are-copied-to-remote-headless-mach) · [análise Zylos](https://zylos.ai/research/2026-08-05-refresh-token-rotation-cloned-agent-instances)
- Codex: [auth](https://learn.chatgpt.com/docs/auth) · [CI/CD auth](https://learn.chatgpt.com/docs/auth/ci-cd-auth) · [hooks](https://developers.openai.com/codex/hooks) · [subagents](https://developers.openai.com/codex/subagents) · [commit de refresh #11802 (espelho)](https://forge.lthn.ai/core/core-agent-ide/commit/999576f7b8626deec238f80225ab18cd323bb3de) · exec-server (terceiros): [danielvaughan](https://codex.danielvaughan.com/2026/04/21/codex-cli-remote-connections-ssh-websocket-secure-tunnels/)
- Docker Sandboxes: [Claude Code no sbx](https://docs.docker.com/ai/sandboxes/agents/claude-code.md) · [Docker Desktop sandboxes (deprecated)](https://docs.docker.com/ai/sandboxes/docker-desktop.md) · [visão geral (terceiros)](https://www.morphllm.com/docker-sandbox)
- Skill original: `~/.claude/skills/agentbox/SKILL.md`, `~/orca/projects/agentbox/{bin/agentbox,image/tools/{agentlog.py,tunnel.py,proxy,render},templates/subagent-prompt.md,runs/pp-*}`
