#!/usr/bin/env bash
# qa-preflight.sh - confere o ambiente de QA (08 AR-825). Roadmap: completa em T1-02.
#
# Contrato
#   Confere : Docker (docker info), CLIs (claude, codex, gh auth status), e se Acessibilidade
#             e Gravação de Tela estão concedidas ao processo que roda o script.
#   Não intrusivo: nunca abre prompts de permissão; nunca imprime tokens.
#   Saída   : uma linha OK/FALTA/INCERTO por item. exit 0 se nada FALTA; exit 1 se algum FALTA.
#   Obs     : as permissões TCC valem para o app do terminal que executa o script.
# Uso: scripts/qa-preflight.sh [--help]
set -uo pipefail
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

MISSING=0
report() { printf '%-7s %-22s %s\n' "$1" "$2" "$3"; [ "$1" = "FALTA" ] && MISSING=1; return 0; }

# Docker
if command -v docker >/dev/null 2>&1; then
  if dv="$(docker info --format '{{.ServerVersion}}' 2>/dev/null)" && [ -n "$dv" ]; then
    report OK docker "engine $dv; contexto $(docker context show 2>/dev/null)"
  else
    report FALTA docker "daemon inacessível no contexto '$(docker context show 2>/dev/null)' (docker info falhou)"
  fi
else
  report FALTA docker "binário não encontrado"
fi

# CLIs
for c in claude codex; do
  if command -v "$c" >/dev/null 2>&1; then
    v="$("$c" --version 2>&1 | head -1)" && report OK "$c" "$v" || report FALTA "$c" "--version falhou"
  else
    report FALTA "$c" "não encontrado no PATH"
  fi
done
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    report OK gh "autenticado ($(gh api user -q .login 2>/dev/null || echo '?'))"
  else
    report FALTA gh "gh auth status falhou (rode: gh auth login)"
  fi
else
  report FALTA gh "não encontrado"
fi

# Acessibilidade e Gravação de Tela: APIs de preflight do CoreGraphics/ApplicationServices (não abrem prompt)
if command -v swift >/dev/null 2>&1; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  ax="$(swift -e 'import ApplicationServices; print(AXIsProcessTrusted() ? "granted" : "denied")' 2>/dev/null | tail -1)"
  case "$ax" in
    granted) report OK accessibility "concedida ao processo atual" ;;
    denied) report FALTA accessibility "negada ao app do terminal (Ajustes > Privacidade > Acessibilidade)" ;;
    *) report INCERTO accessibility "não foi possível consultar" ;;
  esac
  sc="$(swift -e 'import CoreGraphics; print(CGPreflightScreenCaptureAccess() ? "granted" : "denied")' 2>/dev/null | tail -1)"
  case "$sc" in
    granted) report OK screen-recording "concedida ao processo atual" ;;
    denied) report FALTA screen-recording "negada (Ajustes > Privacidade > Gravação de Tela)" ;;
    *) report INCERTO screen-recording "não foi possível consultar" ;;
  esac
else
  report INCERTO accessibility "swift indisponível"
  report INCERTO screen-recording "swift indisponível"
fi

[ "$MISSING" = 0 ] && echo "qa-preflight: OK" || echo "qa-preflight: itens faltando" >&2
exit "$MISSING"
