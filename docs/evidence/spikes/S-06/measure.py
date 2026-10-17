import os, pty, sys, time, select, signal, subprocess, json, statistics, pwd, shutil, re

SCR = "/private/tmp/claude-501/-Users-gabriel-orca-workspaces-agent-box-otter/5dda428d-ecea-4852-b667-584fd17012cc/scratchpad/s06"
SHELL = pwd.getpwuid(os.getuid()).pw_shell
SECRET = re.compile(r"KEY|TOKEN|SECRET|PASS|AUTH", re.I)
PROXY = ["HTTP_PROXY","HTTPS_PROXY","NO_PROXY","ALL_PROXY","http_proxy","https_proxy","no_proxy","all_proxy"]
RUNS = 5
TIMEOUT = 10.0

# Ambiente mínimo parecido ao que o launchd entrega ao app (não o da sessão do Claude).
BASE_ENV = {"HOME": os.environ["HOME"], "USER": os.environ["USER"], "LOGNAME": os.environ["USER"],
            "SHELL": SHELL, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
            "LANG": os.environ.get("LANG", "en_US.UTF-8")}
ssh = subprocess.run(["launchctl", "getenv", "SSH_AUTH_SOCK"], capture_output=True, text=True).stdout.strip()
if ssh:
    BASE_ENV["SSH_AUTH_SOCK"] = ssh  # como o launchd da sessão do usuário entrega

def analyze(name, raw, begin, end, elapsed, timed_out, exit_code):
    text = raw
    res = {"name": name, "elapsed_s": round(elapsed, 3), "timed_out": timed_out, "exit": exit_code,
           "bytes_total": len(raw)}
    if begin not in raw or end not in raw:
        res.update(markers_found=False)
        return res
    i = raw.index(begin) + len(begin)
    j = raw.index(end, i)
    pre = raw[:raw.index(begin)]
    post = raw[j + len(end):]
    res.update(markers_found=True, junk_before_bytes=len(pre), junk_after_bytes=len(post),
               junk_before_lines=pre.count(b"\n"), junk_after_lines=post.count(b"\n"),
               junk_before_has_ansi=b"\x1b" in pre)
    body = raw[i:j]
    if body.startswith(b"\r\n"): body = body[2:]
    env = {}
    for entry in body.split(b"\0"):
        if not entry or b"=" not in entry: continue
        k, _, v = entry.partition(b"=")
        env[k.decode("utf-8", "replace")] = v.decode("utf-8", "replace")
    path = env.get("PATH", "")
    res["env_vars"] = len(env)
    res["secret_like_names"] = sorted(k for k in env if SECRET.search(k) and k != "SSH_AUTH_SOCK")
    res["ssh_auth_sock_present"] = "SSH_AUTH_SOCK" in env
    res["proxy_vars_present"] = sorted(k for k in PROXY if k in env)
    res["orca_vars_present"] = sorted(k for k in env if k.startswith("ORCA_"))
    res["which"] = {c: (shutil.which(c, path=path) or "NOT FOUND") for c in ["claude","node","gh","codex"]}
    res["path_entries"] = len(path.split(":")) if path else 0
    res["_env"] = env
    return res

def run_A(i):
    """(1) $SHELL -l -c, sem PTY, stdin vazio."""
    cmd = "printf MARK; env -0; printf MARK"
    t = time.monotonic()
    try:
        p = subprocess.run([SHELL, "-l", "-c", cmd], env=dict(BASE_ENV, TERM="dumb"), stdin=subprocess.DEVNULL,
                           capture_output=True, timeout=TIMEOUT)
        el = time.monotonic() - t
        raw = p.stdout
        return analyze(f"A-run{i}", raw, b"MARK", b"MARK", el, False, p.returncode), raw
    except subprocess.TimeoutExpired as e:
        el = time.monotonic() - t
        raw = e.stdout or b""
        return analyze(f"A-run{i}", raw, b"MARK", b"MARK", el, True, None), raw

def run_B(i, shell_args=None, env_extra=None):
    """(2) $SHELL -l -i -c dentro de PTY oculto, TERM=dumb, marcadores separando lixo."""
    begin, end = b"__AB_ENV__", b"__AB_ENV_END__"
    cmd = 'printf "\\n__AB_ENV__\\n"; /usr/bin/env -0; printf "\\n__AB_ENV_END__\\n"'
    env = dict(BASE_ENV, TERM="dumb")
    if env_extra: env.update(env_extra)
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execve(SHELL, [SHELL, "-l", "-i", "-c", cmd], env)
        finally:
            os._exit(127)
    buf = b""; t = time.monotonic(); timed_out = False; exit_code = None
    while True:
        remaining = TIMEOUT - (time.monotonic() - t)
        if remaining <= 0:
            timed_out = True; break
        r, _, _ = select.select([fd], [], [], min(remaining, 0.05))
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break  # EIO: child closed the pty
            if not chunk: break
            buf += chunk
            if end in buf and buf.rstrip().endswith(end):
                break
        else:
            wpid, status = os.waitpid(pid, os.WNOHANG)
            if wpid == pid:
                exit_code = os.waitstatus_to_exitcode(status); break
    el = time.monotonic() - t
    if timed_out:
        try: os.killpg(pid, signal.SIGKILL)
        except Exception:
            try: os.kill(pid, signal.SIGKILL)
            except Exception: pass
    try:
        _, status = os.waitpid(pid, 0)
        exit_code = os.waitstatus_to_exitcode(status)
    except ChildProcessError:
        pass
    try: os.close(fd)
    except OSError: pass
    return analyze(f"B-run{i}", buf, begin, end, el, timed_out, exit_code), buf

def summarize(results):
    els = [r["elapsed_s"] for r in results]
    return {"median_s": round(statistics.median(els), 3), "max_s": round(max(els), 3),
            "min_s": round(min(els), 3), "timeouts": sum(r["timed_out"] for r in results),
            "markers_ok": sum(bool(r.get("markers_found")) for r in results), "runs": len(results)}

if __name__ == "__main__":
    mode = sys.argv[1]
    extra = None
    if len(sys.argv) > 2 and sys.argv[2] == "noisy":
        extra = {"ZDOTDIR": os.path.join(SCR, "noisy-zdotdir")}
    out = []; raws = []
    for i in range(1, RUNS + 1):
        if mode == "A":
            r, raw = run_A(i)
        else:
            r, raw = run_B(i, env_extra=extra)
        out.append(r); raws.append(raw)
        print(json.dumps({k: v for k, v in r.items() if k != "_env"}, ensure_ascii=False), flush=True)
    tag = mode + ("-noisy" if extra else "")
    with open(os.path.join(SCR, f"result-{tag}.json"), "w") as f:
        json.dump({"summary": summarize(out), "runs": [{k: v for k, v in r.items() if k != "_env"} for r in out]}, f, ensure_ascii=False, indent=1)
    with open(os.path.join(SCR, f"raw-{tag}-run1.bin"), "wb") as f:
        f.write(raws[0])  # cru: contém valores de env (não copiar para o repo)
    print("SUMMARY", json.dumps(summarize(out)))
