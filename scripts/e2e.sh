#!/usr/bin/env bash
# e2e.sh - ESQUELETO (Fatia 0). Conteúdo completo em: T1-24 (passos 1-3 e 7); completo na Fatia 3.
#
# Contrato
#   Entrada : app instalado + 'agentbox ctl', Docker real e CLIs reais (modelo barato, custo <= US$ 0,50).
#   Efeitos : executa os passos de 08 AR-810; evidências em docs/evidence/e2e/.
#   Saída   : exit 0 em sucesso; exit != 0 em falha; exit 64 = "não implementado" (esqueleto).
# Uso: scripts/e2e.sh [--steps 1,2,3,7] [--help]
set -euo pipefail
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
echo "ERRO: e2e.sh ainda não implementado (completa em T1-24 (passos 1-3 e 7); completo na Fatia 3)." >&2
exit 64
