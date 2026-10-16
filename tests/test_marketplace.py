import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('marketplace_preparation', ROOT / 'scripts/prepare-marketplace.py')
PREPARATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARATION)


class MarketplacePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repository = Path(self.temp.name) / 'repo'
        self.repository.mkdir()
        for name in (*PREPARATION.RUNTIME_FILES, 'manifest.json', 'README.md', 'LICENSE',
                     'CHANGELOG.md', 'config.example.json', 'preview.png',
                     'docs/marketplace-update.template.md', 'docs/security-review.md'):
            target = self.repository / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        self.git('init', '-q')
        self.commit()
        self.output = Path(self.temp.name) / 'draft'
        self.committed_version = json.loads((self.repository / 'manifest.json').read_text())['version']
        original = PREPARATION.ROOT
        PREPARATION.ROOT = self.repository
        self.addCleanup(setattr, PREPARATION, 'ROOT', original)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repository), *args], stderr=subprocess.PIPE)

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                 'commit', '-qm', 'Snapshot')

    def generate(self):
        with contextlib.redirect_stdout(io.StringIO()):
            PREPARATION.prepare(self.output)
        return json.loads((self.output / 'marketplace-preflight.json').read_text())

    def test_draft_targets_commit_and_excludes_working_changes(self):
        head = self.git('rev-parse', 'HEAD').decode().strip()
        preview_hash = hashlib.sha256((self.repository / 'preview.png').read_bytes()).hexdigest()
        manifest = json.loads((self.repository / 'manifest.json').read_text())
        manifest['version'] = '9.9.9'
        (self.repository / 'manifest.json').write_text(json.dumps(manifest))
        with (self.repository / 'preview.png').open('ab') as preview:
            preview.write(b'local draft')
        self.git('add', 'preview.png')
        index_before = self.git('diff', '--cached', '--binary')
        report = self.generate()
        self.assertEqual(report['targetCommit'], head)
        self.assertEqual(report['version'], self.committed_version)
        self.assertEqual(report['preview']['sha256'], preview_hash)
        self.assertEqual(len(report['workingTreeChangesNotIncluded']), 2)
        body = (self.output / 'marketplace-update.md').read_text()
        self.assertIn(head, body)
        self.assertNotIn('{{', body)
        self.assertIn('- [ ]', body)
        self.assertEqual(report['dependencyReviewStatus'], 'incomplete')
        self.assertFalse(report['securityApprovalClaimed'])
        self.assertFalse(report['submissionSent'])
        self.assertFalse(report['remoteHeadChecked'])
        self.assertEqual(index_before, self.git('diff', '--cached', '--binary'))

    def test_invalid_manifest_snapshot_is_rejected(self):
        manifest = json.loads((self.repository / 'manifest.json').read_text())
        manifest['id'] = 'wrong.identity'
        (self.repository / 'manifest.json').write_text(json.dumps(manifest))
        self.commit()
        with self.assertRaisesRegex(ValueError, 'plugin ID'):
            self.generate()
        self.assertFalse(self.output.exists())

    def test_committed_symlinks_are_rejected(self):
        (self.repository / 'linked.js').symlink_to('ProjectStore.js')
        self.commit()
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            self.generate()
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
