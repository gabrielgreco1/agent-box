#!/usr/bin/env bash
# drive.sh - evidencia visual da T2-04 (atencao e notificacoes).
#
# Contrato
#   Entrada : build/Racky/Racky.app (scripts/build.sh). Nada de notificacao real: RACKY_NOTIFICATIONS=fake.
#   Efeitos : abre o app em segundo plano (open -g) com a automacao, Fatia 2 e um RACKY_HOME isolado, com a fixture
#             `attention-demo` (7 sessoes com terminais de agente de mentira, sem daemon nem processo). Dispara eventos
#             REAIS com `racky hook` (payloads gravados no S-05 e no S-08) e fotografa a janela com `racky ctl screenshot`.
#   Saida   : PNGs, fake-notifications.jsonl e dock-badge.txt em docs/evidence/ui/T2-04/. Encerra o app so por PID.
# Uso: docs/evidence/ui/T2-04/drive.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
OUT="$ROOT/docs/evidence/ui/T2-04"
APP="$ROOT/build/Racky/Racky.app"
BIN="$APP/Contents/MacOS/racky"
H=/tmp/abev24
SOCK="$H/run/app.sock"
SPIKES="$ROOT/docs/evidence/spikes"
rm -rf "$H"; mkdir -p "$H/run"

open -g -n "$APP" --env RACKY_AUTOMATION=1 --env RACKY_SLICE=2 --env RACKY_SKIP_ONBOARDING=1 \
  --env RACKY_HOME="$H" --env RACKY_APP_SOCK="$SOCK" --env RACKY_SCREEN=attention-demo --env RACKY_NOTIFICATIONS=fake
PID=""
for _ in $(seq 1 50); do
  PID="$(lsof -U 2>/dev/null | awk -v s="$SOCK" '$0 ~ s {print $2; exit}' || true)"
  [ -n "$PID" ] && "$BIN" ctl state --sock "$SOCK" >/dev/null 2>&1 && break
  sleep 0.2
done
[ -n "$PID" ] || { echo "app nao subiu" >&2; exit 1; }
trap 'kill "$PID" 2>/dev/null || true' EXIT
echo "app pid $PID"

ctl() { "$BIN" ctl "$@" --sock "$SOCK"; }
shot() { ctl screenshot --window --size "${2:-1440x900}" --out "$OUT/$1.png" >/dev/null; echo "shot $1"; }
act() { ctl ui action "$@" >/dev/null; }

# Eventos reais: payload gravado, correlacao so por env (RACKY_RUN_ID, RACKY_PANE_ID), como o Claude o chamaria.
hook() { # <n> <fixture> <evento[@ocorrencia][>evento-enviado]> [campo=valor ...]
  local n="$1" fixture="$2" spec="$3"; shift 3
  local event="${spec##*>}"; event="${event%@*}"
  local pane run
  pane="$(printf '%08X-0000-4000-8000-A%d0000000000' "$n" "$n")"
  run="$(printf '%08X-0000-4000-8000-B%d0000000000' "$n" "$n")"
  python3 - "$SPIKES/$fixture" "$spec" "$@" <<'PY' | RACKY_APP_SOCK="$SOCK" RACKY_RUN_ID="$run" RACKY_PANE_ID="$pane" "$BIN" hook --provider claude --event "$event" >/dev/null
import json, sys
path, spec, *edits = sys.argv[1:]
source, _, dest = spec.partition(">")
name, _, nth = source.partition("@")
dest = dest or name
events = [e["payload"] for e in json.load(open(path))["events"] if not e["tag"].startswith("project-")]
payload = [p for p in events if p["hook_event_name"] == name][int(nth or 1) - 1]
for edit in edits:
    key, _, value = edit.partition("=")
    if key.startswith("tool_input."):
        payload.setdefault("tool_input", {})[key.split(".", 1)[1]] = value
    elif value == "":
        payload.pop(key, None)
    else:
        payload[key] = value
payload["hook_event_name"] = dest
print(json.dumps(payload))
PY
}
BASIC=S-05/claude-settings-hooks-payloads.json
PERM=S-05/claude-permission-request.json
SUB=S-08/subagent-hook-payloads.json

# 1. Antes dos hooks: todo agente vivo e "Status unavailable".
shot 01-sessions-before-hooks-1440x900

# 2. Settings > Notifications: permissao nao pedida; depois o clique em "Allow" (o centro falso concede).
act app.settings
act settings.openSection select notifications
sleep 0.6
shot 02-settings-notifications-permission-1440x900
act notifications.request
act settings.notifications.terminalBell set on
sleep 0.6
shot 03-settings-notifications-allowed-1440x900
act settings.testNotification
act settings.notifications.terminalBell set off
act settings.back
sleep 0.4

# 3. Eventos reais por `racky hook`.
hook 1 "$PERM" SessionStart; hook 1 "$PERM" UserPromptSubmit
hook 1 "$PERM" PermissionRequest tool_input.command="git push origin fix/pagination" tool_name=Bash
hook 2 "$BASIC" SessionStart; hook 2 "$BASIC" UserPromptSubmit
hook 2 "$BASIC" PreToolUse tool_name=AskUserQuestion tool_input.command="Which table should I use, permits_2024 or permits_v2?"
hook 3 "$BASIC" SessionStart; hook 3 "$BASIC" UserPromptSubmit; hook 3 "$BASIC" PreToolUse tool_name=Bash tool_input.command="pnpm test"
hook 4 "$BASIC" SessionStart; hook 4 "$BASIC" UserPromptSubmit
hook 4 "$BASIC" Stop last_assistant_message="Opened PR #412 with the pagination fix and a regression test for the empty-page case."
hook 5 "$SUB" SessionStart; hook 5 "$SUB" UserPromptSubmit
hook 5 "$SUB" SubagentStart@1; hook 5 "$SUB" SubagentStart@2; hook 5 "$SUB" Stop last_assistant_message="Launched two researchers; waiting for them."
hook 6 "$BASIC" SessionStart; hook 6 "$BASIC" UserPromptSubmit
hook 6 "$BASIC" "Stop>StopFailure" error=rate_limit last_assistant_message=
hook 7 "$BASIC" SessionStart
sleep 1.2

shot 04-cards-states-1440x900
act page.inbox
sleep 0.5
shot 05-inbox-1440x900
act inbox.filter select needsYou
sleep 0.4
shot 06-inbox-needs-you-1440x900
act inbox.filter select all

ctl ui tree --root sidebar.nav.inbox.badge > "$OUT/inbox-badge-tree.json" || true
cp "$H/run/fake-notifications.jsonl" "$OUT/fake-notifications.jsonl"
cp "$H/run/dock-badge.txt" "$OUT/dock-badge.txt"
echo "fake notifications: $(wc -l < "$OUT/fake-notifications.jsonl"), dock badge: '$(cat "$OUT/dock-badge.txt")'"
