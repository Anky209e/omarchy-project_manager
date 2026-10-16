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
