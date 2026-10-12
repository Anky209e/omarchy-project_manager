// Project Manager — pure logic. No Qt/QML objects, no state, so it can be
// unit-tested with plain node. The QML overlay owns processes and I/O.

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function expandPath(path, home) {
  var s = String(path || "")
  if (s === "~") return home
  if (s.indexOf("~/") === 0) return home + s.substring(1)
  return s
}

function basename(path) {
  var parts = String(path || "").split("/")
  var name = parts[parts.length - 1]
  return name.length > 0 ? name : String(path || "")
}

function pathKey(path) {
  var s = String(path || "")
  return s.replace(/\/+$/, "") || "/"
}

function shellQuote(value) {
  return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
}

// --------------------------------------------------------------- config

function defaultConfig() {
  return {
    version: 1,
    defaultEditor: "vscode",
    discovery: {
      enabled: true,
      roots: ["~/Projects"],
      maxDepth: 3,
      exclude: [
        "node_modules", ".git", ".venv", "venv", "__pycache__",
        "dist", "build", "target", "vendor", ".cache", ".next",
        ".turbo", "coverage"
      ]
    },
    editors: {
      vscode: { label: "VS Code", command: "code", args: ["{path}"], kind: "gui" },
      zed: { label: "Zed", command: "zed", args: ["{path}"], kind: "gui" },
      cursor: { label: "Cursor", command: "cursor", args: ["{path}"], kind: "gui" },
      nvim: { label: "Neovim", command: "nvim", args: ["{path}"], kind: "terminal" },
      godot: { label: "Godot", command: "godot", args: ["--path", "{path}", "--editor"], kind: "gui" }
    },
    projects: []
  }
}

function normalizeEditor(editor, id) {
  if (!isObject(editor)) {
    return { id: id, label: id, command: "", args: ["{path}"], kind: "gui" }
  }
  return {
    id: id,
    label: String(editor.label || id),
    command: String(editor.command || ""),
    args: Array.isArray(editor.args) ? editor.args.map(String) : ["{path}"],
    kind: editor.kind === "terminal" ? "terminal" : "gui"
  }
}

function mergeEditors(base, over) {
  var out = {}
  var k
  for (k in base) out[k] = normalizeEditor(base[k], k)
  if (isObject(over)) {
    for (k in over) out[k] = normalizeEditor(over[k], k)
  }
  return out
}

function mergeDiscovery(base, over) {
  if (!isObject(over)) {
    return {
      enabled: base.enabled,
      roots: base.roots.slice(),
      maxDepth: base.maxDepth,
      exclude: base.exclude.slice()
    }
  }
  return {
    enabled: over.enabled === undefined ? base.enabled : !!over.enabled,
    roots: Array.isArray(over.roots) ? over.roots.map(String) : base.roots.slice(),
    maxDepth: isFinite(Number(over.maxDepth)) ? Math.max(1, Math.floor(Number(over.maxDepth))) : base.maxDepth,
    exclude: Array.isArray(over.exclude) ? over.exclude.map(String) : base.exclude.slice()
  }
}

function normalizeTasks(tasks) {
  var out = []
  var i, t
  if (isObject(tasks)) {
    for (t in tasks) out.push({ name: t, command: String(tasks[t]) })
  } else if (Array.isArray(tasks)) {
    for (i = 0; i < tasks.length; i++) {
      var item = tasks[i]
      if (isObject(item) && item.name) out.push({ name: String(item.name), command: String(item.command || "") })
      else if (typeof item === "string") out.push({ name: item, command: "" })
    }
  }
  return out
}

function normalizeProjects(list, home) {
  if (!Array.isArray(list)) return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!isObject(p) || !p.path) continue
    var path = expandPath(String(p.path), home)
    out.push({
      name: String(p.name || basename(path)),
      path: path,
      editor: p.editor ? String(p.editor) : "",
      tags: Array.isArray(p.tags) ? p.tags.map(String) : [],
      tasks: normalizeTasks(p.tasks),
      pinned: !!p.pinned
    })
  }
  return out
}

function normalizeConfig(raw, home) {
  var base = defaultConfig()
  var parsed = raw
  if (typeof raw === "string") {
    parsed = null
    var text = String(raw).trim()
    if (text.length > 0) {
      try { parsed = JSON.parse(text) } catch (e) { parsed = null }
    }
  }
  if (!isObject(parsed)) parsed = {}

  var config = {
    version: 1,
    defaultEditor: base.defaultEditor,
    discovery: mergeDiscovery(base.discovery, parsed.discovery),
    editors: mergeEditors(base.editors, parsed.editors),
    projects: normalizeProjects(parsed.projects, home)
  }

  if (typeof parsed.defaultEditor === "string" && config.editors[parsed.defaultEditor])
    config.defaultEditor = parsed.defaultEditor
  if (!config.editors[config.defaultEditor]) {
    var keys = Object.keys(config.editors)
    config.defaultEditor = keys.length > 0 ? keys[0] : "vscode"
  }
  return config
}

// ---------------------------------------------------------------- scan

function scanArgs(config, scriptPath, home) {
  var args = ["bash", scriptPath, "scan"]
  var discovery = config.discovery || {}

  if (discovery.enabled !== false) {
    args.push("--depth", String(discovery.maxDepth || 3))
    args.push("--exclude", (discovery.exclude || []).join(","))
    var roots = discovery.roots || []
    for (var i = 0; i < roots.length; i++) args.push("--root", expandPath(roots[i], home))
  }

  var editors = config.editors || {}
  for (var id in editors) {
    if (editors[id].command) args.push("--editor-command", editors[id].command)
  }

  args.push("--")
  var projects = config.projects || []
  for (var j = 0; j < projects.length; j++) args.push(projects[j].path)
  return args
}

function normalizeGit(git) {
  if (!isObject(git)) return null
  return {
    branch: String(git.branch || ""),
    dirty: !!git.dirty,
    ahead: Number(git.ahead || 0) || 0,
    behind: Number(git.behind || 0) || 0,
    remote: String(git.remote || "")
  }
}

function parseScan(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!isObject(data)) return null
    var projects = []
    var list = Array.isArray(data.projects) ? data.projects : []
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!isObject(p) || !p.path) continue
      projects.push({
        name: String(p.name || basename(p.path)),
        path: String(p.path),
        git: normalizeGit(p.git)
      })
    }
    return {
      projects: projects,
      availableCommands: Array.isArray(data.availableCommands) ? data.availableCommands.map(String) : []
    }
  } catch (e) {
    return null
  }
}

// --------------------------------------------------------------- merge

function buildProject(path, name, git, meta, config) {
  var editorId = meta && meta.editor && config.editors[meta.editor] ? meta.editor : config.defaultEditor
  var editor = config.editors[editorId]
  return {
    name: String(name || basename(path)),
    path: path,
    editor: editorId,
    editorLabel: editor ? editor.label : editorId,
    tags: meta && Array.isArray(meta.tags) ? meta.tags.slice() : [],
    tasks: meta && Array.isArray(meta.tasks) ? meta.tasks.slice() : [],
    pinned: !!(meta && meta.pinned),
    git: git || null
  }
}

function mergeProjects(scanned, config, home) {
  var explicit = config.projects || []
  var byPath = {}
  var i
  for (i = 0; i < explicit.length; i++) byPath[pathKey(explicit[i].path)] = explicit[i]

  var out = []
  var used = {}
  var list = Array.isArray(scanned) ? scanned : []
  for (i = 0; i < list.length; i++) {
    var s = list[i]
    var key = pathKey(s.path)
    used[key] = true
    out.push(buildProject(s.path, s.name, s.git, byPath[key], config))
  }

  // Configured projects the scan didn't return (discovery off, path missing,
  // or outside every root) still appear, just without git data.
  for (i = 0; i < explicit.length; i++) {
    var key2 = pathKey(explicit[i].path)
    if (used[key2]) continue
    out.push(buildProject(explicit[i].path, explicit[i].name, null, explicit[i], config))
  }
  return out
}

// ------------------------------------------------------------ ranking

function frecencyScore(entry, now) {
  if (!isObject(entry)) return 0
  var count = Number(entry.count || 0)
  var last = Number(entry.last || 0)
  if (!count || !last) return 0
  var hours = Math.max(0, (Number(now || 0) - last) / 3600000)
  var recency = 1 / (1 + hours / 24)
  return count * recency
}

function rankProjects(projects, usage, now) {
  var list = Array.isArray(projects) ? projects.slice() : []
  var u = isObject(usage) ? usage : {}
  list.sort(function (a, b) {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
    var sa = frecencyScore(u[a.path], now)
    var sb = frecencyScore(u[b.path], now)
    if (Math.abs(sa - sb) > 1e-9) return sb - sa
    return String(a.name).localeCompare(String(b.name))
  })
  return list
}

function filterProjects(projects, query) {
  var list = Array.isArray(projects) ? projects : []
  var q = String(query || "").trim().toLowerCase()
  if (!q) return list.slice()
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    var hay = [
      p.name,
      p.path,
      p.editorLabel,
      (p.tags || []).join(" "),
      p.git ? p.git.branch : ""
    ].join(" ").toLowerCase()
    if (hay.indexOf(q) >= 0) out.push(p)
  }
  return out
}

// ------------------------------------------------------------ formatting

function gitSummary(git) {
  if (!git) return ""
  var branch = git.branch && git.branch !== "(detached)" ? git.branch : "detached"
  var s = branch
  if (git.dirty) s += "*"
  if (Number(git.ahead) > 0) s += " \u2191" + git.ahead
  if (Number(git.behind) > 0) s += " \u2193" + git.behind
  return s
}

function remoteToWebUrl(remote) {
  var r = String(remote || "").trim()
  if (!r) return ""
  r = r.replace(/\.git$/, "")
  var m = r.match(/^git@([^:]+):(.+)$/)
  if (m) return "https://" + m[1] + "/" + m[2]
  m = r.match(/^ssh:\/\/git@([^/]+)\/(.+)$/)
  if (m) return "https://" + m[1] + "/" + m[2]
  m = r.match(/^git:\/\/([^/]+)\/(.+)$/)
  if (m) return "https://" + m[1] + "/" + m[2]
  if (r.indexOf("http://") === 0 || r.indexOf("https://") === 0) return r
  return ""
}

function projectRow(project) {
  var git = project.git
  return {
    name: project.name,
    path: project.path,
    editorLabel: project.editorLabel,
    gitText: gitSummary(git),
    branch: git ? git.branch : "",
    dirty: !!(git && git.dirty),
    hasGit: !!git,
    hasRemote: !!(git && git.remote),
    pinned: !!project.pinned,
    project: project
  }
}

// -------------------------------------------------------------- actions

function commandAvailable(cmd, available) {
  var c = String(cmd || "")
  if (!c) return false
  var list = Array.isArray(available) ? available : []
  if (list.indexOf(c) >= 0) return true
  var base = c.split("/").pop()
  return list.indexOf(base) >= 0
}

function availableEditors(config, available) {
  var out = []
  var editors = config.editors || {}
  for (var id in editors) {
    if (editors[id].command && commandAvailable(editors[id].command, available)) out.push(id)
  }
  return out
}

function actionsFor(project, config, available, effectiveEditorId) {
  var actions = []
  var editorId = effectiveEditorId && config.editors[effectiveEditorId] ? effectiveEditorId : project.editor
  var editor = config.editors[editorId] || config.editors[config.defaultEditor]

  if (editor) {
    actions.push({
      id: "editor:" + editorId,
      kind: editor.kind === "terminal" ? "editor-terminal" : "editor-gui",
      label: "Open in " + editor.label,
      hint: "Enter",
      enabled: commandAvailable(editor.command, available),
      editorId: editorId
    })
  }

  actions.push({
    id: "terminal",
    kind: "terminal",
    label: "Open terminal here",
    hint: "\u21e7Enter",
    enabled: commandAvailable("xdg-terminal-exec", available)
  })

  actions.push({
    id: "files",
    kind: "files",
    label: "Open file manager",
    hint: "\u2325Enter",
    enabled: commandAvailable("xdg-open", available)
  })

  var url = project.git ? remoteToWebUrl(project.git.remote) : ""
  actions.push({
    id: "github",
    kind: "github",
    label: url ? "Open repository in browser" : "No repository remote",
    hint: "Ctrl G",
    enabled: !!url,
    url: url
  })

  actions.push({
    id: "copy",
    kind: "copy",
    label: "Copy project path",
    hint: "Ctrl Y",
    enabled: commandAvailable("wl-copy", available)
  })

  var tasks = project.tasks || []
  for (var i = 0; i < tasks.length; i++) {
    actions.push({
      id: "task:" + tasks[i].name,
      kind: "task",
      label: "Run task: " + tasks[i].name,
      hint: i < 9 ? "Ctrl " + (i + 1) : "",
      enabled: true,
      command: tasks[i].command
    })
  }

  return actions
}

// Returns { argv: [...] } for direct execution or { shell: "..." } for a
// string that must run under a shell. null means "nothing to run".
function commandFor(action, project, config) {
  if (!action) return null
  var path = project ? project.path : ""

  if (action.kind === "editor-gui" || action.kind === "editor-terminal") {
    var editor = config.editors[action.editorId] || config.editors[config.defaultEditor]
    if (!editor) return null
    var args = editor.args || ["{path}"]
    var rendered = []
    for (var i = 0; i < args.length; i++) rendered.push(String(args[i]).replace("{path}", path))
    var cmd = [editor.command].concat(rendered)
    if (editor.kind === "terminal") {
      return { argv: ["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path, "-e"].concat(cmd) }
    }
    return { argv: ["setsid", "uwsm-app", "--"].concat(cmd) }
  }

  if (action.kind === "terminal")
    return { argv: ["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path] }

  if (action.kind === "files")
    return { argv: ["setsid", "uwsm-app", "--", "xdg-open", path] }

  if (action.kind === "github") {
    if (!action.url) return null
    return { argv: ["setsid", "uwsm-app", "--", "omarchy-launch-browser", action.url] }
  }

  if (action.kind === "copy")
    return { shell: "printf %s " + shellQuote(path) + " | wl-copy" }

  if (action.kind === "task") {
    if (!action.command) return null
    return { shell: "cd " + shellQuote(path) + " && " + action.command }
  }

  return null
}

// ---------------------------------------------------------------- usage

function parseUsage(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    if (!isObject(data)) return {}
    var out = {}
    for (var k in data) {
      if (!isObject(data[k])) continue
      out[k] = { count: Number(data[k].count || 0) || 0, last: Number(data[k].last || 0) || 0 }
    }
    return out
  } catch (e) {
    return {}
  }
}

function recordUsage(usage, path, now) {
  var out = {}
  for (var k in usage) out[k] = usage[k]
  var entry = out[path] || { count: 0, last: 0 }
  out[path] = { count: (Number(entry.count || 0) || 0) + 1, last: Number(now || 0) }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    isObject: isObject,
    expandPath: expandPath,
    basename: basename,
    pathKey: pathKey,
    shellQuote: shellQuote,
    defaultConfig: defaultConfig,
    normalizeConfig: normalizeConfig,
    scanArgs: scanArgs,
    parseScan: parseScan,
    mergeProjects: mergeProjects,
    rankProjects: rankProjects,
    frecencyScore: frecencyScore,
    filterProjects: filterProjects,
    gitSummary: gitSummary,
    remoteToWebUrl: remoteToWebUrl,
    projectRow: projectRow,
    commandAvailable: commandAvailable,
    availableEditors: availableEditors,
    actionsFor: actionsFor,
    commandFor: commandFor,
    parseUsage: parseUsage,
    recordUsage: recordUsage
  }
}
