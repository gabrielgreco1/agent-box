import json
from pathlib import Path
import tempfile
import threading
import unittest
from datetime import datetime, timezone
import urllib.error
import urllib.request
from unittest.mock import patch

from engine import ComputerEngine, RealDisplay, RuntimeFailure
from server import ComputerServer


class FakeBrowser:
    def __init__(self): self.calls = []
    def call(self, name, *args, **kwargs):
        self.calls.append((name, args))
        if name in ('launch', 'navigate'): return args[-1]
        if name == 'screenshot': return b'fake-browser-jpeg'
        if name == 'page':
            return {'url': 'https://example.com/', 'title': 'Example', 'text': 'T' * 70_000,
                    'links': [{'url': 'https://example.com/a', 'label': 'L' * 400}] * 201,
                    'truncated': False, 'input_value': 'must not escape'}
        return None


class FakeDisplay:
    def __init__(self): self.running = False; self.actions = []; self.releases = 0
    def start(self): self.running = True
    def ready(self): return self.running
    def frame(self): return b'fake-whole-display-jpeg'
    def input(self, action): self.actions.append(action)
    def release_input(self): self.releases += 1
    def stop(self): self.running = False


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.browser, self.display = FakeBrowser(), FakeDisplay()
        self.engine = ComputerEngine('a635d250-14d1-4432-bac5-af57f613bb3a', Path(self.temp.name), self.browser, self.display)
        self.token = 'a' * 40
        self.server = ComputerServer(('127.0.0.1', 0), self.engine, self.token)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = 'http://127.0.0.1:' + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(2)
        self.engine.profile_lock.close(); self.temp.cleanup()

    def request(self, path, body=None, token=True, lease=None):
        headers = {'Authorization': 'Bearer ' + (self.token if token else 'wrong')}
        if body is not None: headers['Content-Type'] = 'application/json'
        if lease:
            headers.update({'X-Racky-Actor-ID': lease['actor_id'],
                            'X-Racky-Lease-Epoch': str(lease['epoch']),
                            'X-Racky-Control-Token': lease['control_token']})
        request = urllib.request.Request(self.base + path, data=None if body is None else json.dumps(body).encode(), headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                payload = response.read()
                return response.status, response.headers, json.loads(payload) if response.headers.get_content_type() == 'application/json' else payload
        except urllib.error.HTTPError as error:
            with error:
                return error.code, error.headers, json.loads(error.read())

    def grant(self):
        code, _, lease = self.request('/v1/control/grant', {'actor_id': 'human', 'epoch': 7,
                                                              'paths': ['mode', 'input', 'navigate']})
        self.assertEqual(code, 200)
        return lease

    def test_auth_and_health(self):
        self.assertEqual(self.request('/v1/health', token=False)[0], 401)
        code, _, health = self.request('/v1/health')
        self.assertEqual(code, 200)
        self.assertEqual(health['mode'], 'http')
        self.assertFalse(health['display_ready'])
        self.assertEqual(health['frame_source'], 'none')

    def test_lease_gates_writes_and_revocation_ack(self):
        self.assertEqual(self.request('/v1/mode', {'mode': 'desktop'})[0], 403)
        lease = self.grant()
        bad = dict(lease, control_token='wrong')
        self.assertEqual(self.request('/v1/mode', {'mode': 'desktop'}, lease=bad)[0], 403)
        self.assertEqual(self.request('/v1/mode', {'mode': 'desktop'}, lease=lease)[0], 200)
        code, headers, frame = self.request('/v1/frame')
        self.assertEqual((code, headers['X-Racky-Frame-Source'], frame), (200, 'desktop', b'fake-whole-display-jpeg'))
        stream_request = urllib.request.Request(self.base + '/v1/stream', headers={'Authorization': 'Bearer ' + self.token})
        with urllib.request.urlopen(stream_request, timeout=3) as stream:
            self.assertEqual(stream.headers['X-Racky-Frame-Source'], 'desktop')
            self.assertIn(b'fake-whole-display-jpeg', stream.read(150))
        self.assertEqual(self.request('/v1/input', {'kind': 'click', 'button': 1}, lease=lease)[0], 200)
        self.assertEqual(self.request('/v1/input', {'kind': 'button', 'button': 1, 'pressed': True}, lease=lease)[0], 200)
        self.assertEqual(self.request('/v1/input', {'kind': 'move', 'x': 1279, 'y': 799}, lease=lease)[0], 200)
        self.assertEqual(self.request('/v1/input', {'kind': 'button', 'button': 1, 'pressed': False}, lease=lease)[0], 200)
        self.assertEqual(self.request('/v1/input', {'kind': 'scroll', 'direction': 'left', 'clicks': 2}, lease=lease)[0], 200)
        self.assertEqual(len(self.display.actions), 5)
        self.assertEqual(self.request('/v1/input', {'kind': 'button', 'button': 1, 'pressed': True}, lease=bad)[0], 403)
        self.assertEqual(self.request('/v1/control/revoke', {'actor_id': 'human', 'epoch': 6})[0], 409)
        code, _, ack = self.request('/v1/control/revoke', {'actor_id': 'human', 'epoch': 7})
        self.assertEqual(code, 200)
        self.assertTrue(ack['acknowledged'])
        self.assertEqual(self.display.releases, 1)
        self.assertEqual(self.request('/v1/input', {'kind': 'click', 'button': 1}, lease=lease)[0], 403)
        self.assertEqual(self.request('/v1/control/grant', {'actor_id': 'agent', 'epoch': 7, 'paths': ['input']})[0], 400)

    def test_promotion_preserves_profile_checkpoint_and_full_display(self):
        lease = self.grant()
        self.request('/v1/mode', {'mode': 'headless'}, lease=lease)
        self.request('/v1/navigate', {'url': 'https://example.com/'}, lease=lease)
        _, headers, frame = self.request('/v1/frame')
        self.assertEqual(headers['X-Racky-Frame-Source'], 'browser')
        self.assertEqual(frame, b'fake-browser-jpeg')
        self.assertEqual(self.request('/v1/stream')[0], 409)
        _, _, health = self.request('/v1/mode', {'mode': 'desktop'}, lease=lease)
        self.assertEqual((health['generation'], health['frame_source']), (2, 'desktop'))
        self.assertEqual(self.browser.calls[-1], ('launch', (True, 'https://example.com/')))
        checkpoint = json.loads((Path(self.temp.name) / 'checkpoint.json').read_text())
        self.assertEqual(checkpoint['last_url'], 'https://example.com/')
        self.assertTrue((Path(self.temp.name) / 'profile').is_dir())
        self.assertTrue((Path(self.temp.name) / 'workspace').is_dir())

    def test_authenticated_page_snapshot_is_bounded_and_mode_specific(self):
        self.assertEqual(self.request('/v1/page', token=False)[0], 401)
        self.assertEqual(self.request('/v1/page')[0], 409)
        lease = self.grant()
        self.request('/v1/mode', {'mode': 'headless'}, lease=lease)
        code, _, page = self.request('/v1/page')
        self.assertEqual(code, 200)
        self.assertEqual((page['computer_id'], page['generation']), (self.engine.computer_id, 1))
        self.assertEqual((len(page['text']), len(page['links']), len(page['links'][0]['label'])),
                         (65_536, 200, 300))
        self.assertTrue(page['truncated'])
        self.assertNotIn('input_value', page)
        self.request('/v1/mode', {'mode': 'desktop'}, lease=lease)
        self.assertEqual(self.request('/v1/page')[0], 200)

    def test_http_request_keeps_lease_and_attaches_computer_identity(self):
        body = {'url': 'https://example.com/', 'method': 'HEAD'}
        self.assertEqual(self.request('/v1/http/request', body)[0], 403)
        code, _, lease = self.request('/v1/control/grant', {'actor_id': 'agent', 'epoch': 8,
                                                           'paths': ['http_request']})
        self.assertEqual(code, 200)
        with patch('server.public_http.request', return_value={
                'status': 200, 'content_type': 'text/plain', 'body_base64': ''}) as fetch:
            code, _, result = self.request('/v1/http/request', body, lease=lease)
        self.assertEqual(code, 200)
        fetch.assert_called_once_with(body)
        self.assertEqual((result['computer_id'], result['generation']), (self.engine.computer_id, 0))
        self.assertEqual(result['status'], 200)

    def test_capture_config_requires_bearer_and_explicit_allowlist(self):
        settings = {'enabled': True, 'hosts': ['example.com'], 'path_prefixes': [],
                    'include_json': False, 'json_fields': [], 'max_body_bytes': 4096,
                    'max_events': 2, 'retention_seconds': 3600}
        self.assertEqual(self.request('/v1/capture/config', settings, token=False)[0], 401)
        self.assertEqual(self.request('/v1/capture/config', dict(settings, hosts=[]))[0], 400)
        code, _, configured = self.request('/v1/capture/config', settings)
        self.assertEqual(code, 200)
        self.assertTrue(configured['enabled'])
        self.assertEqual(configured['computer_id'], self.engine.computer_id)
        self.assertEqual(configured['events'], [])
        self.assertEqual(self.request('/v1/capture?after=0', token=False)[0], 401)
        self.assertEqual(self.request('/v1/capture?after=nope')[0], 400)

        code, _, lease = self.request('/v1/control/grant', {'actor_id': 'agent', 'epoch': 8,
                                                           'paths': ['http_request']})
        self.assertEqual(code, 200)
        with patch('server.public_http.request', return_value={
                'status': 200, 'content_type': 'text/plain', 'body_base64': ''}):
            self.assertEqual(self.request('/v1/http/request',
                {'url': 'https://example.com/private?token=SECRET', 'method': 'GET'}, lease=lease)[0], 200)
        code, _, batch = self.request('/v1/capture?after=0')
        self.assertEqual(code, 200)
        self.assertEqual(len(batch['events']), 1)
        self.assertEqual(batch['events'][0]['url'], 'https://example.com')
        self.assertNotIn('SECRET', json.dumps(batch))
        self.assertEqual(batch['events'][0]['source'], 'http_tool')
        self.assertEqual(datetime.fromisoformat(batch['events'][0]['timestamp']).tzinfo, timezone.utc)
        self.assertEqual(batch['next_cursor'], 1)
        self.assertEqual(self.request('/v1/capture?after=1')[2]['events'], [])
        self.assertEqual(self.request('/v1/capture/config', settings)[2]['events'], batch['events'],
                         "Idempotent configuration must return a full retained batch")

        old_id = batch['capture_id']
        settings['hosts'] = ['other.example']
        self.assertNotEqual(self.request('/v1/capture/config', settings)[2]['capture_id'], old_id)
        self.assertEqual(self.request('/v1/capture?after=0')[2]['events'], [])
        self.assertEqual(self.request('/v1/capture/clear', {}, token=False)[0], 401)
        self.assertEqual(self.request('/v1/capture/clear', {'unexpected': True})[0], 400)
        prior = self.request('/v1/capture?after=0')[2]['capture_id']
        code, _, cleared = self.request('/v1/capture/clear', {})
        self.assertEqual(code, 200)
        self.assertEqual(cleared['events'], [])
        self.assertTrue(cleared['enabled'])
        self.assertNotEqual(cleared['capture_id'], prior)
        self.assertEqual(self.request('/v1/capture?after=0')[2]['capture_id'], cleared['capture_id'])

    def test_profile_lock_rejects_second_engine(self):
        with self.assertRaises(RuntimeFailure):
            ComputerEngine('another', Path(self.temp.name), FakeBrowser(), FakeDisplay())

    def test_real_display_input_tracks_held_buttons_and_scroll(self):
        display = RealDisplay()
        with patch.object(display, 'ready', return_value=True), patch('engine.subprocess.run') as run:
            display.input({'kind': 'button', 'button': 1, 'pressed': True})
            display.input({'kind': 'move', 'x': 400, 'y': 300})
            display.input({'kind': 'button', 'button': 1, 'pressed': True})
            display.input({'kind': 'scroll', 'direction': 'right', 'clicks': 3})
            self.assertEqual(run.call_count, 3)
            self.assertEqual(run.call_args.args[0], ['xdotool', 'click', '--repeat', '3', '7'])
            display.release_input()
            self.assertEqual(run.call_args.args[0], ['xdotool', 'mouseup', '1'])
            self.assertEqual(display.pressed_buttons, set())
            with self.assertRaises(ValueError): display.input({'kind': 'button', 'button': True, 'pressed': True})
            with self.assertRaises(ValueError): display.input({'kind': 'scroll', 'direction': 'up', 'clicks': True})


if __name__ == '__main__': unittest.main()
