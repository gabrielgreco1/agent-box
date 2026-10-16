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

from desktop_browser import DesktopBrowserProcess


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
        desktop = None
        attached_browser = None

        def close_browser():
            nonlocal context, desktop, attached_browser
            if desktop is not None:
                if attached_browser is not None:
                    try: attached_browser.new_browser_cdp_session().send('Browser.close')
                    except Exception: pass
                    try: attached_browser.close()
                    except Exception: pass
                desktop.stop(graceful=True)
            elif context is not None:
                context.close()
            context = desktop = attached_browser = None

        try:
            from playwright.sync_api import sync_playwright
            with sync_playwright() as playwright:
                while True:
                    job, args, reply = self.jobs.get()
                    try:
                        if job == 'stop':
                            close_browser()
                            reply.put((True, None))
                            return
                        if job == 'launch':
                            close_browser()
                            headed, initial_url = args
                            if headed:
                                desktop = DesktopBrowserProcess(playwright.chromium.executable_path,
                                                                self.profile, self.downloads)
                                desktop.start()
                                attached_browser = playwright.chromium.connect_over_cdp(
                                    desktop.endpoint, no_defaults=True, timeout=10000)
                                context = attached_browser.contexts[0]
                            else:
                                context = playwright.chromium.launch_persistent_context(
                                    str(self.profile), channel='chromium', headless=True,
                                    accept_downloads=True, downloads_path=str(self.downloads),
                                    viewport={'width': 1280, 'height': 800},
                                    env={k: v for k, v in os.environ.items() if not k.startswith('AB_')},
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
                            if headed: page.bring_to_front()
                            reply.put((True, page.url))
                        elif job == 'close':
                            close_browser()
                            reply.put((True, None))
                        elif job == 'navigate':
                            if not context: raise RuntimeFailure('browser is not running')
                            (url,) = args
                            page = context.pages[0] if context.pages else context.new_page()
                            page.goto(url, wait_until='domcontentloaded', timeout=15000)
                            page.bring_to_front()
                            reply.put((True, page.url))
                        elif job == 'screenshot':
                            if not context: raise RuntimeFailure('browser is not running')
                            page = context.pages[0] if context.pages else context.new_page()
                            reply.put((True, page.screenshot(type='jpeg', quality=70, timeout=5000)))
                        elif job == 'page':
                            if not context: raise RuntimeFailure('browser is not running')
                            page = context.pages[0] if context.pages else context.new_page()
                            # Clone only readable page nodes. Form controls, scripts and storage
                            # are never serialized back to the caller.
                            reply.put((True, page.evaluate("""() => {
                              const forbidden = 'input,textarea,select,option,script,style,template,svg,canvas,noscript,iframe,[contenteditable]';
                              const readable = (node) => {
                                if (node.matches && node.matches(forbidden)) return '';
                                const copy = node.cloneNode(true);
                                copy.querySelectorAll(forbidden).forEach(child => child.remove());
                                return (copy.textContent || '').replace(/\\s+/g, ' ').trim();
                              };
                              const fullText = document.body ? readable(document.body) : '';
                              const anchors = document.querySelectorAll('a[href]');
                              const fullURL = location.href;
                              const fullTitle = document.title;
                              let truncated = fullText.length > 65536 || anchors.length > 200 ||
                                              fullURL.length > 4096 || fullTitle.length > 500;
                              const links = Array.from(anchors).slice(0, 200).map(anchor => {
                                const fullLabel = readable(anchor);
                                if (fullLabel.length > 300 || anchor.href.length > 4096) truncated = true;
                                return {url: anchor.href.slice(0, 4096), label: fullLabel.slice(0, 300)};
                              });
                              return {url: fullURL.slice(0, 4096), title: fullTitle.slice(0, 500),
                                      text: fullText.slice(0, 65536), links, truncated};
                            }""")))
                    except Exception as exc:
                        if job == 'launch':
                            try: close_browser()
                            except Exception: pass
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

    def close(self):
        """Flush the browser profile before Docker terminates this runtime."""
        with self.lock:
            self.lease = None
            try:
                self.browser.call('stop', timeout=7)
            finally:
                self.browser_ready = False
                self.mode = 'http'
                self.display.stop()
                self.profile_lock.close()

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

    def page(self):
        with self.lock:
            if self.mode not in ('headless', 'desktop') or not self.browser_ready:
                raise RuntimeFailure('browser is not running')
            source = self.browser.call('page')
            if not isinstance(source, dict): raise RuntimeFailure('page snapshot is invalid')
            url = source.get('url', '')
            title = source.get('title', '')
            text = source.get('text', '')
            links = source.get('links', [])
            if not isinstance(url, str) or not isinstance(title, str) or not isinstance(text, str) or not isinstance(links, list):
                raise RuntimeFailure('page snapshot is invalid')
            truncated = bool(source.get('truncated')) or len(url) > 4096 or len(title) > 500 or len(text) > 65_536 or len(links) > 200
            bounded_links = []
            for link in links[:200]:
                if not isinstance(link, dict) or not isinstance(link.get('url'), str) or not isinstance(link.get('label'), str):
                    continue
                if len(link['url']) > 4096 or len(link['label']) > 300: truncated = True
                bounded_links.append({'url': link['url'][:4096], 'label': link['label'][:300]})
            return {'url': url[:4096], 'title': title[:500], 'text': text[:65_536],
                    'links': bounded_links, 'truncated': truncated,
                    'generation': self.generation, 'computer_id': self.computer_id}

    def input(self, action):
        with self.lock:
            if self.mode != 'desktop': raise RuntimeFailure('input requires desktop mode')
            self.display.input(action)
            return {'accepted': True, 'generation': self.generation}
