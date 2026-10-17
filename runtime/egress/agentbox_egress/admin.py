"""Admin API do egress (publicada só em 127.0.0.1 pelo app; 07 CS-111, CS-603, 08 AR-107).

Autenticada pelo token do computador (arquivo montado, nunca env): `Authorization: Bearer <token>`. Só `/v1/health` é aberto
e não devolve nada além de "ok". Não há rota que escreva no reqlog: quem escreve é o proxy.
"""
from __future__ import annotations

import asyncio
import hmac
import json
from urllib.parse import parse_qs, urlsplit

from .config import load_config
from .proxy import EgressProxy, header_value, parse_head


class AdminServer:
    def __init__(self, proxy: EgressProxy, token: str | None, config_loader=lambda: load_config(required=True)):
        self.proxy = proxy
        self.token = token
        self.config_loader = config_loader

    def _authorized(self, headers) -> bool:
        if not self.token:
            return False  # sem token configurado, nada além do health
        supplied = header_value(headers, "authorization") or ""
        if not supplied.lower().startswith("bearer "):
            return False
        return hmac.compare_digest(supplied[7:].strip().encode(), self.token.encode())

    async def handle(self, reader, writer) -> None:
        try:
            try:
                head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 10)
            except Exception:
                return
            request_line, headers = parse_head(head)
            method, _, rest = request_line.partition(" ")
            target = rest.rpartition(" ")[0]
            url = urlsplit(target)
            query = parse_qs(url.query)
            try:
                status, ctype, body = await self.route(method, url.path, query, headers)
            except Exception as exc:  # config inválida etc.: o estado anterior fica; nunca devolve valores de segredo
                status, ctype, body = 500, "application/json", {"error": "internal", "type": type(exc).__name__}
            data = body if isinstance(body, bytes) else json.dumps(body, sort_keys=True).encode()
            writer.write(f"HTTP/1.1 {status} X\r\nContent-Type: {ctype}\r\nContent-Length: {len(data)}\r\nConnection: close\r\n\r\n".encode() + data)
            await writer.drain()
        except ConnectionError:
            pass
        finally:
            try:
                writer.close()
            except Exception:
                pass

    async def route(self, method: str, path: str, query, headers):
        if method == "GET" and path == "/v1/health":
            return 200, "application/json", {"ok": True}
        if not self._authorized(headers):
            return 401, "application/json", {"error": "unauthorized"}
        p = self.proxy
        if method == "GET" and path == "/v1/usage":
            return 200, "application/json", p.usage_snapshot()
        if method == "GET" and path == "/v1/proxy":
            up = p.config.upstream
            return 200, "application/json", {
                "via": p.config.via, "scheme": up.scheme if up else None, "host": up.host if up else None,
                "port": up.port if up else None, "geo": up.geo_country if up else None,
                "allow_cidrs": p.config.allow_cidrs, "allow_hosts": p.config.allow_hosts,
            }
        if method == "GET" and path == "/v1/reqlog":
            since = (query.get("since") or [None])[0]
            limit = int((query.get("limit") or ["200"])[0])
            return 200, "application/json", {"records": p.reqlog.read(since, max(1, min(limit, 1000)))}
        if method == "GET" and path.startswith("/v1/reqlog/") and path.endswith("/body"):
            rid = path[len("/v1/reqlog/"):-len("/body")]
            kind = (query.get("kind") or ["response"])[0]
            rec = next((r for r in p.reqlog.read(None, 100000) if r["id"] == rid), None)
            rel = rec.get(f"{kind}_body_file") if rec else None
            file = p.reqlog.body_path(rel) if rel else None
            if file is None:
                return 404, "application/json", {"error": "not_found"}
            return 200, "text/plain; charset=utf-8", file.read_bytes()
        if method == "POST" and path == "/v1/proxy/reload":
            cfg = await asyncio.to_thread(self.config_loader)  # pode esperar o bind do host enxergar o arquivo novo
            closed = p.apply_config(cfg)
            p.flush_usage()
            return 200, "application/json", {"applied": True, "via": cfg.via, "closed_tunnels": closed}
        return 404, "application/json", {"error": "not_found"}
