# Security review status

The external-dependency review is incomplete. Passing local tests or generating
a marketplace draft does not close it or establish marketplace approval.

## Addressed: remote credentials during automatic scanning

Reported snapshot: `91860438bd232988c96fa759c11deaea4316b1be`.

That snapshot reads `remote.origin.url` from Git configuration, then puts the
raw value in `jq --arg remote`. An HTTPS username/password or token can therefore
appear in an external process's argv. It also persists through the JSON sent to
later jq processes and can reach a browser launcher.

The fix sends the raw remote from `git config` directly to jq over stdin. Before
emitting any scan JSON, jq removes URL user information, query strings, and
fragments, validates the host, and converts supported SSH/SCP/git forms to a
public HTTP(S) repository link. Unsupported/malformed forms produce an empty
link. The Git configuration itself is not changed. JavaScript repeats this
sanitization when parsing legacy scan data and constructing browser URLs.

Tests use synthetic credentials in temporary repositories. They instrument
scanner dependencies before exec and check that credentials do not appear in
child argv, child environments, or scan JSON. Additional cases cover encoded
user information, SSH/SCP remotes, IPv6, ports, missing remotes, and malformed or
unsupported values. Browser command construction is checked independently.
These tests do not constitute a cross-account procfs access test.

## Dependency inventory and remaining scope

| Path | Dependencies / behavior | Review status |
| --- | --- | --- |
| Automatic discovery | Bash; GNU findutils/coreutils; grep, sed, awk; jq; Git `rev-parse`, `status`, and `config` | Credential propagation fixed and tested; broader review incomplete |
| Project metadata parsing | jq reads package scripts; grep/awk read Make/Just headers | Shell quoting has regression coverage; parser/resource-limit review incomplete |
| UI and persistence | Omarchy/Quickshell/Qt; FileView reads config and writes usage/preferences | Headless behavior tested; dependency and native compositor review incomplete |
| Explicit launch actions | `uwsm-app`, `xdg-terminal-exec`, `xdg-open`, Omarchy editor/browser launchers, `wl-copy`, optional editors/lazygit | Command construction tested in part; external wrapper review incomplete |
| Managed tasks | Bash, `setsid`, `kill`, `sleep`, and the user's chosen task tools | Process group cancellation tested; broader lifecycle/dependency review incomplete |
| Clone/create | Git and Bash commands requested by the user | Broader URL, transport, and tool-configuration review incomplete |

The Git review still needs to cover configuration-controlled behavior of
`git status`, including filesystem monitors and filters, and inherited process
configuration. The helper resolution/startup review still needs to cover PATH
and shell startup behavior. This patch does not pin, vendor, or audit those
system dependencies.

Explicit clone URLs and arbitrary task/editor arguments are still passed to
subprocesses as configured. Secrets deliberately supplied in those commands are
outside the automatic-scan fix. Prefer Git credential helpers rather than
embedding secrets in clone URLs. Do not describe the whole plugin as having
completed a security or dependency review on the basis of this patch.
