# T2-10 legacy JSON importer dry-run (real data, read-only)

Only counts. The database used was a throwaway temporary store.

## Files

| File | Result |
|---|---|
| `workspace.json` | imported |
| `library.json` | absent |
| `AgentRuns.json` | imported |
| `computer-policy.json` | absent |
| `docker-connection.json` | imported |
| `secret-references.json` | absent |
| `secrets.json` | absent |
| `browser-computers.json` | absent |
| `ControlBroker.json` | absent |
| `human-requests.json` | absent |
| `agent-launch-bindings.json` | absent |
| `scraping-box-assignments.json` | absent |
| `directory-bookmarks.json` | absent |
| `image-update.json` | absent |

## Counts

- agentRuns.new: 1
- sessions.new: 1
- settings.new: 1
- tabs.new: 1
- terminals.new: 1
- unknownFields: 0

## Source integrity

- source hash before: `3fcb4781b24fdb99424b1afd0270748cff7623365c22c69a342085d9c1b6fbf2`
- source hash after:  `3fcb4781b24fdb99424b1afd0270748cff7623365c22c69a342085d9c1b6fbf2`
- unchanged: true
- copy directory created by dry-run: none
