import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'project-manager.sh'


class ScannerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'])

    def tool(self, name, body='exit 0'):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def scan(self, *args):
        return json.loads(subprocess.check_output(
            ['bash', str(SCRIPT), 'scan', *map(str, args)], env=self.env, text=True))

    def test_generated_task_tools_are_available(self):
        self.tool('npm')
        (self.root / 'package.json').write_text('{"scripts":{"test":"true"}}')
        result = self.scan('--', self.root)
        self.assertIn('npm', result['availableCommands'])
        self.assertIn('npm', [t['requires'] for t in result['projects'][0]['tasks']])


if __name__ == '__main__':
    unittest.main()
