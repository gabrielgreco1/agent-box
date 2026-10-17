#!/bin/sh
# Entrypoint por papel (07 §2.2). Na T3-01 só existe o esqueleto: sem argumentos o container fica ocioso e
# recebe `exec` pela Engine API. A API de ações do runtime (Xvfb, Chromium, CDP, lease) entra na T3-03.
set -eu
if [ "$#" -gt 0 ]; then
  exec "$@"
fi
case "${AGENTBOX_ROLE:-work}" in
  runtime|work) exec sleep infinity ;;
  *) echo "papel desconhecido: ${AGENTBOX_ROLE}" >&2; exit 64 ;;
esac
