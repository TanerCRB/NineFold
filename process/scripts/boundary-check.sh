#!/usr/bin/env bash
# boundary-check.sh — did a role call change anything outside the paths it may write?
#
# Copy into the product repository (e.g. scripts/boundary-check.sh) and run it from the task's
# worktree around every call of a role that may write (Architect, QA), and of any role invoked
# through a general-purpose mechanism that doesn't enforce its `tools` field:
#
#   scripts/boundary-check.sh snapshot "$T/state"               # immediately BEFORE the call
#   ... role call ...
#   scripts/boundary-check.sh verify "$T/state" tests/          # immediately AFTER; allowed prefixes
#   scripts/boundary-check.sh verify "$T/state" --none          # a read-only role: nothing may change
#   scripts/boundary-check.sh --self-test                       # built-in contrast cases
#
# Exit codes: 0 = clean, 1 = violation (automatic STOP), 2 = the check itself failed (also STOP —
# a check that couldn't run must never read as "clean").
#
# What it compares, and why all three: a change can hide in any one of them.
#   - HEAD         — a commit made during the call (roles never commit);
#   - the index    — a change added with `git add` leaves the working tree equal to the index, so
#                    comparing only the working tree against the index misses it;
#   - the working tree, including new files — hashed as a whole tree through a temporary index,
#                    so a file already modified before the call and modified again is caught.
# Paths are handled NUL-separated (spaces, newlines), renames are split into delete + add so both
# names are checked, and file modes count as a change.
#
# What it does NOT cover, stated so nobody reads it as more: files ignored by .gitignore, anything
# outside the repository, and processes started by the role that outlive it. This is a check over
# what git can see, not filesystem isolation.

set -Eeuo pipefail
trap 'echo "boundary-check: the check itself failed (line $LINENO) — treat as STOP" >&2; exit 2' ERR

git_quiet() { git -c core.safecrlf=false "$@"; }

# Tree of the working tree as it is now: every non-ignored file, tracked or not, through a
# temporary index so the real index is left untouched.
worktree_tree() {
  local idx
  idx="$(mktemp)"
  rm -f "$idx"
  (cd "$(git rev-parse --show-toplevel)" && GIT_INDEX_FILE="$idx" git_quiet add -A -- . 2>/dev/null)
  GIT_INDEX_FILE="$idx" git write-tree
  rm -f "$idx"
}

snapshot() {
  local state="$1"
  local head index worktree
  head="$(git rev-parse --verify HEAD)"
  index="$(git write-tree)"            # fails on unmerged entries — that is a failed check, exit 2
  worktree="$(worktree_tree)"
  printf '%s %s %s\n' "$head" "$index" "$worktree" > "$state"
}

verify() {
  local state="$1"
  shift
  if [ "${1:-}" = "--none" ] && [ $# -eq 1 ]; then
    shift                               # a read-only role: nothing may change at all
  elif [ $# -eq 0 ]; then
    echo "boundary-check: no allowed path given (use --none for a read-only role) — refusing to guess" >&2
    exit 2
  fi
  local h0 i0 w0 extra
  read -r h0 i0 w0 extra < "$state" || true
  if [ -z "${w0:-}" ] || [ -n "${extra:-}" ]; then
    echo "boundary-check: state file $state is missing or malformed" >&2
    exit 2
  fi

  local h1 i1 w1
  h1="$(git rev-parse --verify HEAD)"
  i1="$(git write-tree)"
  w1="$(worktree_tree)"

  local violations=0
  if [ "$h0" != "$h1" ]; then
    echo "VIOLATION: HEAD moved during the call ($h0 -> $h1) — roles never commit" >&2
    violations=$((violations + 1))
  fi

  local changed
  changed="$(mktemp)"
  {
    git diff --no-renames --name-only -z "$i0" "$i1"
    git diff --no-renames --name-only -z "$w0" "$w1"
    if [ "$h0" != "$h1" ]; then git diff --no-renames --name-only -z "$h0" "$h1"; fi
  } | sort -zu > "$changed"

  local path prefix allowed
  while IFS= read -r -d '' path; do
    allowed=0
    for prefix in "$@"; do
      case "$path" in "$prefix"*) allowed=1 ;; esac
    done
    if [ "$allowed" -eq 0 ]; then
      printf 'VIOLATION: changed outside the allowed paths: %s\n' "$path" >&2
      violations=$((violations + 1))
    fi
  done < "$changed"
  rm -f "$changed"

  if [ "$violations" -gt 0 ]; then
    echo "boundary-check: $violations violation(s) — automatic STOP" >&2
    exit 1
  fi
  echo "boundary check: clean"
}

# ---------------------------------------------------------------------------------- self-test
# Every case is a contrast: it runs the real snapshot/verify against a throwaway repository and
# would fail if the comparison it targets were removed.

self_test() {
  local self root failures=0 total=0
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  root="$(mktemp -d)"
  trap - ERR
  set +e

  fresh() {
    rm -rf "$root/repo" && mkdir -p "$root/repo/src" "$root/repo/tests" && cd "$root/repo" || return 1
    git init -q && git config user.email t@t && git config user.name t && git config core.autocrlf false
    printf 'base behavior\n' > src/guard.txt
    printf 'other\n' > src/other.txt
    printf 'test\n' > tests/guard_test.txt
    git add -A && git commit -qm base
  }
  # expect <name> <expected exit> <setup-before-snapshot> <change-during-call> [allowed...]
  expect() {
    local name="$1" want="$2" before="$3" during="$4"
    shift 4
    total=$((total + 1))
    fresh
    eval "$before"
    bash "$self" snapshot "$root/state" 2>/dev/null
    eval "$during"
    local out code
    out="$(bash "$self" verify "$root/state" "$@" 2>&1)"
    code=$?
    if [ "$code" -eq "$want" ]; then
      echo "ok   $name"
    else
      echo "FAIL $name — expected exit $want, got $code: $out"
      failures=$((failures + 1))
    fi
    LAST_OUT="$out"
  }

  expect "allowed edit in tests/ passes"                0 ":" "printf 'more\n' >> tests/guard_test.txt" tests/
  expect "unstaged production edit is a violation"      1 ":" "printf 'x\n' >> src/guard.txt" tests/
  expect "staged production edit is a violation (F02)"  1 ":" "printf 'x\n' >> src/guard.txt; git add src/guard.txt" tests/
  # The working file is put back after `git add`: only the index still carries the change, and
  # the next commit would ship it. Only the index comparison can see this one.
  expect "change hidden in the index behind a restored file is a violation" 1 ":" \
    "cp src/guard.txt \"\$root/orig\"; printf 'x\n' >> src/guard.txt; git add src/guard.txt; cp \"\$root/orig\" src/guard.txt" tests/
  expect "commit during the call is a violation"        1 ":" "printf 'x\n' >> src/guard.txt; git commit -qam sneaky" tests/
  expect "commit of an allowed file is still a violation" 1 ":" "printf 'y\n' >> tests/guard_test.txt; git commit -qam sneaky" tests/
  expect "new production file is a violation"           1 ":" "printf 'n\n' > src/new.txt" tests/
  expect "deleted production file is a violation"       1 ":" "rm src/other.txt" tests/
  expect "already-dirty file changed again is caught"   1 "printf 'dev\n' >> src/guard.txt" "printf 'again\n' >> src/guard.txt" tests/
  expect "rename out of place is a violation"           1 ":" "git mv src/other.txt tests/other.txt" tests/
  expect "name with a space is reported intact"         1 ":" "printf 's\n' > 'src/with space.txt'" tests/
  case "$LAST_OUT" in
    *"src/with space.txt"*) ;;
    *) echo "FAIL name with a space is reported intact — path mangled: $LAST_OUT"; failures=$((failures + 1)) ;;
  esac
  if [ "$(git -C "$root/repo" config core.filemode)" = "true" ]; then
    expect "mode change is a violation"                 1 ":" "chmod +x src/guard.txt" tests/
  else
    echo "skip mode change is a violation — core.filemode is off on this filesystem"
  fi
  expect "no allowed path given fails the check"        2 ":" ":"
  expect "read-only role (--none) with no change passes" 0 ":" ":" --none
  expect "read-only role (--none) writing even a test is a violation" 1 ":" "printf 'w\n' >> tests/guard_test.txt" --none
  total=$((total + 1))
  fresh
  printf 'garbage\n' > "$root/state"
  if bash "$self" verify "$root/state" tests/ >/dev/null 2>&1; [ $? -eq 2 ]; then
    echo "ok   malformed state file fails the check"
  else
    echo "FAIL malformed state file fails the check"; failures=$((failures + 1))
  fi

  # F01: the developer's work is a checkpoint commit; QA's mutation patch is taken against HEAD and
  # restored from HEAD, so the developer's code survives byte for byte.
  total=$((total + 1))
  fresh
  printf 'developer implementation\nauthorization enabled\n' > src/guard.txt
  git commit -qam "checkpoint: developer"
  cp src/guard.txt "$root/before"
  bash "$self" snapshot "$root/state" 2>/dev/null
  sed -i.bak 's/authorization enabled/authorization disabled/' src/guard.txt && rm -f src/guard.txt.bak
  git diff HEAD -- src > "$root/mutation.patch"
  git restore --source=HEAD --staged --worktree -- src
  if cmp -s src/guard.txt "$root/before" \
     && grep -q '^-authorization enabled' "$root/mutation.patch" \
     && ! grep -q '^[-+]developer implementation' "$root/mutation.patch" \
     && bash "$self" verify "$root/state" tests/ >/dev/null 2>&1; then
    echo "ok   mutation against a checkpoint restores the developer's code exactly (F01)"
  else
    echo "FAIL mutation against a checkpoint restores the developer's code exactly (F01)"
    failures=$((failures + 1))
  fi

  cd / && rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  snapshot) [ $# -eq 2 ] || { echo "usage: $0 snapshot <state-file>" >&2; exit 2; }; snapshot "$2" ;;
  verify)   [ $# -ge 2 ] || { echo "usage: $0 verify <state-file> <allowed-prefix>... | --none" >&2; exit 2; }; shift; verify "$@" ;;
  --self-test) self_test ;;
  *) echo "usage: $0 snapshot <state-file> | verify <state-file> <allowed-prefix>... | --self-test" >&2; exit 2 ;;
esac
