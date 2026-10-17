#!/usr/bin/env python3
# Minimal stdio MCP server: one tool `whoami` returning the identity given on argv + logs each start/call.
import sys,json,os,time
ident=sys.argv[1]; log=os.environ.get("SPIKE_MCP_LOG")
def L(**k):
    if log: open(log,"a").write(json.dumps({"ident":ident,"pid":os.getpid(),"ppid":os.getppid(),"t":time.time(),**k})+"\n")
L(ev="start",env_keys=sorted(k for k in os.environ if k.startswith(("CLAUDE","SPIKE","AGENT"))))
for line in sys.stdin:
    try: m=json.loads(line)
    except Exception: continue
    i=m.get("id"); meth=m.get("method")
    def R(res): sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":i,"result":res})+"\n"); sys.stdout.flush()
    L(ev="rpc",method=meth)
    if meth=="initialize":
        R({"protocolVersion":m["params"].get("protocolVersion","2025-06-18"),"capabilities":{"tools":{}},"serverInfo":{"name":"whoami-"+ident,"version":"0"}})
    elif meth=="tools/list":
        R({"tools":[{"name":"whoami","description":"Returns the identity token of this MCP server instance.","inputSchema":{"type":"object","properties":{}}}]})
    elif meth=="tools/call":
        R({"content":[{"type":"text","text":"I_AM_"+ident}]})
    elif i is not None:
        R({})
