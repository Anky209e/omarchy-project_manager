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
