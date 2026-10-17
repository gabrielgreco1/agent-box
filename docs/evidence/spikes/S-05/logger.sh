#!/bin/sh
# usage: logger.sh <tag> ; appends {"tag","argv_event","stdin"} to $SPIKE_LOG
IN=$(cat)
printf '%s\n' "$IN" | python3 -c '
import sys,json,os
raw=sys.stdin.read()
try: p=json.loads(raw)
except Exception: p={"_raw":raw}
print(json.dumps({"tag":sys.argv[1],"pid":os.getpid(),"env_keys":sorted(k for k in os.environ if k.startswith(("CLAUDE","CODEX","SPIKE","AGENT"))),"payload":p}))
' "$1" >> "${SPIKE_LOG:-/dev/null}"
printf '{}\n'
