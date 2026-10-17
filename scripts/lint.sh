#!/usr/bin/env bash
# lint.sh - ESQUELETO (Fatia 0). Conteúdo completo em: T1-01.
#
# Contrato
#   Entrada : código Swift novo (Packages/, App/); nunca legacy/.
#   Falha em : warnings do Swift 6 estrito; DispatchSemaphore.wait, Thread.sleep, locks em I/O fora de Platform/.
#   Saída   : exit 0 em sucesso; exit != 0 em falha; exit 64 = "não implementado" (esqueleto).
# Uso: scripts/lint.sh [--help]
set -euo pipefail
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
echo "ERRO: lint.sh ainda não implementado (completa em T1-01)." >&2
exit 64
