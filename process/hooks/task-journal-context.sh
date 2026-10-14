#!/usr/bin/env bash
# task-journal-context.sh — puts a task's journal back into a session that lost it.
#
# A SessionStart hook for Claude Code. Copy it into the product repository (e.g.
# scripts/task-journal-context.sh, versioned) and register it in the shared .claude/settings.json:
#
#   "hooks": {
#     "SessionStart": [
#       { "matcher": "startup|clear|compact",
#         "hooks": [ { "type": "command",
#                      "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/task-journal-context.sh\"" } ] }
#     ]
#   }
#
# The task command keeps a journal in the task's worktree, at .task/journal.md (ignored by git;
# format in task-command.md, "Task journal and hand-offs"). When a session starts, is cleared or
# is compacted inside that worktree, this hook prints the journal's header, its last lines and the
# next step the last line names — Claude Code adds a SessionStart hook's output to the session's
# context.
#
# Anywhere else it prints nothing: outside a git repository, in a repository with no journal, or
# in the main checkout (tasks don't run there). It always exits 0 — a broken hook must never stop
# a session from starting — except --self-test, which exits 1 when a case fails.
#
# What it does NOT do: decide anything. The journal is a memory aid, not evidence. The output
# says so, and the task command checks every line against `git log` and the Issue's labels before
# acting on it; where they disagree, they win.
#
#   task-journal-context.sh                 # as the hook: reads the current directory
#   task-journal-context.sh --dir <path>    # the same, for another directory
#   task-journal-context.sh --self-test     # built-in cases

LINES_SHOWN=8

context() {
  local dir="$1" top common gitdir journal header last next
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  journal="$top/.task/journal.md"
  [ -f "$journal" ] || return 0
  # A linked worktree has its own git dir; the main checkout's git dir is the common one.
  gitdir="$(cd "$dir" && cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)" || return 0
  common="$(cd "$dir" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)" || return 0
  [ "$gitdir" != "$common" ] || return 0

  header="$(head -n 1 "$journal" | tr -d '\r')"
  last="$(grep -v '^#' "$journal" | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 1)"
  next="$(printf '%s\n' "$last" | awk -F' [|] ' 'NF >= 7 { sub(/^next:[[:space:]]*/, "", $7); print $7 }')"

  echo "Task journal — $journal"
  echo "$header"
  echo "Last entries (newest last):"
  grep -v '^#' "$journal" | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n "$LINES_SHOWN" | sed 's/^/  /'
  if [ -n "$next" ]; then
    echo "Next step named by the journal: $next"
  else
    echo "Next step: the last line doesn't name one — read the task command's resume rules."
  fi
  echo "This journal is a memory aid, not evidence. Before acting on it, check it against"
  echo "\`git log\` on this branch and the Issue's labels; where they disagree, they win."
}

self_test() {
  local self root failures=0 total=0 out
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  root="$(mktemp -d)"

  # expect <name> <dir> <must contain, or "" for empty output> [<must not contain>]
  expect() {
    local name="$1" dir="$2" must="$3" mustnot="${4:-}" code
    total=$((total + 1))
    out="$(bash "$self" --dir "$dir" < /dev/null 2>&1)"; code=$?
    if [ "$code" -ne 0 ]; then
      echo "FAIL $name — exit $code: $out"; failures=$((failures + 1))
    elif [ -z "$must" ] && [ -n "$out" ]; then
      echo "FAIL $name — expected no output: $out"; failures=$((failures + 1))
    elif [ -n "$must" ] && [[ "$out" != *"$must"* ]]; then
      echo "FAIL $name — output lacks '$must': $out"; failures=$((failures + 1))
    elif [ -n "$mustnot" ] && [[ "$out" == *"$mustnot"* ]]; then
      echo "FAIL $name — output has '$mustnot': $out"; failures=$((failures + 1))
    else
      echo "ok   $name"
    fi
  }

  mkdir -p "$root/plain" "$root/main"
  ( cd "$root/main" && git init -q && git config user.email t@t && git config user.name t &&
    git commit -q --allow-empty -m base && git worktree add -q "$root/wt" -b task 2>/dev/null )
  local J="$root/wt/.task/journal.md"
  mkdir -p "$root/wt/.task" "$root/wt/src/deep"

  expect "not a git repository prints nothing"      "$root/plain" ""
  expect "worktree without a journal prints nothing" "$root/wt"   ""

  printf '# Task #123 — B1-07 — branch task — started 2026-10-14T10:02Z\n' > "$J"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    printf '2026-10-14T10:%02dZ | analysis | step %d | analyst | READY FOR GATE 1 | - | next: step %d\n' "$i" "$i" "$((i + 1))" >> "$J"
  done
  expect "journal present: header shown"            "$root/wt"   "# Task #123 — B1-07"
  expect "journal present: next step from last line" "$root/wt"  "Next step named by the journal: step 11"
  expect "only the last lines are shown"            "$root/wt"   "step 10 |" "step 2 |"
  expect "found from a subdirectory"                "$root/wt/src/deep" "step 11"
  expect "the evidence warning is always there"     "$root/wt"   "they win"

  printf '2026-10-14T11:00Z | code | step 7 | developer | stopped\r\n' >> "$J"
  expect "a last line without a next field says so" "$root/wt"   "doesn't name one"

  mkdir -p "$root/main/.task" && cp "$J" "$root/main/.task/journal.md"
  expect "main checkout prints nothing"             "$root/main" ""

  total=$((total + 1))
  if bash "$self" --dir "$root/nonexistent" < /dev/null >/dev/null 2>&1; then
    echo "ok   a missing directory still exits 0"
  else
    echo "FAIL a missing directory still exits 0"; failures=$((failures + 1))
  fi

  ( cd "$root/main" && git worktree remove --force "$root/wt" ) >/dev/null 2>&1
  rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  --dir) cat > /dev/null 2>&1 || true; context "${2:-.}" || true ;;
  *) cat > /dev/null 2>&1 || true; context "$PWD" || true ;;
esac
exit 0
