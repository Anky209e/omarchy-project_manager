#!/bin/bash

# Omarchy Project Manager helper.
#
# Scans configured root folders for git repositories, gathers git metadata for
# both discovered repos and explicitly configured projects, and reports which
# external commands are available. Emits a single JSON object on stdout:
#
#   { "projects": [ { "name", "path", "godot": bool, "git": {branch,dirty,ahead,behind,remote}|null } ],
#     "availableCommands": [ ... ] }
#
# usage:
#   project-manager.sh scan [--depth N] [--exclude a,b,c] \
#     [--root DIR]... [--editor-command CMD]... [-- PROJECT_PATH...]

set -uo pipefail

depth=3
exclude_csv="node_modules,.git,.venv,venv,__pycache__,dist,build,target,vendor,.cache,.next,.turbo,coverage"
roots=()
editors=()
explicit=()

while (($#)); do
  case "$1" in
  --depth)
    depth="${2:-3}"
    shift 2
    ;;
  --exclude)
    exclude_csv="${2:-}"
    shift 2
    ;;
  --root)
    roots+=("${2:-}")
    shift 2
    ;;
  --editor-command)
    editors+=("${2:-}")
    shift 2
    ;;
  --)
    shift
    explicit=("$@")
    break
    ;;
  *) shift ;;
  esac
done

# A non-numeric depth would make `find` bail; fall back to the default.
[[ $depth =~ ^[0-9]+$ ]] || depth=3

expand() {
  local p="${1:-}"
  p="${p/#\~/$HOME}"
  printf '%s\n' "$p"
}

declare -A seen=()
declare -A names=()

add_project() {
  local raw="$1" name="$2" path real
  path=$(expand "$raw")
  [[ -d $path ]] || return 0
  real=$(realpath -m -- "$path" 2>/dev/null) || return 0
  [[ -n ${seen[$real]:-} ]] && return 0
  seen[$real]=1
  names[$real]="$name"
}

# Explicitly configured projects come first so their metadata (attached in
# QML by path) always maps onto a scanned entry, even when discovery is off.
for p in "${explicit[@]:-}"; do
  [[ -n $p ]] || continue
  add_project "$p" "$(basename "$(expand "$p")")"
done

IFS=',' read -r -a excludes <<<"$exclude_csv"

discover_root() {
  local root
  root=$(expand "${1:-}")
  [[ -d $root ]] || return 0

  local -a prunable=('(')
  local e added=0
  for e in "${excludes[@]}"; do
    e="${e#"${e%%[![:space:]]*}"}"
    e="${e%"${e##*[![:space:]]}"}"
    [[ -n $e ]] || continue
    prunable+=(-name "$e" -o)
    added=1
  done

  if ((added)); then
    local last=$((${#prunable[@]} - 1))
    unset "prunable[$last]"
    prunable+=(')' -prune -o)
  else
    prunable=()
  fi

  local d
  while IFS= read -r d; do
    [[ -d $d/.git || -f $d/project.godot ]] || continue
    add_project "$d" "$(basename "$d")"
  done < <(find "$root" -maxdepth "$depth" -type d "${prunable[@]}" -type d -print 2>/dev/null)
}

if ((${#roots[@]})); then
  for r in "${roots[@]}"; do
    discover_root "$r"
  done
fi

git_json() {
  local p="$1" out branch ahead behind dirty remote
  if ! git -C "$p" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'null'
    return 0
  fi

  out=$(git -C "$p" status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null || true)
  branch=$(sed -n 's/^# branch.head //p' <<<"$out" | head -n1)
  ahead=$(sed -n 's/^# branch.ab +\([0-9]*\) -.*/\1/p' <<<"$out" | head -n1)
  behind=$(sed -n 's/^# branch.ab .*-\([0-9]*\)$/\1/p' <<<"$out" | head -n1)
  dirty=0
  grep -qv '^#' <<<"$out" && dirty=1
  remote=$(git -C "$p" config --get remote.origin.url 2>/dev/null || true)

  jq -cn \
    --arg branch "${branch:-}" \
    --argjson dirty "$dirty" \
    --argjson ahead "${ahead:-0}" \
    --argjson behind "${behind:-0}" \
    --arg remote "${remote:-}" \
    '{branch:$branch, dirty:($dirty == 1), ahead:$ahead, behind:$behind, remote:$remote}'
}

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT

while IFS= read -r real; do
  [[ -n $real ]] || continue
  git=$(git_json "$real")
  godot=false
  [[ -f $real/project.godot ]] && godot=true
  jq -cn --arg name "${names[$real]}" --arg path "$real" --argjson git "$git" --argjson godot "$godot" \
    '{name:$name, path:$path, git:$git, godot:$godot}' >>"$tmp"
done < <(printf '%s\n' "${!seen[@]}" | sort)

avail=()
add_avail() {
  local c="${1:-}" base
  [[ -n $c ]] || return 0
  if [[ $c == */* ]]; then
    [[ -x $c ]] || return 0
  else
    command -v "$c" >/dev/null 2>&1 || return 0
  fi
  for existing in "${avail[@]:-}"; do
    [[ $existing == "$c" ]] && return 0
  done
  avail+=("$c")
}

for c in "${editors[@]:-}" git wl-copy xdg-open xdg-terminal-exec omarchy-launch-browser; do
  add_avail "$c"
done

if ((${#avail[@]})); then
  avail_json=$(printf '%s\n' "${avail[@]}" | jq -R . | jq -s .)
else
  avail_json='[]'
fi

jq -s --argjson available "$avail_json" \
  '{projects: ., availableCommands: $available}' "$tmp"
