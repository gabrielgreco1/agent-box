# Agent Box browser/desktop runtime

This is the container workload for one computer. The host app owns container creation, policy, lease arbitration and port discovery. This directory does not install or start Docker or modify host configuration.

## Build and isolation contract

The Dockerfile uses the official Playwright Python `v1.63.0-noble` image pinned to digest `sha256:72bd171a9ffc2b4b59532aaa6210e21014d07093120dc25528870c0b840da1f0`, matching `playwright==1.63.0`, `mss==10.2.0`, `Pillow==12.3.0`, and exact Ubuntu package versions for Xvfb, Openbox and xdotool. It runs as UID 10001. The pinned apt versions may disappear from ordinary Ubuntu repositories over time; a release build should use an apt snapshot or a controlled mirror. The image was built and smoke-tested on arm64 Colima.

The host must publish **only** `127.0.0.1:<ephemeral-host-port>:8765`, never `0.0.0.0`. Supply a fresh unpredictable `AB_API_TOKEN` (at least 32 characters) and stable `AB_COMPUTER_ID` UUID, preferably through a temporary owner-only env file. Never put the token in a URL or log. Docker admin users can inspect environment and control the container. Persist `/data` in a per-computer volume: `/data/profile`, `/data/workspace` (including downloads) and checkpoint. Do not expose VNC, CDP, the X11 socket, a Docker socket or privileged mode. The tested hardening is `--cpus 1 --memory 2g --pids-limit 256 --shm-size 256m --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp:rw,nosuid,nodev,size=256m --tmpfs /home/agentbox:rw,nosuid,nodev,size=32m,uid=10001,gid=10001` with writable `/data`. The UID/GID on the home tmpfs is required for Chromium crashpad; a root-owned tmpfs caused headed launch failure. Exact creation policy belongs to Core/Docker integration.

`/ready` is a generic unauthenticated Docker health probe. Every `/v1/*` read needs `Authorization: Bearer <AB_API_TOKEN>`. Writes also need the active lease's `X-AgentBox-Actor-ID`, `X-AgentBox-Lease-Epoch` and `X-AgentBox-Control-Token`. All write routes and grant/revoke serialize under one lock. Revocation ACK means the previous write completed before control moved. Host broker grants only one writer per computer and must reconcile live health after reconnect. Health returns active lease identity/epoch/paths, never its token.

| Route | Purpose |
|---|---|
| `GET /v1/health` | computer UUID, generation, mode, browser/display readiness, frame source, active lease |
| `GET /v1/frame` | one JPEG with `X-AgentBox-Frame-Source: browser` or `desktop` |
| `GET /v1/stream` | multipart JPEG of the **entire Xvfb display**; desktop mode only, max 4 frames/s |
| `POST /v1/control/grant` | host-only bearer request `{actor_id,epoch,paths}`; returns ephemeral control token |
| `POST /v1/control/revoke` | host-only bearer request `{actor_id,epoch}`; returns ACK after in-flight write |
| `POST /v1/mode` | leased `{mode:"http"|"headless"|"desktop"}` |
| `POST /v1/navigate` | leased `{url}` for browser modes |
| `POST /v1/input` | leased X11 `move`, `click`, `key`, `text` or `scroll` |
| `POST /v1/http/request` | leased GET/HEAD, 10 s timeout, 1 MiB cap, no redirects |

`http` mode has no browser. `headless` uses the persistent Playwright context and can provide a browser screenshot, but never a desktop stream. `desktop` starts Xvfb and Openbox, then restarts the **same** persistent browser profile in headed mode. Promotion closes the old context before reopening it, so transient page/form state is lost; the last URL, cookies/profile files, downloads and workspace survive. Each successful mode change increments generation. The host should refresh its endpoint after a change. The profile lock prevents a second runtime process from using the same profile concurrently.

The MJPEG stream captures the entire Xvfb display, including windows beyond Chromium. `xdotool` drives XTEST input with validated argv and no shell. If the display or window manager stops, health ceases to report desktop readiness. Applications opened on the same display appear in the stream.

**Security boundary:** the API lease gate controls calls to this server. It cannot constrain an untrusted process with shell access inside the same container: that process can reach its own X11 socket and browser profile. Until the control plane is isolated from agent-executable processes, the host must not advertise the lease as an adversarial in-container boundary or grant arbitrary shell access to this container. The HTTP request route also does not enforce destination policy or DNS re-resolution protection; an agent-facing network policy gateway is needed before allowing untrusted URLs.

## Local verification

`python3 -m unittest discover -s runtime/boxes -p 'test_*.py'` uses fake browser/display components and a loopback HTTP server. It does not need Docker, Playwright, Xvfb or host credentials. `python3 runtime/boxes/smoke_docker.py` is an explicit destructive-to-its-own-resources Docker smoke test restricted to context `colima-agentbox-dev`: it creates unique labeled test container/volume resources, verifies headless JavaScript, whole-display capture/input, lease takeover and profile persistence, then removes only those resources. It does not stop Colima. Arm64 passed with final image ID `sha256:813e4cadc07c7d307a593cf0d5698f374677947a0703de4cdce6b08a0fd9dc77`; other architectures remain unverified.
