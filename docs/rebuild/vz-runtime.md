# Docker-less computer runtime (`RackyVZ`)

On macOS 26+ with Apple silicon, Racky runs each computer as a small Linux virtual machine hosted by the app itself
(Virtualization.framework through [apple/containerization](https://github.com/apple/containerization) 0.52.1, pinned exactly in
`Packages/RackyKit/Package.swift`). No Docker is needed. Everywhere else (macOS < 26, Intel, a build without the virtualization
entitlement, or Settings › Computers › "Use Docker instead") the existing Docker path is used, unchanged.

## Design

```
AppComputerProvisioning (RackyCore)
  ├─ nativeTarget()  ── RuntimeSelector.choose(forceDocker:) ──┐
  │      native: NativeComputerRuntime  (protocol, RackyCore)   │  macOS 26+ & arm64 & entitled & !forceDocker
  │         └─ VZRuntime (RackyVZ): assets, sweep, capacity,    │
  │            VZComputerProvisioning → VZBackend → RunningVM   │
  └─ Docker path (DockerComputerProvisioning, adoption, GC) ◄───┘  otherwise
```

### The "ComputerRuntime" protocol decision

`ComputerHostAccess` (RackyDocker) cannot be the abstraction: it carries a `DockerClient`, and there is no Engine API, label, named
network or event stream here. Instead of retrofitting it, the seam is two small protocols:

| Protocol | Module | What it covers |
| --- | --- | --- |
| `NativeComputerRuntime` | RackyCore | `unavailableReason`, `ensureReady(progress)`, `vmCapacity`, `provision`, `shutdown`; `AppComputerProvisioning` routes to it |
| `ComputerExecTransport` + `ComputerExecSession` | RackyCore | what the tool backend needs from a runtime: start an exec as `agent`/`egress` (stdin, frames, exit code, process-group kill) and rewrite the egress config. `DockerComputerBackend` is now generic over it (Docker keeps `DockerExecTransport`) |
| `VZBackend` / `RunningVM` | RackyVZ | boot a VM from a plan, `startProcess`, `dialVsock`, `copyIn/Out`, `stop`. The real one is `ContainerizationBackend` (`@available(macOS 26)`); tests use `FakeBackend`/`FakeVM` |

`RackyDocker` and `RackyCore` do not import containerization; only `RackyVZ` does (and `RackyUI`/`RackyVZSelfTest` link it).
The app deployment target stays macOS 15: everything touching Virtualization/vmnet is `@available(macOS 26, *)` plus runtime
checks (`RuntimeSelector`, `VZRuntime.unavailableReason`, entitlement probe via `SecTask`).

### What maps to what

The VM is built from the **same `ContainerSpec` the Docker path builds** (`ComputerProvisioner.containerSpec`, so hardening, tmpfs
and binds stay in one place), converted by `VZVMPlan(spec:)`:

| Docker | VM |
| --- | --- |
| memory / cpus | VM memory (+128 MiB guest overhead) / vCPUs (rounded up) |
| `pidsLimit` | cgroup `pids.max` |
| tmpfs `/tmp`, `/home/agent`, `/run/racky` (uid, gid, mode, size) | same tmpfs mounts (`rw` dropped) |
| binds `/work`, `/run/abx-secrets:ro`, `/run/racky/logs` | virtiofs shares of the Mac folders (parents mounted before nested mounts) |
| `CapDrop ALL` + `CapAdd` (NET_ADMIN, SETUID, SETGID, SETPCAP, KILL) | process capability sets = exactly that list; exec as `agent` gets none + `no_new_privs` |
| `Init`, `no-new-privileges`, hostname, env, workdir | same |
| published admin port | `127.0.0.1:<ephemeral>` TCP listener on the Mac bridged to vsock 8791 (`VZPortBridge`), forwarded in the VM to the admin API on 127.0.0.1:8790 (`racky_supervisor/vsock.py`, runs as `egress`, no capabilities) |
| `abx-provision` exec with stdin | identical; **only** way into the tmpfs (`copyIn/copyOut` cannot see tmpfs) |
| labels (`racky.owner`, `racky.computer`...) | `vz/registry.json` (`VZRegistry`) |
| `docker exec` kill group | same pidfile wrapper + a second exec sending the signal |
| read-only rootfs | not applied: the rootfs is a private APFS clone discarded at teardown and the VM is the boundary |
| IPv6 | disabled by sysctl (vmnet hands out a ULA and a dead default route; the proxy tried AAAA first and failed intermittently; Docker computers have no IPv6 either) |

Also new in the image: admin API can bind loopback only (`RACKY_ADMIN_BIND=127.0.0.1`), so nothing on the shared vmnet reaches it.

### Warm start

`VZAssetStore` unpacks the image once to `vz/templates/<image digest>/rootfs.ext4` (sparse 6 GiB ext4). Each computer is
`clonefile(2)` of it (instant, copy-on-write). Measured on this Mac (M-series, macOS 27): VM boot 0.3 s; headless computer with
Chromium ready 1.25–1.8 s; teardown of a running VM ~50–100 ms.

### Who owns the VMs (decision: the app, for now)

Virtualization.framework VMs live in the process that created them. The scheduler/orchestrator also live in the app process, so
hosting VMs in the app is correct today; the cost is that **computers stop when the app quits**:

* `liveComputers()` of the native path returns `[]` (not `nil`), so on the next start `adoptRunning` marks the rows `removed` and
  releases the children's reservations. Docker containers from earlier sessions are still adopted if Docker answers.
* Quit: `AppEnvironment.markCleanExit` stops all VMs (`shutdownNative`). Crash / SIGKILL: the VM helper dies with the process (verified);
  `VZRegistry.sweep` at the next start deletes the stale rootfs clones and registry entries (and never touches a live other process).
* "Keep running in background" keeps the app process, hence the VMs.

**Daemon plan (not built).** To make computers outlive the UI, host VMs in `rackyd` (already a launchd agent): (1) move
`VZRuntime`/`ContainerizationBackend` into a new `rackyd` service on the existing UDS with peer auth; (2) API: `boot(plan)`, `exec`
(stream frames), `copyIn/Out`, `bridgePort(vm)`, `stop`, `list` (the registry becomes the daemon's truth and adoption returns real
`LiveComputer`s); (3) give `rackyd` the `com.apple.security.virtualization` entitlement (it is signed separately in
`scripts/build.sh`; the launcher `rackyd-launch` execs it, so entitle the real binary); (4) the TCP bridge listener must live in the
daemon, and the app reads the port from the API. The scheduler would then adopt exactly like Docker. Estimated 2–3 days; the
`VZBackend`/`RunningVM` seam was drawn so the daemon only has to serialize it.

## Assets

Three files, listed in a manifest (`runtime/vz-manifest.json`, baked into `Contents/Resources/runtime`; **placeholders until
published**): `kernel` (Kata `vmlinux`), `vminit` (apple/containerization guest init, OCI tar), `computer` (the slim image, OCI tar). Each
has `url` + `sha256` (+ size). `AssetDownloader` is checksummed and resumable (`Range`, `.part`, sidecar `.verified`), supports
`https` and `file://`. The first reservation shows "Downloading the computer runtime (X of Y MB)…" on the computer row and in
Settings › Computers › Computer runtime, then "Preparing the computer runtime…" (OCI import + one-time unpack). State lives in
`vz/assets/ready.json`; afterwards nothing needs the network.

Manifest lookup: `RACKY_VZ_MANIFEST` (URL or path; relative asset URLs resolve next to it) else `<runtime>/vz-manifest.json`.

### Build locally (no publishing)

```sh
scripts/vz/fetch-kernel.sh          # Kata 3.32.0 tarball (~650 MB, resumable) -> build/vz-assets/{vmlinux,vmlinux.config,KERNEL-SOURCE.txt}
scripts/vz/build-image.sh           # docker build runtime/computer/Dockerfile.slim (linux/arm64, label racky.vz-dev=1) + docker save;
                                    # vminit via the containerization client (docker pull rejects the published image's diff ids);
                                    # writes build/vz-assets/vz-manifest.json (relative URLs, sha256, sizes)
scripts/vz/selftest.sh              # boots REAL VMs from those files with a temp RACKY_HOME; or RACKY_TEST_VZ=1 scripts/test.sh integration
RACKY_VZ_MANIFEST=$PWD/build/vz-assets/vz-manifest.json   # to try it in a dev app build
```

`scripts/vz/publish-assets.sh` only **prints** the `gh release` commands and the manifest update; it executes nothing.

The kernel is GPL-2.0-only: it is downloaded as a separate file (never linked into the app); the manifest and `KERNEL-SOURCE.txt`
point at the Kata/kernel.org source, and `vmlinux.config` must be published beside the binary.

`runtime/computer/Dockerfile.slim` is the ported `Dockerfile.slim2` (1.38 GB image, 387 MB tar): python:3.12-slim-bookworm pinned by
digest, Chromium only, no `playwright` pip package (the runtime uses `patchright`), no Mesa/LLVM. The original `Dockerfile` stays
for Docker mode.

## Limits

* **One shared vmnet subnet** (default `192.168.64.0/24`) for all VMs and the Mac gateway. Isolation relies on: the per-uid iptables
  in each VM, the proxy's SSRF filter (`internal_subnet` is set to the real vmnet subnet), the admin API bound to loopback inside the VM,
  and per-computer tokens. No per-computer networks.
* **Memory ~1.3 GB host footprint per VM** with an idle Chromium (guest limit 2.5 GiB headless); capacity for admission is 60% of
  physical memory (`VZRuntime.Config.memoryShare`), not a Docker VM size.
* **VM lifetime = app lifetime** (above). No `docker restart`-style resurrection.
* **virtiofs coherence:** a host file replaced by rename becomes visible in the VM after ~1.1 s (entry cache); new files are
  immediate; guest writes are visible to the Mac immediately. The selftest asserts both.
* **No persistent Chromium profile** in this runtime (the Docker provisioning path does not wire named profiles either); `/profile` is
  in the discarded rootfs.
* **No seccomp**: the vmexec launch path ignores `linux.seccomp`. Probed: an `agent` process cannot connect to vminitd's vsock
  port (CID 1 reset, CID 3 error), so it cannot drive vminitd, but this is an empirical check on kernel 6.18.35, not a policy.
  Shipping runc + a profile that denies `AF_VSOCK` would make it a policy.
* Disk: template ≈ 0.95 GB on disk + OCI blobs ≈ 0.4 GB; each running computer adds only its copy-on-write delta.
* Requires macOS 26 (vmnet network API) and the entitlement `com.apple.security.virtualization`, applied to the app by
  `scripts/build.sh` (`App/Racky.entitlements`; works with ad-hoc and the local identity). A build without it silently stays on Docker.

## Tests

* Unit: `VZTests` (plan mapping, registry + sweep, manifest, downloader incl. a local Range-capable HTTP server, provisioning flow
  with a fake VM and the real bridge), `DockerTests/RuntimeSelectorTests`, `CoreTests/NativeRuntimeSelectionTests`, Python
  `runtime/computer/tests/test_vsock_forward.py`.
* Integration (`RACKY_TEST_VZ=1`): `LiveVZTests` runs `scripts/vz/selftest.sh` (the test process has no virtualization entitlement, so
  the self-test binary is built and signed ad-hoc with it). It covers boot, exec, virtiofs both ways + coherence, copyIn/Out,
  secrets by stdin, bridge to :8790, admin API not reachable over the vmnet IP, vsock probe, headless computer with real Chromium
  (page open through the egress proxy), VNC websocket through the bridge, kill-on-timeout, two computers at once, teardown leaves nothing.

## What is left

* Publish the three assets and replace the placeholders in `runtime/vz-manifest.json` (needs the owner's go-ahead).
* Host VMs in `rackyd` if computers must survive the UI (plan above).
* Onboarding/Diagnostics still probe and mention Docker/images; they should report "not needed" when the native runtime is active.
* seccomp/AF_VSOCK denial (ship runc), per-computer networks, persistent profiles.
* Consume images straight from a registry (`ImageStore.pull`) instead of OCI tar files, so GHCR hosting is enough.
* Soft/hard memory pressure policy (balloon) and an Intel/older-macOS story beyond "use Docker".
