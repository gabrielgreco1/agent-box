"""Bounded public-web GET/HEAD with DNS validation and a pinned socket."""
from __future__ import annotations

import base64
import http.client
import ipaddress
import queue
import socket
import ssl
import threading
import time
from urllib.parse import urlsplit

BODY_LIMIT = 1_048_576
TIMEOUT = 10
_DNS_SLOTS = threading.BoundedSemaphore(8)


def _resolve(host, port, deadline):
    # getaddrinfo has no timeout parameter. Bound waiting without accumulating
    # unbounded resolver threads if the system resolver stalls.
    if not _DNS_SLOTS.acquire(blocking=False):
        raise TimeoutError('DNS resolver is busy')
    result = queue.Queue(maxsize=1)

    def work():
        try:
            result.put((socket.getaddrinfo(host, port, type=socket.SOCK_STREAM,
                                           proto=socket.IPPROTO_TCP), None))
        except BaseException as exc:
            result.put((None, exc))
        finally:
            _DNS_SLOTS.release()

    threading.Thread(target=work, daemon=True).start()
    try:
        answer, error = result.get(timeout=max(0, deadline - time.monotonic()))
    except queue.Empty as exc:
        raise TimeoutError('HTTP request timed out') from exc
    if error is not None:
        raise error
    return answer


def _public_address(value):
    address = ipaddress.ip_address(value)
    if not address.is_global or address.is_reserved or address.is_multicast:
        raise ValueError('URL resolves to a non-public address')
    return address


def _destination(url, deadline):
    if not isinstance(url, str) or not (1 <= len(url) <= 4096) or any(ord(c) < 32 for c in url):
        raise ValueError('invalid URL')
    try:
        parsed = urlsplit(url)
        if parsed.scheme not in ('http', 'https') or not parsed.netloc or parsed.username is not None or parsed.password is not None:
            raise ValueError('invalid URL')
        hostname = parsed.hostname
        if not hostname or '%' in hostname or '\\' in hostname:
            raise ValueError('invalid URL')
        host = hostname.encode('idna').decode('ascii')
        port = parsed.port or (443 if parsed.scheme == 'https' else 80)
        if not 1 <= port <= 65535:
            raise ValueError('invalid URL')
        target = (parsed.path or '/') + (('?' + parsed.query) if parsed.query else '')
        if any(ord(c) < 32 for c in target):
            raise ValueError('invalid URL')
    except (UnicodeError, ValueError) as exc:
        raise ValueError('invalid URL') from exc
    results = _resolve(host, port, deadline)
    if not results:
        raise ValueError('URL has no addresses')
    # A mixed public/private DNS answer is unsafe even if the first answer is public.
    vetted = [(_public_address(entry[4][0]), entry[0]) for entry in results]
    return parsed.scheme, host, port, target, vetted[0]


def _socket_to(address, family, port, timeout):
    sock = socket.socket(family, socket.SOCK_STREAM, socket.IPPROTO_TCP)
    try:
        sock.settimeout(timeout)
        sock.connect((str(address), port))
        return sock
    except BaseException:
        sock.close()
        raise


class _PinnedHTTP(http.client.HTTPConnection):
    def __init__(self, host, port, address, family, timeout):
        super().__init__(host, port, timeout=timeout)
        self.address, self.family = address, family

    def connect(self):
        self.sock = _socket_to(self.address, self.family, self.port, self.timeout)


class _PinnedHTTPS(http.client.HTTPSConnection):
    def __init__(self, host, port, address, family, timeout):
        super().__init__(host, port, timeout=timeout, context=ssl.create_default_context())
        self.address, self.family = address, family

    def connect(self):
        sock = _socket_to(self.address, self.family, self.port, self.timeout)
        try:
            self.sock = self._context.wrap_socket(sock, server_hostname=self.host)
        except BaseException:
            sock.close()
            raise


def request(body):
    """Return only status, bounded content type and base64 body; never follow redirects."""
    if not isinstance(body, dict) or set(body) - {'url', 'method'}:
        raise ValueError('only URL and method are supported')
    method = body.get('method', 'GET')
    if method not in ('GET', 'HEAD'):
        raise ValueError('only GET and HEAD are supported')
    deadline = time.monotonic() + TIMEOUT
    scheme, host, port, target, (address, family) = _destination(body.get('url'), deadline)
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError('HTTP request timed out')
    connection_type = _PinnedHTTPS if scheme == 'https' else _PinnedHTTP
    connection = connection_type(host, port, address, family, remaining)
    deadline_timer = None
    try:
        connection.request(method, target, headers={})
        connected_socket = connection.sock
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('HTTP request timed out')
        # http.client parses status and headers using buffered readline(). A
        # peer can drip bytes faster than the socket's per-recv timeout, so
        # close the read side at the absolute deadline as well.
        def end_response():
            try:
                connected_socket.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        deadline_timer = threading.Timer(remaining, end_response)
        deadline_timer.daemon = True
        deadline_timer.start()
        connected_socket.settimeout(remaining)
        response = connection.getresponse()
        if time.monotonic() >= deadline:
            raise TimeoutError('HTTP request timed out')
        content_type = response.getheader('Content-Type', '')[:300]
        chunks, total = [], 0
        if method == 'GET':
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError('HTTP request timed out')
                connected_socket.settimeout(remaining)
                # read1 returns after one underlying read; read(n) can keep
                # receiving a slow trickle until n bytes, defeating a deadline.
                chunk = response.read1(min(65_536, BODY_LIMIT + 1 - total))
                if not chunk:
                    break
                total += len(chunk)
                if total > BODY_LIMIT:
                    raise ValueError('HTTP response exceeds 1 MiB')
                chunks.append(chunk)
                if response.isclosed():
                    break
        if time.monotonic() >= deadline:
            raise TimeoutError('HTTP request timed out')
        return {'status': response.status, 'content_type': content_type,
                'body_base64': base64.b64encode(b''.join(chunks)).decode('ascii')}
    except (OSError, http.client.HTTPException) as exc:
        if time.monotonic() >= deadline:
            raise TimeoutError('HTTP request timed out') from exc
        raise
    finally:
        if deadline_timer is not None:
            deadline_timer.cancel()
        connection.close()
