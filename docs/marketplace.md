# Marketplace update preparation

This repository is already listed. Prepare an update of the existing listing,
not a new submission. This document and the preparation script do not push,
create GitHub issues, apply labels, or publish anything.

## Listing identity

- Repository: https://github.com/Anky209e/omarchy-project_manager
- Plugin ID: `io.github.anky209e.project-manager` (unchanged)
- Display name: Project Manager
- Prepared version: 1.1.0
- Existing category: Productivity
- Existing tags: `launcher`, `quickshell`, `hyprland`
- Root manifest: `manifest.json`
- Root preview: `preview.png`
- License: MIT; see `LICENSE`

The public marketplace registry checked on 2026-10-16 records the existing
snapshot as `c8ed6a434972f230ceb6b1368829516b0c01ee92`. That record belongs to the
older snapshot; it does not verify this release. Recheck the registry before
submitting because the listing may change.

Sources:

- [Marketplace registry](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/registry.json)
- [Update workflow](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/VERIFICATION.md#promoting-a-plugin-update)
- [Verification form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml)

## Prepare locally

The dependency review remains incomplete. See [security-review.md](security-review.md)
for the addressed credential issue and remaining scope. These local checks do
not establish that the plugin is ready for security approval.

Run from the repository root after committing the source you want reviewed:

```sh
omarchy plugin validate .
python3 -m unittest discover -s tests
node --test tests/store.test.js
bash -n project-manager.sh task-runner.sh
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_CONTROLS_STYLE=Basic \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml
python3 tests/run_overlay_smoke.py
python3 scripts/prepare-marketplace.py
```

The last command checks the exact local HEAD snapshot and writes these ignored
local artifacts into `dist/`:

- `marketplace-update.md`: a populated update-request draft for that commit.
- `marketplace-title.txt`: the issue title.
- `release-notes.md`: release notes from that commit's changelog.
- `marketplace-preflight.json`: checked metadata, preview dimensions, target
  commit, and any working-tree changes excluded from the target snapshot.

The generator is offline. It does not run the regression suite, check remote
branch state, or claim marketplace approval. Commit any further desired changes
and regenerate the artifacts to avoid requesting review of an older snapshot.
An uncommitted or staged screenshot is excluded from the target commit until
you commit it; the report calls that out instead of silently including it.

## Runtime notes for reviewers

- The overlay runs in the Omarchy shell with normal user permissions.
- Discovery reads configured roots, type markers, task definitions, and Git
  status. It does not automatically launch detected tasks. Remote values are
  sanitized through stdin before scan JSON or external argv can contain them.
  Broader Git/configuration-dependent behavior is still under review.
- Persistent writes are confined to the plugin's usage/preferences files unless
  the user requests project creation, cloning, or task execution.
- Project config is read from `~/.config/omarchy/project-manager.json` and is not
  overwritten. Installation does not edit shell settings or keybindings.
- Editors, browser, file manager, terminal, and clipboard are launched through
  system commands. Dependencies are documented in the README; missing tools
  disable the corresponding action.
- Cloning and user-launched commands can access the network. Configured tasks
  are shell commands; package scripts run when the user chooses their task.
- Cancellation signals the process group created for the current managed task,
  without privileged process control or shared temporary PID files.
- No sudo or pkexec is required. There are no install hooks or bundled binaries.
- Removing the plugin leaves its config and state available for reinstallation.
- Native Wayland placement/focus still needs an interactive check. The automated
  smoke harness substitutes only the window host for headless testing.

## When the owner chooses to submit

Keep the existing listing ID, repository, category, and tags. Review the new
preview and the local draft, perform the native overlay check, then make the
chosen commit available on the public repository's default branch. That later
push is not part of preparation.

Verify that the full target SHA is still the current public default-branch HEAD
before using the existing-plugin verification form. Choose the newer-commit
update action, use the generated values, and personally review the acknowledgment
before checking it. The draft deliberately leaves that acknowledgment unchecked.
There is no request here to change the listing's installation mode.

The marketplace performs its own compatibility and security-baseline checks on
that exact commit and requires maintainer approval before promoting an update.
Local checks and the older listing's review do not replace those steps. Do not
open a second new-plugin submission for this already-listed ID.
