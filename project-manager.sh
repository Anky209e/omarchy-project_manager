#!/bin/bash

# Omarchy Project Manager helper.
#
# Scans configured root folders for git repositories, gathers git metadata for
# both discovered repos and explicitly configured projects, and reports which
# external commands are available. Emits a single JSON object on stdout:
#
#   { "projects": [ { "name", "path", "godot": bool, "types": [...],
#                     "tasks": [ {name,command,requires} ],
#                     "git": {branch,dirty,ahead,behind,remote}|null } ],
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
declare -A aliases=()

add_project() {
  local raw="$1" name="$2" path real
  path=$(expand "$raw")
  [[ -d $path ]] || return 0
  real=$(realpath -m -- "$path" 2>/dev/null) || return 0
  aliases[$real]=$(jq -cn --argjson existing "${aliases[$real]:-[]}" --arg path "$path" '$existing + [$path] | unique')
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
    [[ -d $d/.git || -f $d/.git || -f $d/project.godot ]] || continue
    add_project "$d" "$(basename "$d")"
  done < <(find "$root" -maxdepth "$depth" -type d "${prunable[@]}" -type d -print 2>/dev/null)
}

if ((${#roots[@]})); then
  for r in "${roots[@]}"; do
    discover_root "$r"
  done
fi

git_json() {
  local p="$1" out branch ahead behind dirty
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
  # A configured remote can contain credentials. Feed it only through stdin,
  # never argv or the environment, and expose only a public repository URL.
  # Downstream jq invocations and browser launchers receive the sanitized value.
  { git -C "$p" config --get remote.origin.url 2>/dev/null || true; } |
    jq -Rsc \
      --arg branch "${branch:-}" \
      --argjson dirty "$dirty" \
      --argjson ahead "${ahead:-0}" \
      --argjson behind "${behind:-0}" '
      def valid_host:
        test("^([A-Za-z0-9][A-Za-z0-9.-]*|\\[[0-9A-Fa-f:.]+\\])(:[0-9]+)?$");
      def public_remote:
        rtrimstr("\n")
        | if test("[\\x00-\\x20\\x7f\\\\]") then ""
          elif test("^(https?|ssh|git)://"; "i") then
            try (
              capture("^(?<scheme>https?|ssh|git)://(?<host>[^/?#]+)(?<path>/[^?#]*)([?#].*)?$"; "i")
              | .host = (.host | split("@") | last)
              | if (.host | valid_host) then
                  (if (.scheme | ascii_downcase) == "http" then "http://" else "https://" end)
                  + .host + .path
                else "" end
            ) catch ""
          elif contains("://") then ""
          else
            try (
              capture("^([^@/:]+@)?(?<host>\\[[0-9A-Fa-f:.]+\\]|[A-Za-z0-9][A-Za-z0-9.-]*):(?<path>[^?#]+)([?#].*)?$")
              | "https://" + .host + "/" + (.path | ltrimstr("/"))
            ) catch ""
          end;
      {branch:$branch, dirty:($dirty == 1), ahead:$ahead, behind:$behind,
       remote: (public_remote // "")}'
}

# ---------------------------------------------------- project type & tasks

has() { [[ -e "$1/$2" ]]; }

# Commands required by generated tasks; added to the availability scan so the
# overlay can grey out tasks whose tool is not installed.
declare -a NEEDED=()
declare -a TASK_OBJS=()

task() {
  TASK_OBJS+=("$(jq -cn --arg n "$1" --arg c "$2" --arg r "${3:-}" '{name:$n, command:$c, requires:$r}')")
  [[ -n ${3:-} ]] && NEEDED+=("$3")
}

detect_types() {
  local d="$1" out=()
  has "$d" project.godot && out+=(godot)
  has "$d" package.json && out+=(node)
  has "$d" Cargo.toml && out+=(rust)
  has "$d" go.mod && out+=(go)
  { has "$d" pyproject.toml || has "$d" uv.lock || has "$d" requirements.txt || has "$d" setup.py; } && out+=(python)
  { has "$d" flake.nix || has "$d" default.nix; } && out+=(nix)
  has "$d" CMakeLists.txt && out+=(cmake)
  has "$d" Gemfile && out+=(ruby)
  has "$d" composer.json && out+=(php)
  has "$d" Makefile && out+=(make)
  { has "$d" justfile || has "$d" Justfile || has "$d" .justfile; } && out+=(just)
  if ((${#out[@]})); then printf '%s\n' "${out[@]}" | jq -R . | jq -sc .; else printf '[]'; fi
}

node_tasks() {
  local d="$1" pm=npm scripts s quoted i=0
  has "$d" bun.lockb && pm=bun
  has "$d" pnpm-lock.yaml && pm=pnpm
  has "$d" yarn.lock && pm=yarn
  task "Install dependencies" "$pm install" "$pm"
  [[ -f $d/package.json ]] || return 0
  scripts=$(jq -r '.scripts // {} | keys[]' "$d/package.json" 2>/dev/null || true)
  [[ -n $scripts ]] || return 0
  local ordered=() prio="dev start build test lint format typecheck check serve watch preview"
  for s in $prio; do grep -qxF "$s" <<<"$scripts" && ordered+=("$s"); done
  while IFS= read -r s; do
    [[ -n $s ]] || continue
    [[ " ${ordered[*]:-} " == *" $s "* ]] && continue
    ordered+=("$s")
  done <<<"$scripts"
  for s in "${ordered[@]}"; do
    ((i >= 8)) && break
    printf -v quoted '%q' "$s"
    task "$pm run $s" "$pm run -- $quoted" "$pm"
    ((i++))
  done
}

make_tasks() {
  local d="$1" t i=0
  task "make (default)" "make" make
  while IFS= read -r t; do
    [[ -n $t ]] || continue
    ((i >= 6)) && break
    task "make $t" "make $t" make
    ((i++))
  done < <(grep -oE '^[a-zA-Z0-9][a-zA-Z0-9_.-]*:' "$d/Makefile" 2>/dev/null | sed 's/:$//' | sort -u)
}

just_tasks() {
  local d="$1" f t i=0
  for f in justfile Justfile .justfile; do [[ -f $d/$f ]] && break; done
  [[ -f ${d:-}/$f ]] || return 0
  while IFS= read -r t; do
    [[ -n $t ]] || continue
    ((i >= 8)) && break
    task "just $t" "just $t" just
    ((i++))
  done < <(awk '
    # Only parameterless recipe headers can run without prompting for arguments.
    # In particular, assignments (:=) and directives are not recipes.
    /^@?[a-zA-Z_][a-zA-Z0-9_-]*[[:blank:]]*:/ {
      if ($0 ~ /^[^:]*:=/) next
      sub(/^@/, "")
      sub(/[[:blank:]]*:.*/, "")
      print
    }
  ' "$d/$f" 2>/dev/null | sort -u)
}

detect_tasks() {
  local d="$1" t
  TASK_OBJS=()
  for t in $(detect_types "$d" | jq -r '.[]' 2>/dev/null); do
    case "$t" in
    node) node_tasks "$d" ;;
    make) make_tasks "$d" ;;
    just) just_tasks "$d" ;;
    rust)
      task "cargo build" "cargo build" cargo
      task "cargo run" "cargo run" cargo
      task "cargo test" "cargo test" cargo
      task "cargo clippy" "cargo clippy" cargo
      ;;
    go)
      task "go build" "go build ./..." go
      task "go run" "go run ." go
      task "go test" "go test ./..." go
      ;;
    python)
      if has "$d" uv.lock || has "$d" pyproject.toml; then task "uv run pytest" "uv run pytest" uv
      else task "pytest" "pytest" pytest; fi
      ;;
    nix)
      task "nix develop" "nix develop" nix
      task "nix build" "nix build" nix
      ;;
    cmake) task "CMake build" "cmake -S . -B build && cmake --build build" cmake ;;
    ruby) task "bundle install" "bundle install" bundle ;;
    php) task "composer install" "composer install" composer ;;
    esac
  done
  if ((${#TASK_OBJS[@]})); then printf '%s\n' "${TASK_OBJS[@]}" | jq -s .; else printf '[]'; fi
}

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT

while IFS= read -r real; do
  [[ -n $real ]] || continue
  git=$(git_json "$real")
  godot=false
  [[ -f $real/project.godot ]] && godot=true
  types=$(detect_types "$real")
  tasks=$(detect_tasks "$real")
  while IFS= read -r required; do
    [[ -n $required ]] && NEEDED+=("$required")
  done < <(jq -r '.[].requires | select(length > 0)' <<<"$tasks")
  jq -cn --arg name "${names[$real]}" --arg path "$real" --argjson git "$git" --argjson godot "$godot" \
    --argjson types "$types" --argjson tasks "$tasks" --argjson aliases "${aliases[$real]:-[]}" \
    '{name:$name, path:$path, aliases:$aliases, git:$git, godot:$godot, types:$types, tasks:$tasks}' >>"$tmp"
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

for c in "${editors[@]:-}" setsid uwsm-app git lazygit wl-copy xdg-open xdg-terminal-exec tmux omarchy-launch-browser "${NEEDED[@]:-}"; do
  [[ -n $c ]] || continue
  add_avail "$c"
done

if ((${#avail[@]})); then
  avail_json=$(printf '%s\n' "${avail[@]}" | jq -R . | jq -s .)
else
  avail_json='[]'
fi

jq -s --argjson available "$avail_json" \
  '{projects: ., availableCommands: $available}' "$tmp"
