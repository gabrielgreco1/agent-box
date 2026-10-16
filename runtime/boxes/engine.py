"""One persistent Agent Box computer. No Docker or host control lives here."""
from __future__ import annotations

import fcntl
import io
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
import uuid
from urllib.parse import urlparse


class RuntimeFailure(Exception):
    pass


class BrowserWorker:
    """Playwright's sync API stays on its own thread across all calls."""
    def __init__(self, profile: Path, downloads: Path):
        self.profile, self.downloads = profile, downloads
        self.jobs: queue.Queue = queue.Queue()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        context = None
        try:
            from playwright.sync_api import sync_playwright
            with sync_playwright() as playwright:
                while True:
                    job, args, reply = self.jobs.get()
                    try:
                        if job == 'stop':
                            if context: context.close()
                            reply.put((True, None))
                            return
                        if job == 'launch':
                            if context: context.close()
                            headed, initial_url = args
                            context = playwright.chromium.launch_persistent_context(
                                str(self.profile), headless=not headed, accept_downloads=True,
                                downloads_path=str(self.downloads), viewport={'width': 1280, 'height': 800},
                                env=dict(os.environ, DISPLAY=':99') if headed else None,
                            )
                            def save_download(download):
                                safe_name = Path(download.suggested_filename).name
                                download.save_as(str(self.downloads / f'{uuid.uuid4().hex}-{safe_name}'))
                            def attach_page(page):
                                page.on('download', save_download)
                            context.on('page', attach_page)
                            for existing_page in context.pages: attach_page(existing_page)
                            page = context.pages[0] if context.pages else context.new_page()
                            if initial_url: page.goto(initial_url, wait_until='domcontentloaded', timeout=15000)
                            reply.put((True, page.url))
                        elif job == 'close':
                            if context: context.close()
                            context = None
                            reply.put((True, None))
                        elif job == 'navigate':
                            if not context: raise RuntimeFailure('browser is not running')
                            (url,) = args
                            page = context.pages[0] if context.pages else context.new_page()
                            page.goto(url, wait_until='domcontentloaded', timeout=15000)
                            reply.put((True, page.url))
                        elif job == 'screenshot':
                            if not context: raise RuntimeFailure('browser is not running')
                            page = context.pages[0] if context.pages else context.new_page()
                            reply.put((True, page.screenshot(type='jpeg', quality=70, timeout=5000)))
                    except Exception as exc:
                        reply.put((False, str(exc)))
        except Exception as exc:
            while True:
                _, _, reply = self.jobs.get()
                reply.put((False, f'Playwright unavailable: {exc}'))

    def call(self, job, *args, timeout=22):
        reply = queue.Queue(maxsize=1)
        self.jobs.put((job, args, reply))
        try: ok, value = reply.get(timeout=timeout)
        except queue.Empty: raise RuntimeFailure('browser operation timed out')
        if not ok: raise RuntimeFailure(value)
        return value


class RealDisplay:
    def __init__(self):
        self.xvfb = self.wm = None
        self.environment = dict(os.environ, DISPLAY=':99')
        self.pressed_buttons = set()

    def start(self):
        if self.xvfb and self.xvfb.poll() is None: return
        self.xvfb = subprocess.Popen(['Xvfb', ':99', '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(30):
            if self.xvfb.poll() is not None: raise RuntimeFailure('Xvfb exited')
            if Path('/tmp/.X11-unix/X99').exists(): break
            time.sleep(.1)
        else: raise RuntimeFailure('Xvfb did not become ready')
        self.wm = subprocess.Popen(['openbox', '--sm-disable'], env=self.environment,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(.2)
        if self.wm.poll() is not None: raise RuntimeFailure('window manager exited')
        os.environ['DISPLAY'] = ':99'

    def ready(self):
        return bool(self.xvfb and self.wm and self.xvfb.poll() is None and self.wm.poll() is None)

    def frame(self):
        if not self.ready(): raise RuntimeFailure('desktop display is unavailable')
        from mss import mss
        from PIL import Image
        with mss(display=':99') as capture:
            monitor = capture.monitors[1]
            raw = capture.grab(monitor)
            image = Image.frombytes('RGB', raw.size, raw.rgb)
            output = io.BytesIO()
            image.save(output, format='JPEG', quality=65)
            return output.getvalue()

    def input(self, action):
        if not self.ready(): raise RuntimeFailure('desktop display is unavailable')
        kind = action.get('kind')
        if kind == 'move':
            x, y = action.get('x'), action.get('y')
            if type(x) is not int or type(y) is not int or not (0 <= x < 1280 and 0 <= y < 800):
                raise ValueError('invalid desktop coordinates')
            argv = ['xdotool', 'mousemove', str(x), str(y)]
        elif kind == 'click':
            button = action.get('button')
            if type(button) is not int or button not in (1, 2, 3): raise ValueError('invalid mouse button')
            argv = ['xdotool', 'click', str(button)]
        elif kind == 'button':
            button, pressed = action.get('button'), action.get('pressed')
            if type(button) is not int or button not in (1, 2, 3) or type(pressed) is not bool:
                raise ValueError('invalid button event')
            if pressed and button in self.pressed_buttons: return
            if not pressed and button not in self.pressed_buttons: return
            argv = ['xdotool', 'mousedown' if pressed else 'mouseup', str(button)]
        elif kind == 'key':
            key = action.get('key')
            if not isinstance(key, str) or not (1 <= len(key) <= 60) or not all(c.isalnum() or c in '+_-.' for c in key):
                raise ValueError('invalid key name')
            argv = ['xdotool', 'key', '--clearmodifiers', key]
        elif kind == 'text':
            value = action.get('text')
            if not isinstance(value, str) or len(value) > 4096 or '\x00' in value: raise ValueError('invalid text')
            argv = ['xdotool', 'type', '--clearmodifiers', '--delay', '1', '--', value]
        elif kind == 'scroll':
            direction = action.get('direction')
            if direction not in ('up', 'down', 'left', 'right'): raise ValueError('invalid scroll direction')
            clicks = action.get('clicks', 1)
            if type(clicks) is not int or not 1 <= clicks <= 20: raise ValueError('invalid scroll clicks')
            argv = ['xdotool', 'click', '--repeat', str(clicks),
                    {'up': '4', 'down': '5', 'left': '6', 'right': '7'}[direction]]
        else: raise ValueError('unsupported input kind')
        subprocess.run(argv, env=self.environment, timeout=5, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if kind == 'button':
            if pressed: self.pressed_buttons.add(button)
            else: self.pressed_buttons.remove(button)

    def release_input(self):
        if not self.ready():
            self.pressed_buttons.clear()
            return
        for button in tuple(sorted(self.pressed_buttons)):
            self.input({'kind': 'button', 'button': button, 'pressed': False})

    def stop(self):
        self.release_input()
        for process in (self.wm, self.xvfb):
            if process and process.poll() is None:
                process.terminate()
                try: process.wait(timeout=2)
                except subprocess.TimeoutExpired: process.kill()
        self.wm = self.xvfb = None


class ComputerEngine:
    def __init__(self, computer_id: str, data: Path, browser=None, display=None):
        self.computer_id = computer_id
        self.data = data
        self.data.mkdir(parents=True, exist_ok=True)
        (data / 'profile').mkdir(exist_ok=True)
        (data / 'workspace' / 'downloads').mkdir(parents=True, exist_ok=True)
        self.profile_lock = (data / 'profile.lock').open('a+')
        try: fcntl.flock(self.profile_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.profile_lock.close()
            raise RuntimeFailure('profile already has an active computer')
        self.lock = threading.RLock()
        self.browser = browser or BrowserWorker(data / 'profile', data / 'workspace' / 'downloads')
        self.display = display or RealDisplay()
        self.mode = 'http'
        self.browser_ready = False
        self.generation = 0
        self.last_epoch = 0
        self.lease = None
        self.last_url = None
        checkpoint = data / 'checkpoint.json'
        if checkpoint.exists():
            saved = json.loads(checkpoint.read_text())
            self.generation = int(saved.get('generation', 0))
            self.last_url = saved.get('last_url')

    def _checkpoint(self):
        path = self.data / 'checkpoint.json'
        temp = path.with_suffix('.tmp')
        temp.write_text(json.dumps({'generation': self.generation, 'last_url': self.last_url}))
        temp.replace(path)

    def health(self):
        with self.lock:
            ready = self.display.ready() if self.mode == 'desktop' else False
            source = 'desktop' if ready else ('browser' if self.mode == 'headless' else 'none')
            return {'computer_id': self.computer_id, 'generation': self.generation, 'mode': self.mode,
                    'browser_ready': self.browser_ready, 'display_ready': ready,
                    'frame_source': source, 'active_lease': None if self.lease is None else
                    {key: self.lease[key] for key in ('actor_id', 'epoch', 'paths')}}

    def switch_mode(self, mode):
        if mode not in ('http', 'headless', 'desktop'): raise ValueError('invalid mode')
        with self.lock:
            if mode == self.mode: return self.health()
            previous = self.mode
            if previous in ('headless', 'desktop'):
                self.browser.call('close')
                self.browser_ready = False
            if mode == 'desktop': self.display.start()
            try:
                if mode in ('headless', 'desktop'):
                    self.last_url = self.browser.call('launch', mode == 'desktop', self.last_url)
                    self.browser_ready = True
                self.mode = mode
                self.generation += 1
                self._checkpoint()
            except Exception:
                self.mode = 'http'
                self.browser_ready = False
                self.display.stop()
                raise
            if previous == 'desktop' and mode != 'desktop': self.display.stop()
            return self.health()

    def navigate(self, url):
        parsed = urlparse(url)
        if parsed.scheme not in ('http', 'https') or not parsed.netloc: raise ValueError('invalid URL')
        with self.lock:
            if self.mode == 'http': raise RuntimeFailure('browser is not running')
            self.last_url = self.browser.call('navigate', url)
            self._checkpoint()
            return {'url': self.last_url, 'generation': self.generation}

    def frame(self):
        with self.lock:
            if self.mode == 'desktop': return self.display.frame(), 'desktop'
            if self.mode == 'headless': return self.browser.call('screenshot'), 'browser'
            raise RuntimeFailure('no frame available in HTTP mode')

    def input(self, action):
        with self.lock:
            if self.mode != 'desktop': raise RuntimeFailure('input requires desktop mode')
            self.display.input(action)
            return {'accepted': True, 'generation': self.generation}
