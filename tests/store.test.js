const assert = require('node:assert/strict')
const { test } = require('node:test')
const Store = require('../ProjectStore.js')

test('configured project names survive discovery', () => {
  const config = Store.normalizeConfig({ projects: [
    { path: '/tmp/demo', name: 'Custom name' },
    { path: '/tmp/other' }
  ] }, '/home/test')
  const projects = Store.mergeProjects([
    { path: '/tmp/demo', name: 'demo' },
    { path: '/tmp/other', name: 'other' }
  ], config)
  assert.deepEqual(projects.map(p => p.name), ['Custom name', 'other'])
})

test('clone commands finish after Git and propagate errors', () => {
  const fs = require('node:fs')
  const os = require('node:os')
  const path = require('node:path')
  const cp = require('node:child_process')
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'project-manager-clone-'))
  try {
    const source = path.join(dir, 'source')
    cp.execFileSync('git', ['init', '-q', source])
    const root = path.join(dir, 'new root')
    const config = Store.normalizeConfig({discovery: {roots: [root]}}, dir)
    const command = Store.cloneCommand(config, dir, source).argv
    assert.equal(cp.spawnSync(command[0], command.slice(1)).status, 0)
    assert.ok(fs.existsSync(path.join(root, 'source', '.git')))
    assert.notEqual(cp.spawnSync(command[0], command.slice(1)).status, 0)
  } finally { fs.rmSync(dir, {recursive: true, force: true}) }
})

test('scanner aliases preserve metadata and suppress duplicate configured paths', () => {
  const config = Store.normalizeConfig({projects: [
    {path: '~/linked/../linked/demo/', name: 'Linked project', pinned: true,
      editor: 'nvim', tags: ['custom'], tasks: {Build: 'make'}}
  ]}, '/home/test')
  const scan = Store.parseScan(JSON.stringify({projects: [
    {path: '/real/demo', name: 'demo', aliases: ['/home/test/linked/../linked/demo/']}
  ]}))
  const projects = Store.mergeProjects(scan.projects, config)
  assert.equal(projects.length, 1)
  assert.equal(projects[0].path, '/real/demo')
  assert.equal(projects[0].name, 'Linked project')
  assert.equal(projects[0].pinned, true)
  assert.equal(projects[0].editor, 'nvim')
  assert.deepEqual(projects[0].tags, ['custom'])
  assert.equal(projects[0].tasks[0].command, 'make')
})

test('preferences persist explicit unpin and editor choices without changing config', () => {
  const config = Store.normalizeConfig({projects: [{path: '/tmp/demo', pinned: true}]}, '/home/test')
  const original = Store.mergeProjects([], config)
  let prefs = Store.parsePreferences('')
  prefs = Store.updatePreference(prefs, '/tmp/demo/', 'pinned', false)
  prefs = Store.updatePreference(prefs, '/tmp/demo', 'editor', 'nvim')
  const restored = Store.parsePreferences(JSON.stringify(prefs))
  const projects = Store.applyPreferences(original, restored, config, ['nvim'])
  assert.equal(projects[0].pinned, false)
  assert.equal(projects[0].editorId, 'nvim')
  assert.equal(projects[0].editorLabel, 'Neovim')
  assert.equal(original[0].pinned, true)
  assert.equal(original[0].editor, '')
  assert.equal(config.projects[0].pinned, true)
})

test('malformed preferences and removed editors fall back safely', () => {
  const config = Store.normalizeConfig({}, '/home/test')
  const projects = Store.mergeProjects([{path: '/tmp/demo'}], config)
  for (const raw of ['bad json', 'null', '{"version":9,"projects":{}}']) {
    assert.deepEqual(Store.parsePreferences(raw), {version: 1, projects: {}})
  }
  const preferences = {version: 1, projects: {'/tmp/demo': {editor: 'removed', pinned: 'yes'}}}
  assert.equal(Store.applyPreferences(projects, preferences, config, [])[0].editorId, 'omarchy')
  assert.equal(Store.applyPreferences(projects, preferences, config, [])[0].pinned, false)
})

test('actions are grouped without changing task shortcut order and explain missing tools', () => {
  const config = Store.normalizeConfig({}, '/home/test')
  const project = {path: '/tmp/demo', name: 'Demo', tasks: [
    {name: 'Build', command: 'make', requires: 'make'},
    {name: 'Test', command: 'make test', requires: 'make'}
  ]}
  const actions = Store.actionsFor(project, config, ['setsid'])
  assert.deepEqual([...new Set(actions.map(a => a.group))], ['Open', 'Git', 'Tasks', 'Project'])
  assert.equal(actions[0].kind, 'editor-direct')
  assert.equal(actions[0].enabled, false)
  assert.match(actions[0].disabledReason, /omarchy-launch-editor/)
  const tasks = actions.filter(a => a.kind === 'task')
  assert.deepEqual(tasks.map(t => t.hint), ['Ctrl 1', 'Ctrl 2'])
  assert.match(tasks[0].disabledReason, /make/)
  const enabled = Store.actionsFor(project, config, ['setsid', 'make']).filter(a => a.kind === 'task')
  assert.equal(enabled[0].enabled, true)
})

test('task execution defaults to managed, with legacy modes preserved', () => {
  const project = {path: "/tmp/project 'quoted'", name: 'Demo'}
  const task = {kind: 'task', command: 'echo hi', label: 'Test'}
  const managed = Store.normalizeConfig({}, '/home/test')
  assert.equal(managed.taskMode, 'managed')
  assert.equal(Store.commandFor(task, project, managed).managed.path, project.path)
  assert.ok(Store.commandFor(task, project, Store.normalizeConfig({tasksInTerminal: true}, '')).argv.includes('xdg-terminal-exec'))
  assert.ok(Store.commandFor(task, project, Store.normalizeConfig({tasksInTerminal: false}, '')).shell.includes('echo hi'))
  assert.equal(Store.normalizeConfig({taskMode: 'managed', tasksInTerminal: true}, '').taskMode, 'managed')
})

test('matching pinned projects stay first in search results', () => {
  const projects = [
    {name: 'Demo', path: '/tmp/demo', pinned: false},
    {name: 'A demo project', path: '/tmp/pinned', pinned: true}
  ]
  assert.equal(Store.filterProjects(projects, 'demo')[0].path, '/tmp/pinned')
  assert.equal(Store.filterProjects(projects, 'no match').length, 0)
})

test('browser links discard remote credentials, query strings and fragments', () => {
  const cases = [
    ['https://user:secret@example.com/org/repo.git?token=secret#secret', 'https://example.com/org/repo'],
    ['https://user:secret@example.com/org/repo.git.git', 'https://example.com/org/repo.git'],
    ['HTTP://token@localhost:3000/org/repo', 'http://localhost:3000/org/repo'],
    ['ssh://user:secret@example.com/org/repo.git', 'https://example.com/org/repo'],
    ['git://user:secret@example.com/org/repo.git', 'https://example.com/org/repo'],
    ['git@example.com:org/repo.git', 'https://example.com/org/repo'],
    ['git@[::1]:org/repo.git', 'https://[::1]/org/repo'],
    ['https://user:secret@/org/repo', ''],
    ['file:///tmp/repo', ''],
    ['https://example.com/org/repo\nsecret', ''],
    ['https://example.com/org\\repo', '']
  ]
  for (const [remote, expected] of cases) {
    assert.equal(Store.remoteToWebUrl(remote), expected)
    const config = Store.normalizeConfig({}, '/home/test')
    const parsed = Store.parseScan(JSON.stringify({projects: [{path: '/tmp/demo', git: {remote}}]}))
    assert.equal(Store.remoteToWebUrl(parsed.projects[0].git.remote), expected)
    const project = parsed.projects[0]
    const action = Store.actionsFor(project, config, ['setsid', 'uwsm-app', 'omarchy-launch-browser'])
      .find(a => a.kind === 'github')
    assert.equal(action.enabled, Boolean(expected))
    if (expected) assert.equal(Store.commandFor(action, project, config).argv.at(-1), expected)
    assert.ok(!JSON.stringify(parsed).includes('secret'))
  }
})

test('tmux action opens a per-project session and needs tmux', () => {
  const project = {path: '/home/test/Projects/my.app', name: 'my.app'}
  const config = Store.normalizeConfig({}, '/home/test')
  const withTmux = Store.actionsFor(project, config, ['setsid', 'uwsm-app', 'xdg-terminal-exec', 'tmux'])
  const action = withTmux.find(a => a.id === 'terminal-tmux')
  assert.equal(action.enabled, true)
  assert.equal(action.group, 'Open')
  assert.deepEqual(Store.commandFor(action, project, config).tmux,
    {name: 'my_app', path: '/home/test/Projects/my.app', command: ''})
  const withLayout = Store.normalizeConfig({tmuxStartCommand: '  ix  '}, '/home/test')
  assert.equal(Store.commandFor(action, project, withLayout).tmux.command, 'ix')
  assert.equal(Store.normalizeConfig({tmuxStartCommand: 42}, '/home/test').tmuxStartCommand, '')

  const withoutTmux = Store.actionsFor(project, config, ['setsid', 'uwsm-app', 'xdg-terminal-exec'])
  const disabled = withoutTmux.find(a => a.id === 'terminal-tmux')
  assert.equal(disabled.enabled, false)
  assert.equal(disabled.disabledReason, 'Missing: tmux')
})

test('tmux session names avoid characters tmux rejects', () => {
  assert.equal(Store.tmuxSessionName('/a/b/my.app'), 'my_app')
  assert.equal(Store.tmuxSessionName('/a/b/x:y/'), 'x_y')
  assert.equal(Store.tmuxSessionName(''), 'project')
})
