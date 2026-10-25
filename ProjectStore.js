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
    defaultEditor: "omarchy",
    // 0 = auto (scale by screen height); otherwise a fixed multiplier.
    scale: 0,
    // Run project tasks in a terminal window so their output is visible.
    tasksInTerminal: true,
    taskMode: "managed",
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
      // Delegates to Omarchy's own default programming editor, so switching it
      // with `omarchy default editor` also switches what this plugin opens.
      omarchy: { label: "Default editor", command: "omarchy-launch-editor", args: ["{path}"], kind: "direct" },
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
  var kind = "gui"
  if (editor.kind === "terminal") kind = "terminal"
  else if (editor.kind === "direct") kind = "direct"
  return {
    id: id,
    label: String(editor.label || id),
    command: String(editor.command || ""),
    args: Array.isArray(editor.args) ? editor.args.map(String) : ["{path}"],
    kind: kind
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
    for (t in tasks) out.push({ name: t, command: String(tasks[t]), requires: "" })
  } else if (Array.isArray(tasks)) {
    for (i = 0; i < tasks.length; i++) {
      var item = tasks[i]
      if (isObject(item) && item.name)
        out.push({ name: String(item.name), command: String(item.command || ""), requires: String(item.requires || "") })
      else if (typeof item === "string") out.push({ name: item, command: "", requires: "" })
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
    scale: 0,
    tasksInTerminal: parsed.tasksInTerminal === undefined ? base.tasksInTerminal : !!parsed.tasksInTerminal,
    taskMode: ["managed", "terminal", "background"].indexOf(parsed.taskMode) >= 0
      ? parsed.taskMode : (parsed.tasksInTerminal === undefined ? "managed"
        : (parsed.tasksInTerminal ? "terminal" : "background")),
    discovery: mergeDiscovery(base.discovery, parsed.discovery),
    editors: mergeEditors(base.editors, parsed.editors),
    projects: normalizeProjects(parsed.projects, home)
  }

  var requestedScale = Number(parsed.scale)
  if (isFinite(requestedScale) && requestedScale > 0) config.scale = requestedScale

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
    remote: publicGitRemote(git.remote)
  }
}

function normalizeScanTasks(tasks) {
  var out = []
  if (!Array.isArray(tasks)) return out
  for (var i = 0; i < tasks.length; i++) {
    var t = tasks[i]
    if (!isObject(t) || !t.name || !t.command) continue
    out.push({
      name: String(t.name),
      command: String(t.command),
      requires: String(t.requires || "")
    })
  }
  return out
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
        aliases: Array.isArray(p.aliases) ? p.aliases.map(String) : [],
        git: normalizeGit(p.git),
        godot: p.godot === true,
        types: Array.isArray(p.types) ? p.types.map(String) : [],
        stack: normalizeStack(p.stack),
        tasks: normalizeScanTasks(p.tasks)
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

var TYPE_META = {
  godot: { icon: "\ue65f", label: "Godot" },
  node: { icon: "\ue718", label: "Node" },
  rust: { icon: "\ue7a8", label: "Rust" },
  go: { icon: "\ue626", label: "Go" },
  python: { icon: "\ue73c", label: "Python" },
  nix: { icon: "\uf313", label: "Nix" },
  cmake: { icon: "\ue794", label: "CMake" },
  ruby: { icon: "\ue739", label: "Ruby" },
  php: { icon: "\ue73d", label: "PHP" },
  make: { icon: "\ue673", label: "Make" },
  just: { icon: "\uf0ad", label: "Just" }
}

function primaryType(types) {
  if (!Array.isArray(types)) return ""
  for (var i = 0; i < types.length; i++) {
    if (TYPE_META[types[i]]) return types[i]
  }
  return ""
}

function typeIcon(types) {
  var t = primaryType(types)
  return t ? TYPE_META[t].icon : ""
}

function typeLabel(types) {
  var t = primaryType(types)
  return t ? TYPE_META[t].label : ""
}

// Framework and language shown on each row. Icons are Nerd Font glyphs.
var STACK_META = {
  nestjs: { icon: "\ue83b", label: "NestJS" },
  nextjs: { icon: "\ue83e", label: "Next.js" },
  nuxt: { icon: "\ue84b", label: "Nuxt" },
  astro: { icon: "\ue735", label: "Astro" },
  angular: { icon: "\ue753", label: "Angular" },
  sveltekit: { icon: "\ue8b7", label: "SvelteKit" },
  svelte: { icon: "\ue8b7", label: "Svelte" },
  vue: { icon: "\ue8dc", label: "Vue" },
  react: { icon: "\ue7ba", label: "React" },
  fastify: { icon: "\ue7d6", label: "Fastify" },
  express: { icon: "\ue7d3", label: "Express" },
  django: { icon: "\ue71d", label: "Django" },
  fastapi: { icon: "\ue7d5", label: "FastAPI" },
  flask: { icon: "\ue7dc", label: "Flask" },
  rails: { icon: "\ue73b", label: "Rails" },
  laravel: { icon: "\ue73f", label: "Laravel" },
  typescript: { icon: "\ue8ca", label: "TypeScript" },
  node: { icon: "\ue718", label: "Node" },
  rust: { icon: "\ue7a8", label: "Rust" },
  go: { icon: "\ue724", label: "Go" },
  python: { icon: "\ue73c", label: "Python" },
  ruby: { icon: "\ue739", label: "Ruby" },
  php: { icon: "\ue73d", label: "PHP" }
}

function normalizeStackItem(item) {
  if (!isObject(item) || !STACK_META[item.id]) return null
  return { id: String(item.id), version: item.version ? String(item.version) : "" }
}

function normalizeStack(stack) {
  if (!isObject(stack)) return { framework: null, language: null }
  return { framework: normalizeStackItem(stack.framework), language: normalizeStackItem(stack.language) }
}

// Row summary. With a framework: "<fw icon> 12.2.0 · <lang icon> 6.0.3".
// Without one: "Rust 1.78" (language name and version). "" when nothing is known.
function stackText(stack) {
  var s = normalizeStack(stack)
  var fw = s.framework
  var lang = s.language
  function withVersion(text, item) { return text + (item.version ? " " + item.version : "") }
  if (fw) {
    var parts = [withVersion(STACK_META[fw.id].icon, fw)]
    if (lang) parts.push(withVersion(STACK_META[lang.id].icon, lang))
    return parts.join("  \u00b7  ")
  }
  if (lang) return withVersion(STACK_META[lang.id].label, lang)
  return ""
}

// Row icon: the framework's, else the language's, else the file-based type icon.
function stackIcon(stack) {
  var s = normalizeStack(stack)
  if (s.framework) return STACK_META[s.framework.id].icon
  if (s.language) return STACK_META[s.language.id].icon
  return ""
}

// Configured tasks win over auto-detected ones with the same name.
function mergeTasks(auto, configured) {
  var out = []
  var seen = {}
  var i
  var conf = Array.isArray(configured) ? configured : []
  for (i = 0; i < conf.length; i++) {
    var c = conf[i]
    if (!c || !c.name) continue
    seen[String(c.name).toLowerCase()] = true
    out.push({ name: c.name, command: c.command || "", requires: c.requires || "", source: "config" })
  }
  var au = Array.isArray(auto) ? auto : []
  for (i = 0; i < au.length; i++) {
    var a = au[i]
    if (!a || !a.name || seen[String(a.name).toLowerCase()]) continue
    seen[String(a.name).toLowerCase()] = true
    out.push({ name: a.name, command: a.command || "", requires: a.requires || "", source: "auto" })
  }
  return out
}

function buildProject(path, name, git, meta, config, godot, types, autoTasks, stack) {
  var explicitEditor = meta && meta.editor && config.editors[meta.editor] ? meta.editor : ""
  var labelId = explicitEditor
  if (!labelId && godot && config.editors.godot) labelId = "godot"
  if (!labelId) labelId = config.defaultEditor
  var editor = config.editors[labelId]
  return {
    name: String((meta && meta.name) || name || basename(path)),
    path: path,
    editor: explicitEditor,
    editorId: labelId,
    editorLabel: editor ? editor.label : labelId,
    godot: !!godot,
    types: Array.isArray(types) ? types.slice() : [],
    stack: normalizeStack(stack),
    tags: meta && Array.isArray(meta.tags) ? meta.tags.slice() : [],
    tasks: mergeTasks(autoTasks, meta && meta.tasks),
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
    if (used[key]) continue
    var meta = byPath[key]
    var aliases = s.aliases || []
    for (var j = 0; j < aliases.length; j++) {
      var alias = pathKey(aliases[j])
      if (!meta && byPath[alias]) meta = byPath[alias]
      used[alias] = true
    }
    used[key] = true
    out.push(buildProject(s.path, s.name, s.git, meta, config, s.godot, s.types, s.tasks, s.stack))
  }

  // Configured projects the scan didn't return (discovery off, path missing,
  // or outside every root) still appear, just without git data.
  for (i = 0; i < explicit.length; i++) {
    var key2 = pathKey(explicit[i].path)
    if (used[key2]) continue
    out.push(buildProject(explicit[i].path, explicit[i].name, null, explicit[i], config, false, [], []))
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

// Fuzzy subsequence score. Returns 0 when query is not a subsequence.
// Higher is better; contiguous and word-boundary matches score highest.
function fuzzyScore(text, query) {
  var t = String(text || "").toLowerCase()
  var q = String(query || "").toLowerCase()
  if (!q) return 0
  if (!t) return 0
  var ti = 0, score = 0, streak = 0
  for (var qi = 0; qi < q.length; qi++) {
    var ch = q.charAt(qi)
    var found = -1
    for (var j = ti; j < t.length; j++) {
      if (t.charAt(j) === ch) { found = j; break }
    }
    if (found < 0) return 0
    if (found === ti) { streak++; score += 3 + streak } else { streak = 0; score += 1 }
    if (found === 0 || /[ \/_.-]/.test(t.charAt(found - 1))) score += 4
    ti = found + 1
  }
  if (t.indexOf(q) >= 0) score += 25
  score -= (t.length - q.length) * 0.05
  return score > 0 ? score : 0.001
}

function projectMatchScore(p, query) {
  var fields = [
    [p.name, 3],
    [(p.tags || []).join(" "), 2],
    [p.path, 1],
    [p.editorLabel, 1],
    [p.git ? p.git.branch : "", 1]
  ]
  var best = 0
  for (var i = 0; i < fields.length; i++) {
    var s = fuzzyScore(fields[i][0], query) * fields[i][1]
    if (s > best) best = s
  }
  return best
}

function filterProjects(projects, query) {
  var list = Array.isArray(projects) ? projects : []
  var q = String(query || "").trim()
  if (!q) return list.slice()
  var scored = []
  for (var i = 0; i < list.length; i++) {
    var s = projectMatchScore(list[i], q)
    if (s > 0) scored.push({ p: list[i], s: s })
  }
  scored.sort(function (a, b) {
    if (a.p.pinned !== b.p.pinned) return a.p.pinned ? -1 : 1
    if (Math.abs(a.s - b.s) > 1e-9) return b.s - a.s
    return String(a.p.name).localeCompare(String(b.p.name))
  })
  var out = []
  for (var k = 0; k < scored.length; k++) out.push(scored[k].p)
  return out
}

function escapeHtml(text) {
  return String(text == null ? "" : text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

// Markdown-free HTML with matched characters wrapped in <b> for QML StyledText.
function highlightHtml(text, query) {
  var t = String(text == null ? "" : text)
  var q = String(query || "").trim().toLowerCase()
  if (!q) return escapeHtml(t)
  var tl = t.toLowerCase()
  var positions = []
  var ti = 0
  for (var qi = 0; qi < q.length; qi++) {
    var found = -1
    for (var j = ti; j < tl.length; j++) {
      if (tl.charAt(j) === q.charAt(qi)) { found = j; break }
    }
    if (found < 0) return escapeHtml(t) // not a subsequence: no highlight
    positions.push(found)
    ti = found + 1
  }
  var mark = {}
  for (var k = 0; k < positions.length; k++) mark[positions[k]] = true
  var out = ""
  var open = false
  for (var x = 0; x < t.length; x++) {
    var isMark = !!mark[x]
    if (isMark && !open) { out += "<b>"; open = true }
    else if (!isMark && open) { out += "</b>"; open = false }
    out += escapeHtml(t.charAt(x))
  }
  if (open) out += "</b>"
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

function publicGitRemote(remote) {
  var r = String(remote || "")
  // Defense in depth for legacy scan data: launch only a credential-free URL.
  if (/[\x00-\x20\x7f\\]/.test(r)) return ""
  r = r.split(/[?#]/)[0]
  var host = "", path = "", scheme = "https://"
  var m = r.match(/^(https?|ssh|git):\/\/([^/]+)(\/.*)$/i)
  if (m) {
    host = m[2].substring(m[2].lastIndexOf("@") + 1)
    path = m[3]
    if (m[1].toLowerCase() === "http") scheme = "http://"
  } else {
    if (r.indexOf("://") >= 0) return ""
    m = r.match(/^(?:[^@/:]+@)?(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9][A-Za-z0-9.-]*):([^?#]+)$/)
    if (!m) return ""
    host = m[1]
    path = "/" + m[2].replace(/^\//, "")
  }
  if (!/^(?:[A-Za-z0-9][A-Za-z0-9.-]*|\[[0-9A-Fa-f:.]+\])(?::[0-9]+)?$/.test(host)) return ""
  return scheme + host + path
}

function remoteToWebUrl(remote) {
  return publicGitRemote(remote).replace(/\.git$/, "")
}

function projectRow(project) {
  var git = project.git
  return {
    name: project.name,
    path: project.path,
    editorLabel: project.editorLabel,
    icon: stackIcon(project.stack) || typeIcon(project.types),
    typeLabel: typeLabel(project.types),
    stackText: stackText(project.stack),
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
  var editorId = effectiveEditorId && config.editors[effectiveEditorId] ? effectiveEditorId : ""
  // Godot projects open in the Godot editor unless the user picked one.
  if (!editorId && project.godot && config.editors.godot
      && commandAvailable(config.editors.godot.command, available)) editorId = "godot"
  if (!editorId) editorId = config.defaultEditor
  var editor = config.editors[editorId] || config.editors[config.defaultEditor]

  if (editor) {
    var actionKind = "editor-gui"
    if (editor.kind === "terminal") actionKind = "editor-terminal"
    else if (editor.kind === "direct") actionKind = "editor-direct"
    actions.push({
      id: "editor:" + editorId,
      kind: actionKind,
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

  if (project.git) {
    actions.push({
      id: "git:lazygit",
      kind: "terminal-cmd",
      label: "Open in lazygit",
      hint: "Ctrl \u21e7G",
      enabled: commandAvailable("lazygit", available),
      command: "lazygit"
    })
  }

  var tasks = project.tasks || []
  for (var i = 0; i < tasks.length; i++) {
    var t = tasks[i]
    var ok = !t.requires || commandAvailable(t.requires, available)
    actions.push({
      id: "task:" + t.name,
      kind: "task",
      label: "Run task: " + t.name,
      hint: i < 9 ? "Ctrl " + (i + 1) : "",
      enabled: ok,
      command: t.command,
      requires: t.requires || ""
    })
  }

  actions.push({id: "pin", kind: "pin", label: project.pinned ? "Unpin project" : "Pin project",
    hint: "Ctrl P", enabled: true})
  actions.push({id: "cycle-editor", kind: "cycle-editor", label: "Change editor",
    hint: "Ctrl E", enabled: availableEditors(config, available).length > 0})

  var order = {Open: 0, Git: 1, Tasks: 2, Project: 3}
  for (var j = 0; j < actions.length; j++) {
    var action = actions[j]
    action.group = action.kind === "task" ? "Tasks"
      : (action.kind === "github" || action.kind === "terminal-cmd" ? "Git"
        : (["copy", "pin", "cycle-editor"].indexOf(action.kind) >= 0 ? "Project" : "Open"))
    action.disabledReason = ""
    var required = []
    if (action.kind.indexOf("editor-") === 0) {
      required.push(editor.command)
      if (editor.kind !== "direct") required.push("setsid", "uwsm-app")
      if (editor.kind === "terminal") required.push("xdg-terminal-exec")
    } else if (action.kind === "terminal") required = ["setsid", "uwsm-app", "xdg-terminal-exec"]
    else if (action.kind === "files") required = ["setsid", "uwsm-app", "xdg-open"]
    else if (action.kind === "github") required = ["setsid", "uwsm-app", "omarchy-launch-browser"]
    else if (action.kind === "terminal-cmd") required = ["setsid", "uwsm-app", "xdg-terminal-exec", "lazygit"]
    else if (action.kind === "copy") required = ["wl-copy"]
    else if (action.kind === "task") {
      if (action.requires) required.push(action.requires)
      var taskMode = config.taskMode || (config.tasksInTerminal === false ? "background" : "terminal")
      if (taskMode === "terminal") required.push("setsid", "uwsm-app", "xdg-terminal-exec")
      else if (taskMode !== "background") required.push("setsid")
      if (!action.command) action.disabledReason = "No command configured"
    }
    var missing = required.filter(function (cmd) { return !commandAvailable(cmd, available) })
    if (missing.length) action.disabledReason = "Missing: " + missing.join(", ")
    if (action.kind === "github" && !url) action.disabledReason = "No supported repository remote"
    if (action.kind === "cycle-editor" && !action.enabled) action.disabledReason = "No installed editors found"
    if (action.disabledReason) action.enabled = false
  }
  // Keep the editor first within Open and preserve task shortcut numbering.
  return actions.map(function (action, index) { return {action: action, index: index} })
    .sort(function (a, b) { return order[a.action.group] - order[b.action.group] || a.index - b.index })
    .map(function (entry) { return entry.action })
}

// Returns { argv: [...] } for direct execution or { shell: "..." } for a
// string that must run under a shell, or { managed: {...} } for the task runner.
// null means "nothing to run".
function commandFor(action, project, config) {
  if (!action) return null
  var path = project ? project.path : ""

  if (action.kind === "editor-gui" || action.kind === "editor-terminal" || action.kind === "editor-direct") {
    var editor = config.editors[action.editorId] || config.editors[config.defaultEditor]
    if (!editor) return null
    var args = editor.args || ["{path}"]
    var rendered = []
    for (var i = 0; i < args.length; i++) rendered.push(String(args[i]).replace("{path}", path))
    var cmd = [editor.command].concat(rendered)
    if (editor.kind === "terminal") {
      return { argv: ["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path, "-e"].concat(cmd) }
    }
    if (editor.kind === "direct") return { argv: cmd }
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

  if (action.kind === "terminal-cmd") {
    if (!action.command) return null
    return terminalArgv(path, "cd " + shellQuote(path) + " && " + action.command, "io.github.anky209e.project-manager.task")
  }

  if (action.kind === "task") {
    if (!action.command) return null
    var cmd = "cd " + shellQuote(path) + " && " + action.command
    var mode = config && config.taskMode ? config.taskMode : "managed"
    if (mode === "managed") return { managed: { path: path, command: action.command,
      label: action.label, projectName: project.name } }
    if (mode === "background") return { shell: cmd }
    return terminalArgv(path, cmd, "io.github.anky209e.project-manager.task")
  }

  return null
}

// Launch `command` in a terminal rooted at `dir`, keeping the window open so
// its output stays readable.
function terminalArgv(dir, command, appId) {
  var hold = "; st=$?; printf '\\n[exit %s] ' \"$st\"; read -r _"
  return {
    argv: [
      "setsid", "uwsm-app", "--", "xdg-terminal-exec",
      "--dir=" + dir, "--app-id=" + appId,
      "-e", "bash", "-lc", command + hold
    ]
  }
}

// --------------------------------------------------------- clone / create

function defaultRoot(config, home) {
  var roots = (config && config.discovery && config.discovery.roots) || []
  if (roots.length > 0) return expandPath(roots[0], home)
  return expandPath("~/Projects", home)
}

function sanitizeProjectName(name) {
  var n = String(name || "").trim().replace(/^[-]+/, "")
  if (!n || n.indexOf("/") >= 0 || n === "." || n === "..") return ""
  return n
}

function cloneCommand(config, home, url) {
  var u = String(url || "").trim()
  if (!/^(https?:\/\/|git@|ssh:\/\/|git:\/\/|file:\/\/|\/)/.test(u)) return null
  var root = defaultRoot(config, home)
  return { argv: ["bash", "-lc", "mkdir -p " + shellQuote(root)
    + " && cd " + shellQuote(root) + " && git clone -- " + shellQuote(u)] }
}

function newProjectCommand(config, home, name) {
  var n = sanitizeProjectName(name)
  if (!n) return null
  var dir = defaultRoot(config, home).replace(/\/+$/, "") + "/" + n
  return { argv: ["bash", "-lc", "mkdir -p " + shellQuote(dir) + " && git -C " + shellQuote(dir) + " init"], path: dir }
}

// ---------------------------------------------------------- preferences

function parsePreferences(raw) {
  try {
    var data = typeof raw === "string" ? JSON.parse(raw) : raw
    if (!isObject(data) || data.version !== 1 || !isObject(data.projects)) return {version: 1, projects: {}}
    var projects = {}
    for (var path in data.projects) {
      if (path.charAt(0) !== "/" || !isObject(data.projects[path])) continue
      var entry = data.projects[path], clean = {}
      if (typeof entry.pinned === "boolean") clean.pinned = entry.pinned
      if (typeof entry.editor === "string") clean.editor = entry.editor
      projects[pathKey(path)] = clean
    }
    return {version: 1, projects: projects}
  } catch (e) { return {version: 1, projects: {}} }
}

function updatePreference(preferences, path, field, value) {
  var out = parsePreferences(preferences)
  var key = pathKey(path)
  if (key.charAt(0) !== "/") return out
  var entry = out.projects[key] || {}
  if (field === "pinned" && typeof value === "boolean") entry.pinned = value
  if (field === "editor" && typeof value === "string") entry.editor = value
  out.projects[key] = entry
  return out
}

function applyPreferences(projects, preferences, config, available) {
  var prefs = parsePreferences(preferences).projects
  return projects.map(function (project) {
    var p = {}
    for (var key in project) p[key] = project[key]
    var saved = prefs[pathKey(p.path)] || {}
    if (typeof saved.pinned === "boolean") p.pinned = saved.pinned
    if (saved.editor && config.editors[saved.editor]) p.editor = saved.editor
    var id = p.editor
    if (!id && p.godot && config.editors.godot
        && commandAvailable(config.editors.godot.command, available)) id = "godot"
    if (!id) id = config.defaultEditor
    p.editorId = id
    p.editorLabel = config.editors[id] ? config.editors[id].label : id
    return p
  })
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
    parsePreferences: parsePreferences,
    updatePreference: updatePreference,
    applyPreferences: applyPreferences,
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
    fuzzyScore: fuzzyScore,
    projectMatchScore: projectMatchScore,
    highlightHtml: highlightHtml,
    escapeHtml: escapeHtml,
    typeIcon: typeIcon,
    typeLabel: typeLabel,
    stackText: stackText,
    stackIcon: stackIcon,
    primaryType: primaryType,
    commandAvailable: commandAvailable,
    availableEditors: availableEditors,
    actionsFor: actionsFor,
    commandFor: commandFor,
    terminalArgv: terminalArgv,
    defaultRoot: defaultRoot,
    sanitizeProjectName: sanitizeProjectName,
    cloneCommand: cloneCommand,
    newProjectCommand: newProjectCommand,
    parseUsage: parseUsage,
    recordUsage: recordUsage
  }
}
