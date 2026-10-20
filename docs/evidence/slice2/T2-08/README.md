# T2-08 · Importação do Orca (núcleo)

Código: `Packages/RackyKit/Sources/RackyCore/Import/` (`OrcaSource.swift`, `OrcaImporter.swift`, `OrcaCoexistence.swift`) e `RackyStore+Import.swift` (tabela `import_run`). Testes: `Tests/CoreTests/Import/`.

## Regra de segurança

O Orca estava em uso durante a descoberta. Nada dele é aberto, movido ou gravado:

- `profile-state.db`, `-wal` e `-shm` são **copiados** para `racky-orca-import-<uuid>/` (temporário do app) e só a cópia é aberta, com `SQLITE_OPEN_READONLY`. A cópia é apagada ao terminar (com erro também).
- Teste de fixture: hash SHA-256 de todos os arquivos sob a pasta de dados do Orca igual antes/depois de dry-run e de import real; diretório temporário vazio depois.
- Dry-run real abaixo: tamanho e mtime de `profile-state.db*` e `orca-data.json` iguais antes/depois (`originalProfileFilesUntouchedByReader: true`).

## Schema descoberto (só nomes, nenhum dado)

`~/Library/Application Support/orca/profiles/<perfil>/profile-state.db` (WAL). `profile_state_meta` tem chaves `schemaVersion`-like (`profile_id`, `revision`, `legacy_json_acceptance`).

```
profile_state_meta(key TEXT PK, value TEXT)
profile_state_documents(domain TEXT PK, payload TEXT /*JSON*/, domain_version INTEGER, revision INTEGER, updated_at INTEGER, content_hash TEXT)
profile_state_automation_runs_meta(domain PK, presence, domain_version, revision, updated_at, content_hash)
profile_state_automation_runs(run_id PK, ordinal, payload, content_hash, revision, updated_at)
```

Domínios em `profile_state_documents` (todos `domain_version = 1`): `repos`, `projects`, `projectHostSetups`, `projectGroups`, `folderWorkspaces`, `sparsePresetsByRepo`, `retiredWorktreeNamesByRepo`, `retiredWorktreeNamesByNamespace`, `worktreeMeta`, `worktreeLineageById`, `workspaceLineageByChildKey`, `settings`, `ui`, `workspaceSession`, `workspaceSessionsByHostId`, `sshTargets`, `sshTargetGenerationCounter`, `deletedSshConfigAliases`, `sshRemotePtyLeases`, `sshPtyConsumerRecoveries`, `claudeLivePtySessionIds`, `migrationUnsupportedPtyEntries`, `legacyPaneKeyAliasEntries`, `automations`, `automationRuns`, `onboarding`, `featureInteractionTelemetryBuckets`, `codexResetCreditAttemptLedger`, `mobileClientTabSelectionsByDeviceId`, `worktreeMetaByIdentity`, `worktreeIdentityAliases`, `schemaVersion`.

Campos lidos (o resto é ignorado):

| Domínio | Campos usados |
|---|---|
| `repos[]` | `id`, `path`, `displayName`, `badgeColor`, `kind` (`git`/`folder`), `gitUsername` (outros: `repoIcon`, `gitRemoteIdentity`, `upstream`, `addedAt`, `externalWorktreeVisibility`, `projectHostSetupMethod`) |
| `folderWorkspaces[]` | `path`, `displayName`/`name`, `id` (vazio na máquina) |
| `worktreeMeta{}` | chave `"<repoId>::<caminho absoluto>"`; valor: `displayName`, `comment`, `sortOrder` (ms), `lastActivityAt` (ms) (outros: `instanceId`, `isUnread`, `workspaceStatus`, `projectId`, `hostId`, `projectHostSetupId`, `manualOrder`) |
| `settings{}` | `workspaceDir`, `branchPrefix` (`git-username`/`custom`/`none`), `branchPrefixCustom`, `defaultTuiAgent`, `terminalDefaultShell`, `setupScriptLaunchMode`, `agentDefaultArgs{agente: string}`, `agentDefaultEnv{agente: {K:V}}`, `agentCmdOverrides{}` |
| `workspaceSession` | `tabsByWorktree{"<repoId>::<caminho>": [abas]}` (só para o detector de coexistência) |

`orca-data.json` (legado) tem os mesmos domínios como chaves de topo e é usado só se o SQLite faltar ou falhar (relatório: "may be outdated").

## Mapeamento implementado

| Orca | Racky |
|---|---|
| `repos[]` | `project` (dedupe por caminho canônico; `source=orca_import`, `import_source_id=orca:<repoId>`), nome, cor, `worktreeRoot = settings.workspaceDir/<pasta>`, prefixo de branch (`gitUsername` / custom / nenhum) |
| `git worktree list` x `worktreeMeta` | `worktree` + `session` tipo `worktree` (`checkout` para o principal, só se houver meta): `displayName` (senão branch, senão pasta), `comment` como nota de status (autor `orca`), `sortOrder` desc como `sortIndex`, `lastActivityAt` como `lastActiveAt`. **Sem tabs nem terminais**: nenhum processo (P15) |
| `agentDefaultArgs.claude/codex` | perfis "Claude · Skip permissions" / "Codex · Bypass approvals" (IDs fixos de `BuiltinProfiles`, `source=orca_import`, `permissionMode` bypass, demais args em `extraArgs`, padrão global se o usuário não tem outro padrão manual); `opencode` vira "OpenCode · Orca defaults" |
| `agentDefaultEnv` | só chaves no relatório; valores só com `importEnvValues` |
| `defaultTuiAgent`, `workspaceDir`, `branchPrefix*` | `AppSettings` (somente na 1a importação ou com "Overwrite my changes") |

Reimportar: atualiza por caminho real, adiciona novos, não sobrescreve edições locais (nome, nota, perfil, projeto arquivado) a menos que `overwriteLocalEdits`. Cada importação real grava `import_run(source='orca', fingerprint SHA-256 do estado lido, summary_json)`.

## Detector de "worktree também aberta no Orca" (`OrcaCoexistence`)

1. `listedInOrca`: caminho canônico em `worktreeMeta` (gatilho de "This worktree is also open in Orca.").
2. `openTabsInOrca`: caminho em `workspaceSession.tabsByWorktree` com abas (informativo).
3. `orcaRunning`: `SingletonLock` (symlink `<host>-<pid>`) na pasta de dados do Orca com pid vivo cujo `proc_name` começa com "Orca"; variante "Orca is open.".

## Dry-run real (Orca em uso, cópia temporária)

Gerado por `RealOrcaDryRunTests` (`RACKY_REAL_ORCA=1`); detalhes e nomes em `dry-run.json`. Só contagens e nomes de repositórios/worktrees.

- Fonte: `sqlite` (JSON legado não usado). 7 repositórios, 120 entradas em `worktreeMeta`.
- Projetos a importar (7): rti-platform, rti-content-platform, rti-global, labrynth-motiondesign, arizona-data-request, crawlers, racky. Pulados: 0.
- Sessões a importar: 119 (1 pulada: meta sem worktree no disco). Por projeto: rti-content-platform 73, racky 28, rti-platform 7, arizona-data-request 4, rti-global 3, crawlers 2, labrynth-motiondesign 2. Worktrees do git sem meta: 0.
- Perfis: "Claude · Skip permissions", "Codex · Bypass approvals". Agentes do Orca sem perfil no Racky (ignorados): 22. Chaves de env importáveis: nenhuma.
- Arquivos do Orca inalterados durante a leitura e diretório temporário vazio depois: verdadeiro.
