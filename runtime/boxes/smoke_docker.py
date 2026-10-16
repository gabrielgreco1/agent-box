"""Explicit disposable smoke test; only touches the named Docker context and owned IDs."""
from __future__ import annotations

import io
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

from PIL import Image

CONTEXT = 'colima-agentbox-dev'
IMAGE = 'agentbox-browser:ab019-dev'
DOCKER = ['docker', '--context', CONTEXT]
RUN_ID = uuid.uuid4().hex[:12]
NAME = f'agentbox-ab019-smoke-{RUN_ID}'
VOLUME = f'agentbox-ab019-smoke-data-{RUN_ID}'
COMPUTER_ID = str(uuid.uuid4())
created_volume = False
containers = []


def docker(*args):
    return subprocess.run(DOCKER + list(args), check=True, text=True, capture_output=True).stdout.strip()


def request(port, token, path, body=None, lease=None):
    headers = {'Authorization': 'Bearer ' + token}
    if body is not None: headers['Content-Type'] = 'application/json'
    if lease:
        headers.update({'X-AgentBox-Actor-ID': lease['actor_id'],
                        'X-AgentBox-Lease-Epoch': str(lease['epoch']),
                        'X-AgentBox-Control-Token': lease['control_token']})
    req = urllib.request.Request(f'http://127.0.0.1:{port}{path}',
                                 data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            data = response.read()
            return response.status, response.headers, json.loads(data) if response.headers.get_content_type() == 'application/json' else data
    except urllib.error.HTTPError as error:
        with error:
            return error.code, error.headers, json.loads(error.read())


def checked(port, token, path, body=None, lease=None):
    code, headers, value = request(port, token, path, body, lease)
    if code != 200: raise RuntimeError(f'{path}: HTTP {code}: {value}')
    return headers, value


def start_container(suffix):
    token = secrets.token_urlsafe(48)
    with tempfile.NamedTemporaryFile(mode='w', prefix='ab019-env-', delete=False) as env_file:
        env_file.write(f'AB_API_TOKEN={token}\nAB_COMPUTER_ID={COMPUTER_ID}\n')
        env_path = env_file.name
    os.chmod(env_path, 0o600)
    name = NAME + suffix
    try:
        ident = docker('run', '-d', '--init', '--name', name,
                       '--label', 'com.agentbox.smoke=' + RUN_ID,
                       '--mount', f'type=volume,source={VOLUME},target=/data',
                       '--publish', '127.0.0.1::8765', '--env-file', env_path,
                       '--cpus', '1', '--memory', '2g', '--pids-limit', '256', '--shm-size', '256m',
                       '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
                       '--read-only', '--tmpfs', '/tmp:rw,nosuid,nodev,size=256m',
                       '--tmpfs', '/home/agentbox:rw,nosuid,nodev,size=32m,uid=10001,gid=10001', IMAGE)
    finally: os.unlink(env_path)
    containers.append(ident)
    port_line = docker('port', ident, '8765/tcp')
    port = int(port_line.rsplit(':', 1)[1])
    for _ in range(60):
        try:
            checked(port, token, '/v1/health')
            break
        except Exception: time.sleep(.25)
    else: raise RuntimeError('runtime did not become healthy')
    return ident, port, token


def start_page_server(ident):
    page = '''<!doctype html><html><head><title>AB JS loading</title><style>body{margin:0;background:red}</style></head><body><script>
    const previous=localStorage.getItem('ab019-smoke');
    document.body.style.background=previous==='persisted'?'blue':'red';
    document.title=previous==='persisted'?'AB JS persisted':'AB JS fresh';
    localStorage.setItem('ab019-smoke','persisted');
    document.addEventListener('click',()=>{document.body.style.background='green';document.title='AB JS clicked'});
    </script></body></html>'''
    docker('exec', ident, 'python', '-c', "from pathlib import Path; Path('/data/workspace/smoke.html').write_text(" + repr(page) + ")")
    docker('exec', '-d', ident, 'python', '-m', 'http.server', '8766', '--bind', '127.0.0.1', '--directory', '/data/workspace')
    time.sleep(.3)


def dominant(data, x=640, y=400):
    image = Image.open(io.BytesIO(data)).convert('RGB')
    return image.getpixel((min(x, image.width - 1), min(y, image.height - 1)))


def main():
    global created_volume
    try:
        docker('volume', 'create', '--label', 'com.agentbox.smoke=' + RUN_ID, VOLUME)
        created_volume = True
        ident, port, token = start_container('-a')
        _, health = checked(port, token, '/v1/health')
        assert health['computer_id'] == COMPUTER_ID and health['mode'] == 'http'
        _, lease = checked(port, token, '/v1/control/grant', {'actor_id': 'agent:smoke', 'epoch': 7,
                                                               'paths': ['mode', 'navigate', 'input']})
        _, health = checked(port, token, '/v1/mode', {'mode': 'headless'}, lease)
        assert health['browser_ready'] and health['frame_source'] == 'browser'
        start_page_server(ident)
        _, nav = checked(port, token, '/v1/navigate', {'url': 'http://127.0.0.1:8766/smoke.html'}, lease)
        _, screenshot = checked(port, token, '/v1/frame')
        headless_pixel = dominant(screenshot)
        assert headless_pixel[0] > 150 and headless_pixel[1] < 100 and headless_pixel[2] < 100, headless_pixel
        _, health = checked(port, token, '/v1/mode', {'mode': 'desktop'}, lease)
        assert health['display_ready'] and health['frame_source'] == 'desktop'
        browser_info = json.loads(docker('exec', ident, 'python', '-c',
            "import json,urllib.request; j=json.load(urllib.request.urlopen('http://127.0.0.1:9222/json/version')); print(json.dumps({k:j[k] for k in ['Browser','User-Agent']}))"))
        assert ':9222' not in docker('port', ident)
        headers, frame = checked(port, token, '/v1/frame')
        assert headers['X-AgentBox-Frame-Source'] == 'desktop'
        assert Image.open(io.BytesIO(frame)).size == (1280, 800)
        checked(port, token, '/v1/input', {'kind': 'move', 'x': 640, 'y': 400}, lease)
        checked(port, token, '/v1/input', {'kind': 'click', 'button': 1}, lease)
        _, after = checked(port, token, '/v1/frame')
        clicked_pixel = dominant(after)
        # The page should occupy the center; exact pixels depend on WM/browser window placement.
        for _ in range(12):
            if clicked_pixel[1] > clicked_pixel[0] and clicked_pixel[1] > clicked_pixel[2]: break
            time.sleep(.25)
            _, after = checked(port, token, '/v1/frame')
            clicked_pixel = dominant(after)
        if os.environ.get('AB_SMOKE_FRAME_PATH'):
            Path(os.environ['AB_SMOKE_FRAME_PATH']).write_bytes(after)
        assert clicked_pixel[1] > clicked_pixel[0] and clicked_pixel[1] > clicked_pixel[2], clicked_pixel
        _, ack = checked(port, token, '/v1/control/revoke', {'actor_id': 'agent:smoke', 'epoch': 7})
        assert ack['acknowledged']
        assert request(port, token, '/v1/input', {'kind': 'click', 'button': 1}, lease)[0] == 403
        _, human = checked(port, token, '/v1/control/grant', {'actor_id': 'human', 'epoch': 8, 'paths': ['input']})
        checked(port, token, '/v1/input', {'kind': 'move', 'x': 400, 'y': 300}, human)
        checked(port, token, '/v1/control/revoke', {'actor_id': 'human', 'epoch': 8})
        docker('stop', ident)
        exit_code = docker('inspect', ident, '--format', '{{.State.ExitCode}}')
        if exit_code != '0':
            raise RuntimeError('runtime shutdown exit ' + exit_code + ': ' + docker('logs', ident))
        docker('rm', ident)
        containers.remove(ident)
        ident2, port2, token2 = start_container('-b')
        start_page_server(ident2)
        _, health2 = checked(port2, token2, '/v1/health')
        assert health2['generation'] == 2 and health2['mode'] == 'http'
        _, second = checked(port2, token2, '/v1/control/grant', {'actor_id': 'human', 'epoch': 9,
                                                                   'paths': ['mode', 'navigate']})
        checked(port2, token2, '/v1/mode', {'mode': 'headless'}, second)
        checked(port2, token2, '/v1/navigate', {'url': 'http://127.0.0.1:8766/smoke.html'}, second)
        _, persisted = checked(port2, token2, '/v1/frame')
        persisted_pixel = dominant(persisted)
        assert persisted_pixel[2] > 150 and persisted_pixel[0] < 100 and persisted_pixel[1] < 100, persisted_pixel
        print(json.dumps({'context': CONTEXT, 'image': IMAGE, 'image_id': docker('image', 'inspect', IMAGE, '--format', '{{.Id}}'),
                          'architecture': docker('image', 'inspect', IMAGE, '--format', '{{.Architecture}}'),
                          'headless_js_pixel': headless_pixel, 'desktop_frame_size': [1280, 800],
                          'desktop_clicked_pixel': clicked_pixel, 'persisted_profile_pixel': persisted_pixel,
                          'lease_takeover': 'passed', 'container_restart': 'passed',
                          'desktop_browser': browser_info, 'result': 'passed'}))
    finally:
        for ident in list(containers):
            try: docker('stop', ident)
            except Exception: pass
            try: docker('rm', ident)
            except Exception: pass
        if created_volume:
            try: docker('volume', 'rm', VOLUME)
            except Exception: pass


if __name__ == '__main__': main()
