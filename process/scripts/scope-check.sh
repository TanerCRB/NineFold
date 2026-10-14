#!/usr/bin/env bash
# scope-check.sh — the scope lock's extraction and fingerprint, in one place.
#
# Copy into the product repository (e.g. scripts/scope-check.sh). The task command, the
# task-status command and the label-guard workflow all call it, so the three can't drift apart
# on what "the scope" is:
#
#   gh issue view <N> --json body --jq .body | scripts/scope-check.sh text -     # the locked text
#   gh issue view <N> --json body --jq .body | scripts/scope-check.sh hash -     # its fingerprint
#   gh issue view <N> --json comments --jq '.comments[].body' \
#     | scripts/scope-check.sh locked -                                          # the binding one
#   scripts/scope-check.sh --self-test                                           # built-in cases
#
# What is locked (task-command.md, "Scope lock"): the Issue's "### Definition of done" and
# "### Out of scope" sections, and everything between "<!-- criteria:start -->" and
# "<!-- criteria:end -->". A section runs to the next "### " heading. Nothing else in the body
# counts, so editing the title, the context or a typo outside those parts keeps the hash.
#
# `hash` is `git hash-object` of what `text` prints — the same value the inline `scope_text`
# of v0.7.0 gave, so fingerprints posted before this script still compare equal.
#
# `locked` reads comment bodies and prints the fingerprint of the LATEST comment that is a lock:
# "Scope for gate 1 — fingerprint: <hash>" or "Scope amended at gate 2 — … — fingerprint: <hash>".
# Any other line carrying a hash — the guard's own comment, a quote — is not a lock.
#
# Exit codes: 0 = done, 1 = a finding (a locked part or a marker is missing, so the body can't
# be compared; `locked`: no lock comment at all), 2 = the check itself failed (a bad argument,
# a missing file) — never read that as "holds".
#
# What it does NOT do: decide anything. A changed scope goes back to the human at gate 1; the
# check never edits the Issue, and neither does an agent.

set -Eeuo pipefail
trap 'echo "scope-check: the check itself failed (line $LINENO) — treat the scope as changed" >&2; exit 2' ERR

usage() { echo "usage: $0 text|hash|locked <file|-> | --self-test" >&2; exit 2; }

read_input() {
  if [ "$1" = "-" ]; then tr -d '\r'
  else
    [ -r "$1" ] || { echo "scope-check: cannot read '$1'" >&2; exit 2; }
    tr -d '\r' < "$1"
  fi
}

# Prints the locked parts in body order; reports every missing part on stderr and exits 1.
extract() {
  local code=0
  [ "$1" = "-" ] || [ -r "$1" ] || { echo "scope-check: cannot read '$1'" >&2; exit 2; }
  read_input "$1" | awk '
    /<!-- criteria:start -->/ { c = 1; starts++ }
    c { print; if (/<!-- criteria:end -->/) { c = 0; ends++ }; next }
    /<!-- criteria:end -->/ { ends++ }
    /^### / { s = ($0 ~ /^### (Definition of done|Out of scope)/)
              if ($0 ~ /^### Definition of done/) dod++
              if ($0 ~ /^### Out of scope/) oos++ }
    s
    END {
      bad = 0
      if (!dod)    { print "scope-check: no \"### Definition of done\" section" > "/dev/stderr"; bad = 1 }
      if (!oos)    { print "scope-check: no \"### Out of scope\" section" > "/dev/stderr"; bad = 1 }
      if (!starts) { print "scope-check: no \"<!-- criteria:start -->\" marker — criteria never written into the Issue" > "/dev/stderr"; bad = 1 }
      else if (c || ends < starts) { print "scope-check: \"<!-- criteria:start -->\" without \"<!-- criteria:end -->\"" > "/dev/stderr"; bad = 1 }
      exit bad
    }' || code=$?
  [ "$code" -le 1 ] || exit 2
  return "$code"
}

latest_lock() {
  local found
  found="$(read_input "$1" | grep -oE '^Scope (for gate 1|amended at gate 2) — .*fingerprint: [0-9a-f]{40,64}' \
    | grep -oE '[0-9a-f]{40,64}$' | tail -n 1 || true)"
  [ -n "$found" ] || { echo "scope-check: no \"Scope for gate 1\" or \"Scope amended at gate 2\" comment — scope never locked" >&2; return 1; }
  echo "$found"
}

run() {
  [ $# -eq 2 ] || usage
  local code=0 tmp
  case "$1" in
    text)   extract "$2" || code=$? ;;
    # Through a file, not a variable: $(…) drops trailing newlines, and the hash covers them.
    hash)   tmp="$(mktemp)"
            extract "$2" > "$tmp" || code=$?
            [ "$code" -ne 0 ] || git hash-object --stdin < "$tmp"
            rm -f "$tmp" ;;
    locked) latest_lock "$2" || code=$? ;;
    *) usage ;;
  esac
  exit "$code"
}

self_test() {
  local self root failures=0 total=0
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  root="$(mktemp -d)"
  trap - ERR
  set +e

  local BODY='### Context\nWhy we do this.\n\n### Definition of done\nA guest can cancel.\n\n### Out of scope\nRefunds.\n\n### Notes\nfree text\n\n### Acceptance criteria\n<!-- criteria:start -->\nK-01 cancel frees the room\n<!-- criteria:end -->\n'
  local LOCKED='### Definition of done\nA guest can cancel.\n\n### Out of scope\nRefunds.\n\n<!-- criteria:start -->\nK-01 cancel frees the room\n<!-- criteria:end -->\n'
  printf -- "$BODY" > "$root/base.md"
  local base; base="$(bash "$self" hash "$root/base.md" 2>&1)"

  ok()   { echo "ok   $1"; }
  fail() { echo "FAIL $1 — $2"; failures=$((failures + 1)); }

  # same_hash <name> <body (printf format)>: an edit outside the locked parts keeps the hash.
  same_hash() {
    total=$((total + 1)); printf -- "$2" > "$root/in.md"
    local h; h="$(bash "$self" hash "$root/in.md" 2>&1)"
    [ "$h" = "$base" ] && ok "$1" || fail "$1" "hash $h, expected $base"
  }
  # new_hash <name> <body>: an edit to a locked part changes it.
  new_hash() {
    total=$((total + 1)); printf -- "$2" > "$root/in.md"
    local h code; h="$(bash "$self" hash "$root/in.md" 2>&1)"; code=$?
    [ "$code" -eq 0 ] && [ "$h" != "$base" ] && ok "$1" || fail "$1" "exit $code, hash $h"
  }
  # finding <name> <body> <text the message must contain>: a missing part is exit 1, named.
  finding() {
    total=$((total + 1)); printf -- "$2" > "$root/in.md"
    local out code; out="$(bash "$self" hash "$root/in.md" 2>&1)"; code=$?
    [ "$code" -eq 1 ] && [[ "$out" == *"$3"* ]] && ok "$1" || fail "$1" "exit $code: $out"
  }

  # The extraction itself, and the fingerprint the inline v0.7.0 function gave.
  total=$((total + 1))
  [ "$(bash "$self" text "$root/base.md")" = "$(printf -- "$LOCKED")" ] && ok "text prints exactly the locked parts" \
    || fail "text prints exactly the locked parts" "$(bash "$self" text "$root/base.md" 2>&1)"
  total=$((total + 1))
  [ "$base" = "$(printf -- "$LOCKED" | git hash-object --stdin)" ] && ok "hash equals git hash-object of the locked text" \
    || fail "hash equals git hash-object of the locked text" "$base"

  total=$((total + 1))
  printf -- '<!-- criteria:start -->\nK-01\n<!-- criteria:end -->\n### Definition of done\nX\n\n### Out of scope\nY\n\n\n' > "$root/tail.md"
  [ "$(bash "$self" hash "$root/tail.md")" = "$(printf -- '<!-- criteria:start -->\nK-01\n<!-- criteria:end -->\n### Definition of done\nX\n\n### Out of scope\nY\n\n\n' | git hash-object --stdin)" ] \
    && ok "trailing blank lines of a locked section are hashed, as before" \
    || fail "trailing blank lines of a locked section are hashed, as before" "hash differs"

  same_hash "an edit to the context keeps the hash"   "${BODY/Why we do this./Why we really do this.}"
  same_hash "an edit to another section keeps it"     "${BODY/free text/other text}"
  same_hash "CRLF line endings keep it"               "$(printf -- "$BODY" | sed 's/$/\r/')\n"
  new_hash  "an edit to Definition of done changes it" "${BODY/A guest can cancel./A guest or a manager can cancel.}"
  new_hash  "an edit to Out of scope changes it"      "${BODY/Refunds./Refunds and fees.}"
  new_hash  "an edit to a criterion changes it"       "${BODY/K-01 cancel frees the room/K-01 cancel frees the room and the slot}"
  new_hash  "an added criterion changes it"           "${BODY/<!-- criteria:end -->/K-02 the guest is told\n<!-- criteria:end -->}"

  finding "no criteria markers is reported"           "${BODY%%### Acceptance*}"                                "no \"<!-- criteria:start -->\""
  finding "an unclosed criteria block is reported"    "${BODY/<!-- criteria:end -->/}"                          "without \"<!-- criteria:end -->\""
  # A pattern starting with "#" anchors to the start in ${var/…}, so the headings are escaped.
  finding "no Definition of done is reported"         "${BODY/\#\#\# Definition of done/### Done}"              "no \"### Definition of done\""
  finding "no Out of scope is reported"               "${BODY/\#\#\# Out of scope/### Not doing}"               "no \"### Out of scope\""

  # The binding lock is the latest lock comment, and only a lock comment.
  local H1=1111111111111111111111111111111111111111 H2=2222222222222222222222222222222222222222 H3=3333333333333333333333333333333333333333
  lock_case() {
    total=$((total + 1)); printf -- "$2" > "$root/c.md"
    local out code; out="$(bash "$self" locked "$root/c.md" 2>&1)"; code=$?
    [ "$code" -eq "$3" ] && [[ "$out" == *"$4"* ]] && ok "$1" || fail "$1" "exit $code: $out"
  }
  lock_case "the gate-1 lock is read"                 "Scope for gate 1 — fingerprint: $H1\n" 0 "$H1"
  lock_case "a gate-2 amendment replaces it"          "Scope for gate 1 — fingerprint: $H1\nlooks good\nScope amended at gate 2 — A-02 — fingerprint: $H2\n" 0 "$H2"
  lock_case "a hash in another comment is no lock"    "Scope for gate 1 — fingerprint: $H1\n**label-guard:** scope now hashes to $H3, not fingerprint: $H3\n" 0 "$H1"
  lock_case "no lock comment is reported"             "Looks good to me\n" 1 "scope never locked"

  # Must fail the check itself, never read as "holds".
  local name
  for name in "missing file" "no arguments" "unknown mode"; do
    total=$((total + 1))
    case "$name" in
      "missing file") bash "$self" hash "$root/none.md" >/dev/null 2>&1 ;;
      "no arguments") bash "$self" >/dev/null 2>&1 ;;
      "unknown mode") bash "$self" sha "$root/base.md" >/dev/null 2>&1 ;;
    esac
    [ $? -eq 2 ] && ok "$name fails the check" || fail "$name fails the check" "exit not 2"
  done

  # Standard input reads the same as a file.
  total=$((total + 1))
  [ "$(printf -- "$BODY" | bash "$self" hash -)" = "$base" ] && ok "standard input gives the same hash" \
    || fail "standard input gives the same hash" "differs"

  rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  *) run "$@" ;;
esac
