# T2-05 GitHub (núcleo) - evidência

Escopo: Core (`RackyCore/GitHub`) e, na etapa seguinte, a UI (abaixo).

- `swift test --filter CoreTests`: 394 testes, 66 suítes, verde (41 deles são GitHub/CheckFailure).
- `scripts/gen.sh`, `scripts/lint.sh`, `scripts/build.sh`: OK.
- `real-gh-read.json`: leitura real (`RACKY_REAL_GH=1`) contra `octocat/Hello-World`, 1 consulta GraphQL, só leitura, sem token.
- Fixtures: `Packages/RackyKit/Tests/CoreTests/GitHub/Fixtures/pr-batch.json` é resposta GraphQL real de repositório público, anonimizada (repo, branches, títulos, números, ids, oids).
  Os demais (`pr-status-contexts`, `rate-limited`, `auth-status-*`) são escritos à mão no formato real, para StatusContext e erros.
- TA-510: teste `tenSessionsInThreeReposMakeThreeRequests` (10 sessões, 3 repos, 3 requisições).

Não feito: UI (chip, painel direito, overlay Create PR), polling agendado por FSEvents (o serviço expõe `refresh`/`branchDidChange`/TTL; o agendador é da UI), colagem no agente (T2-06).

## UI (AC-501, 503, 504, 208)

- Sidebar: linha 2 com `↑n`, ponto de alterações e chip de PR (`#n` + estado + glifo de checks; clique = `git.openPR`); linha 3 com a nota da sessão (duplo clique ou `session.editNote`; vazio remove; hover mostra autor e tempo).
- Painel direito: módulos Source Control (⇧⌘G, só lista contra o merge-base) e Checks (`panel.checks`), lidos do mesmo PR já consultado; sem rede própria.
- `Create Pull Request…` (`git.createPR`): overlay com título, base, descrição e Draft pré-preenchidos; nada é enviado até `Create`; erro mantém o overlay com `Try Again`; `Open Compare on GitHub` roda `gh pr create --web`.
- Polling: ciclo curto da sidebar (15 s com a janela ativa, 5 min em segundo plano) só pergunta ao `GitHubService`, que vai à rede quando o cache vence (45 s ativo, 5 min em segundo plano, 1 consulta GraphQL por repositório); os módulos só trabalham enquanto estão em cena; push detectado pelo status Git agenda a consulta em 5 s. Instância headless, fixtures e `RACKY_GITHUB=off` nunca chamam o `gh`.
- Testes: `Tests/UISnapshotTests/GitHubUITests.swift` (runners falsos de `gh` e `git`; asserta que nenhum push nem `gh pr create` ocorre antes do Create). PNGs desta pasta são gerados por `RACKY_RECORD_SNAPSHOTS=1`.
- Não feito: `[Log In]` do estado "gh não logado" (só a mensagem), `Send Failures to Claude Code` (v1.1, R5.5), ferramenta MCP `session_set_status` do agente.
