#!/usr/bin/env bash
# compare-ui.sh - comparação visual mecânica com o Orca (08 AR-808, P14). Implementado em T1-02.
#
# Contrato
#   Entrada : <tela> (screenId de 03 §0, também passado ao app como AGENTBOX_SCREEN = fixture da tela).
#             Referência: --reference <png> ou docs/rebuild/reference/orca-1.4.219/screens/<tela>-<W>x<H>.png (depois <tela>.png).
#   Efeitos : usa 'agentbox ctl screenshot --size' (ScreenCaptureKit da própria janela) em cada tamanho e grava em
#             docs/evidence/ui/<tarefa>/ (ou --out): <tela>-<WxH>-app.png, -side-by-side.png (referência | Agent Box),
#             -overlay50.png (sobreposição 50%), -diff.png (diferença absoluta) e -metrics.json. Tamanhos padrão:
#             1440x900 e 760x480. Se o app não estiver rodando com o canal ctl, abre o .app (em segundo plano, sem ativar)
#             com AGENTBOX_AUTOMATION=1 num socket privado e o fecha ao terminar.
#   Saída   : exit 0 em sucesso; exit 1 em falha (sem referência, sem app, captura falhou); exit 2 uso inválido.
#   Gate    : a comparação NÃO aprova nada sozinha; a tarefa visual só fecha com o OK do dono (P14/P19).
# Uso: scripts/compare-ui.sh <tela> [--task <id>] [--reference <png>] [--sizes 1440x900,760x480] [--app <Agent Box.app>]
#                            [--bin <agentbox>] [--out <dir>] [--help]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
fail() { echo "ERRO: $*" >&2; exit 1; }

SCREEN=""; TASK="adhoc"; REF=""; SIZES="1440x900,760x480"; APP="${AGENTBOX_APP:-$ROOT/build/AgentBox/Agent Box.app}"
BIN="${AGENTBOX_BIN:-}"; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --task) TASK="${2:?}"; shift 2 ;;
    --reference) REF="${2:?}"; shift 2 ;;
    --sizes) SIZES="${2:?}"; shift 2 ;;
    --app) APP="${2:?}"; shift 2 ;;
    --bin) BIN="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    -*) usage >&2; exit 2 ;;
    *) [ -z "$SCREEN" ] || { usage >&2; exit 2; }; SCREEN="$1"; shift ;;
  esac
done
[ -n "$SCREEN" ] || { usage >&2; exit 2; }
case "$SCREEN" in *[!A-Za-z0-9._-]*) echo "ERRO: <tela> só aceita letras, números, ponto, '_' e '-'" >&2; exit 2 ;; esac
OUT="${OUT:-$ROOT/docs/evidence/ui/$TASK}"
mkdir -p "$OUT"

# Binário agentbox: --bin, $AGENTBOX_BIN, dentro do .app, ou build de desenvolvimento.
if [ -z "$BIN" ]; then
  for c in "$APP/Contents/MacOS/agentbox" "$ROOT/Packages/AgentBoxKit/.build/debug/agentbox" "$ROOT/Packages/AgentBoxKit/.build/release/agentbox"; do
    [ -x "$c" ] && { BIN="$c"; break; }
  done
fi
[ -n "$BIN" ] && [ -x "$BIN" ] || fail "binário agentbox não encontrado (rode scripts/build.sh ou passe --bin)"

# App: usa o que já roda com ctl (AGENTBOX_APP_SOCK ou padrão); senão abre o .app com socket privado.
LAUNCHED_PID=""; PRIVATE_DIR=""
cleanup() {
  if [ -n "$LAUNCHED_PID" ]; then kill "$LAUNCHED_PID" 2>/dev/null || true; fi
  if [ -n "$PRIVATE_DIR" ]; then rm -rf "$PRIVATE_DIR"; fi
}
trap cleanup EXIT

if ! "$BIN" ctl state >/dev/null 2>&1; then
  [ -d "$APP" ] || fail "app não está rodando com ctl e '$APP' não existe (rode scripts/build.sh ou passe --app)"
  PRIVATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/abx-cmp.XXXXXX")"
  export AGENTBOX_APP_SOCK="$PRIVATE_DIR/app.sock"
  # -g: não traz para frente; -j: abre oculto; -n: instância nova (não mexe numa já aberta pelo usuário).
  open -g -j -n --env AGENTBOX_AUTOMATION=1 --env AGENTBOX_SCREEN="$SCREEN" --env "AGENTBOX_APP_SOCK=$AGENTBOX_APP_SOCK" "$APP" \
    || fail "falha ao abrir $APP"
  for _ in $(seq 1 100); do
    "$BIN" ctl state >/dev/null 2>&1 && break
    /bin/sleep 0.2
  done
  STATE="$("$BIN" ctl state 2>/dev/null)" || fail "o app não respondeu no ctl em 20 s"
  LAUNCHED_PID="$(printf '%s' "$STATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"]["pid"])')"
fi

"$BIN" ctl ui wait window.main --timeout 15 >/dev/null || fail "window.main não apareceu"

find_ref() { # W H
  local d="$ROOT/docs/rebuild/reference/orca-1.4.219/screens"
  if [ -n "$REF" ]; then echo "$REF"; return; fi
  for c in "$d/$SCREEN-$1x$2.png" "$d/$SCREEN.png"; do [ -f "$c" ] && { echo "$c"; return; }; done
  return 1
}

STATUS=0
printf '%-12s %-8s %-10s %-10s %s\n' tela tamanho mean-diff px-diff arquivos
IFS=',' read -ra SZ <<< "$SIZES"
for size in "${SZ[@]}"; do
  W="${size%x*}"; H="${size#*x}"
  case "$W$H" in ''|*[!0-9]*) fail "tamanho inválido: $size" ;; esac
  APP_PNG="$OUT/$SCREEN-$size-app.png"
  "$BIN" ctl screenshot --window --size "$size" --out "$APP_PNG" > "$OUT/$SCREEN-$size-screenshot.json" \
    || fail "ctl screenshot falhou em $size (veja $OUT/$SCREEN-$size-screenshot.json; Gravação de Tela concedida?)"
  REF_PNG="$(find_ref "$W" "$H")" || fail "referência ausente para '$SCREEN' em $size em docs/rebuild/reference/orca-1.4.219/screens/ (use --reference)"
  "$BIN" ctl compare "$APP_PNG" "$REF_PNG" --out-dir "$OUT" --name "$SCREEN-$size" > "$OUT/$SCREEN-$size-metrics.json" \
    || fail "comparação falhou em $size"
  python3 - "$OUT/$SCREEN-$size-metrics.json" "$SCREEN" "$size" "$REF_PNG" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print("%-12s %-8s %-10.4f %-10.4f ref=%s%s" % (sys.argv[2], sys.argv[3], m["meanAbsoluteDifference"], m["differingPixelFraction"],
      sys.argv[4], " (referência reescalada" + (", proporção diferente" if m["aspectRatioMismatch"] else "") + ")" if m["referenceScaled"] else ""))
PY
done
echo "compare-ui: arquivos em ${OUT#"$ROOT"/}"
exit $STATUS
