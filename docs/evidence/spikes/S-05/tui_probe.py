#!/usr/bin/env python3
# tui_probe.py <variant: daemon|nodaemon> : launches codex TUI in a PTY (trusted project cwd) with -c hooks + inline trust; types a prompt; records process tree and hook log
import pty,os,time,select,signal,struct,fcntl,termios,subprocess,json,sys
S=os.path.dirname(os.path.abspath(__file__)); L=S+"/logger.sh"; variant=sys.argv[1]
cwd="/Users/gabriel/Desktop/golt"; log=S+f"/tui-{variant}.jsonl"
if os.path.exists(log): os.remove(log)
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
t=",".join('"%s"={trusted_hash="%s"}'%kv for kv in probe())
args=["codex","-m","gpt-5.6-luna","-s","read-only"]+hk+["-c","hooks.state={%s}"%t]+(["--no-daemon"] if variant=="nodaemon" else [])
pid,fd=pty.fork()
if pid==0:
    os.chdir(cwd); os.environ["TERM"]="xterm-256color"; os.environ["SPIKE_LOG"]=log; os.execvp("codex",args)
fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack("HHHH",40,120,0,0))
buf=b""
def drain(t):
    global buf
    end=time.time()+t
    while time.time()<end:
        r,_,_=select.select([fd],[],[],0.3)
        if r:
            try: x=os.read(fd,65536)
            except OSError: return
            if not x: return
            buf+=x
drain(8)
os.write(fd,b"say hi"); time.sleep(.5); os.write(fd,b"\r"); drain(12)
ps=subprocess.run(["ps","-axo","pid,ppid,pgid,tpgid,command"],capture_output=True,text=True).stdout
mine=[l for l in ps.splitlines() if "codex" in l and "zsh -c" not in l and "tui_probe" not in l]

try: print("TUI pid",pid,"pgid",os.getpgid(pid))
except Exception as ex: print("TUI exited early", ex)
print("\n".join(l[:190] for l in mine))
import re
txt=re.sub(rb"\x1b\[[0-9;?<>=]*[ -/]*[@-~]|\x1b\][^\x07]*\x07",b"",buf).decode("utf8","ignore")
print("screen-tail:",txt[-500:].replace("\r","").replace("\n"," | "))
os.write(fd,b"\x03"); time.sleep(.3); os.write(fd,b"\x03"); time.sleep(1)
try: os.kill(pid,signal.SIGKILL)
except: pass
print("hook events:",[json.loads(l)["tag"] for l in open(log)] if os.path.exists(log) else None)
