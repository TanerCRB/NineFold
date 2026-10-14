#!/usr/bin/env bash
# weakening-check.sh — does a change lower the floor the evidence stands on?
#
# Copy into the product repository (e.g. scripts/weakening-check.sh) and run it from the task's
# worktree on a checkpoint, against the base the task branched from:
#
#   scripts/weakening-check.sh origin/main "$CHECKPOINT"    # after the developer checkpoint
#   scripts/weakening-check.sh origin/main "$VERIFIED"      # after the QA checkpoint
#   scripts/weakening-check.sh --self-test                  # built-in contrast cases
#
# It reads `git diff <base>...<head>` — only what the task itself changed — and reports every
# place where the change makes a test harder to fail:
#
#   test-removed        a test file deleted, or renamed to a path that is no longer a test;
#   assertion-removed   a test file loses more assertion lines than it gains;
#   skip-added          a test file gains more skip/only/ignore markers than it loses;
#   suppression-added   any file gains more lint/type/coverage/mutation suppressions than it loses;
#   threshold-lowered   a coverage or mutation threshold in a tool's config goes down, or is
#                       removed without a replacement.
#
# Counting is per file and net: an assertion reformatted or moved inside the same file is a
# removal plus an addition and does not count. Moving assertions to ANOTHER file does count —
# the check can't see that they are the same, and a human answers that in seconds.
#
# Exit codes: 0 = clean, 1 = weakening found (automatic STOP until the human decides),
# 2 = the check itself failed (also STOP — a check that couldn't run must never read as "clean").
#
# A finding is a question for the human, not a verdict: deleting the tests of a removed feature is
# legitimate. What is not legitimate is the same change passing through unseen. The check does not
# accept in-code opt-outs — a marker that silences it would itself be a suppression.
#
# What it does NOT cover, stated so nobody reads it as more: a test made weaker without touching
# any of the patterns below (a looser expected value, a broader matcher, a mocked-out dependency),
# files outside the patterns, and anything git can't diff. Those remain the Reviewer's and QA's
# job; this check only makes the mechanical cases impossible to miss.
#
# The patterns are POSIX extended regular expressions (awk). They are an EXAMPLE covering common
# JavaScript/TypeScript, .NET, Java, Python and Go conventions — adapt them to your stack when you
# copy the script, and keep the self-test cases in step with them.

# ------------------------------------------------------------------------- patterns (adapt)

# Paths that hold tests.
TEST_PATH_RE='(^|/)(test|tests|__tests__|spec|specs)/|[._-](test|tests|spec|specs)\.[A-Za-z0-9]+$|Tests?\.[A-Za-z]+$|(^|/)test_[^/]*\.py$'

# A line that asserts something.
ASSERT_RE='[Aa]ssert|expect\(|\.[Ss]hould|[Vv]erify\(|XCTAssert|t\.(Error|Errorf|Fatal|Fatalf|Fail)\('

# A line that skips a test, or runs only some of them.
SKIP_RE='\.(skip|only|todo)\(|(^|[^A-Za-z0-9_])(xit|xtest|xdescribe|fit|fdescribe)\(|@(Ignore|Disabled)([^A-Za-z0-9_]|$)|\[(Ignore|Explicit)|Skip *=|mark\.(skip|skipif|xfail)|unittest\.skip|\.Skip(f|Now)?\(|#\[ignore\]'

# A line that silences a linter, a type checker, coverage or the mutation tool.
SUPPRESS_RE='eslint-disable|@ts-ignore|@ts-expect-error|@ts-nocheck|# *noqa|# *type: *ignore|pragma: *no *cover|pragma +warning +disable|SuppressMessage|ExcludeFromCodeCoverage|istanbul +ignore|(c8|v8) +ignore|Stryker +disable|nosemgrep|NOSONAR|nolint|@SuppressWarnings|rubocop:disable'

# Config files that can carry a coverage or mutation threshold.
THRESHOLD_FILE_RE='(^|/)(stryker[^/]*\.(json|js|mjs|cjs|conf)|jest\.config[^/]*|vitest\.config[^/]*|\.nycrc[^/]*|\.c8rc[^/]*|karma\.conf[^/]*|codecov\.ya?ml|\.coveragerc|setup\.cfg|pyproject\.toml|tox\.ini|[^/]*\.runsettings|coverlet[^/]*|Directory\.Build\.props|[^/]*\.csproj|package\.json)$'

# A line in such a file that names a threshold (matched case-insensitively).
THRESHOLD_KEY_RE='threshold|break|fail[_-]under|minimum|high|low|lines|branches|functions|statements'

# ------------------------------------------------------------------------------- the check

set -Eeuo pipefail
trap 'echo "weakening-check: the check itself failed (line $LINENO) — treat as STOP" >&2; exit 2' ERR

# The diff parser. Input: `git diff -U0 --find-renames`. One finding per output line:
#   <category>\t<path>:<line>\t<text>
read -r -d '' PARSER <<'AWK' || true
function is_test(p)   { return p ~ ENVIRON["WC_TEST"] }
function strip(p)     { sub(/\t$/, "", p); return p }
function report(cat, path, line, text) {
  gsub(/\t/, " ", text)
  printf "%s\t%s%s\t%s\n", cat, path, (line > 0 ? ":" line : ""), text
}
function key_of(s,    k) {
  k = tolower(s); gsub(/[0-9]+(\.[0-9]+)?/, "#", k); gsub(/[ \t,;]/, "", k); return k
}
# Every number on the line, space-separated: one line can hold several thresholds.
function nums_of(s,    out) {
  out = ""
  while (match(s, /[0-9]+(\.[0-9]+)?/)) {
    out = out (out == "" ? "" : " ") substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
  }
  return out
}
# True when any number in `now` is lower than the number in the same position in `was`.
function lowered(was, now,    w, n, i, c) {
  c = split(was, w, " "); split(now, n, " ")
  for (i = 1; i <= c; i++) if ((n[i] + 0) < (w[i] + 0)) return 1
  return 0
}
# Close one file: turn the per-file counters into findings.
function flush(    i, k, n, used) {
  if (path == "") return
  if (skip_content) { reset(); return }
  if (is_test(path)) {
    if (rem_assert > add_assert) for (i = 1; i <= n_ra; i++) report("assertion-removed", path, ra_line[i], ra_text[i])
    if (add_skip > rem_skip)     for (i = 1; i <= n_as; i++) report("skip-added", path, as_line[i], as_text[i])
  }
  if (add_supp > rem_supp)       for (i = 1; i <= n_ap; i++) report("suppression-added", path, ap_line[i], ap_text[i])
  # Thresholds: pair each removed threshold line with the first unused added line of the same key.
  for (i = 1; i <= n_rt; i++) {
    k = rt_key[i]; used = 0
    for (n = 1; n <= n_at; n++) {
      if (at_used[n] || at_key[n] != k) continue
      at_used[n] = 1; used = 1
      if (lowered(rt_val[i], at_val[n])) report("threshold-lowered", path, at_line[n], rt_text[i] " -> " at_text[n])
      break
    }
    if (!used) report("threshold-lowered", path, rt_line[i], "removed: " rt_text[i])
  }
  reset()
}
function reset() {
  path = ""; skip_content = 0; in_hunk = 0
  rem_assert = add_assert = add_skip = rem_skip = add_supp = rem_supp = 0
  n_ra = n_as = n_ap = n_rt = n_at = 0
  split("", at_used)
}
BEGIN { reset(); old = new = "" }
/^diff --git / { flush(); old = new = ""; deleted = 0; next }
!in_hunk && /^deleted file mode/ { deleted = 1; next }
!in_hunk && /^rename from / { old = substr($0, 13); next }
!in_hunk && /^rename to / {
  new = substr($0, 11); path = new
  if (is_test(old) && !is_test(new)) { report("test-removed", old, 0, "renamed to " new); skip_content = 1 }
  next
}
!in_hunk && /^--- / { if ($0 != "--- /dev/null") old = strip(substr($0, 7)); next }
!in_hunk && /^\+\+\+ / {
  if ($0 == "+++ /dev/null") {
    path = old
    if (deleted && is_test(old)) { report("test-removed", old, 0, "deleted"); skip_content = 1 }
  } else path = strip(substr($0, 7))
  next
}
/^@@ / {
  in_hunk = 1
  split($2, o, ","); oline = substr(o[1], 2) + 0
  split($3, a, ","); nline = substr(a[1], 2) + 0
  next
}
in_hunk && /^-/ {
  t = substr($0, 2)
  if (t ~ ENVIRON["WC_ASSERT"])   { rem_assert++; n_ra++; ra_line[n_ra] = oline; ra_text[n_ra] = t }
  if (t ~ ENVIRON["WC_SKIP"])     rem_skip++
  if (t ~ ENVIRON["WC_SUPPRESS"]) rem_supp++
  if (path ~ ENVIRON["WC_TFILE"] && tolower(t) ~ ENVIRON["WC_TKEY"] && nums_of(t) != "") {
    n_rt++; rt_line[n_rt] = oline; rt_text[n_rt] = t; rt_key[n_rt] = key_of(t); rt_val[n_rt] = nums_of(t)
  }
  oline++; next
}
in_hunk && /^\+/ {
  t = substr($0, 2)
  if (t ~ ENVIRON["WC_ASSERT"])   add_assert++
  if (t ~ ENVIRON["WC_SKIP"])     { add_skip++; n_as++; as_line[n_as] = nline; as_text[n_as] = t }
  if (t ~ ENVIRON["WC_SUPPRESS"]) { add_supp++; n_ap++; ap_line[n_ap] = nline; ap_text[n_ap] = t }
  if (path ~ ENVIRON["WC_TFILE"] && tolower(t) ~ ENVIRON["WC_TKEY"] && nums_of(t) != "") {
    n_at++; at_line[n_at] = nline; at_text[n_at] = t; at_key[n_at] = key_of(t); at_val[n_at] = nums_of(t)
  }
  nline++; next
}
END { flush() }
AWK

check() {
  local base="$1" head="${2:-HEAD}"
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null \
    || { echo "weakening-check: base '$base' is not a commit" >&2; exit 2; }
  git rev-parse --verify --quiet "$head^{commit}" >/dev/null \
    || { echo "weakening-check: head '$head' is not a commit" >&2; exit 2; }

  local findings
  findings="$(mktemp)"
  # core.quotePath=false keeps non-ASCII names readable; a name with a tab or newline would still
  # be quoted by git and reported in quotes.
  git -c core.quotePath=false diff -U0 --no-color --no-ext-diff --find-renames "$base...$head" \
    | WC_TEST="$TEST_PATH_RE" WC_ASSERT="$ASSERT_RE" WC_SKIP="$SKIP_RE" WC_SUPPRESS="$SUPPRESS_RE" \
      WC_TFILE="$THRESHOLD_FILE_RE" WC_TKEY="$THRESHOLD_KEY_RE" awk "$PARSER" > "$findings"

  local count
  count="$(wc -l < "$findings" | tr -d ' ')"
  if [ "$count" -gt 0 ]; then
    while IFS=$'\t' read -r cat where text; do
      printf 'WEAKENING: %-18s %s  %s\n' "$cat" "$where" "$text" >&2
    done < "$findings"
    rm -f "$findings"
    echo "weakening-check: $count finding(s) — $base...$head, automatic STOP until the human decides"
    exit 1
  fi
  rm -f "$findings"
  echo "weakening-check: clean — $base...$head"
}

# ---------------------------------------------------------------------------------- self-test
# Every case is a contrast: it runs the real check against a throwaway repository, and the cases
# that must pass sit next to the ones that must fail, so a pattern made too broad fails as surely
# as one made too narrow.

self_test() {
  local self root failures=0 total=0
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  root="$(mktemp -d)"
  trap - ERR
  set +e

  fresh() {
    rm -rf "$root/repo" && mkdir -p "$root/repo/src" "$root/repo/tests" && cd "$root/repo" || return 1
    git init -q && git config user.email t@t && git config user.name t && git config core.autocrlf false
    printf 'export function price(n) {\n  return n * 2;\n}\n' > src/price.js
    printf 'test("doubles", () => {\n  expect(price(2)).toBe(4);\n  expect(price(0)).toBe(0);\n});\n' > tests/price.test.js
    printf 'other\n' > tests/helper.js
    printf '{\n  "thresholds": { "high": 90, "low": 70, "break": 80 }\n}\n' > stryker.config.json
    printf '{\n  "thresholds": {\n    "high": 90,\n    "low": 70,\n    "break": 80\n  }\n}\n' > stryker.conf.json
    git add -A && git commit -qm base
    BASE="$(git rev-parse HEAD)"
  }
  # expect <name> <expected exit> <change> [<text the output must contain>]
  expect() {
    local name="$1" want="$2" change="$3" must="${4:-}"
    total=$((total + 1))
    fresh
    eval "$change"
    git add -A && git commit -qm change --allow-empty
    local out code
    out="$(bash "$self" "$BASE" HEAD 2>&1)"
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

  # Must pass: ordinary work.
  expect "production change only passes"                 0 "sed -i.bak 's/n \* 2/n + n/' src/price.js && rm src/price.js.bak"
  expect "new test with assertions passes"               0 "printf 'test(\"neg\", () => {\n  expect(price(-1)).toBe(-2);\n});\n' >> tests/price.test.js"
  expect "assertion reformatted in place passes"         0 "printf 'test(\"doubles\", () => {\n  expect(price(2))\n    .toBe(4);\n  expect(price(0)).toBe(0);\n});\n' > tests/price.test.js"
  expect "test renamed inside tests/ passes"             0 "git mv tests/price.test.js tests/pricing.test.js"
  expect "threshold raised passes"                       0 "sed -i.bak 's/\"break\": 80/\"break\": 85/' stryker.conf.json && rm stryker.conf.json.bak"
  expect "a non-test file losing an 'assert' word passes" 0 "printf '// assert nothing here\n' > src/note.js && git add -A && git commit -qm note && BASE=\$(git rev-parse HEAD) && rm src/note.js"

  # Must fail: each category, with the evidence named.
  expect "deleted test file is a finding"                1 "git rm -q tests/price.test.js" "test-removed"
  expect "test renamed out of tests/ is a finding"       1 "git mv tests/price.test.js src/price-check.js" "test-removed"
  expect "removed assertion is a finding"                1 "sed -i.bak '/price(0)/d' tests/price.test.js && rm tests/price.test.js.bak" "tests/price.test.js:3"
  expect "assertion replaced by a comment is a finding"  1 "sed -i.bak 's|expect(price(0)).toBe(0);|// TODO: zero case|' tests/price.test.js && rm tests/price.test.js.bak" "assertion-removed"
  expect "test.skip is a finding"                        1 "sed -i.bak 's/^test(/test.skip(/' tests/price.test.js && rm tests/price.test.js.bak" "skip-added"
  expect "describe.only is a finding"                    1 "printf 'describe.only(\"x\", () => {});\n' >> tests/price.test.js" "skip-added"
  expect ".NET [Ignore] is a finding"                    1 "printf '[Ignore]\npublic void Old() {}\n' > tests/PriceTests.cs" "skip-added"
  expect "eslint-disable in production is a finding"     1 "printf '// eslint-disable-next-line\n' >> src/price.js" "suppression-added"
  expect "Stryker disable is a finding"                  1 "printf '// Stryker disable all\n' >> src/price.js" "src/price.js:4"
  expect "threshold lowered (one line) is a finding"     1 "sed -i.bak 's/\"break\": 80/\"break\": 60/' stryker.config.json && rm stryker.config.json.bak" "threshold-lowered"
  expect "threshold lowered (own line) is a finding"     1 "sed -i.bak 's/\"break\": 80/\"break\": 60/' stryker.conf.json && rm stryker.conf.json.bak" "stryker.conf.json:5"
  expect "threshold removed is a finding"                1 "sed -i.bak '/\"break\"/d; s/\"low\": 70,/\"low\": 70/' stryker.conf.json && rm stryker.conf.json.bak" "removed:"
  expect "name with a space is reported intact"          1 "mkdir -p 'tests/with space' && printf 'test.skip(\"a\", () => {});\n' > 'tests/with space/a.test.js'" "tests/with space/a.test.js:1"

  # Must fail the check itself, never read as clean.
  total=$((total + 1))
  fresh
  if bash "$self" not-a-commit HEAD >/dev/null 2>&1; [ $? -eq 2 ]; then
    echo "ok   unknown base fails the check"
  else
    echo "FAIL unknown base fails the check"; failures=$((failures + 1))
  fi
  total=$((total + 1))
  if bash "$self" >/dev/null 2>&1; [ $? -eq 2 ]; then
    echo "ok   no arguments fails the check"
  else
    echo "FAIL no arguments fails the check"; failures=$((failures + 1))
  fi

  # The exit contract (process/ci-and-branch-protection.md, "Exit contract"): a check's last line
  # on stdout is its result.
  local name last
  for name in clean finding; do
    total=$((total + 1))
    fresh
    [ "$name" = finding ] && git rm -q tests/price.test.js
    git commit -qm change --allow-empty
    last="$(bash "$self" "$BASE" HEAD 2>/dev/null | tail -n 1)"
    case "$name:$last" in
      "clean:weakening-check: clean — "*|"finding:weakening-check: 1 finding(s) — "*) echo "ok   the last line states the result ($name)" ;;
      *) echo "FAIL the last line states the result ($name): '$last'"; failures=$((failures + 1)) ;;
    esac
  done

  cd / && rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  ""|-*) echo "usage: $0 <base> [<head>] | --self-test" >&2; exit 2 ;;
  *) [ $# -le 2 ] || { echo "usage: $0 <base> [<head>] | --self-test" >&2; exit 2; }; check "$@" ;;
esac
