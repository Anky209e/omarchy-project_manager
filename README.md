# Project Manager

A keyboard-driven project launcher for the [Omarchy](https://omarchy.org) shell.
Summon an overlay, type to filter your projects, and open any of them in your
editor, a terminal, or your file manager — with live git status, one-key jumps
to the repo, per-project tasks, and frecency ranking of what you actually use.

![Project Manager overlay](preview.png)

It is an Omarchy overlay plugin that uses the shell’s `[menu]` theme tokens.
It has its own plugin ID and does not replace the built-in clipboard.

## Features

- **Discovery** — recursively scans configured roots (default `~/Projects`) for
  git repositories and Godot projects (`project.godot`), plus any explicit
  entries from the config file.
- **Framework & language versions** — each row shows the project's framework and
  language with versions, e.g. `<NestJS icon> 12.2.0 · <TypeScript icon> 6.0.3`;
  the row icon is the framework's (or the language's when there is no framework).
  Detected from `package.json` dependencies (NestJS, Next.js, Nuxt, Astro, Angular,
  Svelte/SvelteKit, Vue, React, Fastify, Express), Python (Django, FastAPI, Flask),
  Rails, and Laravel; versions come from `node_modules` or the declared range,
  `Cargo.toml`, `go.mod`, `.python-version`, `.ruby-version` and `composer.json`.
  Projects without a framework show the language name and version (e.g. `Rust 1.78`).
- **Project types** — each project is tagged by the files it contains (Node,
  Rust, Go, Python, Nix, CMake, Ruby, PHP, Make, Just, Godot) and shown with a
  matching icon/label.
- **Auto-detected tasks** — project tasks are read straight from `package.json`
  scripts, `Makefile`/`justfile` targets, and `Cargo.toml`/`go.mod`/`pyproject`
  markers, so most projects need no task config. Make and Just tasks also appear
  alongside language tasks; Just detection lists parameterless recipes from
  `justfile`, `Justfile`, or `.justfile`. Tasks with a missing tool are
  greyed out.
- **Omarchy default editor** — by default projects open with whichever editor
  you selected via `omarchy default editor` (through `omarchy-launch-editor`),
  so the plugin follows that choice automatically.
- **Many editors** — VS Code, Zed, Cursor, Neovim (opens in a terminal), and
  Godot built in; add your own. Unavailable editors are shown greyed out, and
  `Ctrl+E` cycles the editor for the current project and remembers your choice.
- **Pin projects** — click the pin or press `Ctrl+P` to keep a project at the
  top. Pins and editor choices survive shell restarts without rewriting config.
- **Godot projects** — anything with a `project.godot` opens in the Godot editor
  automatically (when `godot` is installed), unless you set an editor for it.
- **Terminal & files** — open a terminal in the project dir (`Shift+Enter`) or
  the file manager (`Alt+Enter`).
- **Git at a glance** — branch, dirty marker, ahead/behind counts in the list and
  detail pane.
- **lazygit** — any git repo gets a single "Open in lazygit" action (enabled when
  `lazygit` is installed), also bound to `Ctrl+Shift+G`.
- **Clone & create** — `Ctrl+L` clones a repo into your first discovery root;
  `Ctrl+N` scaffolds a new project (`mkdir` + `git init`). Operations run in
  the overlay, report failures, and refresh discovery when they finish.
- **Fresh metadata** — opening the overlay refreshes projects and Git status.
- **Browser & clipboard** — `Ctrl+G` opens the repository remote; `Ctrl+Y` copies
  the project path.
- **Fuzzy search** — filter matches on name, path, tags, editor and branch as a
  subsequence, with matches highlighted.
- **Tasks** — `Ctrl+1`..`Ctrl+9` runs a task in the overlay with live stdout and
  stderr, exit status, Copy output, Stop, and Rerun. `Ctrl+O` returns to the
  latest output while you browse projects. One managed task runs at a time;
  closing the overlay keeps it running. Interactive tasks can use terminal mode.
- **Grouped actions** — Open, Git, Tasks, and Project sections keep actions easy
  to scan. Disabled actions explain missing tools or unsupported remotes.
- **Frecency** — the projects you open most, most recently, float to the top.

## Install

Add the plugin straight from GitHub:

```sh
omarchy plugin add https://github.com/Anky209e/omarchy-project_manager.git --enable
```

`omarchy plugin add` clones the repo into
`~/.config/omarchy/plugins/io.github.anky209e.project-manager`, validates the
manifest, and (with `--enable`) turns it on. It never runs anything from the
plugin and never asks for `sudo`.

> **Plugins run unsandboxed.** A plugin is code that runs inside the long-lived
> Omarchy shell process with your user permissions. Only install repositories
> you trust, and read them first if you are unsure.

If you installed without `--enable`, enable it later:

```sh
omarchy plugin enable io.github.anky209e.project-manager
```

### Bind a key

The plugin has no bar widget — it is summoned through the shell. Add a binding
to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + P", "Project manager", "omarchy-shell shell toggle io.github.anky209e.project-manager")
```

Then reload Hyprland (`hyprctl reload`). The same `toggle` command can be bound
anywhere, run from a script, or invoked directly.

Optionally, give the overlay a stable layer namespace rule in
`~/.config/hypr/looknfeel.lua` so it animates/rounds like the rest of the shell
— the overlay uses the namespace `omarchy-project-manager`.

### Update

```sh
omarchy plugin update io.github.anky209e.project-manager
```

### Remove

```sh
omarchy plugin remove io.github.anky209e.project-manager
```

Removal deletes the plugin folder only. Your config
(`~/.config/omarchy/project-manager.json`), frecency state
(`~/.local/state/omarchy/project-manager/usage.json`), and preferences
(`~/.local/state/omarchy/project-manager/preferences.json`) are left untouched.

## Requirements

- Omarchy shell with third-party plugins enabled (Quattro).
- `bash`, `git`, `jq` (for the scan helper), `setsid` (for managed tasks).
- Standard Omarchy/Arch tools: GNU coreutils, findutils, grep, sed, awk, and util-linux.
- For GUI and terminal actions: `uwsm-app`, `xdg-open`, `xdg-terminal-exec`,
  `omarchy-launch-editor`, and `omarchy-launch-browser`.
- Optional: `wl-copy` for clipboard actions; `lazygit` for its Git action;
  your chosen editors and task tools (npm, Cargo, Make, Just, and others).
  Actions explain which tools are missing.

No sudo or pkexec is required. There are no install hooks, automatic dependency
installations, or telemetry. Discovery reads local directories and Git metadata.
Discovery exports only sanitized public repository links: URL user information,
query strings, and fragments are removed without changing Git config.
Cloning contacts the repository you request. Explicitly launched tasks may use
the network, install project dependencies, or change project files according to
the command. They run with your normal user permissions. The plugin writes its
own state files and creates/clones projects only when you request it; it does
not edit Hyprland bindings or the Omarchy shell configuration.

## Release notes

Version 1.1.0 adds persistent project preferences, grouped actions, and managed
task output. See [CHANGELOG.md](CHANGELOG.md) for fixes and migration notes.
Marketplace update preparation is documented in [docs/marketplace.md](docs/marketplace.md).
The dependency review remains incomplete; see [docs/security-review.md](docs/security-review.md)
for the remote-credential fix and remaining scope.

## Development

Clone and validate the source without changing your installed plugin:

```sh
git clone https://github.com/Anky209e/omarchy-project_manager.git ~/Projects/omarchy-project_manager
cd ~/Projects/omarchy-project_manager
omarchy plugin validate .
```

For an isolated development copy, place these source files in a separate test
plugin directory and use a separate plugin ID. Omarchy validation rejects
symlinks inside plugin folders, so development symlinks are not part of the
supported installation path. After updating the installed plugin, restart the
shell to load the kept overlay instance:

```sh
omarchy restart shell
```

Run the regression checks from the repository root:

```sh
python3 -m unittest discover -s tests
node --test tests/store.test.js
bash -n project-manager.sh task-runner.sh
```

The tests use temporary local repositories and stub tools. For UI checks on a
machine with Qt Test and Quickshell installed:

```sh
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_CONTROLS_STYLE=Basic \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml
python3 tests/run_overlay_smoke.py --screenshots /tmp/project-manager-preview
```

The smoke test isolates HOME and configuration, substitutes the Wayland window
host for headless rendering, and runs the production controller, file I/O,
scanner, and task runner. It checks preferences across new instances, stdout /
stderr, failure status, rerun, cancellation, and prompts with no search results.
It does not change your desktop or launch editors. Native layer-shell placement
and compositor focus still need an interactive check.

## Keybindings

| Key | Action |
| --- | --- |
| `SUPER + ALT + P` | Toggle the overlay |
| type | Filter projects |
| `Up` / `Down` | Move selection (or the action list when focused) |
| `Right` / `Tab` | Focus the action list |
| `Left` / `Shift+Tab` | Back to the project list |
| `Enter` | Open the highlighted action (default: editor) |
| `Shift+Enter` | Open a terminal in the project |
| `Alt+Enter` | Open the file manager |
| `Ctrl+E` | Cycle and remember the editor for the current project |
| `Ctrl+P` | Pin or unpin the current project |
| `Ctrl+O` | Show the latest task output (again to return) |
| `Ctrl+X` | Stop the managed task while viewing output |
| `Ctrl+Enter` | Rerun the last task while viewing output |
| `Ctrl+G` | Open the repository in the browser |
| `Ctrl+Shift+G` | Open the repo in lazygit |
| `Ctrl+Y` | Copy the project path |
| `Ctrl+N` | New project (name prompt) |
| `Ctrl+L` | Clone a repository (URL prompt) |
| `Ctrl+R` | Rescan projects |
| `Ctrl+1`..`Ctrl+9` | Run the nth task |
| `PageUp` / `PageDown`, `Home` / `End` | Jump within the list |
| `Esc` | Clear the filter, then leave the actions, then close |
| mouse | Hover/click select; double-click opens the default action |

## Configuration

User config: `~/.config/omarchy/project-manager.json` (optional; see
`config.example.json`). Everything has sensible defaults, and the file is
watched — saving it reloads live. Frecency state is kept separately in
`~/.local/state/omarchy/project-manager/usage.json`.

```json
{
  "version": 1,
  "defaultEditor": "omarchy",
  "scale": 0,
  "taskMode": "managed",
  "discovery": {
    "enabled": true,
    "roots": ["~/Projects", "~/Work", "~/dev"],
    "maxDepth": 3,
    "exclude": ["node_modules", ".git", ".venv", "dist", "build", "target"]
  },
  "editors": {
    "omarchy": { "label": "Default editor", "command": "omarchy-launch-editor", "args": ["{path}"], "kind": "direct" },
    "vscode":  { "label": "VS Code", "command": "code", "args": ["{path}"], "kind": "gui" },
    "nvim":    { "label": "Neovim",  "command": "nvim", "args": ["{path}"], "kind": "terminal" },
    "godot":   { "label": "Godot",   "command": "godot", "args": ["--path", "{path}", "--editor"], "kind": "gui" }
  },
  "projects": [
    {
      "name": "omarchy-project_manager",
      "path": "~/Projects/omarchy-project_manager",
      "editor": "nvim",
      "tags": ["omarchy", "qml"],
      "pinned": true,
      "tasks": {
        "Validate": "omarchy plugin validate .",
        "Git status": "git status"
      }
    }
  ]
}
```

### Fields

- **`discovery.enabled`** — turn auto-discovery off to use only `projects`.
- **`discovery.roots`** — directories to scan (supports `~`).
- **`discovery.maxDepth`** — recursion depth (minimum 1).
- **`discovery.exclude`** — directory names to skip anywhere in the tree.
- **`defaultEditor`** — editor id used when a project doesn't specify one. The
  built-in `omarchy` editor delegates to `omarchy-launch-editor`, so it follows
  your Omarchy default. A project with a `project.godot` still opens in Godot
  (when installed) unless it sets its own `editor`.
- **`scale`** — UI scale for the overlay. `0` (default) auto-scales by logical
  screen height so it stays comfortable on 1440p/4K displays (`1080p` → `1.0`,
  `1440p` → `1.33`, capped at `1.6`); set a number to force a fixed multiplier.
- **`taskMode`** — `"managed"` (default) captures output in the overlay and offers
  Stop and Rerun. `"terminal"` opens an interactive terminal; `"background"`
  launches detached. Legacy `tasksInTerminal: true/false` maps to terminal/background
  unless `taskMode` is set explicitly. Editors and lazygit still open externally.
- **Saved preferences** — pins and editor choices live in
  `~/.local/state/omarchy/project-manager/preferences.json` and override project
  config fields. Deleting this file restores configured defaults. An explicit
  unpin overrides `pinned: true` in config; unknown editor IDs fall back to config.
- **Task output** — the latest managed run is retained in memory (up to 128K characters),
  including failures. Output is plain text; commands that require interactive
  input should use `taskMode: "terminal"`. Cancellation sends TERM to the task's
  process group, then KILL after a short grace period. Deliberately detached
  processes are outside that group. Task history is cleared when the shell restarts.
- **`editors[id]`** — `{ label, command, args, kind }`. `kind` is `"gui"` (launch
  via `uwsm-app`), `"terminal"` (run inside `xdg-terminal-exec`), or `"direct"`
  (run the command as-is, e.g. a launcher wrapper). `{path}` in `args` is
  replaced with the project path.
- **`projects[]`** — `{ name?, path, editor?, tags?, pinned?, tasks? }`. `path`
  supports `~`; `name` defaults to the basename. `pinned` projects always sort
  first. `tasks` is a name→command map (or a list of `{name, command}`).

## How it works

| File | Role |
| --- | --- |
| `ProjectManager.qml` | The overlay: window, list, detail/actions pane, key handling, processes and file I/O. |
| `ActionMenu.qml` | Grouped actions, keyboard selection, and disabled explanations. |
| `TaskConsole.qml` / `OverlayButton.qml` | Task output and reusable overlay controls. |
| `TaskRunner.qml` / `task-runner.sh` | Managed task lifecycle, bounded output, and process group cancellation. |
| `ProjectStore.js` | All pure logic (config normalization, scan args, parsing, merge/rank/filter, action + command building, frecency). No Qt types, so it is unit-testable with plain `node`. |
| `project-manager.sh` | Scan helper: walks the roots, reports git branch/dirty/ahead/behind and remote, detects project types (`package.json`, `Cargo.toml`, `go.mod`, …) and generates tasks from `package.json` scripts / `Makefile` / `justfile` / tool markers, and lists which editor/action commands exist on `$PATH`. Emits JSON. |
| `manifest.json` | Plugin manifest (`overlay` kind, `keepLoaded`). |
| `config.example.json` | Sample user config. |

Architecture: `ProjectManager.qml` owns side effects; every decision — what to
scan, how to rank, which command to run — is delegated to `ProjectStore.js`,
which the QML imports as `Store`. `project-manager.sh` is invoked only to do
filesystem + git discovery in one fast pass.

## License

[MIT](LICENSE) © 2026 Ankit Kumar (anky209e)
