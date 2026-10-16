import base64
import json
import unittest

from capture import CaptureStore


def config(**changes):
    value = {'enabled': True, 'hosts': ['example.com'], 'path_prefixes': [],
             'include_json': False, 'json_fields': [], 'max_body_bytes': 4096,
             'max_events': 256, 'retention_seconds': 3600}
    value.update(changes)
    return value


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.now = 1000.0
        self.store = CaptureStore('computer-1', clock=lambda: self.now)

    def test_disabled_until_explicit_host_allowlist_and_instance_identity(self):
        self.store.browser(request_id='one', method='GET',
                           url='https://example.com/?secret=x', status=200)
        self.assertEqual(self.store.snapshot(0)['events'], [])
        with self.assertRaises(ValueError): self.store.configure(config(hosts=[]))
        with self.assertRaises(ValueError): self.store.configure(config(hosts=['*.example.com']))
        response = self.store.configure(config())
        self.assertEqual(response['coverage_version'], 'agentbox-capture/1')
        self.assertEqual(response['computer_id'], 'computer-1')
        self.assertNotEqual(response['capture_id'], CaptureStore('computer-1').capture_id)
        self.assertIn('browser_response_bodies', response['gaps'])

    def test_origin_only_static_prefix_and_no_url_secrets(self):
        self.store.configure(config(path_prefixes=['/api/public']))
        self.store.browser(request_id='one', method='POST',
            url='https://example.com/api/public/private-token?key=SECRET#SECRET',
            status=302, mime='application/json; secret=SECRET', duration_ms=12.5)
        self.store.browser(request_id='two', method='GET',
            url='https://example.com/account/SECRET?key=SECRET', status=200)
        self.store.browser(request_id='three', method='GET',
            url='https://elsewhere.test/?key=SECRET', status=200)
        self.store.browser(request_id='four', method='GET',
            url='https://user:SECRET@example.com/', status=200)
        events = self.store.snapshot(0)['events']
        self.assertEqual(len(events), 2)
        self.assertEqual([event['url'] for event in events],
                         ['https://example.com/api/public', 'https://example.com'])
        self.assertEqual(events[0]['omission'], 'browser_body_not_captured')
        self.assertIsNone(events[0]['mime'])
        self.assertNotIn('SECRET', json.dumps(events))

    def test_cursor_capacity_expiry_and_disable_are_explicit(self):
        self.store.configure(config(max_events=2, retention_seconds=5))
        for request_id in ('a', 'b', 'c'):
            self.store.browser(request_id=request_id, method='GET',
                               url='http://example.com/', status=200)
        snapshot = self.store.snapshot(1)
        self.assertEqual([event['sequence'] for event in snapshot['events']], [2, 3])
        self.assertEqual((snapshot['next_cursor'], snapshot['dropped']), (3, 1))
        self.now += 6
        self.assertEqual(self.store.snapshot(3)['dropped'], 3)
        self.assertEqual(self.store.snapshot(0)['events'], [])
        previous_id = self.store.capture_id
        self.store.configure(config(enabled=False))
        self.assertFalse(self.store.snapshot(0)['enabled'])
        self.assertEqual(self.store.snapshot(0)['next_cursor'], 0)
        self.assertNotEqual(self.store.capture_id, previous_id)

    def test_http_json_scalar_allowlist_and_body_bound(self):
        body = json.dumps({'name': 'fixture', 'count': 2, 'private': 'SECRET',
                           'nested': {'secret': 'SECRET'}, 'other': 'SECRET'}).encode()
        # The explicit field allowlist is the user's content decision; fields
        # outside it and non-scalars are always omitted.
        self.store.configure(config(include_json=True, json_fields=['name', 'count', 'nested'],
                                    max_body_bytes=256))
        self.store.broker_http(method='GET', url='https://example.com/data?token=SECRET',
            result={'status': 200, 'content_type': 'application/json; charset=utf-8',
                    'body_base64': base64.b64encode(body).decode()}, duration_ms=10)
        event = self.store.snapshot(0)['events'][0]
        self.assertEqual(event['body_json'], {'name': 'fixture', 'count': 2})
        self.assertIsNotNone(event['body_sha256'])
        self.assertNotIn('SECRET', json.dumps(event))
        self.store.broker_http(method='GET', url='https://example.com/data',
            result={'status': 200, 'content_type': 'application/json',
                    'body_base64': base64.b64encode(b'x' * 257).decode()}, duration_ms=10)
        self.assertEqual(self.store.snapshot(1)['events'][0]['omission'], 'body_too_large')
        self.assertIsNone(self.store.snapshot(1)['events'][0]['body_sha256'])

    def test_config_rejects_unsafe_shapes_without_changing_active_config(self):
        self.store.configure(config())
        for changed in (config(max_events=True), config(retention_seconds=0),
                        config(max_body_bytes=65_537), config(path_prefixes=['/token?secret']),
                        config(json_fields=['a.b']), config(json_fields=['access_token']),
                        config(hosts=['bad..host']), config(hosts=['-bad.host']),
                        config(include_json=True),
                        dict(config(), unexpected=True)):
            with self.assertRaises(ValueError): self.store.configure(changed)
            self.assertTrue(self.store.snapshot(0)['enabled'])

        self.store.browser(request_id='method', method='TRACE',
                           url='https://example.com/', status=200)
        self.assertEqual(self.store.snapshot(0)['events'][0]['method'], 'OTHER')

    def test_ring_total_bytes_are_bounded_below_one_megabyte(self):
        fields = [f'value{i}' for i in range(8)]
        self.store.configure(config(max_events=1000, include_json=True,
                                    json_fields=fields, max_body_bytes=4096))
        value = base64.b64encode(json.dumps({field: 'x' * 256 for field in fields}).encode()).decode()
        for _ in range(1000):
            self.store.broker_http(method='GET', url='https://example.com/',
                result={'status': 200, 'content_type': 'application/json',
                        'body_base64': value}, duration_ms=1)
        snapshot = self.store.snapshot(0)
        self.assertLess(len(json.dumps(snapshot).encode()), 1_000_000)
        self.assertGreater(snapshot['dropped'], 0)

    def test_old_inflight_browser_request_cannot_cross_configuration_change(self):
        self.store.configure(config())
        old_capture_id = self.store.capture_id
        self.store.configure(config(path_prefixes=['/approved']))
        self.store.browser(request_id='old', method='GET',
            url='https://example.com/approved/secret', status=200,
            capture_id=old_capture_id)
        self.assertEqual(self.store.snapshot(0)['events'], [])
        self.store.browser(request_id='new', method='GET',
            url='https://example.com/approved/secret', status=200,
            capture_id=self.store.capture_id)
        self.assertEqual(self.store.snapshot(0)['events'][0]['url'],
                         'https://example.com/approved')

    def test_clear_rotates_instance_and_preserves_active_filters(self):
        self.store.configure(config(path_prefixes=['/approved']))
        self.store.browser(request_id='old', method='GET',
            url='https://example.com/approved/secret', status=200)
        old_id = self.store.capture_id
        cleared = self.store.clear()
        self.assertTrue(cleared['enabled'])
        self.assertEqual(cleared['events'], [])
        self.assertEqual((cleared['next_cursor'], cleared['dropped']), (0, 0))
        self.assertNotEqual(cleared['capture_id'], old_id)
        self.store.browser(request_id='new', method='GET',
            url='https://example.com/approved/secret?token=HIDDEN', status=200)
        self.assertEqual(self.store.snapshot(0)['events'][0]['url'],
                         'https://example.com/approved')


if __name__ == '__main__': unittest.main()
