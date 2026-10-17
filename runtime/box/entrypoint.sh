#!/bin/sh
# Entrypoint por papel (07 §2.2). Sem argumentos: `runtime` sobe Xvfb + Chromium headed + servidor de controle (T3-03);
# `work` fica ocioso e recebe `exec` pela Engine API.
set -eu
if [ "$#" -gt 0 ]; then
  exec "$@"
fi
case "${AGENTBOX_ROLE:-work}" in
  runtime) exec python -m agentbox_runtime ;;
  work) exec sleep infinity ;;
  *) echo "papel desconhecido: ${AGENTBOX_ROLE}" >&2; exit 64 ;;
esac
