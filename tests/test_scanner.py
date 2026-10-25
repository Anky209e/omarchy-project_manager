import json
import os
import shutil
import sys
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

    def test_stack_reports_framework_and_language_versions(self):
        project = self.root / 'api'
        (project / 'node_modules' / '@nestjs' / 'core').mkdir(parents=True)
        (project / 'node_modules' / '@nestjs' / 'core' / 'package.json').write_text('{"version":"10.3.0"}')
        (project / 'package.json').write_text(
            '{"dependencies":{"@nestjs/core":"^10.0.0"},"devDependencies":{"typescript":"~5.4.5"}}')
        result = self.scan('--', project)
        self.assertEqual(result['projects'][0]['stack'], {
            'framework': {'id': 'nestjs', 'version': '10.3.0'},
            'language': {'id': 'typescript', 'version': '5.4.5'},
        })

    def test_stack_falls_back_to_language_only_or_nothing(self):
        rust = self.root / 'rs'
        rust.mkdir()
        (rust / 'Cargo.toml').write_text('[package]\nrust-version = "1.78"\n')
        plain = self.root / 'plain'
        plain.mkdir()
        result = {p['name']: p['stack'] for p in self.scan('--', rust, plain)['projects']}
        self.assertEqual(result['rs'], {'framework': None, 'language': {'id': 'rust', 'version': '1.78'}})
        self.assertEqual(result['plain'], {'framework': None, 'language': None})

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

    def test_make_and_just_tasks_coexist_with_language_tasks(self):
        (self.root / 'package.json').write_text('{"scripts":{"test":"true"}}')
        (self.root / 'Makefile').write_text('build:\n\ttrue\n')
        (self.root / '.justfile').write_text(
            'export TOKEN := "value"\n'
            'value := "text"\n'
            'set shell := ["bash", "-c"]\n'
            'import "shared.just"\n'
            '[private]\n'
            'build:\n    true\n'
            '@quiet: build\n    true\n'
            'test arg:\n    true\n'
            '# comment:\n'
        )
        project = self.scan('--', self.root)['projects'][0]
        self.assertEqual(project['types'], ['node', 'make', 'just'])
        names = {t['name'] for t in project['tasks']}
        self.assertIn('npm run test', names)
        self.assertIn('make build', names)
        self.assertEqual({n for n in names if n.startswith('just ')},
                         {'just build', 'just quiet'})

    def record_dependency_arguments(self):
        log = self.root / 'dependency-arguments.jsonl'
        self.env['SCANNER_ARGV_LOG'] = str(log)
        # Instrument actual child argv before exec, without recording the user's
        # environment. All credential markers in these tests are synthetic.
        for name in ('git', 'jq', 'sed', 'grep', 'head', 'sort', 'basename',
                     'realpath', 'find', 'mktemp', 'rm', 'awk'):
            executable = shutil.which(name)
            self.assertIsNotNone(executable)
            wrapper = self.bin / name
            wrapper.write_text(
                '#!' + sys.executable + '\n'
                'import json, os, sys\n'
                'with open("/proc/self/cmdline", "rb") as source:\n'
                '    proc_argv = source.read().decode().split("\\0")\n'
                'with open(os.environ["SCANNER_ARGV_LOG"], "a") as log:\n'
                '    log.write(json.dumps({"argv": sys.argv, "procCmdline": proc_argv, "secretInEnvironment": '
                'any("SCANNER_TEST_SECRET_" in v for v in os.environ.values())}) + "\\n")\n'
                + 'os.execv(' + repr(executable) + ', [' + repr(executable) + '] + sys.argv[1:])\n'
            )
            wrapper.chmod(0o755)
        return log

    def test_remote_credentials_never_reach_child_arguments_or_scan_output(self):
        self.git('init', self.root)
        remote = ('https://SCANNER_TEST_SECRET_USER:SCANNER_TEST_SECRET_PASSWORD@'
                  'example.com/owner/repo.git?token=SCANNER_TEST_SECRET_QUERY'
                  '#SCANNER_TEST_SECRET_FRAGMENT')
        self.git('-C', self.root, 'config', 'remote.origin.url', remote)
        log = self.record_dependency_arguments()
        process = subprocess.run(['bash', str(SCRIPT), 'scan', '--root', str(self.root)],
                                 env=self.env, capture_output=True, text=True, check=True)
        self.assertNotIn('SCANNER_TEST_SECRET_', process.stdout + process.stderr)
        result = json.loads(process.stdout)
        self.assertEqual(result['projects'][0]['git']['remote'],
                         'https://example.com/owner/repo.git')
        self.assertNotIn('SCANNER_TEST_SECRET_', json.dumps(result))
        records = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertTrue(any(Path(r['argv'][0]).name == 'jq' for r in records))
        self.assertNotIn('SCANNER_TEST_SECRET_', json.dumps(records))
        self.assertFalse(any(r['secretInEnvironment'] for r in records))
        # Do not change the actual Git remote; only the displayed/exported URL.
        actual = self.git('-C', self.root, 'config', '--get', 'remote.origin.url')
        self.assertEqual(actual.stdout.strip(), remote)

    def test_remote_sanitization_preserves_links_and_drops_unsupported_values(self):
        self.git('init', self.root)
        cases = [
            ('https://user:password@example.com/org/repo.git', 'https://example.com/org/repo.git'),
            ('https://token@example.com/org/repo.git?access_token=secret#fragment', 'https://example.com/org/repo.git'),
            ('HTTPS://user:p%40ss@example.com:8443/org/repo.git', 'https://example.com:8443/org/repo.git'),
            ('http://user:pass@localhost:3000/org/repo', 'http://localhost:3000/org/repo'),
            ('https://user@host@evil.example/org/repo', 'https://evil.example/org/repo'),
            ('https://user:pass@[::1]:443/org/repo.git', 'https://[::1]:443/org/repo.git'),
            ('ssh://git:password@example.com/org/repo.git', 'https://example.com/org/repo.git'),
            ('git://user:password@example.com/org/repo.git', 'https://example.com/org/repo.git'),
            ('git@example.com:org/repo.git', 'https://example.com/org/repo.git'),
            ('private-user@example.com:/org/repo.git', 'https://example.com/org/repo.git'),
            ('example.com:org/repo.git', 'https://example.com/org/repo.git'),
            ('git@[::1]:org/repo.git', 'https://[::1]/org/repo.git'),
            ('/tmp/local-repo', ''),
            ('file:///tmp/local-repo', ''),
            ('ext::unrecognized transport', ''),
            ('https://password@/org/repo', ''),
            ('https://user:pass@exa%6dple.com/org/repo', ''),
            ('https://user:pass@example.com/org/repo\nextra', ''),
            ('https://user:pass@example.com/owner\\repo', ''),
        ]
        for remote, expected in cases:
            with self.subTest(remote=remote):
                self.git('-C', self.root, 'config', 'remote.origin.url', remote)
                project = self.scan('--', self.root)['projects'][0]
                self.assertEqual(project['git']['remote'], expected)

    def test_repository_without_remote_has_empty_public_url(self):
        self.git('init', self.root)
        project = self.scan('--', self.root)['projects'][0]
        self.assertEqual(project['git']['remote'], '')


if __name__ == '__main__':
    unittest.main()
