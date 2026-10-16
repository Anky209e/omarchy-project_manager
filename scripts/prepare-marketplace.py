#!/usr/bin/env python3
"""Generate local marketplace update drafts from the exact local HEAD commit."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'https://github.com/Anky209e/omarchy-project_manager'
PLUGIN_ID = 'io.github.anky209e.project-manager'
RUNTIME_FILES = (
    'ProjectManager.qml', 'ProjectStore.js', 'ActionMenu.qml', 'OverlayButton.qml',
    'TaskConsole.qml', 'TaskRunner.qml', 'project-manager.sh', 'task-runner.sh',
)


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def prepare(output):
    commit = git('rev-parse', 'HEAD').decode().strip()
    def snapshot(path):
        return git('show', f'{commit}:{path}')

    manifest = json.loads(snapshot('manifest.json'))
    if manifest.get('schemaVersion') != 1 or manifest.get('id') != PLUGIN_ID:
        raise ValueError('Unexpected manifest schema or plugin ID')
    if manifest.get('kinds') != ['overlay'] or manifest.get('entryPoints') != {'overlay': 'ProjectManager.qml'}:
        raise ValueError('Unexpected overlay entry point')
    if not re.fullmatch(r'\d+\.\d+\.\d+', manifest.get('version', '')):
        raise ValueError('Expected a numeric major.minor.patch version')
    for field in ('name', 'author', 'description', 'license'):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise ValueError(f'Missing manifest field: {field}')

    tree = git('ls-tree', '-r', '-z', commit).split(b'\0')
    if any(entry.startswith(b'120000 ') for entry in tree if entry):
        raise ValueError('Committed plugin tree contains symlinks')
    for filename in (*RUNTIME_FILES, 'config.example.json', 'LICENSE', 'CHANGELOG.md', 'README.md'):
        if not snapshot(filename):
            raise ValueError(f'Missing or empty release file: {filename}')
    readme = snapshot('README.md').decode()
    for command in ('omarchy plugin add', 'omarchy plugin remove'):
        if command not in readme:
            raise ValueError(f'README missing {command}')
    json.loads(snapshot('config.example.json'))

    preview = snapshot('preview.png')
    if len(preview) < 24 or preview[:8] != b'\x89PNG\r\n\x1a\n' or preview[12:16] != b'IHDR':
        raise ValueError('Root preview is not a PNG with a valid header')
    width, height = struct.unpack('>II', preview[16:24])
    if not width or not height or width * height > 40_000_000 or len(preview) > 50_000_000:
        raise ValueError('Preview exceeds marketplace size limits or has invalid dimensions')

    body = snapshot('docs/marketplace-update.template.md').decode()
    for key, value in {'PLUGIN_ID': PLUGIN_ID, 'REPOSITORY_URL': REPOSITORY, 'TARGET_COMMIT': commit}.items():
        body = body.replace('{{' + key + '}}', value)
    if '{{' in body:
        raise ValueError('Unresolved draft placeholder')
    changes = git('status', '--porcelain=v1', '--untracked-files=normal').decode().splitlines()
    report = {
        'targetCommit': commit,
        'version': manifest['version'],
        'pluginId': PLUGIN_ID,
        'repository': REPOSITORY,
        'category': 'Productivity',
        'tags': ['launcher', 'quickshell', 'hyprland'],
        'localSnapshotChecksPassed': True,
        'testsRunByGenerator': False,
        'remoteHeadChecked': False,
        'submissionSent': False,
        'ownerAcknowledgmentPending': True,
        'workingTreeChangesNotIncluded': changes,
        'preview': {'width': width, 'height': height, 'bytes': len(preview),
                    'sha256': hashlib.sha256(preview).hexdigest()},
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / 'marketplace-update.md').write_text(body)
    (output / 'marketplace-title.txt').write_text(f"[Verify]: {manifest['name']} {manifest['version']}\n")
    (output / 'release-notes.md').write_bytes(snapshot('CHANGELOG.md'))
    (output / 'marketplace-preflight.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"Prepared {manifest['name']} {manifest['version']} at {commit}")
    print(f'Local drafts: {output}')
    if changes:
        print('Working-tree changes are excluded from this exact-commit draft; see the preflight report.')
    print('Nothing was pushed, submitted, or published. Owner review and remote HEAD verification remain pending.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    prepare(args.output.resolve())


if __name__ == '__main__':
    main()
