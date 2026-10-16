from pathlib import Path
import os
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from desktop_browser import DesktopBrowserProcess


class DesktopBrowserTests(unittest.TestCase):
    def test_launch_preserves_existing_preferences_and_excludes_runtime_capability(self):
        with tempfile.TemporaryDirectory() as root:
            profile = Path(root) / 'profile'
            preferences = profile / 'Default' / 'Preferences'
            preferences.parent.mkdir(parents=True)
            preferences.write_text('{"user-setting":42}')
            browser = DesktopBrowserProcess('/usr/bin/chromium', profile, Path(root) / 'downloads')
            response = MagicMock()
            response.__enter__.return_value.status = 200
            process = MagicMock()
            process.poll.return_value = None
            with patch.dict(os.environ, {'AB_API_TOKEN': 'not-for-browser', 'AB_COMPUTER_ID': 'private'}), \
                 patch('desktop_browser.subprocess.Popen', return_value=process) as spawn, \
                 patch('desktop_browser.urllib.request.urlopen', return_value=response):
                browser.start()
                self.assertNotIn('AB_API_TOKEN', spawn.call_args.kwargs['env'])
                self.assertNotIn('AB_COMPUTER_ID', spawn.call_args.kwargs['env'])
                self.assertEqual(preferences.read_text(), '{"user-setting":42}')
                self.assertIn('--remote-debugging-address=127.0.0.1', spawn.call_args.args[0])
                browser.stop()
                process.terminate.assert_called_once()
                self.assertIsNone(browser.process)

    def test_failed_start_does_not_leave_browser_process(self):
        with tempfile.TemporaryDirectory() as root:
            browser = DesktopBrowserProcess('/usr/bin/chromium', Path(root) / 'profile', Path(root) / 'downloads')
            process = MagicMock()
            process.poll.return_value = 1
            with patch('desktop_browser.subprocess.Popen', return_value=process):
                with self.assertRaisesRegex(RuntimeError, 'exited during launch'): browser.start()
            self.assertIsNone(browser.process)
            process.wait.assert_called_once()

    def test_shutdown_escalates_only_owned_process_when_it_will_not_exit(self):
        browser = DesktopBrowserProcess('/usr/bin/chromium', Path('/unused'), Path('/unused'))
        process = MagicMock()
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired('chromium', 5), 0]
        browser.process = process
        browser.stop()
        process.kill.assert_called_once()
        self.assertIsNone(browser.process)

    def test_graceful_close_waits_for_profile_flush_before_termination(self):
        browser = DesktopBrowserProcess('/usr/bin/chromium', Path('/unused'), Path('/unused'))
        process = MagicMock()
        browser.process = process
        browser.stop(graceful=True)
        process.wait.assert_called_once_with(timeout=3)
        process.terminate.assert_not_called()
        process.kill.assert_not_called()
        self.assertIsNone(browser.process)

    def test_graceful_timeout_falls_back_to_termination(self):
        browser = DesktopBrowserProcess('/usr/bin/chromium', Path('/unused'), Path('/unused'))
        process = MagicMock()
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired('chromium', 3), 0]
        browser.process = process
        browser.stop(graceful=True)
        process.terminate.assert_called_once()
        process.kill.assert_not_called()
        self.assertIsNone(browser.process)
