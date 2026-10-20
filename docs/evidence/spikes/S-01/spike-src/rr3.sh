#!/bin/bash
# rr2 com o ambiente do signed.sh: TMPDIR=scratch e keychain efemero na lista do usuario.
S="$(cd "$(dirname "$0")" && pwd)"
export TMPDIR="$S/"
REPO=/Users/gabriel/orca/agent-box/.claude/worktrees/agent-a59f55fca5dd2120b
ORIG_LIST="$(security list-keychains -d user | tr -d '"')"
if [ "${KEYCHAIN:-0}" = 1 ]; then
  OUT="$("$REPO/scripts/make-dev-cert.sh" --ephemeral)"
  KC="$(sed -n 's/^RACKY_EPHEMERAL_KEYCHAIN=//p' <<<"$OUT")"
  trap 'security delete-keychain "$KC"; security list-keychains -d user -s $ORIG_LIST' EXIT
fi
export REBUILD=alive PROBE=${PROBE:-1} SETTLE BUMP NOREREG
bash "$S/rr2.sh"
