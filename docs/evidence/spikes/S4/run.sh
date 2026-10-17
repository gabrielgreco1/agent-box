#!/bin/bash
# S4: deny de Skill(agentbox) por --settings sob --dangerously-skip-permissions (claude 2.1.302, haiku).
# Uso: docs/evidence/spikes/S4/run.sh [variante...]   (padrao: control deny)
cd "$(dirname "$0")" || exit 1
P="$(cat prompt.txt)"
variants=("$@"); [ ${#variants[@]} -eq 0 ] && variants=(control deny)
for v in "${variants[@]}"; do
  case "$v" in
    control) S='{}' ;;
    deny) S='{"permissions":{"deny":["Skill(agentbox)"]}}' ;;
    denybare) S='{"permissions":{"deny":["Skill"]}}' ;;
  esac
  claude -p --model haiku --dangerously-skip-permissions --max-budget-usd 0.08 --output-format stream-json --verbose --settings "$S" "$P" > "$v.jsonl" 2> "$v.err"
  { echo "== $v (settings: $S)"; python3 -I summarize.py "$v.jsonl"; } | tee "summary-$v.txt"
done
