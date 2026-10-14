#!/usr/bin/env bash
# evidence-chain.sh — does every criterion have its proof, and every proof a criterion?
#
# Copy into the product repository (e.g. scripts/evidence-chain.sh). Two modes:
#
#   gh issue view <N> --json body --jq .body | scripts/evidence-chain.sh lint -        # before gate 1
#   scripts/evidence-chain.sh chain <issue-body> <pr-body> [--repo <dir>]             # before gate 2
#   scripts/evidence-chain.sh --self-test                                             # built-in cases
#
# LINT reads the criteria the task command wrote into the Issue, between "<!-- criteria:start -->"
# and "<!-- criteria:end -->", in the Analyst's format (agents/analyst.md, "Output format"):
#
#   ### K-01 — <claim>
#   **Contrast:** <…>
#   **Mutation that must kill it:** <…>
#   **Judged by:** test / human — <why no test can decide it>
#
# Findings: no markers; a heading inside the block that isn't "### K-<n> — <claim>"; a claim,
# contrast, mutation or "Judged by" missing or left as a <placeholder>; "Judged by" that is
# neither test nor human; human without a reason; an ID used twice; more than seven criteria
# (split the Story). Fewer than four is a warning, not a finding.
#
# CHAIN lints the same criteria, then reads the PR description and the test files of the
# repository (tracked files matching TEST_PATH_RE below). The PR carries one line per link, outside
# HTML comments, in the sections the PR templates name:
#
#   ## Definition of done — proof   - K-01 — test: <a name that appears in a test file>
#   ## Mutation                     - K-01 — removed: <mechanism> — result: killed, <n> tests failed
#                                   - K-03 — removed: <mechanism> — result: SURVIVED — <why>
#   ## Undecidable                  - K-02 — decision: <the human's decision at gate 2>
#
# Findings: a criterion judged by a test with no test line, or with a test line naming something
# no test file contains; a criterion judged by a test with no mutation line, or a mutation that
# SURVIVED, or a result that is neither "killed" nor "SURVIVED"; a criterion judged by a human with
# no decision; a test, mutation or decision line naming a criterion the Issue doesn't have; a line
# that starts "- K-…" in those sections but isn't in the format.
#
# Exit codes: 0 = the chain holds (warnings may be printed), 1 = a finding, 2 = the check itself
# failed (a missing file, not a git repository, a bad argument) — never read that as "holds".
#
# What it does NOT check: that a test proves its criterion — only that it exists and that a
# mutation showed it can fail. Whether the right mechanism was removed is QA's report and the
# Reviewer's reading. An infrastructure PR proves by a run, not by a test in the tree: run only
# `lint` there. Adapt TEST_PATH_RE and the section headings to your repository, and keep the
# self-test cases in step with them.

set -Eeuo pipefail
trap 'echo "evidence-chain: the check itself failed (line $LINENO) — treat the chain as broken" >&2; exit 2' ERR

# Paths that hold tests — the same pattern as weakening-check.sh.
TEST_PATH_RE='(^|/)(test|tests|__tests__|spec|specs)/|[._-](test|tests|spec|specs)\.[A-Za-z0-9]+$|Tests?\.[A-Za-z]+$|(^|/)test_[^/]*\.py$'
# PR sections, by the start of their heading.
PROOF_HEADING='## Definition of done'
MUTATION_HEADING='## Mutation'
DECISION_HEADING='## Undecidable'

usage() { echo "usage: $0 lint <issue-body|-> | chain <issue-body> <pr-body> [--repo <dir>] | --self-test" >&2; exit 2; }

readable() { [ "$1" = "-" ] || [ -r "$1" ] || { echo "evidence-chain: cannot read '$1'" >&2; exit 2; }; }

# Criteria → lines "FINDING\t<id>\t<text>", "WARN\t<id>\t<text>", "CRIT\t<id>\t<test|human>".
criteria() {
  tr -d '\r' < "$1" | awk '
    function blank(v) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); return v == "" || v ~ /^<.*>$/ }
    function close_crit() {
      if (id == "") return
      if (!has["contrast"]) print "FINDING\t" id "\tno contrast"
      if (!has["mutation"]) print "FINDING\t" id "\tno mutation that must kill it"
      if (judge == "")      print "FINDING\t" id "\tno \"Judged by\""
      else print "CRIT\t" id "\t" judge
      id = ""; judge = ""; delete has
    }
    /<!-- criteria:start -->/ { inblock = 1; seen = 1; next }
    /<!-- criteria:end -->/   { if (inblock) { close_crit(); inblock = 0; ended = 1 }; next }
    !inblock { next }
    /^### / {
      close_crit()
      if (match($0, /^### K-[0-9]+[[:space:]]+(—|–|-)[[:space:]]*/)) {
        h = substr($0, 5); sub(/[[:space:]].*/, "", h); id = h
        claim = substr($0, RLENGTH + 1)
        if (count[id]++) print "FINDING\t" id "\tthe ID is used twice"
        n++
        if (blank(claim)) print "FINDING\t" id "\tno claim in the heading"
      } else print "FINDING\t-\ta heading that is not \"### K-<n> — <claim>\": " $0
      next
    }
    id != "" && /^\*\*Contrast:\*\*/                   { v = $0; sub(/^\*\*Contrast:\*\*/, "", v); has["contrast"] = !blank(v); next }
    id != "" && /^\*\*Mutation that must kill it:\*\*/ { v = $0; sub(/^\*\*Mutation that must kill it:\*\*/, "", v); has["mutation"] = !blank(v); next }
    id != "" && /^\*\*Judged by:\*\*/ {
      v = $0; sub(/^\*\*Judged by:\*\*[[:space:]]*/, "", v); w = tolower(v)
      if (w ~ /^test([^a-z]|$)/) judge = "test"
      else if (w ~ /^human([^a-z]|$)/) {
        judge = "human"; r = v; sub(/^[A-Za-z]+[[:space:]]*(—|–|-|,|:)?[[:space:]]*/, "", r)
        if (blank(r)) print "FINDING\t" id "\tjudged by a human, with no reason why no test can decide it"
      } else if (!blank(v)) { print "FINDING\t" id "\t\"Judged by\" is neither test nor human: " v; judge = "invalid" }
      next
    }
    END {
      if (!seen) { print "FINDING\t-\tno \"<!-- criteria:start -->\" marker — the criteria were never written into the Issue"; exit }
      if (!ended) { close_crit(); print "FINDING\t-\t\"<!-- criteria:start -->\" without \"<!-- criteria:end -->\"" }
      if (!n) print "FINDING\t-\tno criteria between the markers"
      else if (n > 7) print "FINDING\t-\t" n " criteria — more than seven; split the Story (agents/analyst.md, \"What you don’t handle\")"
      else if (n < 4) print "WARN\t-\t" n " criteria — the Analyst writes four to seven; check that none is missing"
    }'
}

# PR description → "TEST\t<id>\t<name>", "MUT\t<id>\t<result>", "DEC\t<id>\t<decision>", "FINDING…".
links() {
  tr -d '\r' < "$1" | awk -v P="$PROOF_HEADING" -v M="$MUTATION_HEADING" -v D="$DECISION_HEADING" '
    function trim(v) { gsub(/^[[:space:]`]+|[[:space:]`]+$/, "", v); return v }
    function blank(v) { v = trim(v); return v == "" || v ~ /^<.*>$/ }
    {
      line = $0
      if (incomment) { if (index(line, "-->")) { incomment = 0; line = substr(line, index(line, "-->") + 3) } else next }
      while (index(line, "<!--")) {
        pre = substr(line, 1, index(line, "<!--") - 1); rest = substr(line, index(line, "<!--") + 4)
        if (index(rest, "-->")) line = pre substr(rest, index(rest, "-->") + 3)
        else { line = pre; incomment = 1 }
      }
    }
    /^## / { sec = index($0, P) == 1 ? "P" : index($0, M) == 1 ? "M" : index($0, D) == 1 ? "D" : ""; next }
    sec == "" || line !~ /^[[:space:]]*[-*][[:space:]]+K-[0-9]+/ { next }
    {
      s = line; sub(/^[[:space:]]*[-*][[:space:]]+/, "", s)
      id = s; sub(/[^A-Za-z0-9-].*/, "", id); rest = substr(s, length(id) + 1)
      SEP = "^[[:space:]]+(—|–|-)[[:space:]]+"
      if (sec == "P" && match(rest, SEP "test:")) {
        v = substr(rest, RLENGTH + 1); if (!blank(v)) { print "TEST\t" id "\t" trim(v); next }
      } else if (sec == "M" && match(rest, SEP "removed:")) {
        v = substr(rest, RLENGTH + 1)
        if (match(v, /[[:space:]]+(—|–|-)[[:space:]]+result:/)) {
          mech = substr(v, 1, RSTART - 1); res = substr(v, RSTART + RLENGTH)
          if (!blank(mech) && !blank(res)) { print "MUT\t" id "\t" trim(res); next }
        }
      } else if (sec == "D" && match(rest, SEP "decision:")) {
        v = substr(rest, RLENGTH + 1); if (!blank(v)) { print "DEC\t" id "\t" trim(v); next }
      }
      want = sec == "P" ? "- K-<n> — test: <name>" : sec == "M" ? "- K-<n> — removed: <mechanism> — result: <killed … / SURVIVED …>" : "- K-<n> — decision: <the human’s decision>"
      print "FINDING\t" id "\ta line not in the format \"" want "\": " trim(line)
    }'
}

report() {  # report <records file> → prints, sets the exit code
  local findings warns
  findings=$(grep -c '^FINDING' "$1" || true); warns=$(grep -c '^WARN' "$1" || true)
  awk -F '\t' '$1 == "FINDING" { printf "FINDING  %-6s %s\n", $2, $3 } $1 == "WARN" { printf "WARN     %-6s %s\n", $2, $3 }' "$1"
  echo "evidence chain: $(grep -c '^CRIT' "$1" || true) criteria, $findings finding(s), $warns warning(s)"
  [ "$findings" -eq 0 ]
}

lint() {
  [ $# -eq 1 ] || usage; readable "$1"
  local tmp; tmp="$(mktemp -d)"
  if [ "$1" = "-" ]; then cat > "$tmp/issue"; else cat "$1" > "$tmp/issue"; fi
  criteria "$tmp/issue" > "$tmp/rec"
  local code=0; report "$tmp/rec" || code=1
  rm -rf "$tmp"; exit "$code"
}

chain() {
  [ $# -ge 2 ] || usage
  local issue="$1" pr="$2" repo=""; shift 2
  while [ $# -gt 0 ]; do
    case "$1" in --repo) [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;; *) usage ;; esac
  done
  [ "$issue" != "-" ] && [ "$pr" != "-" ] || usage
  readable "$issue"; readable "$pr"
  [ -n "$repo" ] || repo="."
  git -C "$repo" rev-parse --show-toplevel > /dev/null 2>&1 || { echo "evidence-chain: '$repo' is not a git repository" >&2; exit 2; }

  local tmp; tmp="$(mktemp -d)"
  criteria "$issue" > "$tmp/rec"
  links "$pr" > "$tmp/links"
  grep '^FINDING' "$tmp/links" >> "$tmp/rec" || true
  ( cd "$(git -C "$repo" rev-parse --show-toplevel)" && git ls-files | grep -E "$TEST_PATH_RE" || true ) > "$tmp/tests"
  local root; root="$(git -C "$repo" rev-parse --show-toplevel)"

  local kind id judge name res
  # Each criterion: its links.
  while IFS=$'\t' read -r kind id judge; do
    [ "$kind" = "CRIT" ] || continue
    if [ "$judge" = "test" ]; then
      grep -q "^TEST	$id	" "$tmp/links" || printf 'FINDING\t%s\tjudged by a test, but the PR names no test for it (%s)\n' "$id" "$PROOF_HEADING" >> "$tmp/rec"
      if grep -q "^MUT	$id	" "$tmp/links"; then
        while IFS=$'\t' read -r _ _ res; do
          case "$(printf '%s' "$res" | tr '[:upper:]' '[:lower:]')" in
            killed*) ;;
            survived*) printf 'FINDING\t%s\tthe mutation SURVIVED — its test does not prove the criterion: %s\n' "$id" "$res" >> "$tmp/rec" ;;
            *) printf 'FINDING\t%s\ta mutation result that is neither "killed" nor "SURVIVED": %s\n' "$id" "$res" >> "$tmp/rec" ;;
          esac
        done < <(grep "^MUT	$id	" "$tmp/links")
      else
        printf 'FINDING\t%s\tjudged by a test, but the PR has no mutation for it (%s)\n' "$id" "$MUTATION_HEADING" >> "$tmp/rec"
      fi
    elif [ "$judge" = "human" ]; then
      grep -q "^DEC	$id	" "$tmp/links" || printf 'FINDING\t%s\tjudged by a human, but the PR records no decision (%s)\n' "$id" "$DECISION_HEADING" >> "$tmp/rec"
    fi
  done < "$tmp/rec"

  # Each link: its criterion, and each named test: a test file that contains it.
  while IFS=$'\t' read -r kind id name; do
    case "$kind" in TEST|MUT|DEC) ;; *) continue ;; esac
    grep -q "^CRIT	$id	" "$tmp/rec" || printf 'FINDING\t%s\tthe PR links a criterion the Issue does not have\n' "$id" >> "$tmp/rec"
    if [ "$kind" = "TEST" ]; then
      local found=""
      if [ -s "$tmp/tests" ]; then
        found=$(cd "$root" && tr '\n' '\0' < "$tmp/tests" | xargs -0 grep -lF -- "$name" 2>/dev/null | head -n 1 || true)
      fi
      [ -n "$found" ] || printf 'FINDING\t%s\tnames test "%s", which no test file contains\n' "$id" "$name" >> "$tmp/rec"
    fi
  done < "$tmp/links"

  local code=0; report "$tmp/rec" || code=1
  rm -rf "$tmp"; exit "$code"
}

self_test() {
  local self root failures=0 total=0
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  root="$(mktemp -d)"
  trap - ERR
  set +e

  crit() {  # crit <id> <judged by> [<claim>]
    # A leading newline and no trailing one: $(…) strips trailing newlines and would glue criteria.
    printf '\n### %s — %s\n**Boundary:** tenant\n**Observable:** test\n**Contrast:** another tenant sees it\n**Mutation that must kill it:** drop the tenant filter\n**Edges:** none\n**Foundation:** verified\n**Judged by:** %s' \
      "$1" "${3:-the guest sees only their bookings}" "$2"
  }
  issue() {  # issue <criteria text> → a full Issue body
    printf '### Definition of done\nCancel works.\n\n### Out of scope\nRefunds.\n\n### Acceptance criteria\n<!-- criteria:start -->%s\n<!-- criteria:end -->\n' "$1"
  }
  local FOUR; FOUR="$(crit K-01 test)$(crit K-02 'human — whether the message sounds courteous')$(crit K-03 test)$(crit K-04 test)"
  local PR_OK='Refs #7

## Definition of done — proof

<!--
- K-09 — test: inside a comment is ignored
-->
- Condition: Cancel works.
- K-01 — test: `cancel frees the room`
- K-03 — test: refund quote rounds half-up
- K-04 — test: long note is cut at 500

## Mutation

- K-01 — removed: the tenant filter — result: killed, 2 tests failed
- K-03 — removed: the rounding call — result: Killed, 1 test failed
- K-04 — removed: the length cap — result: killed, 1 test failed

## Undecidable — the human'"'"'s decisions

- K-02 — decision: accepted as written, @anna
'
  # A throwaway repository with one test file.
  git init -q "$root/repo"; git -C "$root/repo" config core.autocrlf false
  mkdir -p "$root/repo/test"
  printf "it('cancel frees the room')\nit('refund quote rounds half-up')\nit('long note is cut at 500')\n" > "$root/repo/test/cancel.test.js"
  printf "cancel frees the room is also a string here\n" > "$root/repo/notes.md"
  git -C "$root/repo" add -A

  # expect <name> <expected exit> <output must contain> -- <args…>
  expect() {
    local name="$1" want="$2" must="$3"; shift 4
    total=$((total + 1))
    local out code; out="$(bash "$self" "$@" 2>&1)"; code=$?
    if [ "$code" -ne "$want" ]; then echo "FAIL $name — expected exit $want, got $code: $out"; failures=$((failures + 1))
    elif [ -n "$must" ] && [[ "$out" != *"$must"* ]]; then echo "FAIL $name — output lacks '$must': $out"; failures=$((failures + 1))
    else echo "ok   $name"; fi
  }
  lint_case() {  # lint_case <name> <exit> <must> <criteria text>
    issue "$4" > "$root/issue.md"; expect "$1" "$2" "$3" -- lint "$root/issue.md"
  }
  chain_case() {  # chain_case <name> <exit> <must> <criteria text> <pr body>
    issue "$4" > "$root/issue.md"; printf '%s' "$5" > "$root/pr.md"
    expect "$1" "$2" "$3" -- chain "$root/issue.md" "$root/pr.md" --repo "$root/repo"
  }

  # Lint: what must pass.
  lint_case "four complete criteria pass"            0 "4 criteria, 0 finding(s), 0 warning(s)" "$FOUR"
  lint_case "an amendment line inside the block passes" 0 "0 finding(s)" "$FOUR"$'\n''Amended at gate 2, 2026-10-14, A-02: the note is cut, not refused'
  lint_case "three criteria is only a warning"       0 "WARN     -      3 criteria" "$(crit K-01 test)$(crit K-02 test)$(crit K-03 test)"
  total=$((total + 1))
  issue "$FOUR" | sed 's/$/\r/' > "$root/crlf.md"
  if bash "$self" lint "$root/crlf.md" > /dev/null 2>&1; then echo "ok   CRLF line endings pass"; else echo "FAIL CRLF line endings pass"; failures=$((failures + 1)); fi

  # Lint: each finding.
  lint_case "an empty criteria block"                1 "no criteria between the markers" ""
  total=$((total + 1))
  printf '### Definition of done\nx\n' > "$root/nomark.md"
  out="$(bash "$self" lint "$root/nomark.md" 2>&1)"
  [ $? -eq 1 ] && [[ "$out" == *"never written"* ]] && echo "ok   a body with no block at all" || { echo "FAIL a body with no block at all: $out"; failures=$((failures + 1)); }
  lint_case "a missing contrast"                     1 "K-03   no contrast" "$(crit K-01 test)$(crit K-02 test)$(crit K-03 test | grep -v Contrast)$(crit K-04 test)"
  lint_case "a placeholder mutation"                 1 "K-02   no mutation" "$(crit K-01 test)$(crit K-02 test | sed 's/\(must kill it:\*\*\).*/\1 <what to remove>/')$(crit K-03 test)$(crit K-04 test)"
  lint_case "no Judged by"                           1 "K-04   no \"Judged by\"" "$(crit K-01 test)$(crit K-02 test)$(crit K-03 test)$(crit K-04 test | grep -v Judged)"
  lint_case "Judged by neither test nor human"       1 "neither test nor human" "$(crit K-01 test)$(crit K-02 'the PO')$(crit K-03 test)$(crit K-04 test)"
  lint_case "human with no reason"                   1 "with no reason" "$(crit K-01 test)$(crit K-02 human)$(crit K-03 test)$(crit K-04 test)"
  lint_case "a duplicate ID"                         1 "K-03   the ID is used twice" "$(crit K-01 test)$(crit K-03 test)$(crit K-03 test)$(crit K-04 test)"
  lint_case "a heading without a claim"              1 "no claim in the heading" "$(crit K-01 test)$(crit K-02 test ' ')$(crit K-03 test)$(crit K-04 test)"
  lint_case "a heading that is not a criterion"      1 "is not \"### K-<n>" "$(crit K-01 test)"$'\n'"### Notes$(crit K-03 test)$(crit K-04 test)"
  lint_case "eight criteria: split the Story"        1 "split the Story" "$FOUR$(crit K-05 test)$(crit K-06 test)$(crit K-07 test)$(crit K-08 test)"
  total=$((total + 1))
  issue "$FOUR" | sed '/criteria:end/d' > "$root/open.md"
  out="$(bash "$self" lint "$root/open.md" 2>&1)"
  [ $? -eq 1 ] && [[ "$out" == *"without"* ]] && echo "ok   an unclosed block" || { echo "FAIL an unclosed block: $out"; failures=$((failures + 1)); }

  # Chain: the clean one, and each broken link.
  chain_case "a clean chain holds"                   0 "4 criteria, 0 finding(s)" "$FOUR" "$PR_OK"
  chain_case "a criterion with no test"              1 "K-04   judged by a test, but the PR names no test" "$FOUR" "${PR_OK/- K-04 — test: long note is cut at 500/}"
  chain_case "a test that does not exist"            1 "names test \"cancel frees the slot\"" "$FOUR" "${PR_OK/cancel frees the room/cancel frees the slot}"
  chain_case "a name found only outside test files"  1 "which no test file contains" "$FOUR" "${PR_OK/refund quote rounds half-up/cancel frees the room is also}"
  chain_case "a criterion with no mutation"          1 "K-03   judged by a test, but the PR has no mutation" "$FOUR" "${PR_OK/- K-03 — removed: the rounding call — result: Killed, 1 test failed/}"
  chain_case "a mutation that survived"              1 "K-04   the mutation SURVIVED" "$FOUR" "${PR_OK/the length cap — result: killed, 1 test failed/the length cap — result: SURVIVED — the cap is also in the DB}"
  chain_case "a result that is neither"              1 "neither \"killed\" nor \"SURVIVED\"" "$FOUR" "${PR_OK/result: killed, 2 tests failed/result: looks fine}"
  chain_case "a human criterion with no decision"    1 "K-02   judged by a human, but the PR records no decision" "$FOUR" "${PR_OK/- K-02 — decision: accepted as written, @anna/None}"
  chain_case "an orphan mutation"                    1 "K-07   the PR links a criterion the Issue does not have" "$FOUR" "${PR_OK/- K-04 — removed:/- K-07 — removed: x — result: killed, 1 test failed
- K-04 — removed:}"
  chain_case "an orphan test line"                   1 "K-08   the PR links a criterion" "$FOUR" "${PR_OK/- Condition: Cancel works./- K-08 — test: cancel frees the room}"
  chain_case "a malformed line in a section"         1 "a line not in the format" "$FOUR" "${PR_OK/- K-01 — removed: the tenant filter — result: killed, 2 tests failed/- K-01 removed the tenant filter, 2 failed}"
  chain_case "a lint finding fails the chain too"    1 "K-03   no contrast" "$(crit K-01 test)$(crit K-02 'human — courteous')$(crit K-03 test | grep -v Contrast)$(crit K-04 test)" "$PR_OK"

  # Must fail the check itself, never read as "holds".
  issue "$FOUR" > "$root/issue.md"; printf '%s' "$PR_OK" > "$root/pr.md"; mkdir -p "$root/plain"
  local name
  for name in "missing file" "no arguments" "unknown mode" "not a git repository" "standard input for chain"; do
    total=$((total + 1))
    case "$name" in
      "missing file")         bash "$self" lint "$root/none.md" >/dev/null 2>&1 ;;
      "no arguments")         bash "$self" >/dev/null 2>&1 ;;
      "unknown mode")         bash "$self" check "$root/issue.md" >/dev/null 2>&1 ;;
      "not a git repository") bash "$self" chain "$root/issue.md" "$root/pr.md" --repo "$root/plain" >/dev/null 2>&1 ;;
      "standard input for chain") bash "$self" chain - "$root/pr.md" < "$root/issue.md" >/dev/null 2>&1 ;;
    esac
    [ $? -eq 2 ] && echo "ok   $name fails the check" || { echo "FAIL $name fails the check"; failures=$((failures + 1)); }
  done

  # Standard input reads the same as a file for lint.
  total=$((total + 1))
  issue "$FOUR" | bash "$self" lint - > /dev/null 2>&1 && echo "ok   lint reads standard input" || { echo "FAIL lint reads standard input"; failures=$((failures + 1)); }

  rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  lint) shift; lint "$@" ;;
  chain) shift; chain "$@" ;;
  *) usage ;;
esac
