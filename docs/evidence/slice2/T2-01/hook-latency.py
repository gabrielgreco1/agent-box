#!/usr/bin/env python3
"""Latência do helper `agentbox hook` (08 AR-707: p95 <= 30 ms). Ferramenta de medição de desenvolvimento; não faz parte do produto.

Uso: hook-latency.py <caminho do agentbox> [execuções]

Cenários (cada execução é um processo novo, medido de ponta a ponta com perf_counter):
  closed  app fechado: connect falha na hora, o evento vai para o spool
  live    app aberto: um servidor falso de app.sock responde handshake e ack (só mede o helper, não o app)
  hung    app trava: aceita e nunca responde; o helper deve desistir em ~200 ms e gravar no spool
"""
import json, os, socket, struct, subprocess, sys, tempfile, threading, time

binary = sys.argv[1]
runs = int(sys.argv[2]) if len(sys.argv) > 2 else 200
payload = json.dumps({"session_id": "s", "hook_event_name": "PreToolUse", "tool_name": "Bash",
                      "tool_input": {"command": "ls -la"}}).encode()


def frame(b):
    return struct.pack(">I", len(b)) + b


def serve(sock, mode):
    while True:
        try:
            c, _ = sock.accept()
        except OSError:
            return
        def handle(c=c):
            try:
                buf = b""
                need = 2
                got = 0
                while got < need:
                    d = c.recv(65536)
                    if not d:
                        return
                    buf += d
                    got = 0
                    i = 0
                    while len(buf) - i >= 4:
                        n = struct.unpack(">I", buf[i:i + 4])[0]
                        if len(buf) - i - 4 < n:
                            break
                        i += 4 + n
                        got += 1
                if mode == "hung":
                    time.sleep(5)
                    return
                c.sendall(frame(b'{"ok":true}') + frame(b'{"ok":true,"duplicate":false}'))
            finally:
                c.close()
        threading.Thread(target=handle, daemon=True).start()


def bench(mode):
    home = tempfile.mkdtemp(prefix="abl-", dir="/tmp")
    os.makedirs(home + "/run")
    path = home + "/run/app.sock"
    srv = None
    if mode in ("live", "hung"):
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(path)
        srv.listen(16)
        threading.Thread(target=serve, args=(srv, mode), daemon=True).start()
    env = {"PATH": "/usr/bin:/bin", "HOME": home, "AGENTBOX_APP_SOCK": path, "AGENTBOX_RUN_ID": "11111111-2222-4333-8444-555555555555",
           "AGENTBOX_PANE_ID": "66666666-7777-4888-9999-000000000000"}
    samples = []
    n = runs if mode != "hung" else max(10, runs // 10)
    for _ in range(n):
        t = time.perf_counter()
        r = subprocess.run([binary, "hook", "--provider", "claude", "--event", "PreToolUse"], input=payload, env=env,
                           capture_output=True)
        samples.append((time.perf_counter() - t) * 1000)
        assert r.returncode == 0 and r.stdout == b"{}\n", (r.returncode, r.stdout, r.stderr)
    samples.sort()
    p = lambda q: samples[min(len(samples) - 1, int(len(samples) * q))]
    spooled = os.path.exists(home + "/run/spool/hooks")
    print(f"{mode:7s} runs={n:4d} p50={p(.5):6.1f} ms  p95={p(.95):6.1f} ms  max={samples[-1]:6.1f} ms  spooled={spooled}")
    return p(.95)


baseline = []
for _ in range(runs):
    t = time.perf_counter()
    subprocess.run(["/usr/bin/true"], capture_output=True)
    baseline.append((time.perf_counter() - t) * 1000)
baseline.sort()
print(f"binary={binary}")
print(f"spawn baseline (/usr/bin/true): p50={baseline[len(baseline)//2]:.1f} ms p95={baseline[int(len(baseline)*.95)]:.1f} ms")
results = {m: bench(m) for m in ("closed", "live", "hung")}
ok = results["closed"] <= 30 and results["live"] <= 30 and results["hung"] < 400
print("AR-707 (p95 <= 30 ms closed/live, hung gives up near 200 ms):", "OK" if ok else "ABOVE TARGET")
