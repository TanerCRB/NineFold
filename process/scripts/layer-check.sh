#!/usr/bin/env bash
# layer-check.sh — does a change add a dependency that crosses a layer the wrong way?
#
# Copy into the product repository (e.g. scripts/layer-check.sh). It reads the layer table
# (process/registers/layer-dependencies.md) and the lines a change adds:
#
#   scripts/layer-check.sh origin/main "$CHECKPOINT"          # step 10a, after the developer checkpoint
#   scripts/layer-check.sh --register <file> <base> [<head>]  # another table than the default
#   scripts/layer-check.sh --self-test                        # built-in contrast cases
#
# A table row is a Markdown table row: the layer name in backticks, one path glob in backticks, the
# prefixes other code refers to the layer by (comma-separated, `—` for none), and the layers it must
# not depend on (comma-separated, `—` for none):
#
#   | `domain` | `src/Domain/**` | `Acme.Domain`, `@/domain` | infrastructure, api | ADR-0003 |
#
# `*` and `**` both match across directories. Rows still holding a <placeholder> are skipped.
#
# For every added line in a file under a layer's glob, the check takes the references the line
# makes (REFERENCE PATTERNS below) and finds the layer each one points to: a relative import by
# resolving it against the file and matching the globs, anything else by the longest
# "Referenced as" prefix that matches on a boundary (`.` or `/`). A reference to a layer the
# file's layer must not depend on is a finding:
#
#   layer-violation   <path>:<line>   <layer> must not depend on <layer>: <the line>
#
# Exit contract (ci-and-branch-protection.md, §8): 0 = clean, 1 = findings (they go to the
# Architect), 2 = the check itself failed and is never clean: the table is missing, has no real
# rows, names an unknown layer, or a changed file falls under two layers; a commit doesn't exist.
#
# What it does NOT cover, stated so nobody reads it as more: it reads lines, not a compiled
# graph. A dependency through a fully qualified name with no `using`/`import`, reflection, a
# dynamic import built from a string, a transitive dependency (A → B → C), Python relative imports,
# and rules broken on lines the change didn't add all pass. The Architect still reads the design.
#
# The reference patterns are an EXAMPLE for C#, TS/JS and Python — adapt them when you copy the
# script, and keep the self-test cases in step with them.

set -Eeuo pipefail
trap 'echo "layer-check: the check itself failed (line $LINENO) — treat as STOP" >&2; exit 2' ERR

REGISTER="docs/layer-dependencies.md"

usage() { echo "usage: $0 [--register <file>] <base> [<head>] | --self-test" >&2; exit 2; }

# The table's rows → three lists in "$1": globs (layer<TAB>glob), prefixes (layer<TAB>prefix) and
# rules (layer<TAB>forbidden layer). Exit 2 on anything that isn't a clean table.
read_table() {
  local register="$1" out="$2" code=0
  [ -r "$register" ] || { echo "layer-check: cannot read the table '$register'" >&2; exit 2; }
  tr -d '\r' < "$register" | awk -v out="$out" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function unquote(s) { s = trim(s); if (s ~ /^`.*`$/) s = substr(s, 2, length(s) - 2); return s }
    /^\|/ {
      split($0, cell, "|")
      name = trim(cell[2]); glob = trim(cell[3])
      if (name !~ /^`[^`]+`$/ || glob !~ /^`[^`]+`$/) next      # header, separator, prose
      if ($0 ~ /</) next                                         # a placeholder row of the template
      name = unquote(name); glob = unquote(glob)
      defined[name] = 1; rows++
      print name "\t" glob > (out "/globs")
      n = split(cell[4], p, ",")
      for (i = 1; i <= n; i++) { v = unquote(p[i]); if (v != "" && v != "—" && v != "-") print name "\t" v > (out "/prefixes") }
      n = split(cell[5], f, ",")
      for (i = 1; i <= n; i++) { v = unquote(f[i]); if (v != "" && v != "—" && v != "-") { nr++; r_from[nr] = name; r_to[nr] = v } }
    }
    END {
      if (!rows) { print "layer-check: the table has no rows with a real layer — every dependency would read as allowed" > "/dev/stderr"; exit 2 }
      for (i = 1; i <= nr; i++) {
        if (!(r_to[i] in defined)) { print "layer-check: layer " r_from[i] " names an unknown layer \"" r_to[i] "\"" > "/dev/stderr"; bad = 1; continue }
        print r_from[i] "\t" r_to[i] > (out "/rules")
      }
      if (bad) exit 2
    }' || code=$?
  [ "$code" -eq 0 ] || exit 2
  touch "$out/prefixes" "$out/rules"
}

# ------------------------------------------------------------------- reference patterns (adapt)
# The diff parser. Input: `git diff -U0`. POSIX awk only: CI runners often have mawk.
read -r -d '' PARSER <<'AWK' || true
function glob_re(g,    r) {
  r = g
  gsub(/[][\\.^$+?(){}|]/, "\\\\&", r)
  gsub(/\*\*/, "*", r); gsub(/\*/, ".*", r)
  return "^" r "$"
}
function layer_of_path(p,    i, found, l) {
  found = ""
  for (i = 1; i <= ng; i++) if (p ~ g_re[i]) {
    l = g_layer[i]
    if (found != "" && found != l) { ambiguous[p] = found " and " l; return found }
    found = l
  }
  return found
}
function layer_of_prefix(ref,    i, best, bl, pr) {
  best = ""; bl = 0
  for (i = 1; i <= np; i++) {
    pr = p_val[i]
    if (length(pr) <= bl) continue
    if (ref == pr || substr(ref, 1, length(pr) + 1) == pr "." || substr(ref, 1, length(pr) + 1) == pr "/") { best = p_layer[i]; bl = length(pr) }
  }
  return best
}
# A relative import, resolved against the importing file's directory.
function resolve(file, ref,    dir, n, part, i, out, k, stack) {
  dir = file; sub(/\/[^\/]*$/, "", dir); if (dir == file) dir = ""
  n = split(dir "/" ref, part, "/"); k = 0
  for (i = 1; i <= n; i++) {
    if (part[i] == "" || part[i] == ".") continue
    if (part[i] == "..") { if (k > 0) k--; continue }
    stack[++k] = part[i]
  }
  out = ""; for (i = 1; i <= k; i++) out = out (i > 1 ? "/" : "") stack[i]
  return out
}
function target_layer(ref,    p, l) {
  if (ref ~ /^\.\.?\//) {
    p = resolve(path, ref)
    l = layer_of_path(p); if (l == "") l = layer_of_path(p "/index")
    return l
  }
  return layer_of_prefix(ref)
}
function check(ref, text,    to) {
  to = target_layer(ref)
  if (to != "" && to != from && ((from SUBSEP to) in forbidden))
    { gsub(/\t/, " ", text); printf "layer-violation\t%s:%d\t%s must not depend on %s: %s\n", path, nline, from, to, text }
}
# The references one added line makes, by file type.
function references(s, text,    m, q, rest, n, mods, i) {
  if (path ~ /\.(cs)$/) {
    if (s !~ /^(global +)?using +/) return
    sub(/^(global +)?using +(static +)?/, "", s)
    if (s ~ /=/) { sub(/^[^=]*= */, "", s) }
    sub(/ *;.*$/, "", s)
    if (s ~ /^[A-Za-z_][A-Za-z0-9_.]*$/) check(s, text)
  } else if (path ~ /\.(js|jsx|ts|tsx|mjs|cjs|vue|svelte)$/) {
    rest = s
    while (match(rest, /(from|import|require|import *\() *\(? *['"][^'"]+['"]/)) {
      m = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
      match(m, /['"][^'"]+['"]/); q = substr(m, RSTART + 1, RLENGTH - 2)
      check(q, text)
    }
  } else if (path ~ /\.py$/) {
    if (s ~ /^from +[A-Za-z_][A-Za-z0-9_.]* +import/) {
      sub(/^from +/, "", s); sub(/ +import.*$/, "", s); check(s, text)
    } else if (s ~ /^import +[A-Za-z_]/) {
      sub(/^import +/, "", s); n = split(s, mods, ",")
      for (i = 1; i <= n; i++) { m = mods[i]; gsub(/^ +| +$/, "", m); sub(/ +as +.*$/, "", m); sub(/[ #].*$/, "", m); check(m, text) }
    }
  }
}
BEGIN {
  FS = "\n"
  while ((getline line < (dir "/globs")) > 0)    { split(line, f, "\t"); ng++; g_layer[ng] = f[1]; g_re[ng] = glob_re(f[2]) }
  while ((getline line < (dir "/prefixes")) > 0) { split(line, f, "\t"); np++; p_layer[np] = f[1]; p_val[np] = f[2] }
  while ((getline line < (dir "/rules")) > 0)    { split(line, f, "\t"); forbidden[f[1] SUBSEP f[2]] = 1 }
}
/^diff --git / { path = ""; from = ""; in_hunk = 0; next }
!in_hunk && /^\+\+\+ / {
  path = ($0 == "+++ /dev/null") ? "" : substr($0, 7); sub(/\t$/, "", path)
  from = (path == "") ? "" : layer_of_path(path)
  next
}
/^@@ / { in_hunk = 1; split($0, h, " "); split(h[3], a, ","); nline = substr(a[1], 2) + 0; next }
in_hunk && /^\+/ {
  if (from != "") {
    t = substr($0, 2); s = t; sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s)
    if (s !~ /^(\/\/|#|\*|\/\*)/) references(s, t)
  }
  nline++; next
}
END {
  for (p in ambiguous) { print "layer-check: " p " falls under two layers, " ambiguous[p] > "/dev/stderr"; bad = 1 }
  if (bad) exit 2
}
AWK

run() {
  local register="$REGISTER"
  if [ "${1:-}" = "--register" ]; then [ $# -ge 2 ] || usage; register="$2"; shift 2; fi
  [ $# -ge 1 ] && [ $# -le 2 ] || usage
  case "$1" in -*) usage ;; esac
  local base="$1" head="${2:-HEAD}"
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null \
    || { echo "layer-check: base '$base' is not a commit" >&2; exit 2; }
  git rev-parse --verify --quiet "$head^{commit}" >/dev/null \
    || { echo "layer-check: head '$head' is not a commit" >&2; exit 2; }

  local tmp code=0; tmp="$(mktemp -d)"
  read_table "$register" "$tmp"
  git -c core.quotePath=false diff -U0 --no-color --no-ext-diff --find-renames "$base...$head" \
    | awk -v dir="$tmp" "$PARSER" > "$tmp/findings" || code=$?
  [ "$code" -eq 0 ] || { rm -rf "$tmp"; exit 2; }

  local count cat where text
  count="$(wc -l < "$tmp/findings" | tr -d ' ')"
  if [ "$count" -gt 0 ]; then
    while IFS=$'\t' read -r cat where text; do
      printf 'LAYER: %s  %s\n' "$where" "$text" >&2
    done < "$tmp/findings"
    rm -rf "$tmp"
    echo "layer-check: $count finding(s) — $base...$head, to the Architect"
    exit 1
  fi
  rm -rf "$tmp"
  echo "layer-check: clean — $base...$head"
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

  cat > "$root/table.md" <<'EOF'
# Layer dependencies

| Layer | Path (glob) | Referenced as | Must not depend on | Why |
|---|---|---|---|---|
| `<core>` | `<src/Core/**>` | <`Acme.Core`> | <web> | <placeholder row, skipped> |
| `domain` | `src/Domain/**` | `Acme.Domain`, `@/domain`, `acme.domain` | infrastructure, api | ADR-0003 |
| `domain` | `web/src/domain/**` | — | infrastructure, api | the frontend's domain |
| `infrastructure` | `src/Infrastructure/**` | `Acme.Infrastructure`, `@/infrastructure`, `acme.infrastructure` | api | ADR-0004 |
| `infrastructure` | `web/src/infrastructure/**` | — | api | |
| `api` | `src/Api/**` | `Acme.Api`, `@/api` | — | outermost |
| `shared` | `src/Shared/**` | `Acme.Infrastructure.Contracts` | — | contracts the domain may use |
EOF

  fresh() {
    rm -rf "$root/repo" && mkdir -p "$root/repo/src/Domain" "$root/repo/src/Api" "$root/repo/web/src/domain" "$root/repo/web/src/infrastructure" "$root/repo/py/acme/domain" && cd "$root/repo" || return 1
    git init -q && git config user.email t@t && git config user.name t && git config core.autocrlf false
    printf 'using Acme.Infrastructure.Sql;\nnamespace Acme.Domain;\n' > src/Domain/Legacy.cs
    printf 'namespace Acme.Domain;\npublic class Price {}\n' > src/Domain/Price.cs
    printf 'export const price = 1;\n' > web/src/domain/price.ts
    printf 'x = 1\n' > py/acme/domain/total.py
    git add -A && git commit -qm base
    BASE="$(git rev-parse HEAD)"
  }
  # expect <name> <expected exit> <change> [<text the output must contain>] [<table>]
  expect() {
    local name="$1" want="$2" change="$3" must="${4:-}" table="${5:-$root/table.md}"
    total=$((total + 1))
    fresh
    eval "$change"
    git add -A && git commit -qm change --allow-empty
    local out code
    out="$(bash "$self" --register "$table" "$BASE" HEAD 2>&1)"
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

  # Must pass.
  expect "an allowed reference passes"                    0 "printf 'using Acme.Domain.Pricing;\n' > src/Api/Prices.cs"
  expect "a reference inside the layer passes"            0 "printf 'using Acme.Domain.Pricing;\n' >> src/Domain/Price.cs"
  expect "a forbidden reference on an unchanged line is not reported" 0 "printf '// touched\n' >> src/Domain/Legacy.cs"
  expect "a prefix matches on a boundary only"            0 "printf 'using Acme.ApiClient;\nusing Acme.Infrastructures;\n' >> src/Domain/Price.cs"
  expect "a file outside every layer passes"              0 "mkdir -p tools && printf 'using Acme.Api;\n' > tools/Gen.cs"
  expect "a commented-out import passes"                  0 "printf '// using Acme.Api;\n' >> src/Domain/Price.cs"
  expect "a using statement is not a namespace"           0 "printf 'using var conn = Acme.Api.Open();\n' >> src/Domain/Price.cs"
  expect "a relative import inside the layer passes"      0 "printf \"import { price } from './price';\n\" > web/src/domain/total.ts"

  # Must fail, with the evidence named.
  expect "a forbidden C# using is a finding"              1 "printf 'using Acme.Infrastructure.Sql;\n' >> src/Domain/Price.cs" "src/Domain/Price.cs:3"
  expect "a C# using alias is a finding"                  1 "printf 'using Db = Acme.Infrastructure.Sql.Db;\n' >> src/Domain/Price.cs" "domain must not depend on infrastructure"
  expect "a forbidden TS alias import is a finding"       1 "printf \"import { api } from '@/api/client';\n\" >> web/src/domain/price.ts" "web/src/domain/price.ts:2"
  expect "a forbidden relative import is a finding"       1 "printf \"import { db } from '../infrastructure/db';\n\" >> web/src/domain/price.ts" "domain must not depend on infrastructure"
  expect "a relative directory import is a finding"       1 "printf \"const db = require('../infrastructure');\n\" >> web/src/domain/price.ts" "price.ts:2"
  expect "a Python from-import is a finding"              1 "mkdir -p src/Domain/py && printf 'from acme.infrastructure.sql import db\n' > src/Domain/py/x.py" "src/Domain/py/x.py:1"
  expect "a Python import list is a finding"              1 "printf 'import os, acme.infrastructure.sql as sql\n' > src/Domain/y.py" "src/Domain/y.py:1"
  expect "the longest prefix wins"                        0 "printf 'using Acme.Infrastructure.Contracts.Prices;\n' >> src/Domain/Price.cs"
  expect "the shorter prefix still holds beside it"       1 "printf 'using Acme.Infrastructure.ContractsSql;\n' >> src/Domain/Price.cs" "must not depend on infrastructure"

  # The table itself, and the check's own failures: exit 2, never clean.
  printf '| `domain` | `src/Domain/**` | `Acme.Domain` | storage |  |\n' > "$root/unknown.md"
  expect "an unknown layer fails the check"               2 "printf 'x\n' >> src/Domain/Price.cs" "" "$root/unknown.md"
  printf '| Layer | Path |\n|---|---|\n| `<domain>` | `<src/**>` | <`A`> | <api> |  |\n' > "$root/template.md"
  expect "a table with only placeholders fails"           2 "printf 'x\n' >> src/Domain/Price.cs" "" "$root/template.md"
  expect "a missing table fails"                          2 "printf 'x\n' >> src/Domain/Price.cs" "" "$root/none.md"
  { cat "$root/table.md"; printf '| `api` | `src/**` | — | — |  |\n'; } > "$root/overlap.md"
  expect "a file under two layers fails"                  2 "printf 'using Acme.Api;\n' >> src/Domain/Price.cs" "" "$root/overlap.md"
  tr -d '\r' < "$root/table.md" | sed 's/$/\r/' > "$root/crlf.md"
  expect "a CRLF table reads the same"                    1 "printf 'using Acme.Infrastructure.Sql;\n' >> src/Domain/Price.cs" "src/Domain/Price.cs:3" "$root/crlf.md"
  total=$((total + 1))
  fresh
  if bash "$self" --register "$root/table.md" not-a-commit HEAD >/dev/null 2>&1; [ $? -eq 2 ]; then
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
    [ "$name" = finding ] && printf 'using Acme.Api;\n' >> src/Domain/Price.cs && git add -A
    git commit -qm change --allow-empty
    last="$(bash "$self" --register "$root/table.md" "$BASE" HEAD 2>/dev/null | tail -n 1)"
    case "$name:$last" in
      "clean:layer-check: clean — "*|"finding:layer-check: 1 finding(s) — "*) echo "ok   the last line states the result ($name)" ;;
      *) echo "FAIL the last line states the result ($name): '$last'"; failures=$((failures + 1)) ;;
    esac
  done

  cd / && rm -rf "$root"
  echo "Self-test: $total cases ran, $((total - failures)) passed, $failures failed."
  [ "$failures" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  "") usage ;;
  *) run "$@" ;;
esac
