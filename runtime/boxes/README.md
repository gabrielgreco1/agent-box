# Agent Box browser/desktop runtime

This is the container workload for one computer. The host app owns container creation, policy, lease arbitration and port discovery. This directory does not install or start Docker or modify host configuration.

## Build and isolation contract

The Dockerfile uses the official Playwright Python `v1.63.0-noble` image pinned to digest `sha256:72bd171a9ffc2b4b59532aaa6210e21014d07093120dc25528870c0b840da1f0`, matching `playwright==1.63.0`, `mss==10.2.0`, `Pillow==12.3.0`, and exact Ubuntu package versions for Xvfb, Openbox and xdotool. It runs as UID 10001. The pinned apt versions may disappear from ordinary Ubuntu repositories over time; a release build should use an apt snapshot or a controlled mirror. The image was built and smoke-tested on arm64 Colima.

The host must publish **only** `127.0.0.1:<ephemeral-host-port>:8765`, never `0.0.0.0`. Supply a fresh unpredictable `AB_API_TOKEN` (at least 32 characters) and stable `AB_COMPUTER_ID` UUID, preferably through a temporary owner-only env file. Never put the token in a URL or log. Docker admin users can inspect environment and control the container. Persist `/data` in a per-computer volume: `/data/profile`, `/data/workspace` (including downloads) and checkpoint. Do not expose VNC, CDP, the X11 socket, a Docker socket or privileged mode. The tested hardening is `--init --cpus 1 --memory 2g --pids-limit 256 --shm-size 256m --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp:rw,nosuid,nodev,size=256m --tmpfs /home/agentbox:rw,nosuid,nodev,size=32m,uid=10001,gid=10001` with writable `/data`. The UID/GID on the home tmpfs is required for Chromium crashpad; a root-owned tmpfs caused headed launch failure. Exact creation policy belongs to Core/Docker integration.

`/ready` is a generic unauthenticated Docker health probe. Every `/v1/*` read needs `Authorization: Bearer <AB_API_TOKEN>`. Writes also need the active lease's `X-AgentBox-Actor-ID`, `X-AgentBox-Lease-Epoch` and `X-AgentBox-Control-Token`. All write routes and grant/revoke serialize under one lock. Revocation ACK means the previous write completed before control moved. Host broker grants only one writer per computer and must reconcile live health after reconnect. Health returns active lease identity/epoch/paths, never its token.

| Route | Purpose |
|---|---|
| `GET /v1/health` | computer UUID, generation, mode, browser/display readiness, frame source, active lease |
| `GET /v1/frame` | one JPEG with `X-AgentBox-Frame-Source: browser` or `desktop` |
| `GET /v1/page` | headless/desktop page `{url,title,text,links,truncated,generation,computer_id}` |
| `GET /v1/stream` | multipart JPEG of the **entire Xvfb display**; desktop mode only, max 4 frames/s |
| `POST /v1/control/grant` | host-only bearer request `{actor_id,epoch,paths}`; returns ephemeral control token |
| `POST /v1/control/revoke` | host-only bearer request `{actor_id,epoch}`; returns ACK after in-flight write |
| `POST /v1/mode` | leased `{mode:"http"|"headless"|"desktop"}` |
| `POST /v1/navigate` | leased `{url}` for browser modes |
| `POST /v1/input` | leased X11 `move`, `click`, `key`, `text` or `scroll` |
| `POST /v1/http/request` | leased public-web GET/HEAD, 10 s deadline, 1 MiB cap, no redirects |

`/v1/page` removes form controls (including password fields), contenteditable nodes, scripts, styles, frames and non-text graphics before extracting page text or link labels. It never returns raw HTML, input values, cookies or browser storage. Text is capped at 65,536 characters, links at 200, labels at 300 characters, URLs at 4,096 characters and title at 500 characters; `truncated` reports clipping. It reads the same Playwright page used for browser navigation and screenshots, and returns 409 in HTTP mode.

`/v1/http/request` accepts only `{url,method}` with an HTTP(S) URL of at most 4,096 characters and GET or HEAD. It rejects URL credentials and any private, loopback, link-local, multicast or reserved address in **any** DNS result, then connects to a vetted numeric address while keeping the original Host header and HTTPS certificate hostname. Environment proxies and redirects are not used. The response returns status, bounded content type, base64 body, generation and computer UUID; it does not expose response headers. A local fake-server test checks pinning, mixed public/private DNS, proxy isolation, redirects, response limits and a stalled resolver. This is an application-layer guard; container/network egress policy remains a separate defense.

`http` mode has no browser. `headless` uses the persistent Playwright context and can provide a browser screenshot, but never a desktop stream. `desktop` starts Xvfb and Openbox, then launches the full Chromium binary as an independent desktop process using the **same** persistent profile. Playwright attaches via container-internal loopback CDP with `no_defaults=True`; port 9222 is never published. No user-agent override or fingerprint patch is applied. Headless mode uses the full Chromium channel too. Promotion closes the old context before reopening it, so transient page/form state is lost; the last URL, cookies/profile files, downloads and workspace survive. Each successful mode change increments generation. The host should refresh its endpoint after a change. The profile lock prevents a second runtime process from using the same profile concurrently.

The MJPEG stream captures the entire Xvfb display, including windows beyond Chromium. `xdotool` drives XTEST input with validated argv and no shell. If the display or window manager stops, health ceases to report desktop readiness. Applications opened on the same display appear in the stream.

**Security boundary:** the API lease gate controls calls to this server. It cannot constrain an untrusted process with shell access inside the same container: that process can reach its own X11 socket and browser profile. Until the control plane is isolated from agent-executable processes, the host must not advertise the lease as an adversarial in-container boundary or grant arbitrary shell access to this container.

## Local verification

`python3 -m unittest discover -s runtime/boxes -p 'test_*.py'` uses fake browser/display components and a loopback HTTP server. It does not need Docker, Playwright, Xvfb or host credentials. `python3 runtime/boxes/smoke_docker.py` is an explicit destructive-to-its-own-resources Docker smoke test restricted to context `colima-agentbox-dev`: it creates unique labeled test container/volume resources, verifies headless JavaScript, whole-display capture/input, lease takeover and profile persistence, then removes only those resources. It does not stop Colima. Arm64 passed with final image ID `sha256:43bf099353c79148d8b960389f2359864a121183585e10b61d1c54ef7509166c`; other architectures remain unverified.

Use `--init` so child processes are reaped. On SIGTERM the API stops serving, closes Chromium through CDP, waits for profile flush and stops the display. The smoke checks exit status zero before reusing its volume; forced termination is not proof of a clean profile. Existing containers keep their original image. Browser upgrades and profile recovery after abrupt power loss require separate migration work. See [AB-037](../../docs/tasks/AB-037-native-desktop-browser.md).
