# Project Manager

Anky209e/omarchy-project_manager

A keyboard-driven project launcher for the [Omarchy](https://omarchy.org) shell.
Summon an overlay, type to filter your projects, and open any of them in your
editor, a terminal, or your file manager — with live git status, one-key jumps
to the repo, per-project tasks, and frecency ranking of what you actually use.

It is an Omarchy *overlay* plugin (same kind as the built-in clipboard) whose
styling derives from `omarchy.clipboard`, so it shares the `[menu]` theme
tokens. It runs as its own plugin — the clone metadata is intentionally **not**
declared — so the clipboard's own `SUPER + CTRL + V` keeps working.

## Features

- **Discovery** — recursively scans configured roots (default `~/Projects`) for
  projects, plus any explicit entries from the config file.
- **Many editors** — VS Code, Zed, Cursor, Neovim (opens in a terminal), and
  Godot built in; add your own. Unavailable editors are shown greyed out, and
  `Ctrl+E` cycles the editor for the current project.
- **Terminal & files** — open a terminal in the project dir (`Shift+Enter`) or
  the file manager (`Alt+Enter`).
- **Git at a glance** — branch, dirty marker, ahead/behind counts in the list and
  detail pane.
- **GitHub** — `Ctrl+G` opens the repository remote in the browser.
- **Copy path** — `Ctrl+Y` puts the project path on the clipboard via `wl-copy`.
- **Tasks** — per-project commands (e.g. "Run tests") run with `Ctrl+1`..`Ctrl+9`.
- **Frecency** — the projects you open most, most recently, float to the top.

## Requirements

- Omarchy shell with third-party plugins enabled.
- `bash`, `git`, `jq` (for the scan helper).
- For actions: `wl-copy`, `xdg-open`, `xdg-terminal-exec`,
  `omarchy-launch-browser`. Actions whose tool is missing are disabled, not
  broken.

## Install (development)

The plugin lives in this repo and is linked into the user plugin directory so
edits here are picked up by the shell:

```sh
git clone <this-repo> ~/Projects/anky.project_manager
ln -sfn ~/Projects/anky.project_manager ~/.config/omarchy/plugins/anky.project_manager
omarchy plugin list          # should show anky.project_manager
omarchy plugin validate .    # validates the manifest
```

Enable it in `~/.config/omarchy/shell.json` by adding it to `plugins`:

```json
{ "plugins": [ { "id": "anky.project_manager" } ] }
```

Then bind it (already added to `~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + ALT + P", "Project manager", "omarchy-shell shell toggle anky.project_manager")
```

and give the overlay layer a stable namespace rule in
`~/.config/hypr/looknfeel.lua` (namespace `omarchy-project-manager`).

> **Reloading while developing:** the plugin directory is a symlink, so the
> shell's file watcher does not see edits. After changing any plugin file run
> `omarchy restart shell` to pick them up.

## Keybindings

| Key | Action |
| --- | --- |
| `SUPER + ALT + P` | Toggle the overlay |
| type | Filter projects |
| `Up` / `Down` | Move selection (or the action list when focused) |
| `Left` / `Tab` | Focus the action list |
| `Right` / `Shift+Tab` | Back to the project list |
| `Enter` | Open the highlighted action (default: editor) |
| `Shift+Enter` | Open a terminal in the project |
| `Alt+Enter` | Open the file manager |
| `Ctrl+E` | Cycle editor for the current project |
| `Ctrl+G` | Open the repository in the browser |
| `Ctrl+Y` | Copy the project path |
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
  "defaultEditor": "vscode",
  "scale": 0,
  "discovery": {
    "enabled": true,
    "roots": ["~/Projects", "~/Work", "~/dev"],
    "maxDepth": 3,
    "exclude": ["node_modules", ".git", ".venv", "dist", "build", "target"]
  },
  "editors": {
    "vscode": { "label": "VS Code", "command": "code", "args": ["{path}"], "kind": "gui" },
    "nvim":   { "label": "Neovim",  "command": "nvim", "args": ["{path}"], "kind": "terminal" },
    "godot":  { "label": "Godot",   "command": "godot", "args": ["--path", "{path}", "--editor"], "kind": "gui" }
  },
  "projects": [
    {
      "name": "anky.project_manager",
      "path": "~/Projects/anky.project_manager",
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
- **`defaultEditor`** — editor id used when a project doesn't specify one.
- **`scale`** — UI scale for the overlay. `0` (default) auto-scales by logical
  screen height so it stays comfortable on 1440p/4K displays (`1080p` → `1.0`,
  `1440p` → `1.33`, capped at `1.6`); set a number to force a fixed multiplier.
- **`editors[id]`** — `{ label, command, args, kind }`. `kind` is `"gui"` (run
  directly) or `"terminal"` (run inside `xdg-terminal-exec`). `{path}` in `args`
  is replaced with the project path.
- **`projects[]`** — `{ name?, path, editor?, tags?, pinned?, tasks? }`. `path`
  supports `~`; `name` defaults to the basename. `pinned` projects always sort
  first. `tasks` is a name→command map (or a list of `{name, command}`).

## How it works

| File | Role |
| --- | --- |
| `ProjectManager.qml` | The overlay: window, list, detail/actions pane, key handling, processes and file I/O. |
| `ProjectStore.js` | All pure logic (config normalization, scan args, parsing, merge/rank/filter, action + command building, frecency). No Qt types, so it is unit-testable with plain `node`. |
| `project-manager.sh` | Scan helper: walks the roots, reports git branch/dirty/ahead/behind and remote, and lists which editor/action commands exist on `$PATH`. Emits JSON. |
| `manifest.json` | Plugin manifest (`overlay` kind, `keepLoaded`). |
| `config.example.json` | Sample user config. |

Architecture: `ProjectManager.qml` owns side effects; every decision — what to
scan, how to rank, which command to run — is delegated to `ProjectStore.js`,
which the QML imports as `Store`. `project-manager.sh` is invoked only to do
filesystem + git discovery in one fast pass.
