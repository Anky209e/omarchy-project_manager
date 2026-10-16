#!/bin/bash
# Own a task's process group so cancellation also reaches child processes.
set -uo pipefail
child=""
cancelled=0
cancel_task() {
  cancelled=1
  [[ -n $child ]] || return
  trap '' TERM INT HUP
  kill -TERM -- "-$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null || true
  # Give commands a moment to clean up, then stop stubborn descendants too.
  sleep 1
  kill -KILL -- "-$child" 2>/dev/null || true
  wait "$child" 2>/dev/null || true
  exit 130
}
trap cancel_task TERM INT HUP
[[ $# == 2 ]] || { printf 'Usage: task-runner.sh DIRECTORY COMMAND\n' >&2; exit 2; }
cd -- "$1" || exit 1
setsid bash -lc "$2" < /dev/null &
child=$!
((cancelled)) && cancel_task
wait "$child"
exit $?
