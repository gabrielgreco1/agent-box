# Rename: AgentBox -> Racky

Owner request: "limpar esse nome [agentbox] 100% de tudo". The product is Racky. This file is the plan, the migration design and,
at the end, the ledger of every intentional leftover. It is the only doc that is allowed to say the old name freely.

Mapping applied mechanically (content and paths, case-aware):

| Old | New |
|---|---|
| `AGENTBOX_*`, `AGENT_BOX_*` | `RACKY_*` |
| `AgentBox*` (types, modules, targets, package) | `Racky*` (`AgentBoxKit` -> `RackyKit`) |
| `Agent Box`, `Agent-Box` | `Racky` |
| `agentbox`, `agent-box` | `racky` |
| `agentboxd`, `agentboxd-launch` | `rackyd`, `rackyd-launch` |
| `app.agentbox.*` | `app.racky.*` |
| `AB_UPDATE_GOLDEN`, `AB_RECORD_SNAPSHOTS` | `RACKY_UPDATE_GOLDEN`, `RACKY_RECORD_SNAPSHOTS` |

Protected from the mechanical pass (real external things this change must not break): the owner's checkout paths
(`/Users/gabriel/orca/agent-box/...`, `/Users/gabriel/orca/workspaces/agent-box/...`, scratchpad paths derived from them), the
GitHub test repo `gabrielgreco1/agentbox-e2e` and the external skills repo path `.../skills/tree/<sha>/agentbox`.

## Inventory (groups)

1. **User-visible defaults**: window/menu titles, `TERM_PROGRAM`, `~/AgentBox/{worktrees,sessions,projects,runs}` default folders,
   build dir `build/AgentBox` -> `build/Racky`, README and docs.
2. **Code identifiers**: SPM package `Packages/AgentBoxKit` -> `Packages/RackyKit`; modules
   `AgentBox{Core,UI,Protocol,Platform,Store,Docker,DesignSystem,TerminalCore,ViewerKit,Bench,MCP}`; test targets; executables
   `agentbox` -> `racky`, `agentboxd` -> `rackyd`, `agentboxd-launch` -> `rackyd-launch`; python packages
   `agentbox_{runtime,egress,supervisor}` -> `racky_*`; `project.yml`; `scripts/*`; `App/AgentBox.icns`; the LaunchAgent plist file;
   brand assets in `design/`; `legacy/` (dead pre-rebuild code, renamed for consistency).
   **Build layout change:** the CLI helper `racky` is embedded in `Contents/Helpers/racky`. `Contents/MacOS/racky` would collide with
   the app executable `Racky` on a case-insensitive volume (that collision is why the helper used to be called `agentbox`).
3. **Ids that persist on users' machines**: data folder, default user folders, bundle id, launchd label and socket key, keychain
   services, UserDefaults domain, env vars, SQLite file name and import-source values, Docker image/labels/owner/in-container
   paths, MCP server name and tool prefix, plugin/skill names, worker agent names.
4. **Docs**: README, `docs/**` (including `docs/evidence/**`, readable but with the new name), `design/**`, `legacy/**`.

## Phases

1. Docs and README. 2. Code identifiers (mechanical rename + `git mv`, goldens and the one changed snapshot re-recorded).
3. Persistent ids with migration code and tests. 4. Final sweep and the ledger below.

## Migration design (phase 3)

All old names live in `Packages/RackyKit/Sources/RackyProtocol/Legacy/LegacyNames.swift` and in the code/tests that migrate them.

- **Data folder.** `StartupMigrations.run()` (first statement of `App/main.swift`; the daemon repeats it as a safety net)
  calls `DataFolderMigration.migrateDefault()` before the instance lock and the store. Only the old folder exists: a single
  `rename(2)` (atomic) of `~/Library/Application Support/AgentBox` to `.../Racky`, then `db/agentbox.sqlite{,-wal,-shm}` are renamed
  to `db/racky.sqlite{,-wal,-shm}`. Both exist: the new one is used, the old one is left untouched, the outcome is logged
  (`.bothExist`). An empty new folder (for example created by an installer) is removed (`rmdir`) and the migration proceeds.
  `RACKY_HOME` (tests, evidence, isolated dev) disables it. Nothing hidden inside `StorePaths.default`, so unit tests can never
  touch a real folder. Covered by `DataFolderMigrationTests` with temp dirs. `scripts/install.sh` keeps `previous/` inside the old
  folder until the app has migrated it (otherwise it would create `Racky/` first and block the migration).
- **Default user folders.** Settings are stored whole, so anyone who ever saved settings keeps `~/AgentBox/...` literally, and a custom
  path is never touched (decode unchanged). New settings default to `~/Racky/...`. For someone who never saved settings, but already
  has `~/AgentBox/<x>` on disk and no `~/Racky/<x>`, `LegacyDefaultFolders` keeps the old default for that folder (in memory, until the
  user changes it) so existing worktrees stay inside the configured root. Sessions keep the absolute paths stored in the database.
  Nothing under `~/AgentBox` is ever moved or deleted. `~/Racky/runs` is where new subagent run folders go.
- **Bundle id and LaunchAgent.** Bundle id and signing identifiers are `app.racky.*`; the label is `app.racky.ptyd.v1` with socket key
  `RACKY_PTYD_SOCK_V1`. `BackgroundAgentHost` now runs `LegacyDaemonRetirement` at every `prepare`/`recover` (production identity
  only): if launchd knows `app.agentbox.ptyd.v1` and its daemon (pid from `launchctl print`) has **no child processes** (no
  terminals/agents), it does `SMAppService.unregister` (best effort) plus `launchctl bootout`. If it still has children it is left
  completely alone (`keptRunning`) and re-checked on the next prepare/recover. Caveat found while designing this: the old daemon
  authenticates peers by code-signing identifier (`app.agentbox.mac` + the same certificate leaf), so the new app (`app.racky.mac`)
  cannot attach to a still-busy old daemon; those terminals keep running there until they end and appear as interrupted in the new
  app. That is why the check uses the process tree instead of asking the daemon, and why a busy daemon is never killed. Tested with
  fakes (`LegacyDaemonRetirementTests`); nothing in the tests calls `launchctl`.
- **Keychain.** Vault master key: `MigratingMasterKeyBackend` reads `app.racky.vault`; if absent it reads `app.agentbox.vault` and
  writes the value to the new item (the old item is kept so the update can be undone; deleting the key deletes both). Without this the
  vault would create a new key and lose every stored secret. The new signing identity may show one Keychain prompt on first read.
  The importer's reader of the pre-rebuild app keychain (`com.agentbox.secret.v1`) is unchanged on purpose.
- **UserDefaults.** `LegacyDefaultsMigration` copies the old domain (`app.agentbox.mac`: saved window frame etc.) into the new one once
  (new values win, the old domain is not modified). Skipped under `RACKY_HOME`.
- **Env vars.** `LegacyEnvironment.promoteProcessEnvironment()` runs first in the app, `rackyd` and the `racky` helper: every
  `AGENTBOX_X`/`AGENT_BOX_X` that has no `RACKY_X` becomes `RACKY_X` (`setenv`), so code, children and hook helpers started from an old
  session just work. `rackyd-launch` (C) falls back to `AGENTBOX_HOME`. Scripts use the new names. `AB_UPDATE_GOLDEN` and
  `AB_RECORD_SNAPSHOTS` were renamed outright (test-only).
- **Docker.** New containers/volumes carry `racky.*` labels (owner `racky` or `racky-<hash>` for isolated apps) and run
  `racky-computer` images with `/run/racky`. `RackyLabel.legacyKey/legacyOwner/legacyFilter/value/isOwned` translate to the old
  `agentbox.*` labels and owner (`agent-box`, `agent-box-<hash>`). `GarbageCollector.inventory` queries both namespaces and merges,
  so reaping, `removeComputer` and orphan confirmation also see old containers/networks/volumes. `liveComputers()` (adoption) and the
  Insights source list both; `adopt` reads token and egress policy from `/run/racky` and falls back to `/run/agentbox`. Old images
  are not touched; the first reserve builds the new image. The cloud dead-man script counts both `racky.computer` and
  `agentbox.computer` containers, so a host that still runs old containers is not shut down by mistake (a cloud host created by an old
  build keeps its old script and should be recreated).
- **Agent-facing names.** MCP server `racky`, tool prefix `racky_`, workers `racky-worker-N`, plugin `racky-app`, skills
  `racky-boxes`/`racky-session`, hook command `.../Contents/Helpers/racky hook`. The deny rule `Skill(agentbox)` and the prompt text
  that tells agents not to use the "agentbox" CLI skill still name the old thing on purpose: they target the user's own global skill,
  which still has that name. `GlobalConfigScanner` still detects a global `agentbox` skill/MCP server/hooks for the same reason.
  Agent sessions started by the old app keep hook commands that point to the removed `Contents/MacOS/agentbox`; those hooks fail
  silently (non blocking) until the session is restarted.
- **SQLite.** `import_run.source` has a CHECK constraint with `agentbox_json`/`agentbox_cli` in existing databases, so those stored
  values stay as they are (the Swift cases are `rackyJSON`/`rackyCLI`).

## Remaining occurrences of the old name (final sweep)

`git grep -iE "agent.?box"` returns only these, each intentional:

| Where | Why it stays |
|---|---|
| `Packages/RackyKit/Sources/RackyProtocol/Legacy/LegacyNames.swift`, `LegacyEnvironment.swift` | The single registry of old names used by the migrations. |
| `Packages/RackyKit/Tests/ProtocolTests/LegacyMigrationTests.swift` | Tests of the data-folder and env-var migrations. |
| `Sources/RackyDocker/Labels.swift`, `RackyCore/Computers/Orchestration/DockerComputerProvisioning.swift`, `RackyCore/Insights/InsightsSources.swift`, `Tests/DockerTests/GarbageCollectorTests.swift` | Old-label/owner/in-container-path recognition (comments, `legacy*` helpers and their tests, JSON fixtures of old containers). |
| `Sources/RackyStore/Schema.swift`, `RackyStore+Import.swift`, `RackyStore+Catalog.swift` | Stored SQLite values (`agentbox_json`, `agentbox_cli`) bound by an existing CHECK constraint. |
| `Sources/RackyCore/Settings/LegacyDefaultFolders.swift`, `Tests/CoreTests/Settings/LegacyDefaultFoldersTests.swift` | Keeps `~/AgentBox/...` default folders for existing installs. |
| `Sources/racky/RackyCLI.swift`, `Sources/rackyd/RackyD.swift`, `Sources/rackyd-launch/main.c` | Comments and the C fallback for inherited `AGENTBOX_*` variables. |
| `Tests/CoreTests/Computers/Orchestration/OrchestrationTests.swift`, `SubagentComputersTests.swift`, `Tests/CoreTests/Launch/Golden/slice3/codex/subagent-computers.golden`, `Tests/CoreTests/Diagnostics/*`, `Tests/UISnapshotTests/OnboardingDiagnosticsTests.swift`, `Tests/CoreTests/Import/LegacyImporterTests.swift`, `Tests/CoreTests/Computers/LegacyCLIEnvFileTests.swift` | Tests of the deliberate old-name behaviour (global `agentbox` skill deny/detect/backup, old CLI `.env`, old import values). |
| `runtime/cloud/racky-host.cloud-init.yaml` | Generated reference of the dead-man script that also counts `agentbox.computer` containers (matches `DeadManPolicy`). |
| `scripts/install.sh` | First-upgrade handling: old data folder path and old bundle id used to quit the running old app. |
| `docs/rebuild/rename-racky.md` (this file) | The ledger. |
| `docs/rebuild/spec/05-journeys-and-acceptance.md` | Name of the real GitHub test repo `gabrielgreco1/agentbox-e2e` (repo is not renamed). |
| `legacy/design/docs/spec.html`, `legacy/scripts/build_spec.py`, `docs/spec/index.html` | Links to the external skills repo path `.../skills/tree/<sha>/agentbox` (a real URL). |
| `docs/rebuild/HANDOFF.md`, `docs/rebuild/audit/04-orca-reference.md`, `docs/spec/index.html`, `docs/evidence/**` (39 files) | Absolute paths of the owner's real checkout and of worktrees (`/Users/gabriel/orca/agent-box/...`, `.../orca/workspaces/agent-box/...`, session scratchpad dirs). They are paths on disk, not the product name; the GitHub repo and the checkout are not renamed here. |
