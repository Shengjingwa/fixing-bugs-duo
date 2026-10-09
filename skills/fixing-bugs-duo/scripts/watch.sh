#!/usr/bin/env bash
# usage: watch.sh <worktree> <tag> [transcript]
# env:   DUO_POLL_SECONDS (15)  DUO_HEARTBEAT_MINUTES (20)  DUO_STALL_MINUTES (10)  DUO_WATCH_STATUS (0|1)
# On Windows use watch.ps1: stopping Git for Windows' bash.exe launcher leaves this script running.
wt="$1"
tag="$2"
transcript="${3:-}"
poll="${DUO_POLL_SECONDS:-15}"
beat_min="${DUO_HEARTBEAT_MINUTES:-20}"
stall_min="${DUO_STALL_MINUTES:-10}"
watch_status="${DUO_WATCH_STATUS:-0}"

git_dir=$(git --no-optional-locks -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || {
  echo "DUO_ERROR_${tag} not a git worktree: $wt"
  exit 1
}
duo="$git_dir/duo"
progress="$duo/progress.md"
running="$duo/running"
seq=0
last=$(date +%s)

wake() {
  seq=$((seq + 1))
  echo "DUO_WAKE_${tag} ${seq} $*"
  last=$(date +%s)
}

head_of() { git --no-optional-locks -C "$wt" rev-parse HEAD 2>/dev/null; }

# Wake only for commits A must look at now: Flow: step / fix, or no Flow trailer.
# wip, docs and anchored-adapt-only commits are picked up on the next wake.
needs_review() {
  local shas sha flows
  shas=$(git --no-optional-locks -C "$wt" rev-list "$1..$2" 2>/dev/null) || return 0
  for sha in $shas; do
    flows=$(git --no-optional-locks -C "$wt" log -1 --format=%B "$sha" 2>/dev/null | sed -n 's/^Flow:[[:space:]]*\([^[:space:]]*\).*/\1/p')
    if [ -z "$flows" ] || printf '%s\n' "$flows" | grep -Eqx 'step|fix'; then
      return 0
    fi
  done
  return 1
}

requests_of() {
  if [ -f "$progress" ]; then grep -c '^### R-' "$progress"; else echo 0; fi
  return 0
}

status_of() {
  [ -f "$progress" ] && grep -m 1 '^STATUS:' "$progress" | tr -d '\r'
  return 0
}

transcript_len() {
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then wc -c < "$transcript" | tr -d ' '; else echo -1; fi
}

transcript_idle() {
  tail -n 1 "$transcript" 2>/dev/null | grep -Eq '"type"[[:space:]]*:[[:space:]]*"turn_ended"'
}

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

recent() { [ -e "$1" ] && [ -n "$(find "$1" -maxdepth 0 -mmin "-$stall_min" 2>/dev/null)" ]; }

# Cursor writes a subagent transcript only when its turn ends, so a silent
# transcript proves nothing. Signs of life are the files B touches: a long
# command announced in duo/running (first line: expected minutes), anything
# else under duo/, and this worktree's index, HEAD and HEAD reflog.
other_activity() {
  local now="$1" expected age p
  if [ -f "$running" ]; then
    expected=$(head -n 1 "$running" | grep -Eo '^[[:space:]]*[0-9]+' | tr -d '[:space:]')
    expected=${expected:-30}
    age=$((now - $(mtime "$running")))
    [ "$age" -lt $(((expected + stall_min) * 60)) ] && return 0
  fi
  if [ -d "$duo" ] && [ -n "$(find "$duo" -type f -mmin "-$stall_min" 2>/dev/null | head -n 1)" ]; then
    return 0
  fi
  for p in index HEAD logs/HEAD; do
    recent "$git_dir/$p" && return 0
  done
  return 1
}

# Costlier check, run only before reporting a stall: files B is editing.
worktree_edits() {
  local rel
  while IFS= read -r rel; do
    rel=${rel#???}
    rel=${rel##* -> }
    rel=${rel#\"}
    rel=${rel%\"}
    recent "$wt/$rel" && return 0
  done < <(git --no-optional-locks -C "$wt" status --porcelain -uall 2>/dev/null)
  return 1
}

head=$(head_of)
requests=$(requests_of)
status=$(status_of)
tlen=$(transcript_len)
active_at=$last
stall_reported=0
echo "DUO_READY_${tag} pid=$$ head=${head} requests=${requests} transcript=$([ "$tlen" != -1 ] && echo True || echo False) duo=${duo}"

while true; do
  sleep "$poll"
  now=$(date +%s)
  if [ ! -d "$git_dir" ]; then
    echo "DUO_EXIT_${tag} worktree removed"
    exit 0
  fi

  h=$(head_of)
  if [ -n "$h" ] && [ "$h" != "$head" ]; then
    if [ -z "$head" ] || needs_review "$head" "$h"; then
      wake "commit ${h}"
    fi
    head=$h
  fi

  r=$(requests_of)
  if [ "$r" != "$requests" ]; then
    requests=$r
    wake "request ${r}"
  fi

  if [ "$watch_status" = 1 ]; then
    s=$(status_of)
    if [ "$s" != "$status" ]; then
      status=$s
      [ -n "$s" ] && wake "status ${s}"
    fi
  fi

  idle=0
  t=$(transcript_len)
  if [ "$t" != -1 ]; then
    transcript_idle && idle=1
    if [ "$t" != "$tlen" ] || other_activity "$now"; then
      tlen=$t
      active_at=$now
      stall_reported=0
    elif [ "$idle" = 0 ] && [ "$stall_reported" = 0 ] && [ $((now - active_at)) -ge $((stall_min * 60)) ]; then
      if worktree_edits; then
        active_at=$now
      else
        stall_reported=1
        wake stall
      fi
    fi
  fi

  if [ "$idle" = 1 ]; then
    last=$now
  elif [ $((now - last)) -ge $((beat_min * 60)) ]; then
    wake heartbeat
  fi
done
