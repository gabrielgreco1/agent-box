#!/bin/bash
# Variantes do ciclo: REBUILD=alive|exited (rebuild com o daemon vivo ou depois que ele saiu), PROBE=0|1 (conectar antes do re-registro).
set -uo pipefail
export SUF="${SUF:-rv1}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
S="$(cd "$(dirname "$0")" && pwd)"
APP="$S/ABS01.app"
LABEL="app.racky.ptyd.test-s01$SUF"
run() { rm -f /tmp/s01-rr-out.txt; open -W -g -n --stdout /tmp/s01-rr-out.txt --stderr /tmp/s01-rr-out.txt "$APP" --args "$1" >/dev/null 2>&1; cat /tmp/s01-rr-out.txt | tr '\n' ' '; echo; }
conn() { (echo "$1" | nc -U "$(launchctl getenv RACKY_PTYD_SOCK_V1)" & P=$!; for i in 1 2 3 4 5 6; do kill -0 $P 2>/dev/null || break; sleep 1; done; kill $P 2>/dev/null); }
waitexit() { for i in $(seq 1 40); do launchctl print gui/501/$LABEL | grep -q "^	state = running" || break; sleep 1; done; }
st() { launchctl print gui/501/$LABEL | grep -E "^	state|job state|properties" | tr '\n' ' '; echo; }
rm -f /tmp/s01-daemon.log
bash "$S/build.sh" >/dev/null 2>&1
run register
conn first
sed -i "" "s/start v[0-9]* argv/start v$RANDOM argv/" "$S/daemon.swift"
export BV="${BUMP:-1}"
if [ "${REBUILD:-alive}" = alive ]; then bash "$S/build.sh" >/dev/null 2>&1; waitexit; else waitexit; bash "$S/build.sh" >/dev/null 2>&1; fi
echo "--- apos rebuild+saida:"; st; codesign -dvvv "$APP/Contents/MacOS/s01d" 2>&1 | grep -E "CDHash" 
if [ "${PROBE:-0}" = 1 ]; then conn probe; echo "--- apos sonda:"; st; fi
if [ "${NOREREG:-0}" != 1 ]; then sleep ${SETTLE:-0}; run unregister; run register; fi
conn after
echo "--- final:"; st
grep "start v" /tmp/s01-daemon.log | cut -c1-60
run unregister >/dev/null
