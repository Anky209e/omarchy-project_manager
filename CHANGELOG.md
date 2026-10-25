# Changelog

## Unreleased

### Added

- Framework and language detection with versions on each project row; the row
  icon follows the framework (or the language when there is none).

## 1.1.0 — prepared, not published

### Added

- Pin/unpin projects with the row control or `Ctrl+P`.
- Persist pin overrides and editor choices across shell restarts in a separate
  preferences file, without rewriting user config.
- Group actions into Open, Git, Tasks, and Project, with missing-tool explanations.
- Managed tasks with live stdout/stderr, exit status, Copy output, cancellation,
  and Rerun. `Ctrl+O` returns to output; `Ctrl+X` stops a task; `Ctrl+Enter` reruns it.
- Headless UI component and controller smoke tests, plus regression coverage for
  preferences, scanner behavior, task output, and child-process cancellation.

### Changed

- Emphasize project names, mute paths, and show Git metadata as compact badges.
- Preserve the selected project when pinning, changing editors, or rescanning.
- Refresh discovery when the overlay opens and after clone/create finishes.
- Default new configurations to managed tasks; retain terminal/background modes.
- Provide useful empty-search actions and allow prompts when no projects match.

### Fixed

- Git remote credentials exposed in scanner child-process arguments and scan
  JSON. Raw remotes now use stdin; only sanitized public links are exported.
  The broader dependency review remains incomplete.

- Auto-detected task tools incorrectly reported as unavailable.
- Shell interpretation of spaces and metacharacters in package script names.
- Configured names being replaced by discovered basenames.
- Git worktrees and submodules being missed during discovery.
- Duplicate projects and lost metadata for symlinked and `..` paths.
- Make/Just tasks missing alongside language-specific tasks.
- Just assignments/directives incorrectly detected as runnable recipes.

### Migration

- No config file is required. Defaults discover `~/Projects`.
- Existing `tasksInTerminal: true` keeps terminal execution; `false` keeps
  background execution. Set `"taskMode": "managed"` to enable the new console.
- A saved pin/editor choice overrides the equivalent project config field.
  Removing `~/.local/state/omarchy/project-manager/preferences.json` restores
  config defaults. Usage history is stored separately.
- One managed task can run at a time. Closing the overlay keeps it running;
  its output is retained only for the current shell session.

## 1.0.0

Initial project launcher with discovery, Git metadata, editor/terminal/file
manager actions, fuzzy search, configured and detected tasks, and usage ranking.
