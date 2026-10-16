"""Launch the box's visible browser as a normal persistent desktop process.

DevTools is loopback-only inside the container, never a published Docker port.
No user-agent override, fingerprint patch or imported host profile is used.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request


class DesktopBrowserProcess:
    endpoint = 'http://127.0.0.1:9222'

    def __init__(self, executable: str, profile: Path, downloads: Path):
        self.executable, self.profile, self.downloads = executable, profile, downloads
        self.process = None

    def arguments(self):
        return [self.executable, '--user-data-dir=' + str(self.profile),
                '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=9222',
                '--no-first-run', '--no-default-browser-check', '--window-size=1280,800',
                # Same sandbox constraint as the previous Playwright Docker launch.
                '--no-sandbox', 'about:blank']

    def start(self):
        self.profile.mkdir(parents=True, exist_ok=True)
        self.downloads.mkdir(parents=True, exist_ok=True)
        preferences = self.profile / 'Default' / 'Preferences'
        if not preferences.exists():
            preferences.parent.mkdir(parents=True, exist_ok=True)
            preferences.write_text(json.dumps({'download': {'default_directory': str(self.downloads)}}))
        # Browser children do not need the host-to-runtime API capability.
        environment = {k: v for k, v in os.environ.items() if not k.startswith('AB_')}
        environment['DISPLAY'] = ':99'
        self.process = subprocess.Popen(self.arguments(), env=environment,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                if self.process.poll() is not None: raise RuntimeError('desktop browser exited during launch')
                try:
                    with urllib.request.urlopen(self.endpoint + '/json/version', timeout=.25) as response:
                        if response.status == 200: return
                except (OSError, TimeoutError): pass
                time.sleep(.1)
            raise RuntimeError('desktop browser DevTools did not become ready')
        except Exception:
            self.stop()
            raise

    def stop(self, graceful=False):
        if self.process is None: return
        try:
            if graceful:
                try:
                    self.process.wait(timeout=3)
                    return
                except subprocess.TimeoutExpired: pass
            if self.process.poll() is None:
                self.process.terminate()
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        finally:
            self.process = None
