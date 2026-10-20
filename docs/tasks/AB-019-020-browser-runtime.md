# AB-019/020 — Browser and full desktop runtime base

Implemented in `runtime/boxes/` and `Sources/RackyCore/BrowserRuntime/`.

- Official Playwright Python image/tag `v1.63.0-noble` and matching package; persistent Chromium profile shared across headless and headed modes.
- Real Linux display: Xvfb + Openbox + MSS full-screen JPEG capture and xdotool XTEST input. Headless screenshots have a distinct source label; MJPEG is desktop-only.
- Per-computer `/data` volume contract, profile file lock, generation/checkpoint and persistent downloads/workspace.
- Loopback-published bearer API, separate one-writer epoch/token lease on all write routes, serialized revocation ACK and live lease in health.
- Swift loopback-only typed client and endpoint, identity/generation validation, plus Python fake runtime tests and Swift mock transport tests.

Verified: Python local suite (4 tests), Swift Core BrowserRuntime typecheck, and a real image build/smoke on isolated arm64 Docker context `colima-racky-dev`. The smoke loaded JavaScript in headless Chromium (red page), captured a 1280×800 full desktop frame, clicked through XTEST (green page), revoked an agent lease and granted human control, then recreated the container with the same named volume and saw persisted browser state (blue page). The final smoke also passed a read-only root filesystem, dropped capabilities, no-new-privileges and resource bounds, with writable `/data` and owner-matched tmpfs directories. Owned smoke containers and volumes were removed; Colima remained running. Final local image tag: `racky-browser:ab019-dev`, image ID `sha256:813e4cadc07c7d307a593cf0d5698f374677947a0703de4cdce6b08a0fd9dc77`. The Dockerfile pins the upstream base digest and package versions; apt snapshot availability and other architectures need release validation. Core/Docker must wire user-triggered image build/create, local port mapping, token delivery, persistence and resource flags. Browser/navigation network policy is separate host work. The lease is an API gate, not a guarantee against shell code executing inside the same container.

Primary references: [Playwright Docker](https://playwright.dev/python/docs/docker), [Playwright persistent context](https://playwright.dev/python/docs/api/class-browsertype), [MSS capture](https://python-mss.readthedocs.io/stable/examples.html), [xdotool XTEST](https://github.com/jordansissel/xdotool/blob/main/xdotool.pod).
