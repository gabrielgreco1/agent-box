#!/usr/bin/env bash
# Smoke do app real: onboarding aberto -> Done -> estado de foco.
ROOT=/Users/gabriel/orca/agent-box/.claude/worktrees/agent-a7af4e68d6743ce91
APP="$ROOT/build/Racky/Racky.app"
BIN="$APP/Contents/MacOS/racky"
H=/tmp/abfix1
SOCK=$H/run/app.sock
rm -rf $H; mkdir -p $H/run
open -g -n "$APP" --env RACKY_AUTOMATION=1 --env RACKY_HOME=$H --env RACKY_APP_SOCK=$SOCK
PID=""
for i in $(seq 1 60); do
  PID=$(lsof -U 2>/dev/null | awk -v s="$SOCK" '$0 ~ s {print $2; exit}')
  [ -n "$PID" ] && "$BIN" ctl state --sock $SOCK >/dev/null 2>&1 && break
  sleep 0.3
done
echo "pid $PID"; echo $PID > /tmp/abfix1.pid
show() { "$BIN" ctl state --sock $SOCK | python3 -c "import json,sys; d=json.load(sys.stdin); d=d.get('state',d); print({k:d.get(k) for k in ['firstResponder','blocksTerminalInput']})"; }
sleep 2; echo "-- onboarding open"; show
"$BIN" ctl ui action onboarding.done --sock $SOCK; sleep 1
echo "-- after Done"; show
"$BIN" ctl ui action session.new --sock $SOCK 2>&1 | head -3; sleep 2
echo "-- after new session"; show
kill $PID
