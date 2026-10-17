# T1-05 · Domínio e Store da Fatia 1 — evidência

Comandos (DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer): `scripts/bootstrap.sh`, `scripts/gen.sh`, `scripts/lint.sh`, `scripts/lint.sh --self-test`, `swift test --package-path Packages/AgentBoxKit`.

- `swift-test.log`: 54 testes, 0 falhas (inclui migração, round-trip, corrupção, versão mais nova, debounce, observação e máquinas de estado).
- `lint.log`, `lint-selftest.log`: Swift 6 estrito sem warnings; regras AR-131 verdes.

## Mapa AC e requisitos

| Requisito | Teste |
|---|---|
| AC-T13 (corrupção restaura o backup, UI funciona; sem backup abre vazio) | `CorruptionTests` (arquivo todo e corrupção parcial; sem backup; backup mais novo inválido cai no anterior válido) |
| AC-T14 (backup antes da migração; diários = 7) | `MigrationTests.pendingMigrationCreatesBackupBeforeApplying`, `BackupTests` (7 diários, 5 pré-migração) |
| AR-322 (versão mais nova: somente leitura, nunca altera) | `MigrationTests.newerDatabaseOpensReadOnlyAndIsNeverModified` (bytes idênticos) |
| AR-321 (migração falha: rollback, banco intocado) | `MigrationTests.failedMigrationRollsBackAndOpensReadOnly` |
| AR-311 (`v1_initial` só Fatia 1) | `MigrationTests.emptyDatabaseGetsOnlySlice1Tables` |
| AR-312 (debounce 300 ms, nada a cada frame; UI observa) | `PersistenceDebounceTests`, `ObservationTests` |
| 01 §6 (máquinas de estado) | `StateMachineTests` (todas as combinações estado x evento) |

## Decisões e divergências

- Modelos de domínio (valores `Sendable`) ficam em `AgentBoxProtocol/Domain/`, não em `AgentBoxCore/Domain/`: `AgentBoxStore` não pode depender de `AgentBoxCore` (Core depende de Store, AR-121). As máquinas de estado (funções puras) ficam em `AgentBoxCore/Domain/`.
- AC-T13 cita `corrupt-<ts>.sqlite`; implementado como AR-331 (`db/corrupt-<ts>/agentbox.sqlite*`). O arquivo é preservado e o aviso carrega o caminho para "Reveal Corrupt File".
- `SessionLifecycle` persiste só `active`/`archived` (schema); `creating`, `failedToCreate`, `missing` e `deleted` são estados em memória e `save` os rejeita. `sleeping` (v1.1) fora.
- Banco novo não gera backup pré-migração (nada a preservar); só há backup quando já existe migração aplicada.
- `scripts/lint.sh`: corrigido o motor de regras (`--glob '*.swift'` anulava os globs de escopo, fazendo `ui-system` varrer o projeto todo); agora usa `--type swift`. Caso novo no self-test.
- Leitura de banco em WAL sem `-shm` falha com `readonly`; `Backups.readerQueue` cai para conexão comum, nunca usada para escrita.

## Não feito (fora do escopo de T1-05)

- Corrupção em tempo de execução só é detectada e põe o store em somente leitura; sem teste automatizado (difícil de simular sem o app).
- Agendamento de backup a cada 24 h com o app aberto (o store expõe `backupDailyIfNeeded()`; o app agenda).
- XCUITest de AC-T13 com `AGENTBOX_TEST_CORRUPT_DB=1` (precisa do app, tarefas T1-10 em diante).
- Tabela `agent_run` (`v2_activity`); `AgentRun` existe só como tipo.
