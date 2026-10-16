import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
import socket
import threading
import time
import unittest
from unittest.mock import patch

import public_http


class _Fixture(BaseHTTPRequestHandler):
    hits = []

    def log_message(self, *_): pass

    def _slow_headers(self):
        if self.path not in ('/slow-status', '/slow-header'):
            return False
        try:
            if self.path == '/slow-header':
                self.wfile.write(b'HTTP/1.1 200 OK\r\nX-Slow: ')
            else:
                self.wfile.write(b'HTTP/1.1 ')
            self.wfile.flush()
            for byte in b'200 OK\r\n' if self.path == '/slow-status' else b'abcdefghij\r\n':
                self.wfile.write(bytes([byte]))
                self.wfile.flush()
                time.sleep(.03)
            self.wfile.write(b'Content-Length: 0\r\n\r\n')
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError): pass
        return True

    def do_GET(self):
        self.hits.append((self.path, self.headers.get('Host')))
        if self._slow_headers(): return
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/secret')
            self.end_headers()
            return
        if self.path == '/slow':
            self.send_response(200)
            self.send_header('Content-Length', '10')
            self.end_headers()
            try:
                for _ in range(10):
                    self.wfile.write(b'x')
                    self.wfile.flush()
                    time.sleep(.05)
            except (BrokenPipeError, ConnectionResetError): pass
            return
        body = b'x' * (public_http.BODY_LIMIT + 1) if self.path == '/large' else b'public content'
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except BrokenPipeError: pass

    def do_HEAD(self):
        self.hits.append((self.path, self.headers.get('Host')))
        if self._slow_headers(): return
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()


class PublicHTTPTests(unittest.TestCase):
    def setUp(self):
        _Fixture.hits = []
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), _Fixture)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def _request(self, path, method='GET'):
        port = self.server.server_port
        def resolve(host, requested_port, **kwargs):
            self.assertEqual((host, requested_port), ('example.test', port))
            return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('8.8.8.8', port))]
        def pinned(address, family, requested_port, timeout):
            self.assertEqual((str(address), family, requested_port), ('8.8.8.8', socket.AF_INET, port))
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            sock.connect(('127.0.0.1', port))
            return sock
        with patch('public_http.socket.getaddrinfo', side_effect=resolve), \
             patch('public_http._socket_to', side_effect=pinned), \
             patch.dict(os.environ, {'HTTP_PROXY': 'http://127.0.0.1:1', 'HTTPS_PROXY': 'http://127.0.0.1:1'}):
            return public_http.request({'url': f'http://example.test:{port}{path}', 'method': method})

    def test_pinned_public_get_and_head_ignore_environment_proxy(self):
        get = self._request('/plain')
        self.assertEqual(get['status'], 200)
        self.assertEqual(base64.b64decode(get['body_base64']), b'public content')
        head = self._request('/plain', 'HEAD')
        self.assertEqual((head['status'], head['body_base64']), (200, ''))
        self.assertEqual([path for path, _ in _Fixture.hits], ['/plain', '/plain'])
        self.assertTrue(all(host.startswith('example.test:') for _, host in _Fixture.hits))

    def test_redirect_is_returned_without_following_and_body_is_bounded(self):
        response = self._request('/redirect')
        self.assertEqual(response['status'], 302)
        self.assertEqual([path for path, _ in _Fixture.hits], ['/redirect'])
        with self.assertRaisesRegex(ValueError, 'exceeds 1 MiB'):
            self._request('/large')

    def test_all_dns_answers_must_be_public_before_any_connection(self):
        answers = [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('8.8.8.8', 80)),
                   (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('127.0.0.1', 80))]
        with patch('public_http.socket.getaddrinfo', return_value=answers), \
             patch('public_http._socket_to') as connect:
            with self.assertRaisesRegex(ValueError, 'non-public'):
                public_http.request({'url': 'http://example.test/'})
            connect.assert_not_called()
        for address in ('10.0.0.1', '169.254.169.254', '224.0.0.1', '192.0.2.1', '::1', 'fe80::1'):
            with self.subTest(address=address), self.assertRaises(ValueError):
                public_http._public_address(address)

    def test_malformed_urls_credentials_headers_and_methods_are_rejected(self):
        invalid = [None, '', 'file:///etc/passwd', 'http://user:pass@example.test/',
                   'http://127.0.0.1/', 'http://[fe80::1%25en0]/', 'https://' + 'x' * 4097]
        for url in invalid:
            with self.subTest(url=str(url)[:40]), self.assertRaises((ValueError, OSError)):
                public_http.request({'url': url})
        for body in ({'url': 'http://example.test/', 'headers': {'Authorization': 'secret'}},
                     {'url': 'http://example.test/', 'method': 'POST'}):
            with self.assertRaises(ValueError): public_http.request(body)

    def test_https_pin_retains_original_hostname_for_certificate_check(self):
        address = public_http._public_address('8.8.8.8')
        with patch('public_http.ssl.create_default_context') as context, \
             patch('public_http._socket_to') as open_socket:
            connection = public_http._PinnedHTTPS('example.test', 443, address, socket.AF_INET, 10)
            connection.connect()
            open_socket.assert_called_once_with(address, socket.AF_INET, 443, 10)
            context.return_value.wrap_socket.assert_called_once_with(open_socket.return_value,
                                                                      server_hostname='example.test')

    def test_stalled_dns_is_bounded_before_connect(self):
        def stalled(*_, **__):
            time.sleep(.2)
            return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('8.8.8.8', 80))]
        with patch('public_http.TIMEOUT', .02), patch('public_http.socket.getaddrinfo', side_effect=stalled), \
             patch('public_http._socket_to') as connect:
            started = time.monotonic()
            with self.assertRaises(TimeoutError):
                public_http.request({'url': 'http://example.test/'})
            self.assertLess(time.monotonic() - started, .15)
            connect.assert_not_called()

    def test_slow_trickle_cannot_extend_total_response_deadline(self):
        with patch('public_http.TIMEOUT', .08):
            started = time.monotonic()
            with self.assertRaises(TimeoutError): self._request('/slow')
            self.assertLess(time.monotonic() - started, .3)

    def test_slow_status_and_headers_cannot_extend_total_deadline(self):
        with patch('public_http.TIMEOUT', .08):
            for path in ('/slow-status', '/slow-header'):
                for method in ('GET', 'HEAD'):
                    with self.subTest(path=path, method=method):
                        started = time.monotonic()
                        with self.assertRaises(TimeoutError): self._request(path, method)
                        self.assertLess(time.monotonic() - started, .8)


if __name__ == '__main__': unittest.main()
