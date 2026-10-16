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

    def test_script_names_are_literal_arguments(self):
        capture = self.root / 'args.json'
        self.tool('npm', 'python3 -c \'import json,sys; json.dump(sys.argv[1:],open(sys.argv[1],"w"))\' "$CAPTURE" "$@"')
        name = "dev; touch INJECTED $(touch SUBSTITUTED) 'quoted'"
        (self.root / 'package.json').write_text(json.dumps({'scripts': {name: 'true'}}))
        result = self.scan('--', self.root)
        command = result['projects'][0]['tasks'][1]['command']
        subprocess.run(['bash', '-c', command], cwd=self.root,
                       env=dict(self.env, CAPTURE=str(capture)), check=True)
        self.assertEqual(json.loads(capture.read_text())[1:], ['run', '--', name])
        self.assertFalse((self.root / 'INJECTED').exists())
        self.assertFalse((self.root / 'SUBSTITUTED').exists())

    def git(self, *args):
        return subprocess.run(['git', *map(str, args)], check=True,
                              capture_output=True, text=True)

    def test_discovers_worktrees_and_submodules(self):
        repo = self.root / 'repo'
        self.git('init', repo)
        self.git('-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                 'commit', '--allow-empty', '-m', 'Initial')
        worktree = self.root / 'worktree'
        self.git('-C', repo, 'worktree', 'add', worktree)
        self.git('-c', 'protocol.file.allow=always', '-C', repo,
                 'submodule', 'add', repo, 'sub')
        result = self.scan('--root', self.root)
        projects = {p['path']: p for p in result['projects']}
        for path in (repo, worktree, repo / 'sub'):
            self.assertIn(str(path), projects)
            self.assertIsNotNone(projects[str(path)]['git'])

    def test_canonical_projects_include_configured_aliases(self):
        repo = self.root / 'real' / 'repo'
        repo.mkdir(parents=True)
        self.git('init', repo)
        alias = self.root / 'linked'
        alias.symlink_to(repo.parent, target_is_directory=True)
        configured = str(alias / 'repo') + '/../repo/'
        result = self.scan('--root', self.root, '--', configured, repo)
        self.assertEqual(len(result['projects']), 1)
        project = result['projects'][0]
        self.assertEqual(project['path'], str(repo))
        self.assertIn(configured, project['aliases'])


if __name__ == '__main__':
    unittest.main()
