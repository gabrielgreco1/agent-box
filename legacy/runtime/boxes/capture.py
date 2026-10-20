"""Opt-in, in-memory passive capture of narrowly sanitized network evidence.

This is not a proxy or a universal network recorder. Configuration is supplied
only through the host runtime API; browser pages never receive this object.
"""
from __future__ import annotations

import base64
from collections import deque
from datetime import datetime, timezone
import hashlib
import json
import math
import re
import threading
import time
from urllib.parse import urlsplit
import uuid


COVERAGE = ['browser_context_requests', 'browser_context_responses',
            'browser_context_failures', 'broker_http_get_head']
GAPS = ['browser_worker_internal_requests', 'websocket_frames', 'cache_revalidation_detail',
        'browser_response_bodies', 'curl', 'python_requests', 'curl_cffi',
        'other_python_libraries', 'raw_sockets', 'proxy_traffic',
        'broker_http_redirects_not_followed', 'configuration_changes_clear_ring']
RING_BYTE_LIMIT = 900_000
_HOST = re.compile(r'^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$')
_FIELD = re.compile(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$')
_PREFIX = re.compile(r'^/[A-Za-z0-9/_.-]{0,199}$')
_SAFE_MIME = {'text/html', 'text/plain', 'text/css', 'text/xml',
              'application/json', 'application/problem+json',
              'application/javascript', 'application/xml',
              'application/octet-stream', 'image/png', 'image/jpeg',
              'image/webp', 'image/gif', 'font/woff', 'font/woff2'}
_METHOD = re.compile(r'^[A-Z]{1,16}$')
_METHODS = {'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'}
_SENSITIVE = ('token', 'secret', 'password', 'passwd', 'cookie', 'authorization',
              'auth', 'key', 'credential', 'session')


def _integer(value, low, high):
    if type(value) is not int or not low <= value <= high:
        raise ValueError('invalid capture configuration')
    return value


class CaptureStore:
    def __init__(self, computer_id, clock=time.monotonic):
        self.computer_id = computer_id
        self.capture_id = str(uuid.uuid4())
        self.clock = clock
        self.lock = threading.RLock()
        self.enabled = False
        self.hosts = set()
        self.path_prefixes = ()
        self.include_json = False
        self.json_fields = ()
        self.max_body_bytes = 4096
        self.max_events = 256
        self.retention_seconds = 3600
        self.events = deque()
        self.event_bytes = 0
        self.sequence = 0
        self.dropped = 0

    def configure(self, body):
        keys = {'enabled', 'hosts', 'path_prefixes', 'include_json', 'json_fields',
                'max_body_bytes', 'max_events', 'retention_seconds'}
        if type(body) is not dict or set(body) != keys or type(body['enabled']) is not bool or \
           type(body['include_json']) is not bool:
            raise ValueError('invalid capture configuration')
        hosts = body['hosts']
        if type(hosts) is not list or len(hosts) > 64 or any(type(x) is not str or
                not _HOST.fullmatch(x) or x != x.lower() or '..' in x or
                x.startswith('-') or x.endswith('-') for x in hosts):
            raise ValueError('invalid capture hosts')
        if body['enabled'] and not hosts:
            raise ValueError('capture requires an explicit host allowlist')
        prefixes = body['path_prefixes']
        if type(prefixes) is not list or len(prefixes) > 32 or any(type(x) is not str or
                not _PREFIX.fullmatch(x) or '..' in x or '//' in x for x in prefixes):
            raise ValueError('invalid capture path prefixes')
        fields = body['json_fields']
        if type(fields) is not list or len(fields) > 32 or any(type(x) is not str or
                not _FIELD.fullmatch(x) or any(word in x.lower() for word in _SENSITIVE)
                for x in fields):
            raise ValueError('invalid capture JSON fields')
        if body['include_json'] and not fields:
            raise ValueError('JSON capture requires explicit scalar fields')
        cap = _integer(body['max_body_bytes'], 1, 65_536)
        limit = _integer(body['max_events'], 1, 1000)
        ttl = _integer(body['retention_seconds'], 1, 86_400)
        with self.lock:
            changed = (self.enabled != body['enabled'] or self.hosts != set(hosts) or
                       self.path_prefixes != tuple(sorted(set(prefixes), key=len, reverse=True)) or
                       self.include_json != body['include_json'] or
                       self.json_fields != tuple(dict.fromkeys(fields)) or
                       self.max_body_bytes != cap or self.max_events != limit or
                       self.retention_seconds != ttl)
            if changed:
                self.capture_id = str(uuid.uuid4())
                self.events.clear()
                self.event_bytes = self.sequence = self.dropped = 0
            self.enabled = body['enabled']
            self.hosts = set(hosts)
            self.path_prefixes = tuple(sorted(set(prefixes), key=len, reverse=True))
            self.include_json = body['include_json']
            self.json_fields = tuple(dict.fromkeys(fields))
            self.max_body_bytes, self.max_events, self.retention_seconds = cap, limit, ttl
            self._prune()
            # Configuration responses use the same complete batch schema as
            # polling. An idempotent reapply may still contain retained events.
            return self.snapshot(0)

    def _status(self):
        return {'schema_version': 1, 'coverage_version': 'racky-capture/1',
                'computer_id': self.computer_id, 'capture_id': self.capture_id,
                'enabled': self.enabled, 'coverage': COVERAGE, 'gaps': GAPS,
                'next_cursor': self.sequence, 'dropped': self.dropped}

    def clear(self):
        with self.lock:
            self.capture_id = str(uuid.uuid4())
            self.events.clear()
            self.event_bytes = self.sequence = self.dropped = 0
            result = self._status()
            result['events'] = []
            return result

    def _prune(self):
        deadline = self.clock() - self.retention_seconds
        while self.events and (self.events[0][0] < deadline or len(self.events) > self.max_events or
                               self.event_bytes > RING_BYTE_LIMIT):
            _, _, size = self.events.popleft()
            self.event_bytes -= size
            self.dropped += 1

    def record_loss(self, count, capture_id):
        with self.lock:
            if self.enabled and capture_id == self.capture_id:
                self.dropped += count

    def snapshot(self, after):
        _integer(after, 0, 2**63 - 1)
        with self.lock:
            self._prune()
            result = self._status()
            result['events'] = [event.copy() for _, event, _ in self.events if event['sequence'] > after]
            return result

    def _safe_url(self, raw):
        if not isinstance(raw, str) or len(raw) > 4096:
            return None
        try:
            parsed = urlsplit(raw)
            if parsed.scheme not in ('http', 'https') or not parsed.hostname or \
               parsed.username is not None or parsed.password is not None:
                return None
            host = parsed.hostname.lower().rstrip('.')
            if host not in self.hosts or not _HOST.fullmatch(host):
                return None
            port = parsed.port
            origin = f'{parsed.scheme}://{host}' + (f':{port}' if port is not None else '')
            # Include only a specifically approved static prefix, never a full
            # path or its query/fragment. Paths may themselves contain tokens.
            path = next((x for x in self.path_prefixes if parsed.path.startswith(x)), '')
            return origin + path
        except ValueError:
            return None

    def _add(self, *, source, request_id, method, raw_url, status=None,
             mime=None, duration_ms=None, body_json=None, body_sha256=None, omission=None):
        with self.lock:
            if not self.enabled:
                return
            url = self._safe_url(raw_url)
            if url is None:
                return
            self._prune()
            self.sequence += 1
            event = {'sequence': self.sequence, 'request_id': request_id,
                     'source': source, 'method': method if isinstance(method, str) and
                     _METHOD.fullmatch(method) and method in _METHODS else 'OTHER', 'url': url,
                     'status': status if type(status) is int and 100 <= status <= 599 else None,
                     'mime': mime if mime in _SAFE_MIME else None,
                     'timestamp': datetime.now(timezone.utc).isoformat(timespec='milliseconds'),
                     'duration_ms': round(duration_ms, 2) if type(duration_ms) in (int, float) and
                     math.isfinite(duration_ms) and 0 <= duration_ms < 3_600_000 else None,
                     'body_json': body_json, 'body_sha256': body_sha256, 'omission': omission}
            size = len(json.dumps(event, separators=(',', ':')).encode())
            self.events.append((self.clock(), event, size))
            self.event_bytes += size
            self._prune()

    def browser(self, *, request_id, method, url, status=None, mime=None,
                duration_ms=None, failure=False, capture_id=None):
        with self.lock:
            if capture_id is not None and capture_id != self.capture_id: return
            self._add(source='browser', request_id=request_id, method=method, raw_url=url,
                      status=status, mime=mime, duration_ms=duration_ms,
                      omission='request_failed' if failure else 'browser_body_not_captured')

    def broker_http(self, *, method, url, result, duration_ms, failure=False):
        body_json = body_sha256 = None
        omission = 'body_not_requested'
        mime = result.get('content_type', '').split(';', 1)[0].strip().lower()
        with self.lock:
            capture_json = self.enabled and self.include_json and bool(self.json_fields)
            cap, fields = self.max_body_bytes, self.json_fields
            capture_id = self.capture_id
        if capture_json and not failure:
            omission = 'not_json'
            if mime in ('application/json', 'application/problem+json'):
                encoded = result.get('body_base64', '')
                if isinstance(encoded, str) and len(encoded) <= ((cap + 2) // 3) * 4:
                    try:
                        raw = base64.b64decode(encoded, validate=True)
                        if len(raw) > cap:
                            omission = 'body_too_large'
                        else:
                            value = json.loads(raw)
                            if isinstance(value, dict):
                                selected = {}
                                for field in fields:
                                    item = value.get(field)
                                    if item is None or type(item) is bool or \
                                       type(item) is int or (type(item) is float and math.isfinite(item)) or \
                                       (type(item) is str and len(item) <= 256):
                                        if field in value: selected[field] = item
                                body_json = selected
                                body_sha256 = hashlib.sha256(raw).hexdigest()
                                omission = None
                            else:
                                omission = 'json_not_object'
                    except (ValueError, UnicodeError):
                        omission = 'invalid_json'
                else:
                    omission = 'body_too_large'
        with self.lock:
            if capture_id != self.capture_id: return
            self._add(source='http_tool', request_id=str(uuid.uuid4()), method=method,
                      raw_url=url, status=result.get('status'), mime=mime,
                      duration_ms=duration_ms, body_json=body_json,
                      body_sha256=body_sha256,
                      omission='request_failed' if failure else omission)
