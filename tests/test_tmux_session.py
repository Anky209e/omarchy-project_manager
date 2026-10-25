import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'tmux-session.sh'


class TmuxSessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'calls.log'
        # Only the fakes plus the basics: the real tmux and hyprctl are never touched.
        self.env = dict(os.environ, PATH=str(self.bin) + ':/usr/bin:/bin', LOG=str(self.log))

    def tool(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def run_script(self, *args):
        return subprocess.run(['bash', str(SCRIPT), *args], env=self.env, text=True, capture_output=True)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def fake_tmux(self, has_session):
        self.tool('tmux', f'echo "tmux $*" >> "$LOG"\n[[ $1 == has-session ]] && exit {0 if has_session else 1}\nexit 0')

    def test_creates_the_session_and_opens_a_terminal_when_not_open(self):
        self.fake_tmux(False)
        self.tool('setsid', 'echo "setsid $*" >> "$LOG"')
        result = self.run_script('demo', '/tmp/demo')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertIn('tmux has-session -t =demo', calls)
        self.assertIn('tmux new-session -ds demo -c /tmp/demo', calls)
        self.assertIn('tmux set-option -t =demo: detach-on-destroy on', calls)
        self.assertIn('setsid uwsm-app -- xdg-terminal-exec --dir=/tmp/demo -e tmux attach-session -t =demo', calls)

    def test_types_the_start_command_only_when_the_session_is_created(self):
        self.fake_tmux(False)
        self.tool('setsid', 'echo "setsid $*" >> "$LOG"')
        self.run_script('demo', '/tmp/demo', 'ix')
        calls = self.calls()
        self.assertIn('tmux send-keys -t =demo: -l -- ix', calls)
        self.assertIn('tmux send-keys -t =demo: C-m', calls)

        self.log.unlink()
        self.fake_tmux(True)
        self.run_script('demo', '/tmp/demo', 'ix')
        self.assertFalse([c for c in self.calls() if 'send-keys' in c])

    def test_reuses_an_existing_session(self):
        self.fake_tmux(True)
        self.tool('setsid', 'echo "setsid $*" >> "$LOG"')
        self.run_script('demo', '/tmp/demo')
        self.assertFalse([c for c in self.calls() if c.startswith('tmux new-session')])

    def test_focuses_the_window_that_already_shows_the_session(self):
        self.tool('tmux', 'echo "tmux $*" >> "$LOG"\n'
                          '[[ $1 == has-session ]] && exit 0\n'
                          '[[ $1 == list-clients ]] && echo $PPID_FAKE\nexit 0')
        self.env['PPID_FAKE'] = '4242'
        self.tool('hyprctl',
                  'if [[ $1 == clients ]]; then echo \'[{"pid":4242,"address":"0xabc"}]\'\n'
                  'elif [[ $1 == activewindow ]]; then echo \'{"address":"0xabc"}\'\n'
                  'else echo "hyprctl $*" >> "$LOG"; fi')
        self.tool('jq', 'exec /usr/bin/jq "$@"')
        self.tool('setsid', 'echo "setsid $*" >> "$LOG"')
        result = self.run_script('demo', '/tmp/demo')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertTrue(any(c.startswith('hyprctl dispatch') and '0xabc' in c for c in calls), calls)
        self.assertFalse([c for c in calls if c.startswith('setsid')], calls)

    def test_usage_error_without_arguments(self):
        self.assertEqual(self.run_script().returncode, 2)


if __name__ == '__main__':
    unittest.main()
