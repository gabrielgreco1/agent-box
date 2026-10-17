#!/usr/bin/env bash
# compare-ui.sh - ESQUELETO (Fatia 0). Conteúdo completo em: T1-02 (contrato fechado na Fatia 0).
#
# Contrato
#   Entrada : <tela> (screenId de 03 §0); usa 'agentbox ctl screenshot' e o fixture da tela.
#   Efeitos : grava em docs/evidence/ui/<tarefa>/ nos tamanhos 1440x900 e 760x480: lado a lado, overlay 50% e diferença absoluta contra docs/rebuild/reference/orca-1.4.219.
#   Saída   : exit 0 em sucesso; exit != 0 em falha; exit 64 = "não implementado" (esqueleto).
# Uso: scripts/compare-ui.sh <tela> [--task <id>] [--help]
set -euo pipefail
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
echo "ERRO: compare-ui.sh ainda não implementado (completa em T1-02 (contrato fechado na Fatia 0))." >&2
exit 64
