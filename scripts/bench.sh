#!/usr/bin/env bash
# bench.sh - ESQUELETO (Fatia 0). Conteúdo completo em: T1-09.
#
# Contrato
#   Entrada : build Release do app/daemon.
#   Efeitos : mede os orçamentos AR-702/703/706 e grava docs/evidence/bench/<data>.json; falha se estourar.
#   Saída   : exit 0 em sucesso; exit != 0 em falha; exit 64 = "não implementado" (esqueleto).
# Uso: scripts/bench.sh [--help]
set -euo pipefail
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
echo "ERRO: bench.sh ainda não implementado (completa em T1-09)." >&2
exit 64
