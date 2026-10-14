#!/usr/bin/env bash
# exception-check.sh — has a recorded exception outlived its date?
#
# Copy into the product repository (e.g. scripts/exception-check.sh). It reads text — a PR
# description, the exception register, anything — and finds every recorded exception in it:
#
#   gh pr view <M> --json body --jq .body | scripts/exception-check.sh -    # one task's PR
#   scripts/exception-check.sh docs/exception-register.md                   # the register
#   scripts/exception-check.sh --today 2026-11-01 <file>...                 # as of another day
#   scripts/exception-check.sh --self-test                                  # built-in cases
#
# A recorded exception is ONE line, in the format fixed by the team contract, §3a:
#
#   Exception <task>/<finding> — owner: @<handle> — reason: <one sentence> — blocks again: <YYYY-MM-DD>
#
# e.g. "Exception B1-07/R-02 — owner: @anna — reason: the retry storm needs the queue from
# B1-09 — blocks again: 2026-11-30". A list marker or a quote mark in front is fine, and an en
# dash or a hyphen works as a separator. The exception holds THROUGH the date it names; on the
# next day the finding blocks again. "Today" is the UTC date unless --today says otherwise.
#
# Every line that starts with "Exception <something>/<something>" is a candidate. A candidate
# that doesn't match the whole format — an owner missing, a reason empty, a date that doesn't
# exist — is reported MALFORMED: it is not an exception, so the finding it meant to cover still
# blocks. Lines inside HTML comments (<!-- ... -->) are skipped, so a template can show the
# format without being read as one.
#
# Output: one line per exception — EXPIRED, SOON (within --warn days, default 14), LIVE or
# MALFORMED — with the file and line, then a summary.
# Exit codes: 0 = every exception live (or none found), 1 = an expired or malformed exception,
# 2 = the check itself failed (a missing file, a bad argument) — never read that as "clean".
#
# What it does NOT do: decide anything. An expired exception is a question for the human —
# renew it (a new date and reason, their decision) or fix the finding. The check never edits a
# date, and neither does an agent.

set -Eeuo pipefail
trap 'echo "exception-check: the check itself failed (line $LINENO) — treat as expired" >&2; exit 2' ERR

read -r -d '' PARSER <<'AWK' || true
function leap(y)       { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }
function dim(y, m)     { return m == 2 ? 28 + leap(y) : (m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31 }
function valid(s,  y, m, d) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  return m >= 1 && m <= 12 && d >= 1 && d <= dim(y, m)
}
# Days since an epoch — only differences are used.
function day(s,  y, m, d, a) {
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  a = int((14 - m) / 12); y = y + 4800 - a; m = m + 12 * a - 3
  return d + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400)
}
function plural(n) { return n == 1 ? n " day" : n " days" }
BEGIN {
  SEP  = "[[:space:]]+(—|–|-)[[:space:]]+"
  LEAD = "^[[:space:]>*+-]*Exception[[:space:]]+[^[:space:]/]+/[^[:space:]]+"
  FULL = LEAD SEP "owner:[[:space:]]*@[^[:space:]]+" SEP "reason:[[:space:]]*[^[:space:]].*" SEP \
         "blocks again:[[:space:]]*[0-9-]+[[:space:]]*$"
  now = day(today)
}
FNR == 1 { incomment = 0 }
{
  sub(/\r$/, "")
  line = $0
  # Drop HTML comments, including ones spanning lines.
  out = ""
  while (line != "") {
    if (incomment) {
      p = index(line, "-->"); if (!p) { line = ""; break }
      line = substr(line, p + 3); incomment = 0
    } else {
      p = index(line, "<!--"); if (!p) { out = out line; line = ""; break }
      out = out substr(line, 1, p - 1); line = substr(line, p + 4); incomment = 1
    }
  }
  if (out !~ LEAD) next
  where = FILENAME ":" FNR
  match(out, /Exception[[:space:]]+[^[:space:]]+/)
  id = substr(out, RSTART, RLENGTH); sub(/^Exception[[:space:]]+/, "", id)
  if (out !~ FULL) { print "MALFORMED  " id "  " where "  — not in the §3a format; the finding still blocks"; bad++; next }
  date = out; sub(/.*blocks again:[[:space:]]*/, "", date); sub(/[[:space:]]+$/, "", date)
  owner = out; sub(/.*owner:[[:space:]]*/, "", owner); sub(/[[:space:]].*/, "", owner)
  if (!valid(date)) { print "MALFORMED  " id "  " where "  — '" date "' is not a date; the finding still blocks"; bad++; next }
  left = day(date) - now
  if (left < 0)          { print "EXPIRED    " id "  " where "  blocks again since " date " (" plural(-left) " ago), owner " owner; expired++ }
  else if (left <= warn) { print "SOON       " id "  " where "  holds through " date " (" plural(left) " left), owner " owner; soon++ }
  else                   { print "LIVE       " id "  " where "  holds through " date ", owner " owner; live++ }
}
END {
  n = expired + bad
  printf "exception-check: %s — as of %s: %d live, %d expiring within %d days, %d expired, %d malformed\n", \
         (n ? n " finding(s)" : "clean"), today, live, soon, warn, expired, bad
  exit (expired + bad > 0) ? 1 : 0
}
AWK

usage() { echo "usage: $0 [--today YYYY-MM-DD] [--warn DAYS] <file|->... | --self-test" >&2; exit 2; }

check() {
  local today warn=14
  today="$(date -u +%Y-%m-%d)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --today) [ $# -ge 2 ] || usage; today="$2"; shift 2 ;;
      --warn)  [ $# -ge 2 ] || usage; warn="$2"; shift 2 ;;
      -) break ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  [ $# -ge 1 ] || usage
  [[ "$warn" =~ ^[0-9]+$ ]] || usage
  # The same validity rule the parser uses, so "today" can't be a date that doesn't exist.
  awk -v t="$today" 'BEGIN {
      if (t !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit 1
      y = substr(t, 1, 4) + 0; m = substr(t, 6, 2) + 0; d = substr(t, 9, 2) + 0
      l = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      n = m == 2 ? 28 + l : (m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31
      exit !(m >= 1 && m <= 12 && d >= 1 && d <= n) }' || usage
  local f
  for f in "$@"; do
    [ "$f" = "-" ] || [ -r "$f" ] || { echo "exception-check: cannot read '$f'" >&2; exit 2; }
  done
  # Exit 1 from the parser is a result, not a failure — keep it away from the ERR trap.
  local code=0
  awk -v today="$today" -v warn="$warn" "$PARSER" "$@" || code=$?
  [ "$code" -le 1 ] || exit 2
  exit "$code"
}

self_test() {
  local self root failures=0 total=0
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  root="$(mktemp -d)"
  trap - ERR
  set +e

  # expect <name> <expected exit> <file content (printf format)> [<text the output must contain>]
  expect() {
    local name="$1" want="$2" content="$3" must="${4:-}" out code
    total=$((total + 1))
    printf -- "$content" > "$root/in.md"
    out="$(bash "$self" --today 2026-10-14 "$root/in.md" 2>&1)"
    code=$?
    if [ "$code" -ne "$want" ]; then
      echo "FAIL $name — expected exit $want, got $code: $out"
      failures=$((failures + 1))
    elif [ -n "$must" ] && [[ "$out" != *"$must"* ]]; then
      echo "FAIL $name — output lacks '$must': $out"
      failures=$((failures + 1))
    else
      echo "ok   $name"
    fi
  }
  local E='Exception B1-07/R-02 — owner: @anna — reason: needs the queue from B1-09 — blocks again: '

  # Must pass: live exceptions, and text that only looks like one.
  expect "live exception passes"                   0 "${E}2026-12-31\n"            "LIVE       B1-07/R-02"
  expect "the named date itself still holds"       0 "${E}2026-10-14\n"            "(0 days left)"
  expect "within the warning window is SOON"       0 "${E}2026-10-20\n"            "(6 days left)"
  expect "list marker and en dashes pass"          0 "- Exception B1-07/G-01 – owner: @bo – reason: x – blocks again: 2026-12-01\n" "LIVE       B1-07/G-01"
  expect "a hyphen separator passes"               0 "* Exception B1-07/G-01 - owner: @bo - reason: x - blocks again: 2026-12-01\n" "LIVE"
  expect "CRLF line endings pass"                  0 "${E}2026-12-31\r\n"          "1 live"
  expect "29 February in a leap year passes"       0 "${E}2028-02-29\n"            "LIVE"
  expect "inside an HTML comment is skipped"       0 "<!--\n${E}2020-01-01\n-->\n" "0 live, 0 expiring within 14 days, 0 expired, 0 malformed"
  expect "one-line HTML comment is skipped"        0 "<!-- ${E}2020-01-01 -->\n"   "0 expired"
  expect "prose starting with Exception is ignored" 0 "Exception handling stays in the adapter.\n" "0 malformed"
  expect "no exceptions at all passes"             0 ""                            "0 live"

  # Must fail: expired or malformed, with the evidence named.
  expect "expired yesterday is a finding"          1 "${E}2026-10-13\n"            "EXPIRED    B1-07/R-02"
  expect "days counted across a year"              1 "${E}2025-12-31\n"            "(287 days ago)"
  expect "file and line are reported"              1 "text\n\n${E}2026-01-01\n"    "in.md:3"
  expect "missing owner is malformed"              1 "Exception B1-07/R-02 — reason: x — blocks again: 2026-12-31\n" "MALFORMED  B1-07/R-02"
  expect "owner without @ is malformed"            1 "Exception B1-07/R-02 — owner: anna — reason: x — blocks again: 2026-12-31\n" "MALFORMED"
  expect "empty reason is malformed"               1 "Exception B1-07/R-02 — owner: @anna — reason: — blocks again: 2026-12-31\n" "MALFORMED"
  expect "30 February is malformed"                1 "${E}2026-02-30\n"            "is not a date"
  expect "a date in another order is malformed"    1 "${E}31.12.2026\n"            "MALFORMED"
  expect "no date at all is malformed"             1 "${E}when B1-09 ships\n"      "MALFORMED"
  expect "a comment closing before it still counts" 1 "<!-- note -->\n${E}2026-01-01\n" "EXPIRED"

  # Must fail the check itself, never read as clean.
  local name
  for name in "missing file" "no arguments" "bad --today" "29 February in a common year as --today" "bad --warn"; do
    total=$((total + 1))
    case "$name" in
      "missing file")  bash "$self" "$root/none.md" >/dev/null 2>&1 ;;
      "no arguments")  bash "$self" >/dev/null 2>&1 ;;
      "bad --today")   bash "$self" --today 14.10.2026 "$root/in.md" >/dev/null 2>&1 ;;
      "29 February in a common year as --today") bash "$self" --today 2026-02-29 "$root/in.md" >/dev/null 2>&1 ;;
      "bad --warn")    bash "$self" --warn soon "$root/in.md" >/dev/null 2>&1 ;;
    esac
    if [ $? -eq 2 ]; then echo "ok   $name fails the check"; else echo "FAIL $name fails the check"; failures=$((failures + 1)); fi
  done

  # Standard input, two files at once.
  total=$((total + 1))
  printf "${E}2026-12-31\n" > "$root/a.md"
  local both
  both="$(printf "${E}2026-01-01\n" | bash "$self" --today 2026-10-14 "$root/a.md" - 2>&1)"
  if [[ "$both" == *"1 live, 0 expiring within 14 days, 1 expired"* ]]; then
    echo "ok   a file and standard input are read together"
  else
    echo "FAIL a file and standard input are read together"; failures=$((failures + 1))
  fi

  # The exit contract (process/ci-and-branch-protection.md, "Exit contract"): a check's last line
  # on stdout is its result.
  local last
  last="$(bash "$self" --today 2026-10-14 "$root/a.md" 2>/dev/null | tail -n 1)"
  total=$((total + 1))
  [[ "$last" == "exception-check: clean — as of 2026-10-14: 1 live,"* ]] && echo "ok   the last line states the result (clean)" \
    || { echo "FAIL the last line states the result (clean): '$last'"; failures=$((failures + 1)); }
  last="$(printf "${E}2026-01-01\n" | bash "$self" --today 2026-10-14 - 2>/dev/null | tail -n 1)"
  total=$((total + 1))
  [[ "$last" == "exception-check: 1 finding(s) — as of 2026-10-14:"* ]] && echo "ok   the last line states the result (finding)" \
    || { echo "FAIL the last line states the result (finding): '$last'"; failures=$((failures + 1)); }

  rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  "") usage ;;
  *) check "$@" ;;
esac
