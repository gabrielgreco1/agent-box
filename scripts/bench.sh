#!/usr/bin/env bash
# bench.sh - orçamentos de terminal AR-702/703/704 (08 AR-720). Implementado em T1-09.
#
# Contrato
#   Entrada : Packages/AgentBoxKit (alvos agentbox-bench e agentboxd, build Release). Env: DEVELOPER_DIR.
#   Efeitos : sobe um agentboxd real em /tmp (AGENTBOX_HOME isolado), abre TerminalHostView reais (Metal) anexados
#             por TerminalSessionBinding e mede:
#               AR-702 latência de eco, tecla -> emulador alimentado e tecla -> quadro apresentado (p95 <= 16 ms em
#                      repouso; <= 33 ms com 4 panes, 3 deles com `yes`);
#               AR-703 `cat` de 50 MB num pane: maior parada do main (<= 100 ms) e eco em outro pane (<= 33 ms);
#               AR-704 memória: pegada por view de terminal (<= 30 MiB) e por sessão no daemon (<= 25 MiB) com 5 mil
#                      linhas de scrollback.
#             As janelas de teste ficam com alfa 0,01 (praticamente invisíveis) e sem foco. Grava o JSON e sai com
#             código != 0 se algum orçamento estourar. Não cobre xctrace nem os cenários AR-701/705/706 completos.
#   Saída   : docs/evidence/bench/<data>-<sha>.json (ou --out <arquivo>); exit 0 = dentro dos orçamentos; 1 = estourou;
#             2 = erro de execução.
# Uso: scripts/bench.sh [--quick] [--out <arquivo.json>] [--no-present] [--help]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

OUT=""
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --out) OUT="${2:?--out exige um caminho}"; shift 2 ;;
    --quick|--no-present) EXTRA+=("$1"); shift ;;
    *) usage >&2; exit 64 ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
DATE="$(date +%Y-%m-%d)"
[ -n "$OUT" ] || OUT="$ROOT/docs/evidence/bench/${DATE}-${SHA}.json"
mkdir -p "$(dirname "$OUT")"

PKG=Packages/AgentBoxKit
for prod in agentboxd agentbox-bench; do
  swift build -c release --package-path "$PKG" --product "$prod" 2>&1 | tail -1
done
BIN="$(swift build -c release --package-path "$PKG" --show-bin-path)"

echo "bench: executando (alguns minutos)" >&2
rc=0
"$BIN/agentbox-bench" --out "$OUT" ${EXTRA[@]+"${EXTRA[@]}"} >/dev/null || rc=$?
case "$rc" in
  0) echo "bench: OK -> $OUT" ;;
  1) echo "bench: orçamento estourado (veja failures em $OUT)" >&2 ;;
  *) echo "bench: erro de execução (exit $rc)" >&2 ;;
esac
exit "$rc"
