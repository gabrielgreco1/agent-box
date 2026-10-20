#!/bin/bash
# Variante assinada com certificado efemero (keychain temporario, sem confianca de usuario): LWCR e respawn apos rebuild.
set -uo pipefail
export SUF="${SUF:-sc1}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
S="$(cd "$(dirname "$0")" && pwd)"
APP="$S/ABS01.app"
REPO=/Users/gabriel/orca/agent-box/.claude/worktrees/agent-a59f55fca5dd2120b
ORIG_LIST="$(security list-keychains -d user | tr -d '"')"
export TMPDIR="$S/"
OUT="$("$REPO/scripts/make-dev-cert.sh" --ephemeral)"
KC="$(sed -n 's/^RACKY_EPHEMERAL_KEYCHAIN=//p' <<<"$OUT")"
SHA="$(tail -1 <<<"$OUT")"
echo "keychain=$KC sha=$SHA"
cleanup() {
  open -W -g -n --stdout /tmp/s01-out2.txt --stderr /tmp/s01-out2.txt "$APP" --args unregister
  security delete-keychain "$KC"
  security list-keychains -d user -s $ORIG_LIST
  echo "cleanup done; keychains:"; security list-keychains -d user
}
trap cleanup EXIT
signit() {
  [ "${ADHOC:-0}" = 1 ] && return 0
  codesign --force --options runtime --timestamp=none --sign "Racky Local Signing" --keychain "$KC" --identifier app.racky.ptyd \
    -r="designated => identifier \"app.racky.ptyd\" and certificate leaf = H\"$SHA\"" "$APP/Contents/MacOS/s01d"
  codesign --force --options runtime --timestamp=none --sign "Racky Local Signing" --keychain "$KC" --identifier app.racky.s01test$SUF \
    -r="designated => identifier \"app.racky.s01test$SUF\" and certificate leaf = H\"$SHA\"" "$APP"
}
bash "$S/build.sh" >/dev/null 2>&1; signit 2>&1 | tail -1
rm -f /tmp/s01-out.txt
open -W -g -n --stdout /tmp/s01-out.txt --stderr /tmp/s01-out.txt "$APP" --args register; cat /tmp/s01-out.txt
launchctl print gui/501/app.racky.ptyd.test-s01$SUF | grep -E -A12 "LWCR"
launchctl print gui/501/app.racky.ptyd.test-s01$SUF | grep -E "^	state|properties|job state"
SOCK="$(launchctl getenv RACKY_PTYD_SOCK_V1)"; echo "sock=$SOCK"
(echo one | nc -U "$SOCK" & P=$!; for i in 1 2 3 4 5 6; do kill -0 $P 2>/dev/null || break; sleep 1; done; kill $P 2>/dev/null)
# rebuild com binario diferente, mesma identidade
sed -i "" "s/start v[0-9]* argv/start v$RANDOM argv/" "$S/daemon.swift"
bash "$S/build.sh" >/dev/null 2>&1; signit 2>&1 | tail -1
echo "--- apos rebuild (mesma identidade), daemon antigo ainda vivo:"
launchctl print gui/501/app.racky.ptyd.test-s01$SUF | grep -E "^	state|properties|job state|runs ="
echo "--- aguardando daemon sair por ociosidade"
for i in $(seq 1 40); do launchctl print gui/501/app.racky.ptyd.test-s01$SUF | grep -q "^	state = running" || break; sleep 1; done
echo two | nc -U "$SOCK" &
NCPID=$!
for i in $(seq 1 10); do kill -0 $NCPID 2>/dev/null || break; sleep 1; done
kill $NCPID 2>/dev/null
launchctl print gui/501/app.racky.ptyd.test-s01$SUF | grep -E "^	state|properties|job state|runs =|last exit"
grep -E "start v" /tmp/s01-daemon.log | cut -c1-60
source "$S/extra.sh"
