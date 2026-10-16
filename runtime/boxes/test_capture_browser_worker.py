import sys
import tempfile
import time
import types
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

from capture import CaptureStore
from engine import BrowserWorker


class Request:
    def __init__(self, url):
        self.url, self.method = url, 'GET'


class Response:
    def __init__(self, request, status):
        self.request, self.status = request, status
        self.headers = {'content-type': 'application/json; charset=utf-8'}


class Page:
    def __init__(self, context): self.context, self.pumped = context, False
    def on(self, _name, _handler): pass
    def bring_to_front(self): pass
    @property
    def url(self): return 'about:blank'
    def wait_for_timeout(self, _milliseconds):
        if self.pumped: return
        self.pumped = True
        context = self.context
        # This runs only during the idle Playwright pump, after launch returns.
        new_page = Page(context)
        context.pages.append(new_page)
        context.emit('page', new_page)
        first = Request('https://example.com/redirect?secret=HIDDEN')
        second = Request('https://example.com/result?secret=HIDDEN')
        failed = Request('https://example.com/fail?secret=HIDDEN')
        for request, status in ((first, 302), (second, 200)):
            context.emit('request', request)
            context.emit('response', Response(request, status))
            context.emit('requestfinished', request)
        context.emit('request', failed)
        context.emit('requestfailed', failed)
        # An unrelated in-flight request must not inflate capture loss when the
        # browser closes; it was never eligible for the configured host.
        context.emit('request', Request('https://unlisted.example/private?secret=HIDDEN'))


class Context:
    def __init__(self):
        self.handlers = {}
        self.pages = [Page(self)]
    def on(self, name, handler): self.handlers.setdefault(name, []).append(handler)
    def emit(self, name, value):
        for handler in self.handlers.get(name, []): handler(value)
    def close(self): pass


class Playwright:
    def __init__(self, context):
        self.chromium = types.SimpleNamespace(launch_persistent_context=lambda *a, **kw: context)
    def __enter__(self): return self
    def __exit__(self, *_): pass


class BrowserCaptureTests(unittest.TestCase):
    def test_new_page_redirect_and_failure_pump_while_idle(self):
        with tempfile.TemporaryDirectory() as directory:
            store = CaptureStore('computer-1')
            store.configure({'enabled': True, 'hosts': ['example.com'],
                'path_prefixes': [], 'include_json': False, 'json_fields': [],
                'max_body_bytes': 4096, 'max_events': 256, 'retention_seconds': 3600})
            context = Context()
            package = types.ModuleType('playwright')
            module = types.ModuleType('playwright.sync_api')
            module.sync_playwright = lambda: Playwright(context)
            with patch.dict(sys.modules, {'playwright': package, 'playwright.sync_api': module}):
                worker = BrowserWorker(Path(directory) / 'profile', Path(directory) / 'downloads', store)
                worker.call('launch', False, None)
                deadline = time.monotonic() + 2
                while len(store.snapshot(0)['events']) < 3 and time.monotonic() < deadline:
                    time.sleep(.02)
                worker.call('stop')
        events = store.snapshot(0)['events']
        self.assertEqual(len(events), 3)
        self.assertEqual(store.snapshot(0)['dropped'], 0)
        self.assertEqual([event['status'] for event in events], [302, 200, None])
        self.assertEqual(events[2]['omission'], 'request_failed')
        self.assertTrue(all(event['source'] == 'browser' for event in events))
        self.assertTrue(all(datetime.fromisoformat(event['timestamp']).tzinfo == timezone.utc
                            for event in events))
        self.assertEqual(len({event['request_id'] for event in events}), 3)
        self.assertTrue(all(event['url'] == 'https://example.com' for event in events))
        self.assertNotIn('HIDDEN', str(events))


if __name__ == '__main__': unittest.main()
