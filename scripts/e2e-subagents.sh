#!/usr/bin/env bash
# e2e-subagents.sh - "Subagent computers" com Codex ou OpenCode como pai, de ponta a ponta (app construído, daemon, Docker reais).
#
# Contrato
#   Entrada : Docker rodando, o CLI do agente instalado e logado, um Racky.app construído (AGENTBOX_E2E_APP, padrão build/mp/Racky.app).
#             O app é COPIADO para /tmp/abmp-XXXXXX e abre com AGENTBOX_HOME temporário (outro dono de containers, outro socket, sem tocar no
#             launchd nem no app instalado). Nada é escrito em ~/.codex, ~/.config/opencode ou ~/.claude: tudo entra por lançamento.
#   Passos  : projeto + perfil com o modelo pedido, sessão pelo composer (Subagent computers = full), prompt "um subagente com computador
#             próprio abre https://example.com e envia o título com result_submit"; espera o computador ser reservado, reivindicado pelo
#             worker, o resultado validado e o container removido.
#   --mock  : (Codex) troca o modelo por um servidor local roteirizado (scripts/e2e/mock_codex.py) e isola CODEX_HOME: valida o caminho
#             inteiro sem gastar uso do Codex.
#   Saída   : exit 0 só se todas as checagens passaram. Evidência em docs/evidence/subagents-multi-provider/<provider>-<rótulo>/.
# Uso: scripts/e2e-subagents.sh codex|opencode --model <id> [--label x] [--mock] [--timeout s] [--effort low]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROVIDER="${1:-}"; shift || true
MODEL=""; LABEL="run"; MOCK=0; TIMEOUT=420; EFFORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --mock) MOCK=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    *) sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 64 ;;
  esac
done
case "$PROVIDER" in codex) BASE_PROFILE=A0000000-0000-4000-8000-000000000003 ;; opencode) BASE_PROFILE=A0000000-0000-4000-8000-000000000004 ;; *) echo "uso: $0 codex|opencode --model <id>" >&2; exit 64 ;; esac
[ -n "$MODEL" ] || { echo "ERRO: --model é obrigatório" >&2; exit 64; }
for t in jq python3 sqlite3 docker ditto codesign open; do command -v "$t" >/dev/null 2>&1 || { echo "ERRO: falta '$t'" >&2; exit 2; }; done

APP_SRC="${AGENTBOX_E2E_APP:-$ROOT/build/mp/Racky.app}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/docs/evidence/subagents-multi-provider/$PROVIDER-$LABEL}"
mkdir -p "$EVIDENCE_DIR"
WORK="$(mktemp -d /tmp/abmp-XXXXXX)" || exit 2
HOME_T="$WORK/h"; SOCK="$WORK/app.sock"; APP="$WORK/install/Racky.app"; MACOS="$APP/Contents/MacOS"; REPO="$WORK/repo"; DB="$HOME_T/db/agentbox.sqlite"
mkdir -p "$HOME_T" "$WORK/install" "$REPO" "$WORK/chome"; chmod 700 "$HOME_T"
REPORT="$EVIDENCE_DIR/report.txt"; : > "$REPORT"
FAILS=0; MOCK_PID=""
say() { echo "$*" | tee -a "$REPORT"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then say "  PASS  $d"; else say "  FAIL  $d"; FAILS=$((FAILS + 1)); fi; }
ctl() { "$MACOS/agentbox" ctl "$@" --sock "$SOCK"; }
act() { ctl ui action "$@"; }
act_ok() { act "$@" 2>/dev/null | jq -e '.ok == true' >/dev/null 2>&1; }
db() { sqlite3 -cmd ".timeout 5000" "$DB" "$1" 2>/dev/null; }
wait_for() { local t="$1"; shift; local i=0; while ! "$@" >/dev/null 2>&1; do i=$((i + 1)); [ "$i" -lt $((t * 2)) ] || return 1; sleep 0.5; done; }
tree_has() { ctl ui tree 2>/dev/null | jq -e --arg id "$1" '[.. | objects | select(.id == $id)] | length > 0' >/dev/null 2>&1; }
term_screen() { act terminal.screen select "$1" 2>/dev/null | jq -r '.action.message // empty'; }
term_send() { act terminal.sendText set "$(jq -cn --arg t "$1" --arg x "$2" '{terminal:$t,text:$x}')" >/dev/null 2>&1; }
app_pid() { pgrep -f "$(basename "$WORK")/install/Racky.app/Contents/MacOS/Racky" | head -1; }
OWNER="agent-box-$(python3 -I - "$HOME_T" <<'PY'
import sys
h = 2166136261
for b in sys.argv[1].encode():
    h = ((h ^ b) * 16777619) & 0xFFFFFFFF
print("%08x" % h)
PY
)"
mine_ids() { docker ps -a -q --filter "label=agentbox.owner=$OWNER"; }
owner_snapshot() {
  echo "app instalado:"; pgrep -fl "/Applications/Racky.app/Contents/MacOS" | sed -E "s/^[0-9]+ //" | sort -u
  echo "job do launchd:"; launchctl print "gui/$(id -u)/app.agentbox.ptyd.v1" 2>/dev/null | grep -E "^\s(state|program) = " | sort
  echo "containers do dono:"; docker ps -a -q --filter "label=agentbox.owner=agent-box" | sort
  echo "arquivos globais:"; for f in "$HOME/.codex/config.toml" "$HOME/.codex/hooks.json" "$HOME/.config/opencode/opencode.json" "$HOME/.config/opencode/opencode.jsonc" "$HOME/.claude/settings.json"; do [ -e "$f" ] && stat -f '%N %m %z' "$f"; done
}

cleanup() {
  local rc=$?
  say; say "--- limpeza"
  if [ -S "$SOCK" ]; then ctl ui action app.quitCompletely >/dev/null 2>&1; sleep 2; fi
  local pid; pid="$(app_pid)"; [ -z "$pid" ] || { kill "$pid" 2>/dev/null; sleep 1; }
  for pid in $(pgrep -f "agentboxd .*--home $HOME_T"); do kill "$pid" 2>/dev/null; done
  sleep 1
  for pid in $(pgrep -f "$(basename "$WORK")/install/Racky.app"; pgrep -f "agentboxd .*--home $HOME_T"); do kill -9 "$pid" 2>/dev/null; done
  [ -z "$MOCK_PID" ] || { cp "$WORK/mock.out" "$EVIDENCE_DIR/mock.out" 2>/dev/null; kill "$MOCK_PID" 2>/dev/null; }
  local ids vols; ids="$(mine_ids)"
  [ -z "$ids" ] || { say "removendo containers do teste: $(echo $ids)"; docker rm -f $ids >/dev/null 2>&1; }
  vols="$(for id in $(db "SELECT lower(id) FROM computer;"); do docker volume ls -q --filter "name=ab-prof-$id"; done)"
  [ -z "$vols" ] || { say "removendo volumes do teste: $(echo $vols)"; docker volume rm $vols >/dev/null 2>&1; }
  say "sobrou do teste no Docker: containers=$(mine_ids | wc -l | tr -d ' ')"
  if [ -f "$EVIDENCE_DIR/owner-before.txt" ]; then
    owner_snapshot > "$EVIDENCE_DIR/owner-after.txt" 2>&1
    if diff -q "$EVIDENCE_DIR/owner-before.txt" "$EVIDENCE_DIR/owner-after.txt" >/dev/null; then say "o que é do dono segue idêntico (app, launchd, containers, configs globais)"
    else say "AVISO: o snapshot do dono mudou (o dono pode ter feito algo durante a execução):"; diff "$EVIDENCE_DIR/owner-before.txt" "$EVIDENCE_DIR/owner-after.txt" | tee -a "$REPORT"; fi
  fi
  rm -rf "$WORK"
  say "RESULTADO: $([ "$FAILS" -eq 0 ] && [ "$rc" -eq 0 ] && echo OK || echo "$FAILS falha(s)") (evidência: $EVIDENCE_DIR)"
  [ "$FAILS" -eq 0 ] && [ "$rc" -eq 0 ]
}
trap cleanup EXIT
trap 'exit 130' INT TERM

say "e2e-subagents $(date -u +%Y-%m-%dT%H:%M:%SZ) provider=$PROVIDER model=$MODEL mock=$MOCK work=$WORK owner=$OWNER"
docker info >/dev/null 2>&1 || { say "ERRO: Docker não está rodando"; exit 2; }
[ -d "$APP_SRC" ] || { say "ERRO: app não encontrado em $APP_SRC"; exit 2; }
owner_snapshot > "$EVIDENCE_DIR/owner-before.txt" 2>&1

# --- app isolado ---
ditto "$APP_SRC" "$APP" || exit 2
open -g -n --env "AGENTBOX_HOME=$HOME_T" --env "AGENTBOX_APP_SOCK=$SOCK" --env AGENTBOX_AUTOMATION=1 --env AGENTBOX_SKIP_ONBOARDING=1 "$APP"
wait_for 40 sh -c "[ -S '$SOCK' ] && '$MACOS/agentbox' ctl state --sock '$SOCK' >/dev/null 2>&1" || { say "ERRO: o app de teste não subiu"; exit 2; }
sleep 2
check "app de teste isolado (dados em $HOME_T, owner $OWNER, não é o do dono)" test "$OWNER" != "agent-box" -a -n "$(app_pid)"
ctl state > "$EVIDENCE_DIR/state.json" 2>&1

# --- projeto e perfil ---
( cd "$REPO" && git init -q && echo "e2e repo" > README.md && git add . && git -c user.email=e2e@agentbox.local -c user.name=e2e commit -qm init ) || exit 2
act_ok project.add set "$REPO" || { say "ERRO: project.add"; exit 2; }
wait_for 15 sh -c "[ -n \"\$(sqlite3 '$DB' 'SELECT id FROM session LIMIT 1')\" ]" || exit 2
PROFILE="$(act settings.agents.profileDuplicate select "$BASE_PROFILE" | jq -r '.action.message // empty')"
[ -n "$PROFILE" ] || { say "ERRO: perfil não duplicado"; exit 2; }
act_ok settings.agents.profileModel set "$MODEL" || { say "ERRO: modelo"; exit 2; }
act_ok settings.agents.profileName set "$PROVIDER e2e $MODEL" || true
if [ "$PROVIDER" = codex ] && [ -n "$EFFORT" ]; then db "UPDATE launch_profile SET effort='$EFFORT' WHERE id='$PROFILE';"; fi
if [ "$MOCK" = 1 ]; then
  [ "$PROVIDER" = codex ] || { say "ERRO: --mock só existe para codex"; exit 64; }
  MOCK_PORT=$((20000 + RANDOM % 20000))
  python3 "$ROOT/scripts/e2e/mock_codex.py" "$MOCK_PORT" "$EVIDENCE_DIR/mock-requests.log" > "$WORK/mock.out" 2>&1 & MOCK_PID=$!
  sleep 1
  ARGS="$(jq -cn --arg p "http://127.0.0.1:$MOCK_PORT/v1" '["-c","model_provider=\"mock\"","-c",("model_providers.mock={name=\"mock\",base_url=\"" + $p + "\",wire_api=\"responses\",requires_openai_auth=false}")]')"
  db "UPDATE launch_profile SET extra_args_json='$(echo "$ARGS" | sed "s/'/''/g")', env_json='{\"CODEX_HOME\":\"$WORK/chome\"}' WHERE id='$PROFILE';"
  sleep 2
fi
db "SELECT id,name,provider,model,effort,permission_mode,extra_args_json,env_json FROM launch_profile WHERE id='$PROFILE';" > "$EVIDENCE_DIR/profile.txt"

# --- sessão pelo composer ---
PROMPT="Spawn one subagent with its own computer. It should open https://example.com and submit the page title with result_submit. When it finishes, tell me the title it submitted."
BEFORE="$(db "SELECT count(*) FROM terminal WHERE provider='$PROVIDER';")"
act_ok session.new && wait_for 10 tree_has overlay.composer || { say "ERRO: composer não abriu"; exit 2; }
act_ok composer.setAgent select "$PROVIDER" || { say "ERRO: setAgent"; exit 2; }
act_ok composer.setWhere select mainCheckout || true
act_ok composer.setProfile select "$PROFILE" || { say "ERRO: setProfile"; exit 2; }
check "composer oferece Subagent computers para $PROVIDER (full aceito)" act_ok composer.setSubagentComputers select full
act_ok composer.setPrompt set "$PROMPT" || true
ctl screenshot --window --out "$EVIDENCE_DIR/composer.png" >/dev/null 2>&1 || true
act_ok composer.submit || { say "ERRO: submit"; exit 2; }
wait_for 30 sh -c "[ \"\$(sqlite3 '$DB' \"SELECT count(*) FROM terminal WHERE provider='$PROVIDER'\")\" -gt '${BEFORE:-0}' ]" || { say "ERRO: terminal não criado"; exit 2; }
TID="$(db "SELECT id FROM terminal WHERE provider='$PROVIDER' ORDER BY created_at DESC LIMIT 1;")"
say "terminal $TID"

# --- espera: reserva, claim, resultado, remoção ---
T0=$SECONDS; : > "$EVIDENCE_DIR/timeline.tsv"; SEEN_COMPUTER=0; DONE=0; SHOTS=0
while [ $((SECONDS - T0)) -lt "$TIMEOUT" ]; do
  if [ -z "$(app_pid)" ]; then say "AVISO: o app de teste morreu aos $((SECONDS - T0)) s (crash?)"; ls -t "$HOME/Library/Logs/DiagnosticReports" | head -3 | tee -a "$REPORT"; break; fi
  screen="$(term_screen "$TID")"
  if [ -z "$screen" ] && [ $((SECONDS - T0)) -gt 30 ] && [ ! -s "$EVIDENCE_DIR/hang-sample.txt" ]; then
    # tela vazia depois de 30 s: o app travou? amostra a pilha para diagnosticar (nada é alterado)
    say "AVISO: terminal.screen vazio aos $((SECONDS - T0)) s; amostrando o app"
    sample "$(app_pid)" 3 -file "$EVIDENCE_DIR/hang-sample.txt" >/dev/null 2>&1
  fi
  # Codex pergunta uma vez se confia na pasta nova.
  if echo "$screen" | grep -Eq "Trust and continue|trust the contents|Do you trust"; then term_send "$TID" $'\r'; fi
  states="$(db "SELECT name||'='||state FROM computer;" | tr '\n' ' ')"
  child="$(db "SELECT id||':'||state||':'||ifnull(computer_name,'') FROM orchestration_child WHERE state<>'idle' ORDER BY slot;" | tr '\n' ' ')"
  printf '%s\t%s\t%s\n' "$((SECONDS - T0))" "$states" "$child" >> "$EVIDENCE_DIR/timeline.tsv"
  [ -z "$states" ] || SEEN_COMPUTER=1
  # o diretório do lançamento some quando o agente sai: copia enquanto ele vive
  if [ ! -d "$EVIDENCE_DIR/launch-dir" ] && [ -n "$(ls "$HOME_T/run/launch" 2>/dev/null)" ]; then cp -R "$HOME_T/run/launch" "$EVIDENCE_DIR/launch-dir" 2>/dev/null; fi
  if [ "$SEEN_COMPUTER" = 1 ] && [ "$(db "SELECT count(*) FROM computer WHERE state<>'removed';")" = 0 ] && [ -z "$(mine_ids)" ]; then DONE=1; break; fi
  if [ $((SECONDS - T0)) -ge $((SHOTS * 60)) ]; then term_screen "$TID" > "$EVIDENCE_DIR/screen-t$((SECONDS - T0)).txt"; SHOTS=$((SHOTS + 1)); fi
  sleep 3
done
say "esperou $((SECONDS - T0)) s (computador visto: $SEEN_COMPUTER, tudo removido: $DONE)"
# o pai ainda precisa responder: dá um tempo para o texto final
sleep 20
term_screen "$TID" > "$EVIDENCE_DIR/final-screen.txt"
ctl screenshot --window --out "$EVIDENCE_DIR/window-end.png" >/dev/null 2>&1 || true
ctl state > "$EVIDENCE_DIR/state-end.json" 2>&1
db "SELECT name,mode,display,state,created_at,removed_at,ownerParent FROM (SELECT name,mode,display,state,created_at,removed_at,'' AS ownerParent FROM computer);" > "$EVIDENCE_DIR/computers.txt"
db "SELECT id,parent_id,slot,agent_type,computer_name,state,claimed_at,released_at FROM orchestration_child WHERE state<>'idle' ORDER BY slot;" > "$EVIDENCE_DIR/orchestration-child.txt"
db "SELECT id,session_id,subagent_computers FROM (SELECT id,id AS session_id,subagent_computers FROM session);" > "$EVIDENCE_DIR/session-mode.txt"
# segredos não vão para a evidência: as capabilities são correlação, mas sai tudo que parece token
find "$EVIDENCE_DIR/launch-dir" -type f 2>/dev/null | while read -r f; do sed -E -i '' 's/--capability(","|\\",\\"| )[0-9a-f]{48}/--capability\1<redacted>/g; s/[0-9a-f]{48}/<token-redacted>/g' "$f"; done
RUNDIR="$(ls -d "$HOME_T"/computers/runs/*/* 2>/dev/null | head -1)"
if [ -n "$RUNDIR" ]; then
  mkdir -p "$EVIDENCE_DIR/results"
  cp "$RUNDIR/work/result.json" "$EVIDENCE_DIR/results/result.json" 2>/dev/null
  cp "$RUNDIR/logs/validation.json" "$EVIDENCE_DIR/results/validation.json" 2>/dev/null
  cp "$RUNDIR/logs/timeline.md" "$EVIDENCE_DIR/results/timeline.md" 2>/dev/null
fi

check "um computador foi reservado pelo pai" test "$SEEN_COMPUTER" = 1
check "um slot de worker reivindicou o computador (orchestration_child.claimed_at preenchido)" test -n "$(db "SELECT id FROM orchestration_child WHERE claimed_at IS NOT NULL LIMIT 1;")"
check "result.json enviado com result_submit contém o título" jq -e '.title | type == "string" and test("Example Domain")' "$EVIDENCE_DIR/results/result.json"
check "resultado validado (verified >= 1, cited_missing = 0)" jq -e '.summary.verified >= 1 and .summary.cited_missing == 0' "$EVIDENCE_DIR/results/validation.json"
check "computador liberado e removido" test "$DONE" = 1
check "nenhum container do teste sobrou" wait_for 60 sh -c "[ -z \"\$(docker ps -a -q --filter label=agentbox.owner=$OWNER)\" ]"
check "o pai mostra o título ao final" grep -q "Example Domain" "$EVIDENCE_DIR/final-screen.txt"
exit 0
