#!/usr/bin/env bash
# Tests scripts/watch.sh against throwaway git worktrees.
# Scenarios run in parallel, so the ones that wait out the 1-minute thresholds
# overlap; exits 1 if any check fails. Needs GNU touch (-d @epoch).
set -u
here=$(cd "$(dirname "$0")" && pwd)
watch="$here/../skills/fixing-bugs-duo/scripts/watch.sh"
root=$(mktemp -d)
scenarios="not_git events stall idle running edits slow_repeat slow_step slow_turn"

pass() { echo "PASS $scen $*"; }
fail() { echo "FAIL $scen $*"; }
# usage: check <message> <command...>
check() {
  local msg="$1"
  shift
  if "$@"; then pass "$msg"; else fail "$msg"; fi
}

new_worktree() {
  main="$root/$scen/main"
  wt="$root/$scen/wt"
  mkdir -p "$main"
  git -C "$main" init -q
  git -C "$main" config user.name duo-test
  git -C "$main" config user.email duo-test@localhost
  git -C "$main" config commit.gpgsign false
  git -C "$main" config core.autocrlf false
  echo a > "$main/a.txt"
  git -C "$main" add a.txt
  git -C "$main" commit -q -m init
  git -C "$main" worktree add -q -b fix/x "$wt" 2>/dev/null
  git_dir=$(git -C "$wt" rev-parse --absolute-git-dir)
  duo="$git_dir/duo"
  mkdir -p "$duo/logs"
}

# usage: new_commit <subject> [trailer]; prints the new sha
new_commit() {
  if [ -n "${2:-}" ]; then
    git -C "$wt" commit -q --allow-empty -m "$1" -m "$2"
  else
    git -C "$wt" commit -q --allow-empty -m "$1"
  fi
  git -C "$wt" rev-parse HEAD
}

# Last line decides whether B is idle, as in a Cursor subagent transcript.
new_transcript() {
  transcript="$root/$scen/transcript.jsonl"
  echo '{"role":"user","message":{"content":[{"type":"text","text":"go"}]}}' > "$transcript"
  if [ "$1" = idle ]; then echo '{"type":"turn_ended","status":"success"}' >> "$transcript"; fi
}

# usage: set_age <minutes> <file...>
set_age() {
  local ts f
  ts=$(($(date +%s) - $1 * 60))
  shift
  for f in "$@"; do
    if [ -e "$f" ]; then touch -d "@$ts" "$f"; fi
  done
}

# Make every file the watcher counts as a sign of life look 10 minutes old.
set_quiet() {
  set_age 10 "$git_dir/index" "$git_dir/HEAD" "$git_dir/logs/HEAD"
  find "$duo" -type f | while IFS= read -r f; do set_age 10 "$f"; done
}

# usage: start_watch [VAR=value...]; uses $transcript when set
start_watch() {
  out="$root/$scen.watch.out"
  t0=$(date +%s)
  env DUO_POLL_SECONDS=1 "$@" bash "$watch" "$wt" t ${transcript:+"$transcript"} > "$out" 2>&1 &
  watcher=$!
}

elapsed() { echo $(($(date +%s) - t0)); }
gone() { ! kill -0 "$1" 2>/dev/null; }
# usage: within <value> <min> <max>; true when min <= value < max
within() { [ "$1" -ge "$2" ] && [ "$1" -lt "$3" ]; }

wakes() { sed -n 's/^DUO_WAKE_t [0-9]* //p' "$out" 2>/dev/null; }
wake_count() { wakes | grep -c .; }

# usage: wait_line <regex> <seconds>; on success sets $at to seconds since start_watch
wait_line() {
  local limit=$(($(date +%s) + $2))
  while [ "$(date +%s)" -lt "$limit" ]; do
    if grep -Eq -- "$1" "$out" 2>/dev/null; then
      at=$(elapsed)
      return 0
    fi
    sleep 0.5
  done
  at=-1
  return 1
}

wait_ready() {
  wait_line '^DUO_(READY|ERROR)_t ' 30
  ready=$(grep -E -m 1 '^DUO_(READY|ERROR)_t ' "$out")
  check "watcher ready: $ready" grep -q '^DUO_READY_t ' "$out"
}

scen_not_git() {
  local dir="$root/not_git/dir" no_duo="$root/not_git/no_duo" got code got2 code2
  mkdir -p "$dir" "$no_duo"
  got=$(bash "$watch" "$dir" t 2>&1)
  code=$?
  check "error line: $got" grep -q '^DUO_ERROR_t not a git worktree' <<< "$got"
  check "exit code 1 (got $code)" [ "$code" = 1 ]
  git -C "$no_duo" init -q
  got2=$(bash "$watch" "$no_duo" t 2>&1)
  code2=$?
  check "missing duo error line: $got2" grep -q '^DUO_ERROR_t duo directory missing:' <<< "$got2"
  check "missing duo exit code 1 (got $code2)" [ "$code2" = 1 ]
}

scen_events() {
  local h0 s1 s2 quiet_from
  new_worktree
  h0=$(git -C "$wt" rev-parse HEAD)
  start_watch DUO_WATCH_STATUS=1 DUO_HEARTBEAT_MINUTES=1 DUO_STALL_MINUTES=1 DUO_STEP_MINUTES=1
  wait_ready
  check 'ready line reports head, requests and no transcript' grep -q " head=$h0 requests=0 transcript=False " <<< "$ready"
  new_commit wip $'Flow: wip\nFlow: anchored-adapt A-1' > /dev/null
  sleep 4
  check 'Flow: wip + anchored-adapt commit does not wake' [ "$(wake_count)" = 0 ]
  s1=$(new_commit s1 $'Flow: step S1\nFlow: anchored-adapt A-1')
  check 'Flow: step + anchored-adapt commit wakes' wait_line "^DUO_WAKE_t 1 commit $s1\$" 15
  s2=$(new_commit 'no trailer')
  check 'commit without Flow trailer wakes' wait_line "^DUO_WAKE_t 2 commit $s2\$" 15
  printf 'STATUS: S0-DONE\n\n### R-1 question\n' > "$duo/progress.md"
  check 'new ### R- heading wakes' wait_line '^DUO_WAKE_t 3 request 1$' 15
  check 'STATUS: change wakes with DUO_WATCH_STATUS=1' wait_line '^DUO_WAKE_t 4 status STATUS: S0-DONE$' 15
  quiet_from=$(elapsed)
  wait_line '^DUO_WAKE_t 5 heartbeat$' 100 || at=-100
  check "heartbeat after a quiet minute (after $((at - quiet_from))s)" [ $((at - quiet_from)) -ge 50 ]
  check 'no stall without a transcript' [ "$(wakes | grep -c '^stall$')" = 0 ]
  check 'no slow without a transcript' [ "$(wakes | grep -c '^slow ')" = 0 ]
  git -C "$main" worktree remove --force "$wt"
  check 'DUO_EXIT when the worktree is removed' wait_line '^DUO_EXIT_t worktree removed$' 20
  sleep 2
  check 'watcher exits after DUO_EXIT' gone "$watcher"
}

scen_stall() {
  new_worktree
  new_transcript active
  start_watch DUO_STALL_MINUTES=1 DUO_HEARTBEAT_MINUTES=1
  wait_ready
  check 'ready line reports the transcript' grep -q ' transcript=True ' <<< "$ready"
  set_quiet
  wait_line '^DUO_WAKE_t [0-9]+ stall$' 100
  check "stall after a silent minute (at ${at}s)" [ "$at" -ge 55 ]
  sleep 5
  check "one stall, no heartbeat with a transcript: $(wakes | tr '\n' ',')" [ "$(wake_count)" = 1 ]
}

scen_idle() {
  new_worktree
  new_transcript idle
  start_watch DUO_STALL_MINUTES=1 DUO_HEARTBEAT_MINUTES=1 DUO_STEP_MINUTES=1
  wait_ready
  check 'ready line reports initial idle state' grep -q ' transcript=True idle=True ' <<< "$ready"
  set_quiet
  sleep 80
  check "no wake while the transcript ends with turn_ended: $(wakes | tr '\n' ',')" [ "$(wake_count)" = 0 ]
}

scen_running() {
  new_worktree
  new_transcript active
  printf '30\nslow test suite\n' > "$duo/running"
  start_watch DUO_STALL_MINUTES=1
  wait_ready
  set_quiet
  set_age 5 "$duo/running"
  sleep 80
  check "no stall while a running marker is within its expected minutes: $(wakes | tr '\n' ',')" [ "$(wake_count)" = 0 ]
}

scen_edits() {
  local i
  new_worktree
  new_transcript active
  start_watch DUO_STALL_MINUTES=1
  wait_ready
  set_quiet
  for i in 1 2 3 4 5 6; do
    echo "edit $i" > "$wt/a.txt"
    sleep 15
  done
  check "no stall while B edits tracked files: $(wakes | tr '\n' ',')" [ "$(wake_count)" = 0 ]
}

scen_slow_repeat() {
  local first
  new_worktree
  new_transcript active
  printf '30\nslow test suite\n' > "$duo/running"
  start_watch DUO_STEP_MINUTES=1
  wait_ready
  sleep 30
  new_commit wip 'Flow: wip' > /dev/null
  wait_line '^DUO_WAKE_t 1 slow 1$' 90
  first=$at
  check "slow 1 a minute after start, despite a running marker and a wip commit (at ${first}s)" within "$first" 55 85
  wait_line '^DUO_WAKE_t 2 slow 2$' 90
  check "slow 2 one more minute later (at ${at}s)" within "$at" 115 145
}

scen_slow_step() {
  local s1 committed
  new_worktree
  new_transcript active
  start_watch DUO_STEP_MINUTES=1
  wait_ready
  check 'slow 1 before the step commit' wait_line '^DUO_WAKE_t 1 slow 1$' 90
  s1=$(new_commit s1 'Flow: step S1')
  committed=$(elapsed)
  check 'Flow: step commit wakes' wait_line "^DUO_WAKE_t 2 commit $s1\$" 15
  wait_line '^DUO_WAKE_t 3 slow 1$' 100 || at=-1000
  check "a Flow: step commit restarts the timer and its minutes (slow 1 $((at - committed))s after it): $(wakes | tr '\n' ',')" within $((at - committed)) 55 85
}

scen_slow_turn() {
  local resumed
  new_worktree
  new_transcript active
  start_watch DUO_STEP_MINUTES=1
  wait_ready
  check 'slow 1 during the first turn' wait_line '^DUO_WAKE_t 1 slow 1$' 90
  echo '{"type":"turn_ended","status":"success"}' >> "$transcript"
  check 'turn_ended wakes with idle' wait_line '^DUO_WAKE_t 2 idle$' 15
  sleep 70
  check "no slow while B is idle: $(wakes | tr '\n' ',')" [ "$(wake_count)" = 2 ]
  echo '{"role":"user","message":{"content":[{"type":"text","text":"next"}]}}' >> "$transcript"
  resumed=$(elapsed)
  wait_line '^DUO_WAKE_t 3 slow 1$' 100 || at=-1000
  check "a new turn restarts the timer and its minutes (slow 1 $((at - resumed))s after it): $(wakes | tr '\n' ',')" within $((at - resumed)) 55 85
}

run_scenario() {
  scen="$1"
  transcript=""
  watcher=""
  trap '[ -n "$watcher" ] && kill "$watcher" 2>/dev/null' EXIT
  "scen_$scen"
  echo "DONE $scen"
}

echo "bash $BASH_VERSION, $(git --version)"
for s in $scenarios; do
  (run_scenario "$s") > "$root/$s.log" 2>&1 &
done
wait

failed=0
for s in $scenarios; do
  cat "$root/$s.log"
  n=$(grep -c '^FAIL ' "$root/$s.log")
  failed=$((failed + n))
  if ! grep -qx "DONE $s" "$root/$s.log"; then
    echo "FAIL $s did not finish"
    failed=$((failed + 1))
  fi
done
rm -rf "$root"
if [ "$failed" -gt 0 ]; then
  echo "$failed check(s) failed"
  exit 1
fi
echo 'all checks passed'
