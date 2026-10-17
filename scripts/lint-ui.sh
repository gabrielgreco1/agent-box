#!/usr/bin/env bash
# lint-ui.sh - ESQUELETO (Fatia 0). Conteúdo completo em: T1-02.
#
# Contrato
#   Entrada : código SwiftUI novo (nunca legacy/).
#   Falha em : .sheet(, List(, Form(, Color(hex: fora de DS.Color, literais em .padding(/.frame( fora de DS.Space, LocalProcessTerminalView, emojis;
#             Button fora do ActionRegistry; strings fora do String Catalog.
#   Saída   : exit 0 em sucesso; exit != 0 em falha; exit 64 = "não implementado" (esqueleto).
# Uso: scripts/lint-ui.sh [--help]
set -euo pipefail
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
echo "ERRO: lint-ui.sh ainda não implementado (completa em T1-02)." >&2
exit 64
