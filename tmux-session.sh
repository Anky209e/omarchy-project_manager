#!/bin/bash
# Open a project's tmux session: create it if needed, focus the terminal window
# that already shows it (Hyprland), or open a new terminal attached to it.
# The optional START_COMMAND (e.g. a shell alias that builds a pane layout) is
# typed into the first pane only when the session is created, never when it exists.
set -uo pipefail
[[ $# == 2 || $# == 3 ]] || { printf 'Usage: tmux-session.sh SESSION DIRECTORY [START_COMMAND]\n' >&2; exit 2; }
name=$1
dir=$2
start_command=${3:-}
command -v tmux >/dev/null 2>&1 || { printf 'tmux is not installed\n' >&2; exit 1; }

if ! tmux has-session -t "=$name" 2>/dev/null; then
  tmux new-session -ds "$name" -c "$dir" || exit 1
  if [[ -n $start_command ]]; then
    tmux send-keys -t "=$name:" -l -- "$start_command"
    tmux send-keys -t "=$name:" C-m
  fi
fi
# Typing `exit` in the session should end it and close its terminal, even when
# tmux is configured with detach-on-destroy off (which jumps to another session).
tmux set-option -t "=$name:" detach-on-destroy on

# Walk up from each tmux client attached to the session until a process owns a
# Hyprland window, then focus that window. Returns 1 when there is none.
focus_existing() {
  command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 1
  local windows pid address
  windows=$(hyprctl clients -j 2>/dev/null) || return 1
  while IFS= read -r pid; do
    while [[ -n $pid && $pid -gt 1 ]]; do
      address=$(jq -r --argjson p "$pid" 'first(.[] | select(.pid == $p) | .address) // empty' <<<"$windows")
      if [[ -n $address ]]; then
        # Hyprland may hand focus back to the previous window while the overlay
        # closes; keep trying until the target window is active.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null 2>&1 ||
            hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1
          sleep 0.1
          [[ $(hyprctl activewindow -j 2>/dev/null | jq -r '.address') == "$address" ]] && break
        done
        return 0
      fi
      pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
  done < <(tmux list-clients -t "=$name" -F '#{client_pid}' 2>/dev/null)
  return 1
}

focus_existing && exit 0
exec setsid uwsm-app -- xdg-terminal-exec --dir="$dir" -e tmux attach-session -t "=$name"
