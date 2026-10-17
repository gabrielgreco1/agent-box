# T2-05 GitHub (núcleo) - evidência

Escopo desta entrega: Core (`AgentBoxCore/GitHub`). UI (chip, painel Checks) fica para a etapa seguinte.

- `swift test --filter CoreTests`: 394 testes, 66 suítes, verde (41 deles são GitHub/CheckFailure).
- `scripts/gen.sh`, `scripts/lint.sh`, `scripts/build.sh`: OK.
- `real-gh-read.json`: leitura real (`AGENTBOX_REAL_GH=1`) contra `octocat/Hello-World`, 1 consulta GraphQL, só leitura, sem token.
- Fixtures: `Packages/AgentBoxKit/Tests/CoreTests/GitHub/Fixtures/pr-batch.json` é resposta GraphQL real de repositório público, anonimizada (repo, branches, títulos, números, ids, oids).
  Os demais (`pr-status-contexts`, `rate-limited`, `auth-status-*`) são escritos à mão no formato real, para StatusContext e erros.
- TA-510: teste `tenSessionsInThreeReposMakeThreeRequests` (10 sessões, 3 repos, 3 requisições).

Não feito: UI (chip, painel direito, overlay Create PR), polling agendado por FSEvents (o serviço expõe `refresh`/`branchDidChange`/TTL; o agendador é da UI), colagem no agente (T2-06).
