"""Ponto de entrada do papel `runtime`: Xvfb sempre, Chromium headed, API de ações em :8765 (07 CS-190)."""
from __future__ import annotations

import asyncio
import os
import signal
import subprocess
import sys
from pathlib import Path

from .browser import BrowserSession, OpError
from .ingest import Ingestor, load_token
from .server import RuntimeServer

DISPLAY = os.environ.get("DISPLAY", ":99")
PORT = int(os.environ.get("AGENTBOX_RUNTIME_PORT", "8765"))


class Display:
    """Xvfb sempre ligado. `desktop` liga o Openbox (gerenciador de janelas) sem tocar no Chromium: a troca nunca recarrega a
    página (CS-191/192). Redimensionar o display exigiria reiniciar o Xvfb e fica fora desta tarefa."""

    def __init__(self) -> None:
        self.xvfb: subprocess.Popen | None = None
        self.openbox: subprocess.Popen | None = None
        self.mode = "headless"

    async def start_xvfb(self) -> None:
        self.xvfb = subprocess.Popen(["Xvfb", DISPLAY, "-screen", "0", "1440x900x24", "-nolisten", "tcp", "-ac"],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        socket = Path(f"/tmp/.X11-unix/X{DISPLAY.lstrip(':')}")
        for _ in range(100):
            if socket.exists():
                return
            if self.xvfb.poll() is not None:
                raise RuntimeError("Xvfb exited during startup")
            await asyncio.sleep(0.1)
        raise RuntimeError("Xvfb did not become ready")

    async def set_mode(self, display) -> dict:
        if display not in ("headless", "desktop"):
            raise OpError("invalid_argument", "display must be headless or desktop")
        if display == "desktop" and self.openbox is None:
            self.openbox = subprocess.Popen(["openbox"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if display == "headless" and self.openbox is not None:
            self.openbox.terminate()
            self.openbox = None
        self.mode = display
        return {"display": display, "reloaded": False}

    def stop(self) -> None:
        for proc in (self.openbox, self.xvfb):
            if proc and proc.poll() is None:
                proc.terminate()


async def main() -> int:
    token = load_token()
    if not token:
        print("runtime: sem token em /run/agentbox/token; recusando subir (fail closed)", file=sys.stderr)
        return 2
    display = Display()
    await display.start_xvfb()
    browser = BrowserSession(Ingestor(token))
    server = RuntimeServer(browser, token, display)
    listener = await asyncio.start_server(server.handle, "0.0.0.0", PORT, limit=1 << 20)
    await browser.start()
    print(f"runtime: API em :{PORT}, display {DISPLAY}, browser headed pronto", flush=True)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()
    listener.close()
    await browser.stop()
    display.stop()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
