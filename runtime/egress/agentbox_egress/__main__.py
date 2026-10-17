"""Ponto de entrada: sobe o proxy (só na interface da rede interna) e a admin API."""
from __future__ import annotations

import asyncio
import ipaddress
import signal
import subprocess
import sys

from .admin import AdminServer
from .config import load_config, load_token
from .proxy import EgressProxy


def internal_address(subnet: str) -> str | None:
    """Endereço local dentro de `subnet`. O egress é dual-homed: o proxy NÃO pode escutar na bridge de saída, senão o
    egress de outro computador (mesma bridge) o alcançaria."""
    net = ipaddress.ip_network(subnet, strict=False)
    out = subprocess.run(["ip", "-o", "-4", "addr", "show"], capture_output=True, text=True, timeout=5).stdout
    for line in out.splitlines():
        fields = line.split()
        if "inet" in fields:
            addr = fields[fields.index("inet") + 1].split("/")[0]
            if ipaddress.ip_address(addr) in net:
                return addr
    return None


async def main() -> int:
    config = load_config()
    token = load_token()
    proxy = EgressProxy(config)
    if config.bind:
        bind = config.bind
    elif config.internal_subnet:
        bind = internal_address(config.internal_subnet)
        if bind is None:
            print(f"egress: nenhuma interface em {config.internal_subnet}; recusando subir (fail closed)", file=sys.stderr)
            return 2
    else:
        print("egress: sem internal_subnet nem bind; recusando subir (fail closed)", file=sys.stderr)
        return 2
    proxy_server = await asyncio.start_server(proxy.handle, bind, config.proxy_port, limit=1 << 17, backlog=256)
    admin = AdminServer(proxy, token)
    admin_server = await asyncio.start_server(admin.handle, "0.0.0.0", config.admin_port)
    print(f"egress: proxy em {bind}:{config.proxy_port}, admin em :{config.admin_port}, via={config.via}", flush=True)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    async def flusher() -> None:
        while True:
            await asyncio.sleep(1)
            proxy.flush_usage()

    task = asyncio.ensure_future(flusher())
    await stop.wait()
    task.cancel()
    proxy_server.close()
    admin_server.close()
    proxy.close_all("shutdown")
    proxy.dirty = True
    proxy.flush_usage()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
