"""Run the overlay headlessly without touching the desktop or user config.

Quickshell's layer-shell PanelWindow requires a live Wayland compositor. This
harness substitutes only that window host with a Rectangle; the production
content, controller, FileViews, scanner and task processes run unchanged.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--screenshots', type=Path)
    parser.add_argument('--shell-root', type=Path, default=Path('/usr/share/omarchy/shell'))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='project-manager-smoke-') as temp:
        directory = Path(temp)
        plugin = directory / 'plugin'
        plugin.mkdir()
        for pattern in ('*.qml', '*.js', '*.sh'):
            for source in ROOT.glob(pattern):
                shutil.copy2(source, plugin / source.name)
        qml = (plugin / 'ProjectManager.qml').read_text()
        qml = qml.replace('  PanelWindow {', '  Rectangle {')
        qml = qml.replace('    screen: root.targetScreen', '    property var screen: root.targetScreen')
        qml = qml.replace('    anchors { top: true; bottom: true; left: true; right: true }', '    anchors.fill: parent')
        qml = '\n'.join(line for line in qml.splitlines()
                        if 'WlrLayershell.' not in line and 'exclusionMode:' not in line)
        (plugin / 'ProjectManager.qml').write_text(qml)
        shutil.copy2(ROOT / 'tests/overlay-smoke.qml', directory / 'shell.qml')
        imports = directory / 'imports'
        imports.mkdir()
        (imports / 'qs').symlink_to(args.shell_root, target_is_directory=True)
        home = directory / 'home'
        project = home / 'Projects' / 'demo'
        project.mkdir(parents=True)
        config = home / '.config' / 'omarchy'
        config.mkdir(parents=True)
        (config / 'project-manager.json').write_text(json.dumps({
            'taskMode': 'managed', 'discovery': {'enabled': False},
            'projects': [{'path': str(project), 'name': 'Smoke project', 'tags': ['qml', 'demo'],
                          'tasks': {'Check': 'echo hello'}}]}))
        (project / 'package.json').write_text('{"scripts":{"test":"true"}}')
        runtime = directory / 'runtime'
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, HOME=str(home), XDG_RUNTIME_DIR=str(runtime),
                   XDG_CONFIG_HOME=str(home / '.config'), XDG_STATE_HOME=str(home / '.local/state'),
                   QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                   QT_QUICK_CONTROLS_STYLE='Basic', QML_IMPORT_PATH=str(imports),
                   QSG_RHI_BACKEND='software')
        env.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run(['quickshell', '-p', str(directory / 'shell.qml'), '--no-color'],
                                env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=25)
        print(result.stdout)
        if args.screenshots:
            args.screenshots.mkdir(parents=True, exist_ok=True)
            for image in directory.glob('*.png'):
                shutil.copy2(image, args.screenshots / image.name)
        if result.returncode or 'SMOKE PASS:' not in result.stdout or 'SMOKE FAIL:' in result.stdout:
            raise SystemExit(1)
        # Binding/type errors are failures even when assertions happened to pass.
        if any(word in result.stdout for word in ('ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign')):
            raise SystemExit('QML runtime diagnostics found')


if __name__ == '__main__':
    main()
