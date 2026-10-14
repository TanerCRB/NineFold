#!/usr/bin/env bash
# risk-check.sh — which risk classes does a change touch?
#
# Copy into the product repository (e.g. scripts/risk-check.sh). It reads the risk classes from
# the architecture-sensitive paths register (process/registers/architecture-sensitive-paths.md)
# and matches them against the paths a change touches:
#
#   scripts/risk-check.sh classes <base> [<head>]            # the classes a diff touches
#   printf '%s\n' src/Auth/Login.cs | scripts/risk-check.sh classes --paths -   # planned files
#   scripts/risk-check.sh explain <base> [<head>]            # class, path and the matching glob
#   scripts/risk-check.sh --register <file> classes …        # another register than the default
#   scripts/risk-check.sh --self-test                        # built-in cases
#
# A register row is a Markdown table row whose first cell is one glob in backticks and whose second
# cell lists classes, comma-separated:
#
#   | `src/Auth/**` | auth, personal-data | ADR-0005 | permission pipeline |
#
# `*` and `**` both match across directories. Rows still holding a <placeholder> are skipped.
# The classes are a closed list (CLASSES below), so a typo can't quietly switch a check off. Adapt
# the list to your project, and keep the self-test in step with it.
#
# What the task command does with the classes (task-command.md):
#   - any class                          → no fast lane: the Architect runs;
#   - any class in AUDITOR_CLASSES       → the Security Auditor runs;
#   - any class in NO_EXCEPTION_CLASSES  → a SURVIVED mutation is fixed, never let through by an
#                                          exception.
#
# Exit contract (ci-and-branch-protection.md, §8). Both modes are queries: stdout carries only the
# classes (one per line, sorted) or the explanation lines, and no class touched means empty output,
# exit 0. Exit 2 means the check itself failed and is never read as "no risk": the register is
# missing, it has no real rows, a row names an unknown class, or a commit doesn't exist.

set -Eeuo pipefail
trap 'echo "risk-check: the check itself failed (line $LINENO) — treat every class as touched" >&2; exit 2' ERR

CLASSES="schema auth money personal-data pipeline dependencies secrets external model"
AUDITOR_CLASSES="schema auth personal-data pipeline dependencies secrets external model"
NO_EXCEPTION_CLASSES="schema money"
REGISTER="docs/architecture-sensitive-paths.md"

usage() { echo "usage: $0 [--register <file>] classes|explain <base> [<head>] | classes|explain --paths - | --self-test" >&2; exit 2; }

# The register's rows → "glob<TAB>class" lines; exit 2 on anything that isn't a clean register.
rules() {
  [ -r "$1" ] || { echo "risk-check: cannot read the register '$1'" >&2; exit 2; }
  local code=0
  tr -d '\r' < "$1" | awk -v known=" $CLASSES " '
    /^\|/ {
      n = split($0, cell, "|")
      g = cell[2]; c = cell[3]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", g); gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
      if (g !~ /^`[^`]+`$/) next                       # header, separator, prose
      g = substr(g, 2, length(g) - 2)
      if (g ~ /</ || c ~ /</) next                     # a placeholder row of the template
      m = split(c, cls, /[[:space:]]*,[[:space:]]*/)
      if (m == 0 || c == "") { print "risk-check: row " g " names no class" > "/dev/stderr"; bad = 1; next }
      for (i = 1; i <= m; i++) {
        if (index(known, " " cls[i] " ") == 0) { print "risk-check: row " g " names an unknown class \"" cls[i] "\"" > "/dev/stderr"; bad = 1; continue }
        print g "\t" cls[i]; rows++
      }
    }
    END {
      if (bad) exit 2
      if (!rows) { print "risk-check: the register has no rows with a real path — every change would read as risk-free" > "/dev/stderr"; exit 2 }
    }' || code=$?
  [ "$code" -eq 0 ] || exit 2
}

# The paths a change touches: both sides of a rename count, so moving a file out of a sensitive
# directory is still a change to it.
paths_of() {
  if [ "$1" = "--paths" ]; then
    [ "${2:-}" = "-" ] || usage
    tr -d '\r' | sed '/^[[:space:]]*$/d'
    return
  fi
  local base="$1" head="${2:-HEAD}"
  git rev-parse --verify --quiet "$base^{commit}" > /dev/null || { echo "risk-check: base '$base' is not a commit" >&2; exit 2; }
  git rev-parse --verify --quiet "$head^{commit}" > /dev/null || { echo "risk-check: head '$head' is not a commit" >&2; exit 2; }
  git diff --name-only --no-renames "$base...$head"
}

run() {
  local register="$REGISTER"
  if [ "${1:-}" = "--register" ]; then [ $# -ge 2 ] || usage; register="$2"; shift 2; fi
  local mode="${1:-}"; shift || true
  case "$mode" in classes|explain) ;; *) usage ;; esac
  [ $# -ge 1 ] && [ $# -le 2 ] || usage

  local tmp; tmp="$(mktemp -d)"
  rules "$register" > "$tmp/rules"
  paths_of "$@" > "$tmp/paths"

  local path glob class
  : > "$tmp/hits"
  while IFS= read -r path; do
    while IFS=$'\t' read -r glob class; do
      # In a case pattern `*` already crosses `/`, so `**` needs no special meaning.
      # shellcheck disable=SC2254
      case "$path" in ${glob//\*\*/*}) printf '%s\t%s\t%s\n' "$class" "$path" "$glob" >> "$tmp/hits" ;; esac
    done < "$tmp/rules"
  done < "$tmp/paths"

  if [ "$mode" = classes ]; then cut -f1 "$tmp/hits" | sort -u
  else sort -u "$tmp/hits"; fi
  rm -rf "$tmp"
}

self_test() {
  local self root failures=0 total=0
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  root="$(mktemp -d)"
  trap - ERR
  set +e

  cat > "$root/reg.md" <<'EOF'
# Architecture-sensitive paths

| Path (glob) | Risk classes | Governing decisions | Why it's sensitive |
|---|---|---|---|
| `<src/Data/**>` | <schema> | <ADR-0003> | <placeholder row, skipped> |
| `migrations/**` | schema | ADR-0002 | expand → deploy → contract |
| `src/Auth/**` | auth, personal-data | ADR-0005 | permission pipeline |
| `src/Billing/*.cs` | money | ADR-0009 | invoices |
| `package-lock.json` | dependencies | — | the lock file |
EOF

  # expect <name> <expected exit> <expected stdout (printf format)> <paths (printf format)> [<register>]
  expect() {
    local name="$1" want="$2" out_want="$3" paths="$4" reg="${5:-$root/reg.md}" out code
    total=$((total + 1))
    out="$(printf -- "$paths" | bash "$self" --register "$reg" classes --paths - 2>/dev/null)"; code=$?
    if [ "$code" -ne "$want" ]; then echo "FAIL $name — expected exit $want, got $code: $out"; failures=$((failures + 1))
    elif [ "$code" -eq 0 ] && [ "$out" != "$(printf -- "$out_want")" ]; then echo "FAIL $name — got '$out'"; failures=$((failures + 1))
    else echo "ok   $name"; fi
  }

  # Classes from paths.
  expect "a path outside every glob touches no class"    0 ""                           'src/Rooms/List.cs\nREADME.md\n'
  expect "a migration is schema"                         0 "schema"                     'migrations/0007_add_note.sql\n'
  expect "** crosses directories"                        0 "schema"                     'migrations/2026/10/0008.sql\n'
  expect "a row can name two classes"                    0 "auth\npersonal-data"        'src/Auth/Login.cs\n'
  expect "* crosses directories too, as in a case pattern" 0 "money"                    'src/Billing/Rules/Vat.cs\n'
  expect "classes from several paths, sorted and unique" 0 "auth\ndependencies\npersonal-data" 'package-lock.json\nsrc/Auth/A.cs\nsrc/Auth/B.cs\n'
  expect "the placeholder row is skipped"                0 ""                           'src/Data/Store.cs\n'
  expect "an exact glob matches only itself"             0 ""                           'sub/package-lock.json.bak\n'
  expect "CRLF paths still match"                        0 "money"                      'src/Billing/Invoice.cs\r\n'

  # The register itself.
  printf '| `src/**` | billing |  |  |\n' > "$root/unknown.md"
  expect "an unknown class fails the check"              2 "" 'src/A.cs\n' "$root/unknown.md"
  printf '| `src/**` |  |  |  |\n' > "$root/noclass.md"
  expect "a row with no class fails the check"           2 "" 'src/A.cs\n' "$root/noclass.md"
  printf '| Path | Risk classes |\n|---|---|\n| `<src/**>` | <auth> |\n' > "$root/template.md"
  expect "a register with only placeholders fails"       2 "" 'src/A.cs\n' "$root/template.md"
  expect "a missing register fails"                      2 "" 'src/A.cs\n' "$root/none.md"
  tr -d '\r' < "$root/reg.md" | sed 's/$/\r/' > "$root/crlf.md"
  expect "a CRLF register reads the same"                0 "schema"                     'migrations/1.sql\n' "$root/crlf.md"

  # From a diff, both sides of a rename.
  local repo="$root/repo"
  git init -q "$repo" && git -C "$repo" config core.autocrlf false && git -C "$repo" config user.email t@t && git -C "$repo" config user.name t
  mkdir -p "$repo/src/Auth" "$repo/src/Other"
  printf 'x\n' > "$repo/src/Auth/Token.cs"; printf 'y\n' > "$repo/README.md"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" mv src/Auth/Token.cs src/Other/Token.cs && git -C "$repo" commit -qm move
  total=$((total + 1))
  local out; out="$(cd "$repo" && bash "$self" --register "$root/reg.md" classes HEAD~1 HEAD 2>&1)"
  [ "$out" = "$(printf 'auth\npersonal-data')" ] && echo "ok   moving a file out of a sensitive directory still touches it" \
    || { echo "FAIL moving a file out of a sensitive directory still touches it: '$out'"; failures=$((failures + 1)); }
  total=$((total + 1))
  out="$(cd "$repo" && bash "$self" --register "$root/reg.md" explain HEAD~1 HEAD 2>&1 | head -n 1)"
  [ "$out" = "$(printf 'auth\tsrc/Auth/Token.cs\tsrc/Auth/**')" ] && echo "ok   explain names the class, the path and the glob" \
    || { echo "FAIL explain names the class, the path and the glob: '$out'"; failures=$((failures + 1)); }

  # Must fail the check itself, never read as "no risk".
  local name
  for name in "no arguments" "unknown mode" "a base that isn't a commit" "--paths without -"; do
    total=$((total + 1))
    case "$name" in
      "no arguments")               bash "$self" >/dev/null 2>&1 ;;
      "unknown mode")               bash "$self" --register "$root/reg.md" list --paths - </dev/null >/dev/null 2>&1 ;;
      "a base that isn't a commit") (cd "$repo" && bash "$self" --register "$root/reg.md" classes nope HEAD >/dev/null 2>&1) ;;
      "--paths without -")          bash "$self" --register "$root/reg.md" classes --paths >/dev/null 2>&1 ;;
    esac
    [ $? -eq 2 ] && echo "ok   $name fails the check" || { echo "FAIL $name fails the check"; failures=$((failures + 1)); }
  done

  rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  *) run "$@" ;;
esac
