#!/usr/bin/env python3
# hooks_list2.py <cwd> <outfile> [--cmd-suffix X] [--timeout N] [--trust] [--home-copy]
# Calls hooks/list on `codex app-server` with -c hooks.* (sessionFlags); with --trust also passes hooks.state.* trusted_hash via -c
import subprocess,json,sys,os
cwd,out=sys.argv[1],sys.argv[2]; a=sys.argv[3:]
suf=a[a.index("--cmd-suffix")+1] if "--cmd-suffix" in a else ""
to=a[a.index("--timeout")+1] if "--timeout" in a else "5"
S=os.path.dirname(os.path.abspath(__file__)); logger=S+"/logger.sh"
EV=["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Stop"]
def run(extra):
    args=["codex","app-server","--listen","stdio://"]
    for e in EV: args+=["-c",f'hooks.{e}=[{{hooks=[{{type="command",command="{logger} {e}{suf}",timeout={to}}}]}}]']
    args+=extra
    p=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,cwd=cwd)
    def send(m): p.stdin.write(json.dumps(m)+"\n"); p.stdin.flush()
    def recv(i):
        while True:
            l=p.stdout.readline()
            if not l: return None
            m=json.loads(l)
            if m.get("id")==i: return m
    send({"id":1,"method":"initialize","params":{"clientInfo":{"name":"s05","version":"0"}}}); recv(1)
    send({"method":"initialized"}); send({"id":2,"method":"hooks/list","params":{"cwds":[cwd]}}); r=recv(2); p.terminate()
    return [h for e in r["result"]["data"] for h in e["hooks"] if h["source"]=="sessionFlags"]
hs=run([])
res={"probe":[{k:h[k] for k in("key","eventName","currentHash","trustStatus","timeoutSec")} for h in hs]}
if "--trust" in a:
    extra=[]
    for h in hs: extra+=["-c",f'hooks.state."{h["key"]}".trusted_hash="{h["currentHash"]}"']
    hs2=run(extra)
    res["with_state_via_c"]=[{k:h[k] for k in("key","eventName","currentHash","trustStatus")} for h in hs2]
json.dump(res,open(out,"w"),indent=1)
