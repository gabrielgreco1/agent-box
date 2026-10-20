#!/usr/bin/env bash
# perf-live.sh - medição ao vivo do app Release (T2-11, AC-608/609, AR-704/705): CPU e memória do app e do daemon com 10 sessões ociosas e
# mais 10 com saída alta (`yes`). Só shells: nenhum modelo roda.
#
# Contrato
#   Entrada : <Racky.app já construído por scripts/build.sh> <saída.json> [segundos da carga, padrão 30] [segundos ocioso, padrão 60].
#   Isolamento: copia o app para /tmp/abperf-XXXXXX com RACKY_HOME próprio e `open -g -n` (automação ligada, GitHub desligado); nunca toca
#             no app, no daemon, no launchd nem nos dados do dono. Lê (somente leitura) ~/.claude e ~/.codex como o app faria.
#   Efeitos : espera a primeira varredura do Insights acalmar, mede sem sessões, com 10 ociosas e com +10 de saída alta; ao sair (sempre)
#             encerra só o que subiu e apaga o diretório temporário. `GROWTH=1` mede a RSS a cada sessão aberta.
#   Saída   : JSON com uma linha por cenário (CPU em % de UM núcleo, RSS e pegada em MiB).
# Uso: scripts/perf-live.sh <Racky.app> <saida.json> [segundos] [segundos-ocioso]
set -uo pipefail
SRC="${1:?app}"; OUT="${2:?json}"; SECS="${3:-30}"; IDLE_SECS="${4:-60}"
WORK="$(mktemp -d /tmp/abperf-XXXXXX)"; HOME_T="$WORK/h"; SOCK="$WORK/app.sock"; APP="$WORK/install/Racky.app"; MACOS="$APP/Contents/MacOS"; CWD="$WORK/cwd"
mkdir -p "$HOME_T" "$WORK/install" "$CWD"; chmod 700 "$HOME_T"; ditto "$SRC" "$APP"
ctl() { "$APP/Contents/Helpers/racky" ctl "$@" --sock "$SOCK"; }
act() { ctl ui action "$@"; }
app_pid() { pgrep -f "$(basename "$WORK")/install/Racky.app/Contents/MacOS/Racky" | head -1; }
daemon_pid() { pgrep -f "rackyd .*--home $HOME_T" | head -1; }
cleanup() {
  [ -S "$SOCK" ] && ctl ui action app.quitCompletely >/dev/null 2>&1; sleep 2
  for p in $(pgrep -f "$(basename "$WORK")/install/Racky.app"); do kill "$p" 2>/dev/null; done
  for p in $(pgrep -f "rackyd .*--home $HOME_T"); do kill -9 "$p" 2>/dev/null; done
  # filhos dos shells de teste (yes/sleep) cujo cwd e o nosso
  for p in $(pgrep -f "$WORK" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
  sleep 1; rm -rf "$WORK"
}
trap cleanup EXIT
open -g -n --env "RACKY_HOME=$HOME_T" --env "RACKY_APP_SOCK=$SOCK" --env RACKY_AUTOMATION=1 --env RACKY_SKIP_ONBOARDING=1 --env RACKY_GITHUB=off "$APP"
for i in $(seq 1 60); do [ -S "$SOCK" ] && "$APP/Contents/Helpers/racky" ctl state --sock "$SOCK" >/dev/null 2>&1 && break; sleep 0.5; done
APID="$(app_pid)"; echo "app $APID"
cpu_ms() { # pid -> ms de CPU acumulada (usuario+sistema)
  [ -n "${1:-}" ] || { echo 0; return; }
  ps -o cputime= -p "$1" | awk -F'[:.]' '{ if (NF==3) print ($1*60+$2)*1000+$3*10; else print (($1*3600)+($2*60)+$3)*1000+$4*10 }'; }
fp_mib() { [ -n "${1:-}" ] && footprint "$1" 2>/dev/null | awk '/Footprint:/ {for(i=1;i<=NF;i++) if($i=="Footprint:") {v=$(i+1); u=$(i+2)}; if (u=="GB") v*=1024; else if (u=="KB") v/=1024; printf "%.0f", v; exit}' || echo 0; }
rss_mib() { [ -n "${1:-}" ] && ps -o rss= -p "$1" | awk '{printf "%.1f", $1/1024}' || echo 0; }
sample() { # label segundos
  local label="$1" secs="$2" dpid; dpid="$(daemon_pid)"
  local a0 d0 t0 a1 d1 t1
  a0=$(cpu_ms "$APID"); d0=$(cpu_ms "$dpid"); t0=$(python3 -c 'import time;print(time.time())')
  sleep "$secs"
  a1=$(cpu_ms "$APID"); d1=$(cpu_ms "$dpid"); t1=$(python3 -c 'import time;print(time.time())')
  python3 - "$label" "$a0" "$a1" "$d0" "$d1" "$t0" "$t1" "$(rss_mib "$APID")" "$(rss_mib "$dpid")" "$(fp_mib "$APID")" "$(fp_mib "$dpid")" <<'PY'
import sys, json
l,a0,a1,d0,d1,t0,t1,ar,dr,af,df=sys.argv[1:]
w=(float(t1)-float(t0))*1000
print(json.dumps({"label":l,"appCPUPercentOfOneCore":round((float(a1)-float(a0))/w*100,2),"daemonCPUPercentOfOneCore":round((float(d1)-float(d0))/w*100,2),"appRSSMiB":float(ar),"daemonRSSMiB":float(dr),"appFootprintMiB":float(af or 0),"daemonFootprintMiB":float(df or 0),"windowSeconds":round(w/1000,1)}))
PY
}
launch() { act session.launch set "$(python3 -c 'import json,sys; print(json.dumps({"provider":"custom","argv":["/bin/sh","-c",sys.argv[1]],"cwd":sys.argv[2],"name":sys.argv[3]}))' "$1" "$CWD" "$2")" >/dev/null 2>&1; }
if [ -n "${GROWTH:-}" ]; then
  sleep 5; echo "rss app sem sessoes: $(rss_mib "$APID") MiB"
  for i in $(seq 1 10); do launch "exec sleep 100000" "idle-$i"; sleep 4; echo "sessoes=$i rss app=$(rss_mib "$APID") MiB daemon=$(rss_mib "$(daemon_pid)")"; done
  sleep 10; echo "apos assentar: app=$(rss_mib "$APID") MiB"; sample "growth-idle-10" 20
  exit 0
fi
echo "--- espera a primeira varredura do Insights (ledger vazio, transcripts reais em leitura somente)"
T0=$SECONDS; PEAK=0; QUIET=0
while [ $((SECONDS-T0)) -lt 300 ]; do
  a=$(cpu_ms "$APID"); sleep 3; b=$(cpu_ms "$APID"); r=$(rss_mib "$APID"); r=${r%.*}; [ "${r:-0}" -gt "$PEAK" ] && PEAK=$r
  if [ $(( (b-a)*100/3000 )) -lt 3 ]; then QUIET=$((QUIET+1)); else QUIET=0; fi
  [ "$QUIET" -ge 3 ] && break
done
echo "{\"label\":\"first-scan\",\"settleSeconds\":$((SECONDS-T0)),\"peakRSSMiB\":$PEAK,\"settledFootprintMiB\":$(fp_mib "$APID")}" | tee -a "$OUT.lines"
echo "--- baseline sem sessoes"; sleep 2; sample "baseline-no-sessions" 15 | tee -a "$OUT.lines"
echo "--- 10 sessoes ociosas"
for i in $(seq 1 10); do launch "exec sleep 100000" "idle-$i"; done
sleep 8; sample "10-idle-sessions" "$IDLE_SECS" | tee -a "$OUT.lines"
ctl ui tree 2>/dev/null | python3 -c 'import json,sys;print("tree nodes:",len(json.dumps(json.load(sys.stdin))))'
echo "--- + 10 sessoes com saida alta"
for i in $(seq 1 10); do launch "yes 'the quick brown fox jumps over the lazy dog 0123456789 abcdefghijklmnopqrstuvwxyz'" "flood-$i"; done
sleep 8; sample "10-idle+10-flood-sessions" "$SECS" | tee -a "$OUT.lines"
# a janela segue em 1 sessao visivel; os outros panes estao ocultos
echo "--- encerrando as de saida alta"
python3 - "$OUT" <<'PY'
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1]+".lines")]
json.dump(rows,open(sys.argv[1],"w"),indent=2); print("ok")
PY
rm -f "$OUT.lines"
