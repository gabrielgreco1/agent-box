#!/usr/bin/env bash
# extract-orca-reference.sh - ESQUELETO (Fatia 0). Conteúdo completo em: F0-3.
#
# Contrato
#   Entrada : app.asar do Orca instalado (OrcaApp 1.4.219), caminho opcional via --asar.
#   Efeitos : grava docs/rebuild/reference/orca-1.4.219/source/ e tokens/*.json; registra SHA-256 do app.asar no README.
#   Reprodutível: duas execuções geram os mesmos tokens byte a byte.
#   Saída   : exit 0 em sucesso; exit != 0 em falha; exit 64 = "não implementado" (esqueleto).
# Uso: scripts/extract-orca-reference.sh [--asar <caminho>] [--help]
set -euo pipefail
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
echo "ERRO: extract-orca-reference.sh ainda não implementado (completa em F0-3)." >&2
exit 64
