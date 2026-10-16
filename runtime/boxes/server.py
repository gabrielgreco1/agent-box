"""Authenticated loopback-published Agent Box runtime API."""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hmac
import json
import os
from pathlib import Path
import secrets
import signal
import threading
import time
import uuid
from urllib.parse import parse_qs, urlsplit

from engine import ComputerEngine, RuntimeFailure
import public_http

PATHS = {'http_request', 'navigate', 'input', 'mode'}


class ComputerServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, engine, api_token):
        super().__init__(address, ComputerHandler)
        if not api_token or len(api_token) < 32: raise ValueError('AB_API_TOKEN must be at least 32 characters')
        self.engine, self.api_token = engine, api_token


class ComputerHandler(BaseHTTPRequestHandler):
    server: ComputerServer
    protocol_version = 'HTTP/1.1'

    def log_message(self, format, *args):
        # URLs may contain application secrets. Avoid request logs entirely.
        pass

    def _send(self, status, body, content_type='application/json', extra=None):
        if isinstance(body, dict): body = json.dumps(body, separators=(',', ':')).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        for key, value in (extra or {}).items(): self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status, reason):
        self._send(status, {'error': reason})

    def _authenticated(self):
        supplied = self.headers.get('Authorization', '')
        expected = 'Bearer ' + self.server.api_token
        return hmac.compare_digest(supplied, expected)

    def _body(self):
        try: length = int(self.headers.get('Content-Length', '-1'))
        except ValueError: raise ValueError('invalid content length')
        if length < 0 or length > 65536: raise ValueError('invalid content length')
        payload = json.loads(self.rfile.read(length))
        if not isinstance(payload, dict): raise ValueError('JSON object required')
        return payload

    def _write_allowed(self, path):
        lease = self.server.engine.lease
        if lease is None or path not in lease['paths']: return False
        actor = self.headers.get('X-AgentBox-Actor-ID', '')
        epoch = self.headers.get('X-AgentBox-Lease-Epoch', '')
        token = self.headers.get('X-AgentBox-Control-Token', '')
        return actor == lease['actor_id'] and epoch == str(lease['epoch']) and hmac.compare_digest(token, lease['control_token'])

    def do_GET(self):
        if self.path == '/ready': return self._send(200, {'ready': True})
        if not self._authenticated(): return self._error(401, 'unauthorized')
        if urlsplit(self.path).path == '/v1/capture':
            try:
                parsed = urlsplit(self.path)
                query = parse_qs(parsed.query, keep_blank_values=True, strict_parsing=True)
                if set(query) != {'after'} or len(query['after']) != 1 or \
                   not query['after'][0].isascii() or not query['after'][0].isdigit():
                    raise ValueError('invalid capture cursor')
                return self._send(200, self.server.engine.capture.snapshot(int(query['after'][0])))
            except ValueError: return self._error(400, 'invalid capture cursor')
        if self.path == '/v1/health': return self._send(200, self.server.engine.health())
        if self.path == '/v1/page':
            try: return self._send(200, self.server.engine.page())
            except RuntimeFailure as exc: return self._error(409, str(exc))
        if self.path == '/v1/frame':
            try: frame, source = self.server.engine.frame()
            except RuntimeFailure as exc: return self._error(409, str(exc))
            return self._send(200, frame, 'image/jpeg', {'X-AgentBox-Frame-Source': source})
        if self.path == '/v1/stream': return self._stream()
        return self._error(404, 'not found')

    def _stream(self):
        if self.server.engine.health()['frame_source'] != 'desktop':
            return self._error(409, 'full desktop stream requires desktop mode')
        self.send_response(200)
        self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=agentboxframe')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-AgentBox-Frame-Source', 'desktop')
        self.end_headers()
        try:
            while self.server.engine.health()['frame_source'] == 'desktop':
                frame, source = self.server.engine.frame()
                if source != 'desktop': break
                self.wfile.write(b'--agentboxframe\r\nContent-Type: image/jpeg\r\nContent-Length: ' + str(len(frame)).encode() + b'\r\n\r\n')
                self.wfile.write(frame + b'\r\n')
                self.wfile.flush()
                time.sleep(.25)
        except (BrokenPipeError, ConnectionResetError, RuntimeFailure): pass

    def do_POST(self):
        if not self._authenticated(): return self._error(401, 'unauthorized')
        try: body = self._body()
        except (ValueError, json.JSONDecodeError) as exc: return self._error(400, str(exc))
        engine = self.server.engine
        try:
            with engine.lock:
                if self.path == '/v1/capture/clear':
                    if body: raise ValueError('capture clear expects an empty object')
                    return self._send(200, engine.capture.clear())
                if self.path == '/v1/capture/config':
                    return self._send(200, engine.capture.configure(body))
                if self.path == '/v1/control/grant':
                    actor, epoch, paths = body.get('actor_id'), body.get('epoch'), body.get('paths')
                    if not isinstance(actor, str) or not (1 <= len(actor) <= 200) or type(epoch) is not int or epoch <= engine.last_epoch or not isinstance(paths, list) or not paths or not all(isinstance(path, str) and path in PATHS for path in paths):
                        raise ValueError('invalid grant or stale epoch')
                    if engine.lease is not None: return self._error(409, 'lease already active')
                    token = secrets.token_urlsafe(32)
                    engine.lease = {'actor_id': actor, 'epoch': epoch, 'paths': sorted(set(paths)), 'control_token': token}
                    engine.last_epoch = epoch
                    return self._send(200, dict(engine.lease))
                if self.path == '/v1/control/revoke':
                    actor, epoch = body.get('actor_id'), body.get('epoch')
                    lease = engine.lease
                    if lease is None or actor != lease['actor_id'] or epoch != lease['epoch']:
                        return self._error(409, 'lease mismatch')
                    engine.display.release_input()
                    engine.lease = None
                    return self._send(200, {'revoked_actor_id': actor, 'revoked_epoch': epoch, 'acknowledged': True})
                path = {'/v1/mode': 'mode', '/v1/navigate': 'navigate', '/v1/input': 'input',
                        '/v1/http/request': 'http_request'}.get(self.path)
                if path is None: return self._error(404, 'not found')
                if not self._write_allowed(path): return self._error(403, 'lease denied')
                if path == 'mode': return self._send(200, engine.switch_mode(body.get('mode')))
                if path == 'navigate': return self._send(200, engine.navigate(body.get('url')))
                if path == 'input': return self._send(200, engine.input(body))
                if path == 'http_request':
                    started = time.monotonic()
                    try: result = public_http.request(body)
                    except Exception:
                        engine.capture.broker_http(method=body.get('method', 'GET'),
                            url=body.get('url'), result={},
                            duration_ms=(time.monotonic() - started) * 1000, failure=True)
                        raise
                    engine.capture.broker_http(method=body.get('method', 'GET'),
                        url=body.get('url'), result=result,
                        duration_ms=(time.monotonic() - started) * 1000)
                    result.update(generation=engine.generation, computer_id=engine.computer_id)
                    return self._send(200, result)
        except ValueError as exc: return self._error(400, str(exc))
        except RuntimeFailure as exc: return self._error(409, str(exc))
        except Exception: return self._error(500, 'runtime operation failed')

def main():
    token = os.environ.get('AB_API_TOKEN', '')
    computer_id = os.environ.get('AB_COMPUTER_ID', '')
    try: uuid.UUID(computer_id)
    except ValueError: raise SystemExit('AB_COMPUTER_ID must be a UUID')
    engine = ComputerEngine(computer_id, Path('/data'))
    server = ComputerServer(('0.0.0.0', 8765), engine, token)
    stopping = threading.Event()
    def shutdown(signum, frame):
        if not stopping.is_set():
            stopping.set()
            # BaseServer.shutdown must run outside the serve_forever thread.
            threading.Thread(target=server.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    try:
        server.serve_forever(poll_interval=.1)
    finally:
        server.server_close()
        engine.close()


if __name__ == '__main__': main()
