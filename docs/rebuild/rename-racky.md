# Rename: AgentBox -> Racky

Owner request: "limpar esse nome [agentbox] 100% de tudo". The product is Racky. This file is the plan and, at the end,
the ledger of every intentional leftover. It is the only doc that is allowed to say the old name.

Mapping applied mechanically (content and paths, case-aware):

| Old | New |
|---|---|
| `AGENTBOX_*`, `AGENT_BOX_*` | `RACKY_*` |
| `AgentBox*` (types, modules, targets, package) | `Racky*` (`AgentBoxKit` -> `RackyKit`) |
| `Agent Box`, `Agent-Box` | `Racky` |
| `agentbox`, `agent-box` | `racky` |
| `agentboxd`, `agentboxd-launch` | `rackyd`, `rackyd-launch` |
| `app.agentbox.*` | `app.racky.*` |

Protected from the mechanical pass (real external things that this change must not break): the owner's checkout paths
(`/Users/gabriel/orca/agent-box/...`, `/Users/gabriel/orca/workspaces/agent-box/...`, scratchpad paths derived from them),
the GitHub test repo `gabrielgreco1/agentbox-e2e` and the external skills repo path `.../skills/tree/<sha>/agentbox`.

## Groups

1. **User-visible defaults**: window/menu titles, `~/AgentBox/{worktrees,sessions,projects,runs}` default folders, `TERM_PROGRAM`,
   app name in docs and README, build dir `build/AgentBox` -> `build/Racky`.
2. **Code identifiers**: SPM package `Packages/AgentBoxKit` -> `Packages/RackyKit`; modules
   `AgentBox{Core,UI,Protocol,Platform,Store,Docker,DesignSystem,TerminalCore,ViewerKit,Bench,MCP}`; test targets; executables
   `agentbox` -> `racky` (embedded in `Contents/Helpers/racky`, because `Contents/MacOS/racky` would collide with the app
   executable `Racky` on a case-insensitive volume), `agentboxd` -> `rackyd`, `agentboxd-launch` -> `rackyd-launch`;
   python packages `agentbox_{runtime,egress,supervisor}` -> `racky_*`; `project.yml`; `scripts/*`; `App/AgentBox.icns`; the plist file.
3. **Ids that persist on users' machines** (need migration code, see "Migration design"): data folder, default user folders,
   bundle id, launchd label, keychain services, UserDefaults, env vars, Docker image/labels/owner, MCP server name/tool prefix,
   plugin/skill names, HTTP header names.
4. **Docs**: README, `docs/**` (including `docs/evidence/**`, which keeps its content readable but with the new name), `legacy/**`, `design/**`.

## Phases

1. Docs and README. 2. Code identifiers (mechanical rename + `git mv`). 3. Persistent ids with migration code and tests.
4. Final sweep and the leftover ledger below.

(Migration design and the leftover ledger are filled in as the phases land.)
