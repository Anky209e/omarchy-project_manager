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
