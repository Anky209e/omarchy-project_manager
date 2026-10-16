import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'task-runner.sh'


class TaskRunnerTests(unittest.TestCase):
    def run_task(self, directory, command):
        return subprocess.run(['bash', str(SCRIPT), str(directory), command],
                              capture_output=True, text=True, timeout=8)

    def test_output_exit_status_and_quoted_directory(self):
        with tempfile.TemporaryDirectory(prefix="task 'quoted' ") as directory:
            result = self.run_task(directory, 'pwd; echo error >&2; exit 7')
            self.assertEqual(result.returncode, 7)
            self.assertEqual(result.stdout.strip(), directory)
            self.assertIn('error', result.stderr)

    def test_missing_directory_fails(self):
        result = self.run_task('/does/not/exist/project-manager-test', 'echo should-not-run')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('should-not-run', result.stdout)

    def test_cancellation_kills_stubborn_descendants(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / 'pid'
            ready = Path(directory) / 'ready'
            proc = subprocess.Popen(['bash', str(SCRIPT), directory,
                "bash -c 'trap \"\" TERM; echo $$ > pid; touch ready; sleep 30' & wait"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                deadline = time.monotonic() + 3
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(ready.exists(), 'Task did not start')
                child = int(pidfile.read_text())
                proc.send_signal(signal.SIGTERM)
                proc.communicate(timeout=5)
                self.assertEqual(proc.returncode, 130)
                stat = Path(f'/proc/{child}/stat')
                # A killed child may briefly remain a zombie until PID 1 reaps it.
                self.assertTrue(not stat.exists() or stat.read_text().split()[2] == 'Z')
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.communicate()


if __name__ == '__main__':
    unittest.main()
