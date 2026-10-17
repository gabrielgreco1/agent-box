#!/usr/bin/env python3
# codex_trusted_run.py <logfile> <outprefix> <trust:0|1> <prompt> : codex exec with -c hooks (sessionFlags), optionally trusting them via -c hooks.state inline table
import subprocess,json,os,sys
S=os.path.dirname(os.path.abspath(__file__)); L=S+"/logger.sh"; log,out,trust,prompt=sys.argv[1:5]; cwd=S+"/cwork"
EV=["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Stop"]
hk=[]
for e in EV: hk+=["-c",f'hooks.{e}=[{{hooks=[{{type="command",command="{L} {e}",timeout=5}}]}}]']
def probe():
    p=subprocess.Popen(["codex","app-server","--listen","stdio://"]+hk,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,cwd=cwd)
    def send(m): p.stdin.write(json.dumps(m)+"\n"); p.stdin.flush()
    def recv(i):
        while True:
            m=json.loads(p.stdout.readline())
            if m.get("id")==i: return m
    send({"id":1,"method":"initialize","params":{"clientInfo":{"name":"s05","version":"0"}}}); recv(1); send({"method":"initialized"})
    send({"id":2,"method":"hooks/list","params":{"cwds":[cwd]}}); r=recv(2); p.terminate()
    return [(h["key"],h["currentHash"]) for e in r["result"]["data"] for h in e["hooks"] if h["source"]=="sessionFlags"]
extra=[]
if trust=="1":
    t=",".join('"%s"={trusted_hash="%s"}'%kv for kv in probe()); extra=["-c","hooks.state={%s}"%t]
env=dict(os.environ,SPIKE_LOG=log)
if os.path.exists(log): os.remove(log)
r=subprocess.run(["codex","exec","--skip-git-repo-check","-m","gpt-5.6-luna","-c","model_reasoning_effort=low","-s","read-only"]+hk+extra+["--json",prompt],cwd=cwd,env=env,stdin=subprocess.DEVNULL,capture_output=True,text=True)
open(out+".events.jsonl","w").write(r.stdout); open(out+".err","w").write(r.stderr)
print("exit",r.returncode,"hook-lines",sum(1 for _ in open(log)) if os.path.exists(log) else 0)
