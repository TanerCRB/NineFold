#!/usr/bin/env bash
# markers.sh — read the machine-readable parts of role reports and Issue comments.
#
# Copy into the product repository (e.g. scripts/markers.sh). Two modes:
#
#   scripts/markers.sh verdict .task/handoff/11-qa-1.md         # one evaluating role's report
#   gh issue view <N> --json comments --jq '.comments[].body' \
#     | scripts/markers.sh events -                             # the task's phase events
#   scripts/markers.sh --self-test                              # built-in cases
#
# VERDICT reads the verdict block every evaluating role ends its report with (team contract, §3a):
#
#   ```verdict
#   role: qa | invariant-guardian | reviewer | security-auditor
#   verdict: <the role's main verdict, as in its report format>
#   undecidable: K-02, K-04 | none
#   findings: critical 0, high 0, medium 1, low 0
#   sha: <the SHA the role read>
#   ```
#
# (a "~~~verdict" fence works the same). It prints one line — role, verdict, undecidable,
# critical/high/medium/low, sha, tab-separated — and checks:
#   - exactly one block, at the end of the report, with every field, each value valid for the role;
#   - the block against the prose: the "**Verdict: …**" line names the same main verdict and the
#     same UNDECIDABLE items, and (for all roles but QA) the "## X-01 — High — …" finding headings
#     add up to the same counts;
#   - the block against the contract: a high or medium finding with PASS (Guardian, Reviewer), a
#     critical or high one without STOP or a medium one with PASS (Security Auditor), a STOP with
#     nothing counted, a critical finding from a role that has no such severity.
# A block that contradicts the prose is a role failure, not a parsing problem: the report goes
# back to the role, and the prose is never "corrected" to fit.
#
# EVENTS reads the hidden markers the task command puts on the Issue, one per phase event:
#
#   <!-- ninefold:event=<name> sha=<SHA> [<key>=<value> …] -->
#
# Events and their required keys: task-started, task-stopped, verified, gate-reached (gate=1|2|3),
# scope-locked (gate=1|2, hash), verdict (role, verdict, undecidable, findings), reverify (round).
# Values have no spaces (verdict=pass-with-reservations, undecidable=K-02,K-04 or none,
# findings=0,0,1,0). It prints one line per event, oldest first — name, sha, the other keys — and
# skips markers in quoted lines ("> …") and in code blocks, so a quoted comment never counts as
# the event happening twice. A marker that is malformed or names an unknown event is a finding.
#
# Exit codes: 0 = everything read and consistent, 1 = a finding (on stderr), 2 = the check itself
# failed (a missing file, a bad argument) — never read that as "consistent".

set -Eeuo pipefail
trap 'echo "markers: the check itself failed (line $LINENO)" >&2; exit 2' ERR

usage() { echo "usage: $0 verdict <report|-> | events <comments|-> | --self-test" >&2; exit 2; }

input() {  # input <file|-> → a temporary copy without CR, path on stdout
  local tmp; tmp="$(mktemp)"
  if [ "$1" = "-" ]; then tr -d '\r' > "$tmp"
  else [ -r "$1" ] || { rm -f "$tmp"; echo "markers: cannot read '$1'" >&2; exit 2; }; tr -d '\r' < "$1" > "$tmp"; fi
  echo "$tmp"
}

read -r -d '' VERDICT_AWK <<'AWK' || true
function trim(v) { gsub(/^[[:space:]*]+|[[:space:]*]+$/, "", v); return v }
function normlist(v,   n, a, i, out, seen) {
  v = trim(v); if (tolower(v) == "none" || v == "") return "none"
  n = split(v, a, /[[:space:],]+/); out = ""
  for (i = 1; i <= n; i++) if (a[i] != "" && !seen[a[i]]++) out = out (out == "" ? "" : ",") a[i]
  # sort, so the order of items never makes a mismatch
  n = split(out, a, ","); for (i = 2; i <= n; i++) { x = a[i]; j = i - 1; while (j > 0 && a[j] > x) { a[j + 1] = a[j]; j-- } a[j + 1] = x }
  out = a[1]; for (i = 2; i <= n; i++) out = out "," a[i]
  return out
}
function bad(msg) { print "markers: " msg > "/dev/stderr"; fails++ }
{ lines[NR] = $0 }
/^(```|~~~)verdict[[:space:]]*$/ && !inblock { blocks++; inblock = 1; fence = substr($0, 1, 3); next }
inblock && index($0, fence) == 1 && trim(substr($0, 4)) == "" { inblock = 0; closed = NR; next }
inblock {
  if (blocks > 1) next
  if (match($0, /^[a-z]+:/)) { k = substr($0, 1, RLENGTH - 1); v = trim(substr($0, RLENGTH + 1)); field[k] = v; next }
  if (trim($0) != "") bad("a line in the verdict block that is not \"<field>: <value>\": " $0)
  next
}
blocks == 0 && /^\*\*Verdict:/ && prose == "" { prose = $0 }
/^## [A-Z]+-[0-9]+[[:space:]]+(—|–|-)[[:space:]]+(Critical|High|Medium|Low|critical|high|medium|low)([[:space:]]|$)/ {
  s = $0; sub(/^## [A-Z]+-[0-9]+[[:space:]]+(—|–|-)[[:space:]]+/, "", s); sub(/[[:space:]].*/, "", s); count[tolower(s)]++
}
END {
  if (blocks == 0) { bad("no verdict block — the report must end with one (team contract, §3a)"); exit 1 }
  if (blocks > 1)  bad(blocks " verdict blocks — a report has exactly one")
  if (inblock)     { bad("the verdict block is never closed"); exit 1 }
  for (i = closed + 1; i <= NR; i++) if (trim(lines[i]) != "") { bad("the verdict block is not at the end of the report"); break }

  role = field["role"]; verdict = field["verdict"]
  if (role !~ /^(qa|invariant-guardian|reviewer|security-auditor)$/) bad("role is missing or unknown: \"" role "\"")
  allowed["qa"] = "|PROOF HOLDS|PROOF IS EMPTY|"
  allowed["invariant-guardian"] = "|PASS|STOP|"; allowed["reviewer"] = "|PASS|STOP|"
  allowed["security-auditor"] = "|PASS|PASS WITH RESERVATIONS|STOP|"
  if (verdict == "") bad("verdict is missing")
  else if (role in allowed && index(allowed[role], "|" verdict "|") == 0) bad("verdict \"" verdict "\" is not one the " role " gives")
  if (!("undecidable" in field)) bad("undecidable is missing — write \"none\" when there is nothing")
  und = normlist(field["undecidable"])
  f = field["findings"]; ok = 1
  split("critical high medium low", sev, " ")
  for (i = 1; i <= 4; i++) {
    if (match(f, sev[i] "[[:space:]]+[0-9]+")) { n = substr(f, RSTART, RLENGTH); sub(/^[a-z]+[[:space:]]+/, "", n); c[sev[i]] = n + 0 }
    else ok = 0
  }
  if (!ok) bad("findings must count critical, high, medium and low: \"" f "\"")
  sha = field["sha"]
  if (sha !~ /^[0-9a-f]+$/ || length(sha) < 7 || length(sha) > 40) bad("sha is missing or not a commit SHA: \"" sha "\"")

  # The block against the prose.
  if (prose == "") bad("no \"**Verdict: …**\" line in the prose to compare the block with")
  else {
    pv = prose; sub(/^\*\*Verdict:[[:space:]]*/, "", pv); pu = pv
    sub(/\*\*.*/, "", pv); sub(/[[:space:]]+(—|–|-)[[:space:]].*/, "", pv); sub(/[[:space:]]*\(.*/, "", pv); pv = trim(pv)
    if (verdict != "" && pv != verdict) bad("the block says \"" verdict "\", the prose says \"" pv "\"")
    pund = "none"
    if (match(pu, /UNDECIDABLE:[^*]*/)) { pund = substr(pu, RSTART + 12, RLENGTH - 12); pund = normlist(pund) }
    if (und != pund) bad("the block lists undecidable \"" und "\", the prose \"" pund "\"")
  }
  if (ok && role != "qa" && role != "") for (i = 1; i <= 4; i++)
    if (c[sev[i]] != count[sev[i]] + 0) bad("the block counts " c[sev[i]] " " sev[i] ", the report has " count[sev[i]] + 0 " such finding(s)")

  # The block against the contract (§3a).
  if (ok) {
    if (role == "invariant-guardian" || role == "reviewer") {
      if (c["critical"] > 0) bad("the " role " has no critical severity")
      if (verdict == "PASS" && c["high"] + c["medium"] > 0) bad("PASS with a high or medium finding — one is enough for STOP")
      if (verdict == "STOP" && c["high"] + c["medium"] == 0) bad("STOP with no high or medium finding counted")
    } else if (role == "security-auditor") {
      if (verdict != "STOP" && c["critical"] + c["high"] > 0) bad("a critical or high finding without STOP")
      if (verdict == "PASS" && c["medium"] > 0) bad("PASS with a medium finding — that is PASS WITH RESERVATIONS")
      if (verdict == "STOP" && c["critical"] + c["high"] == 0) bad("STOP with no critical or high finding counted")
    }
  }
  if (fails) exit 1
  printf "%s\t%s\t%s\t%d/%d/%d/%d\t%s\n", role, verdict, und, c["critical"], c["high"], c["medium"], c["low"], sha
}
AWK

read -r -d '' EVENTS_AWK <<'AWK' || true
function bad(msg) { print "markers: " msg > "/dev/stderr"; fails++ }
/^[[:space:]]*(```|~~~)/ { code = !code; next }
code || /^[[:space:]]*>/ { next }
{
  line = $0
  while ((p = index(line, "<!-- ninefold:")) > 0) {
    rest = substr(line, p + 5); q = index(rest, "-->")
    if (!q) { bad("a marker that is never closed: " $0); break }
    body = substr(rest, 1, q - 1); line = substr(rest, q + 3)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", body)
    n = split(body, t, /[[:space:]]+/)
    if (t[1] !~ /^ninefold:event=[a-z-]+$/) { bad("a marker that is not \"ninefold:event=<name> …\": " body); continue }
    name = substr(t[1], 16); delete kv; extra = ""; okm = 1
    for (i = 2; i <= n; i++) {
      if (t[i] !~ /^[a-z]+=[A-Za-z0-9._,:\/-]+$/) { bad("a key=value that isn't one, in " body); okm = 0; continue }
      k = substr(t[i], 1, index(t[i], "=") - 1); kv[k] = substr(t[i], index(t[i], "=") + 1)
      if (k != "sha") extra = extra (extra == "" ? "" : " ") t[i]
    }
    if (!okm) continue
    need = ""
    if (name == "gate-reached") need = "gate"
    else if (name == "scope-locked") need = "gate hash"
    else if (name == "verdict") need = "role verdict undecidable findings"
    else if (name == "reverify") need = "round"
    else if (name !~ /^(task-started|task-stopped|verified)$/) { bad("an unknown event \"" name "\""); continue }
    if (!("sha" in kv) || kv["sha"] !~ /^[0-9a-f]+$/ || length(kv["sha"]) < 7 || length(kv["sha"]) > 40) { bad("event " name " without a commit sha"); continue }
    m = split(need, req, " "); miss = ""
    for (i = 1; i <= m; i++) if (!(req[i] in kv)) miss = miss " " req[i]
    if (miss != "") { bad("event " name " is missing:" miss); continue }
    if (name == "gate-reached" && kv["gate"] !~ /^[123]$/) { bad("gate-reached with gate=" kv["gate"]); continue }
    if (name == "scope-locked" && kv["gate"] !~ /^[12]$/) { bad("scope-locked with gate=" kv["gate"]); continue }
    printf "%s\t%s\t%s\n", name, kv["sha"], extra
  }
}
END { if (fails) exit 1 }
AWK

run() {
  [ $# -eq 2 ] || usage
  local prog
  case "$1" in verdict) prog="$VERDICT_AWK" ;; events) prog="$EVENTS_AWK" ;; *) usage ;; esac
  local f code=0; f="$(input "$2")"
  awk "$prog" "$f" || code=$?
  rm -f "$f"
  [ "$code" -le 1 ] || exit 2
  exit "$code"
}

self_test() {
  local self root failures=0 total=0
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  root="$(mktemp -d)"
  trap - ERR
  set +e
  local SHA=4f1c2a9e0b

  # expect <name> <exit> <text the output must contain> <mode> <input text>
  expect() {
    local name="$1" want="$2" must="$3" mode="$4" out code
    total=$((total + 1))
    printf '%s' "$5" > "$root/in.md"
    out="$(bash "$self" "$mode" "$root/in.md" 2>&1)"; code=$?
    if [ "$code" -ne "$want" ]; then echo "FAIL $name — expected exit $want, got $code: $out"; failures=$((failures + 1))
    elif [ -n "$must" ] && [[ "$out" != *"$must"* ]]; then echo "FAIL $name — output lacks '$must': $out"; failures=$((failures + 1))
    else echo "ok   $name"; fi
  }
  block() {  # block <role> <verdict> <undecidable> <c> <h> <m> <l>
    printf '```verdict\nrole: %s\nverdict: %s\nundecidable: %s\nfindings: critical %s, high %s, medium %s, low %s\nsha: %s\n```\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$SHA"
  }
  local REV_PROSE='# Review — B1-07 — 2026-10-14

**Verdict: STOP** — **UNDECIDABLE: K-04**
Basis: diff at 4f1c2a9

## R-01 — High — the retry double-charges
**Location:** `pay.js:40`

## R-02 — Low — a comment drifted
'
  local QA_PROSE='# QA — B1-07 — 2026-10-14

**Verdict: PROOF HOLDS** — **UNDECIDABLE: K-02, K-04**
Basis: checkpoint 4f1c2a9
'

  # Valid blocks.
  expect "a valid Reviewer block"                    0 "reviewer	STOP	K-04	0/1/0/1	$SHA" verdict "$REV_PROSE
$(block reviewer STOP K-04 0 1 0 1)"
  expect "a valid QA block, items in another order"  0 "qa	PROOF HOLDS	K-02,K-04" verdict "$QA_PROSE
$(block qa 'PROOF HOLDS' 'K-04, K-02' 0 0 0 0)"
  expect "a tilde fence works the same"              0 "qa	PROOF HOLDS" verdict "$QA_PROSE
$(block qa 'PROOF HOLDS' 'K-02, K-04' 0 0 0 0 | sed 's/```/~~~/')"
  expect "a mixed Auditor report: reservations"      0 "security-auditor	PASS WITH RESERVATIONS	none	0/0/1/2" verdict "**Verdict: PASS WITH RESERVATIONS**

## B-01 — Medium — the token lives a day
## B-02 — Low — x
## B-03 — Low — y
$(block security-auditor 'PASS WITH RESERVATIONS' none 0 0 1 2)"
  expect "QA's 'what is missing' after the verdict"  0 "PROOF IS EMPTY" verdict "**Verdict: PROOF IS EMPTY — K-03 has no contrast**
$(block qa 'PROOF IS EMPTY' none 0 0 0 0)"

  # The block itself.
  expect "no block"                                  1 "no verdict block" verdict "$REV_PROSE"
  expect "a missing field"                           1 "sha is missing" verdict "$REV_PROSE
$(block reviewer STOP K-04 0 1 0 1 | grep -v '^sha:')"
  expect "no undecidable field"                      1 "undecidable is missing" verdict "$REV_PROSE
$(block reviewer STOP K-04 0 1 0 1 | grep -v '^undecidable:')"
  expect "findings that don't count all four"        1 "findings must count" verdict "$REV_PROSE
$(block reviewer STOP K-04 0 1 0 1 | sed 's/, low 1//')"
  expect "two blocks in one report"                  1 "2 verdict blocks" verdict "$REV_PROSE
$(block reviewer STOP K-04 0 1 0 1)
$(block reviewer STOP K-04 0 1 0 1)"
  expect "a block not at the end"                    1 "not at the end" verdict "$(block reviewer STOP K-04 0 1 0 1)
$REV_PROSE"
  expect "an unknown role"                           1 "role is missing or unknown" verdict "$REV_PROSE
$(block architect STOP K-04 0 1 0 1)"
  expect "a verdict the role doesn't give"           1 "is not one the qa gives" verdict "**Verdict: PASS**
$(block qa PASS none 0 0 0 0)"

  # The block against the prose.
  expect "block and prose disagree on the verdict"   1 "the block says \"PASS\", the prose says \"STOP\"" verdict "$REV_PROSE
$(block reviewer PASS K-04 0 0 0 1)"
  expect "block and prose disagree on undecidable"   1 "the block lists undecidable \"none\"" verdict "$REV_PROSE
$(block reviewer STOP none 0 1 0 1)"
  expect "block counts differ from the headings"     1 "counts 2 high, the report has 1" verdict "$REV_PROSE
$(block reviewer STOP K-04 0 2 0 1)"

  # The block against the contract.
  expect "PASS with a medium finding (Guardian)"     1 "PASS with a high or medium finding" verdict "**Verdict: PASS**
## S-01 — Medium — rule 4 — x
$(block invariant-guardian PASS none 0 0 1 0)"
  expect "STOP with nothing counted (Reviewer)"      1 "STOP with no high or medium" verdict "**Verdict: STOP**
$(block reviewer STOP none 0 0 0 0)"
  expect "Auditor high without STOP"                 1 "critical or high finding without STOP" verdict "**Verdict: PASS WITH RESERVATIONS**
## B-01 — High — x
$(block security-auditor 'PASS WITH RESERVATIONS' none 0 1 0 0)"
  expect "Auditor medium with PASS"                  1 "that is PASS WITH RESERVATIONS" verdict "**Verdict: PASS**
## B-01 — Medium — x
$(block security-auditor PASS none 0 0 1 0)"

  # Events.
  local E1="Task started — session: s1
<!-- ninefold:event=task-started sha=$SHA -->"
  expect "events are listed in order"                0 "task-started	$SHA	" events "$E1
Gate 1 reached
<!-- ninefold:event=gate-reached sha=$SHA gate=1 -->
<!-- ninefold:event=verdict sha=$SHA role=qa verdict=proof-holds undecidable=K-02,K-04 findings=0,0,0,0 -->"
  expect "a verdict event keeps its keys"            0 "role=qa verdict=proof-holds undecidable=K-02,K-04 findings=0,0,0,0" events "<!-- ninefold:event=verdict sha=$SHA role=qa verdict=proof-holds undecidable=K-02,K-04 findings=0,0,0,0 -->"
  expect "a marker inside a quoted comment is skipped" 0 "" events "> <!-- ninefold:event=gate-reached sha=$SHA gate=1 -->
plain text"
  total=$((total + 1))
  printf '> <!-- ninefold:event=gate-reached sha=%s gate=1 -->\n```\n<!-- ninefold:event=gate-reached sha=%s gate=2 -->\n```\n' "$SHA" "$SHA" > "$root/q.md"
  [ -z "$(bash "$self" events "$root/q.md" 2>&1)" ] && echo "ok   quoted and fenced markers print nothing" || { echo "FAIL quoted and fenced markers print nothing"; failures=$((failures + 1)); }
  expect "a gate event without its gate"             1 "missing: gate" events "<!-- ninefold:event=gate-reached sha=$SHA -->"
  expect "a gate that doesn't exist"                 1 "gate-reached with gate=4" events "<!-- ninefold:event=gate-reached sha=$SHA gate=4 -->"
  expect "an event without a sha"                    1 "without a commit sha" events "<!-- ninefold:event=verified -->"
  expect "an unknown event"                          1 "unknown event \"merged\"" events "<!-- ninefold:event=merged sha=$SHA -->"
  expect "a value with a space"                      1 "a key=value that isn't one" events "<!-- ninefold:event=verdict sha=$SHA role=qa verdict=proof holds undecidable=none findings=0,0,0,0 -->"
  expect "an ordinary HTML comment is not a marker"  0 "" events "<!-- a note -->"

  # Must fail the check itself, never read as "consistent".
  local name
  for name in "missing file" "no arguments" "unknown mode"; do
    total=$((total + 1))
    case "$name" in
      "missing file") bash "$self" verdict "$root/none.md" >/dev/null 2>&1 ;;
      "no arguments") bash "$self" >/dev/null 2>&1 ;;
      "unknown mode") bash "$self" status "$root/in.md" >/dev/null 2>&1 ;;
    esac
    [ $? -eq 2 ] && echo "ok   $name fails the check" || { echo "FAIL $name fails the check"; failures=$((failures + 1)); }
  done
  total=$((total + 1))
  [ "$(printf '%s\n' "$E1" | bash "$self" events - 2>&1)" = "$(printf 'task-started\t%s\t' "$SHA")" ] && echo "ok   standard input reads the same" \
    || { echo "FAIL standard input reads the same"; failures=$((failures + 1)); }

  rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  *) run "$@" ;;
esac
