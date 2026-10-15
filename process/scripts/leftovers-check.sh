#!/usr/bin/env bash
# leftovers-check.sh — did a change leave behind what an agent leaves behind?
#
# Copy into the product repository (e.g. scripts/leftovers-check.sh) and run it from the task's
# worktree on a checkpoint, against the base the task branched from:
#
#   scripts/leftovers-check.sh origin/main "$CHECKPOINT"    # step 10c, after the developer checkpoint
#   scripts/leftovers-check.sh origin/main "$VERIFIED"      # step 11a, after the QA checkpoint
#   scripts/leftovers-check.sh --self-test                  # built-in contrast cases
#
# The pre-push hook (process/hooks/pre-push) runs it too, on every pushed branch, once the script
# is copied to scripts/leftovers-check.sh.
#
# It reads `git diff <base>...<head>` — only what the change itself added — and reports:
#
#   leftover-file    a new file (or a rename target) whose name looks like a copy or a draft:
#                    `Price.copy.cs`, `handler_final.ts`, `PriceOld.cs`, `report (1).md`,
#                    `*.bak`, `*.orig`, `*.rej`, `*.tmp`, `*.swp`, `*~`;
#   debug-output     an added line that prints or breaks for debugging, from a pattern per file
#                    type (DEBUG_RULES below);
#   commented-code   a block of added comment lines in which at least COMMENTED_CODE_MIN lines
#                    read as code: they start with a closing bracket, or they end in `;`, `{`,
#                    `}`, `)` or `:` and start with a keyword or call something (`name(`).
#                    Prose that ends the same way doesn't call anything, so it passes.
#
# A deliberate case goes through visibly, never silently:
#   - a line holding `leftovers-allow: <reason>` is not reported; on the comment line just above a
#     block, or inside it, it covers the whole block. An allow without a reason is not an allow;
#   - a glob on its own line in ALLOW_FILE (read from <head>, so the allow travels with the
#     change) lets a path through entirely. `#` starts a comment there.
#
# Exit contract (ci-and-branch-protection.md, §8): 0 = clean, 1 = findings (they go back to the
# Developer), 2 = the check itself failed (never read as clean).
#
# What it does NOT cover, stated so nobody reads it as more: `/* … */` block comments, debug output
# written in a way the patterns don't name (a logger left at debug level, a custom print helper),
# a scratch file whose name looks ordinary, and anything git can't diff. A reviewer reading for
# meaning still reads the diff; this check only takes the mechanical cases off their desk.
#
# The patterns are an EXAMPLE for common stacks — adapt them when you copy the script, and keep
# the self-test cases in step with them.

# ------------------------------------------------------------------------- patterns (adapt)

# One rule per line: <file-name regex><TAB><line regex>. POSIX extended regular expressions (awk).
DEBUG_RULES="$(printf '%s\t%s\n' \
  '\.(js|jsx|ts|tsx|mjs|cjs|vue|svelte)$' 'console\.(log|debug|trace|dir|table)\(|(^|[^A-Za-z0-9_.])debugger *;?$' \
  '\.(cs|vb|fs)$'                         '(Debug|Console)\.Write(Line)?\(|Debugger\.Break\(' \
  '\.(java|kt)$'                          'System\.(out|err)\.print|\.printStackTrace\(\)' \
  '\.py$'                                 '(^|[^A-Za-z0-9_.])print\(|pdb\.set_trace\(|(^|[^A-Za-z0-9_.])breakpoint\(\)' \
  '\.go$'                                 'fmt\.Print(ln|f)?\(' \
  '\.rs$'                                 'dbg!\(' \
  '\.rb$'                                 'binding\.pry|byebug|(^|[^A-Za-z0-9_.])pp\(' \
  '\.php$'                                'var_dump\(|print_r\(|(^|[^A-Za-z0-9_>:])dd\(')"

# Which comment marker a file type uses. A type missing here gets no commented-code check.
SLASH_COMMENT_RE='\.(js|jsx|ts|tsx|mjs|cjs|vue|svelte|cs|fs|java|kt|go|rs|c|h|cc|cpp|hpp|swift|php|scala|dart)$'
HASH_COMMENT_RE='\.(py|rb|sh|bash|ps1|pl|r|R)$'

# How many code-looking comment lines make a block a finding.
COMMENTED_CODE_MIN=3

# Words in a new file's name that mark a copy or a draft (lower case; split on . _ - space ( )).
LEFTOVER_WORDS="copy final old backup bak orig draft tmp temp kopia"
# Extensions that mark one.
LEFTOVER_EXT_RE='\.(bak|orig|rej|tmp|swp|swo)$|~$'

ALLOW_FILE=".leftovers-allow"

# ------------------------------------------------------------------------------- the check

set -Eeuo pipefail
trap 'echo "leftovers-check: the check itself failed (line $LINENO) — treat as STOP" >&2; exit 2' ERR

usage() { echo "usage: $0 <base> [<head>] | --self-test" >&2; exit 2; }

# The diff parser. Input: `git diff -U0`. One finding per output line: <category>\t<path>:<line>\t<text>
read -r -d '' PARSER <<'AWK' || true
function report(cat, line, text) { gsub(/\t/, " ", text); printf "%s\t%s:%d\t%s\n", cat, path, line, text }
function allowed(t) { return t ~ /leftovers-allow: *[^ ]/ }
# Code, not prose: it starts with a closing bracket, or it ends like a statement and either starts
# with a keyword or calls something (`name(`, with no space before the parenthesis — prose puts
# one there).
function looks_like_code(b) {
  if (b ~ /^[})\]]/) return 1
  if (b !~ /[;{}):]$/) return 0
  if (b ~ /^(if|for|foreach|while|switch|return|const|let|var|def|class|import|from|using|else|elif|try|catch|except|finally|await|throw|raise|yield|new|public|private|protected|static|async|fn|func)([ (:;{]|$)/) return 1
  return b ~ /[A-Za-z0-9_\]>]\(/
}
function close_block(   ) {
  if (b_code >= min && !b_allow) report("commented-code", b_first, b_first_text)
  b_n = b_code = b_allow = 0
}
BEGIN {
  min = ENVIRON["LC_MIN"] + 0
  n = split(ENVIRON["LC_DEBUG"], rl, "\n")
  for (i = 1; i <= n; i++) { if (split(rl[i], f, "\t") == 2) { nr++; r_file[nr] = f[1]; r_line[nr] = f[2] } }
}
/^diff --git / { close_block(); path = ""; in_hunk = 0; next }
!in_hunk && /^\+\+\+ / {
  path = ($0 == "+++ /dev/null") ? "" : substr($0, 7); sub(/\t$/, "", path)
  marker = ""
  if (path ~ ENVIRON["LC_SLASH"]) marker = "//"; else if (path ~ ENVIRON["LC_HASH"]) marker = "#"
  nd = 0; for (i = 1; i <= nr; i++) if (path ~ r_file[i]) { nd++; d_re[nd] = r_line[i] }
  skip = (path == "" || path in allow)
  next
}
/^@@ / { close_block(); in_hunk = 1; split($3, a, ","); nline = substr(a[1], 2) + 0; next }
in_hunk && /^\+/ {
  if (skip) { nline++; next }
  t = substr($0, 2); s = t; sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s)
  is_comment = (marker != "" && index(s, marker) == 1 && !(marker == "//" && s ~ /^\/\/\//) && !(marker == "#" && s ~ /^#!/))
  if (is_comment) {
    body = substr(s, length(marker) + 1); sub(/^[ \t]+/, "", body)
    if (allowed(t)) b_allow = 1
    if (looks_like_code(body)) { b_code++; if (b_code == 1) { b_first = nline; b_first_text = t } }
    b_n++
  } else {
    close_block()
    if (!allowed(t)) for (i = 1; i <= nd; i++) if (s ~ d_re[i]) { report("debug-output", nline, t); break }
  }
  nline++; next
}
in_hunk && /^-/ { next }
in_hunk && /^\\/ { next }
{ close_block() }
END { close_block() }
AWK

# The allow list from <head>, one glob per line, as an awk-readable list of matching paths.
allowed_paths() {
  local head="$1" names="$2" glob path
  git cat-file -e "$head:$ALLOW_FILE" 2>/dev/null || return 0
  while IFS= read -r glob; do
    glob="${glob%%#*}"; glob="${glob%"${glob##*[![:space:]]}"}"; glob="${glob#"${glob%%[![:space:]]*}"}"
    [ -n "$glob" ] || continue
    while IFS= read -r path; do
      # shellcheck disable=SC2254
      case "$path" in ${glob//\*\*/*}) printf '%s\n' "$path" ;; esac
    done < "$names"
  done < <(git show "$head:$ALLOW_FILE" | tr -d '\r')
}

# Does a new file's name look like a copy or a draft?
leftover_name() {
  local name="${1##*/}" lower word stem
  [[ "$name" =~ $LEFTOVER_EXT_RE ]] && return 0
  stem="${name%.*}"
  [[ "$stem" =~ \([0-9]+\)$ ]] && return 0                                   # report (1).md
  [[ "$stem" =~ [a-z0-9](Copy|Final|Old|Backup|Draft)[0-9]*$ ]] && return 0  # PriceOld.cs
  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr '._() -' '      ')"
  for word in $lower; do
    word="${word%%[0-9]*}"
    case " $LEFTOVER_WORDS " in *" $word "*) [ -n "$word" ] && return 0 ;; esac
  done
  return 1
}

check() {
  local base="$1" head="${2:-HEAD}"
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null \
    || { echo "leftovers-check: base '$base' is not a commit" >&2; exit 2; }
  git rev-parse --verify --quiet "$head^{commit}" >/dev/null \
    || { echo "leftovers-check: head '$head' is not a commit" >&2; exit 2; }

  local tmp; tmp="$(mktemp -d)"
  git -c core.quotePath=false diff --name-only --diff-filter=d --no-renames "$base...$head" > "$tmp/changed"
  allowed_paths "$head" "$tmp/changed" > "$tmp/allow"

  # New files and rename targets: their names.
  local status path
  : > "$tmp/findings"
  while IFS=$'\t' read -r status path; do
    case "$status" in A|R*|C*) ;; *) continue ;; esac
    path="${path##*$'\t'}"
    if grep -qxF -- "$path" "$tmp/allow"; then continue; fi
    if leftover_name "$path"; then printf 'leftover-file\t%s\t%s\n' "$path" "new file" >> "$tmp/findings"; fi
  done < <(git -c core.quotePath=false diff --name-status --find-renames "$base...$head")

  # Added lines.
  git -c core.quotePath=false diff -U0 --no-color --no-ext-diff --find-renames "$base...$head" \
    | LC_DEBUG="$DEBUG_RULES" LC_SLASH="$SLASH_COMMENT_RE" LC_HASH="$HASH_COMMENT_RE" LC_MIN="$COMMENTED_CODE_MIN" \
      awk -v allowfile="$tmp/allow" 'BEGIN { while ((getline p < allowfile) > 0) allow[p] = 1 } '"$PARSER" >> "$tmp/findings"

  local count cat where text
  count="$(wc -l < "$tmp/findings" | tr -d ' ')"
  if [ "$count" -gt 0 ]; then
    while IFS=$'\t' read -r cat where text; do
      printf 'LEFTOVER: %-15s %s  %s\n' "$cat" "$where" "$text" >&2
    done < "$tmp/findings"
    rm -rf "$tmp"
    echo "leftovers-check: $count finding(s) — $base...$head, back to the Developer"
    exit 1
  fi
  rm -rf "$tmp"
  echo "leftovers-check: clean — $base...$head"
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
    rm -rf "$root/repo" && mkdir -p "$root/repo/src" "$root/repo/tools" && cd "$root/repo" || return 1
    git init -q && git config user.email t@t && git config user.name t && git config core.autocrlf false
    printf 'export function price(n) {\n  return n * 2;\n}\n' > src/price.js
    printf 'def total(xs):\n    return sum(xs)\n' > src/total.py
    printf 'console.log("old debug, not part of the change");\n' > src/legacy.js
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
  expect "production change only passes"                   0 "printf 'export function half(n) {\n  return n / 2;\n}\n' >> src/price.js"
  expect "an ordinary new file passes"                     0 "printf 'x\n' > src/FinalizeOrder.cs && printf 'y\n' > src/Gold.cs && printf 'z\n' > src/holder.ts"
  expect "a prose comment block passes"                    0 "printf '// The price doubles, because of the rule (team contract)\n// and the invoices (ADR-0009)\n// Rounding happens later (in the invoice).\nexport const k = 1;\n' >> src/price.js"
  expect "prose ending in ; and ) passes"                  0 "printf '# what it reports:\n#   a test deleted;\n#   a skip added (or an only);\n#   see the register (registers/risk.md)\n#   \"hooks\": {\n' >> src/total.py"
  expect "two code-looking comment lines pass"            0 "printf '// const a = 1;\n// const b = 2;\nexport const c = 3;\n' >> src/price.js"
  expect "an unchanged debug line is not reported"         0 "printf 'export const d = 4;\n' >> src/legacy.js"
  expect "a JSDoc triple slash and a shebang pass"         0 "printf '/// <reference path=\"x.d.ts\" />\n/// <reference path=\"y.d.ts\" />\n/// <reference path=\"z.d.ts\" />\n' >> src/price.js && printf '#!/usr/bin/env python3\n' > tools/run.py"
  expect "a method named print_report passes"              0 "printf 'def report():\n    print_report(1)\n    self.print(2)\n' >> src/total.py"
  expect "an allow line with a reason passes"              0 "printf 'console.log(\"ready\"); // leftovers-allow: the CLI prints this on purpose\n' >> src/price.js"
  expect "an allow above a block covers it"                0 "printf '// leftovers-allow: the old formula, kept for the audit until ADR-0012\n// return n * 3;\n// if (n > 0) {\n// }\nexport const e = 5;\n' >> src/price.js"
  expect "an allow-file glob lets a path through"          0 "printf 'tools/**   # the dev scripts print on purpose\n' > .leftovers-allow && printf 'console.log(1);\n' > tools/dev.js && printf 'x\n' > tools/notes.old.md"

  # Must fail: each category, with the evidence named.
  expect "console.log is a finding"                        1 "printf 'console.log(n);\n' >> src/price.js" "src/price.js:4"
  expect "debugger is a finding"                           1 "printf '  debugger;\n' >> src/price.js" "debug-output"
  expect "Python print is a finding"                       1 "printf '    print(xs)\n' >> src/total.py" "src/total.py:3"
  expect "C# Console.WriteLine is a finding"               1 "printf 'Console.WriteLine(x);\n' > src/Price.cs" "debug-output"
  expect "an allow without a reason is not an allow"       1 "printf 'console.log(n); // leftovers-allow:\n' >> src/price.js" "debug-output"
  expect "commented-out code is a finding"                 1 "printf '// const old = n * 3;\n// if (old > 10) {\n//   return old;\n// }\nexport const f = 6;\n' >> src/price.js" "commented-code"
  expect "commented-out Python is a finding"               1 "printf '# total = sum(xs)\n# log(total)\n# return round(total)\n' >> src/total.py" "src/total.py:3"
  expect "a .copy file is a finding"                       1 "cp src/price.js src/price.copy.js" "leftover-file"
  expect "a _final file is a finding"                      1 "printf 'x\n' > src/handler_final.ts" "src/handler_final.ts"
  expect "a CamelCase Old file is a finding"               1 "printf 'x\n' > src/PriceOld.cs" "leftover-file"
  expect "a (1) file is a finding"                         1 "printf 'x\n' > 'src/report (1).md'" "src/report (1).md"
  expect "a .bak file is a finding"                        1 "printf 'x\n' > src/price.js.bak" "leftover-file"
  expect "a rename to a draft name is a finding"           1 "git mv src/total.py src/total_draft.py" "src/total_draft.py"
  expect "an allow file elsewhere doesn't cover src"       1 "printf 'tools/**\n' > .leftovers-allow && printf 'console.log(1);\n' >> src/price.js" "src/price.js:4"

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
    [ "$name" = finding ] && printf 'console.log(n);\n' >> src/price.js && git add -A
    git commit -qm change --allow-empty
    last="$(bash "$self" "$BASE" HEAD 2>/dev/null | tail -n 1)"
    case "$name:$last" in
      "clean:leftovers-check: clean — "*|"finding:leftovers-check: 1 finding(s) — "*) echo "ok   the last line states the result ($name)" ;;
      *) echo "FAIL the last line states the result ($name): '$last'"; failures=$((failures + 1)) ;;
    esac
  done

  cd / && rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  ""|-*) usage ;;
  *) [ $# -le 2 ] || usage; check "$@" ;;
esac
