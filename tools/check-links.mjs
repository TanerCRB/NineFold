#!/usr/bin/env node
// Checks that every relative Markdown link in this repository points at something that exists.
//
// This kit is almost entirely prose that cross-references itself ("see FrameworkDoc.md, section
// 9", "process/ci-and-branch-protection.md"). A renamed or moved file breaks those references
// silently — GitHub renders a dead link without complaint, and a reader who follows it concludes
// the referenced rule doesn't exist. The check is mechanical, so it belongs in CI, not in review.
//
// What counts as a link: inline `[text](target)` and `[text](target#anchor)`, outside fenced code
// blocks and inline code spans (a link shown AS an example inside code is not a link). Ignored:
// anything with a URL scheme (http:, https:, mailto:, ...) and pure `#anchor` links. Only the file
// part is checked — anchors are not, because GitHub's heading-slug rules are not worth
// re-implementing here, and a wrong anchor still lands the reader in the right file.
//
// Usage:
//   node tools/check-links.mjs              checks every *.md under the current directory
//   node tools/check-links.mjs --self-test  runs the built-in contrast cases (exit 0 only if all pass)
//
// Exit codes: 0 all links resolve; 1 broken links found (or self-test failed); 2 nothing was
// checked. The last one is deliberate: a checker that found zero files — wrong working directory,
// a path typo, an over-eager exclusion — would otherwise report "0 broken links" and pass, which
// is "nothing checked" dressed up as "nothing found" (FrameworkDoc.md, section 9).
//
// Run from the root directory of THIS repository.

import { readdirSync, readFileSync, writeFileSync, existsSync, mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname, relative, sep } from "node:path";

// .git is not content; node_modules is not ours. .claude holds agent-tool state, including whole
// worktree copies of this repository — scanning it would check every file several times over and
// report other branches' broken links as this one's.
const SKIP_DIRS = new Set([".git", "node_modules", ".claude"]);

function listMarkdown(root) {
  const found = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name)) walk(join(dir, entry.name));
      } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) {
        found.push(join(dir, entry.name));
      }
    }
  };
  walk(root);
  return found.sort();
}

// Returns [{ line, target }] for every inline link in the text. Code is blanked out first
// (keeping line breaks, so line numbers stay right) instead of parsed around.
function extractLinks(text) {
  const blanked = text
    .replace(/^(\s*)(```|~~~)[^\n]*\n[\s\S]*?^\s*\2[^\n]*$/gm, (block) => block.replace(/[^\n]/g, " "))
    .replace(/`[^`\n]*`/g, (span) => " ".repeat(span.length));
  const links = [];
  const pattern = /\[[^\]\n]*\]\(\s*(<[^>\n]*>|[^()\s]+)(?:\s+"[^"\n]*")?\s*\)/g;
  for (const match of blanked.matchAll(pattern)) {
    const target = match[1].replace(/^<|>$/g, "");
    const line = blanked.slice(0, match.index).split("\n").length;
    links.push({ line, target });
  }
  return links;
}

// null when the link is not ours to check, otherwise the path part (anchor and query stripped).
function relativePathOf(target) {
  if (/^[a-z][a-z0-9+.-]*:/i.test(target)) return null; // http:, https:, mailto:, ...
  if (target.startsWith("#")) return null;
  const path = target.replace(/[?#].*$/, "");
  if (path === "") return null;
  try {
    return decodeURIComponent(path);
  } catch {
    return path;
  }
}

// Checks every Markdown file under `root`. `out.log` receives the report lines.
function checkLinks(root, out) {
  const files = listMarkdown(root);
  let checked = 0;
  const broken = [];
  for (const file of files) {
    for (const { line, target } of extractLinks(readFileSync(file, "utf8"))) {
      const path = relativePathOf(target);
      if (path === null) continue;
      checked++;
      // A leading slash means "from the repository root" on GitHub, not from the filesystem root.
      const resolved = path.startsWith("/") ? join(root, path) : resolve(dirname(file), path);
      if (!existsSync(resolved)) {
        broken.push(`${relative(root, file).split(sep).join("/")}:${line}: ${target}`);
      }
    }
  }
  for (const entry of broken) out.log(`BROKEN ${entry}`);
  out.log(`Checked ${checked} relative links in ${files.length} Markdown files; broken: ${broken.length}.`);
  if (files.length === 0) {
    out.log("ERROR: no Markdown files found — nothing was checked. Run from the repository root.");
    return 2;
  }
  return broken.length === 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------- self-test
//
// Built-in contrast cases (calibration/README.md, Method 3): the same checker, run against
// fixtures whose correct verdict is known, must tell them apart before its green is trusted.

function withFixture(files, run) {
  const root = mkdtempSync(join(tmpdir(), "check-links-self-test-"));
  try {
    for (const [path, content] of Object.entries(files)) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), content);
    }
    const lines = [];
    const code = checkLinks(root, { log: (m) => lines.push(m) });
    return run({ code, lines });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const SELF_TEST_CASES = [
  {
    name: "existing relative links (plain, with anchor, parent dir, directory) pass",
    run: () =>
      withFixture(
        {
          "README.md": "[a](docs/a.md) [b](docs/a.md#part) [d](docs/)\n",
          "docs/a.md": "[up](../README.md)\n",
        },
        ({ code, lines }) =>
          code === 0 && lines.includes("Checked 4 relative links in 2 Markdown files; broken: 0.")
            ? null
            : `expected exit 0 with 4 links in 2 files, got ${code}: ${lines.join(" | ")}`,
      ),
  },
  {
    name: "link to a missing file fails, with file and line",
    run: () =>
      withFixture({ "README.md": "intro\n\n[gone](docs/missing.md#x)\n" }, ({ code, lines }) =>
        code === 1 && lines.includes("BROKEN README.md:3: docs/missing.md#x")
          ? null
          : `expected exit 1 and "BROKEN README.md:3: ...", got ${code}: ${lines.join(" | ")}`,
      ),
  },
  {
    name: "external, pure-anchor and code-block links are ignored",
    run: () =>
      withFixture(
        { "README.md": "[w](https://example.com/x.md) [h](#top) `[c](nope.md)`\n\n```\n[f](nope.md)\n```\n" },
        ({ code, lines }) =>
          code === 0 && lines.includes("Checked 0 relative links in 1 Markdown files; broken: 0.")
            ? null
            : `expected exit 0 with 0 links checked, got ${code}: ${lines.join(" | ")}`,
      ),
  },
  {
    name: "zero Markdown files is an error, not a pass",
    run: () =>
      withFixture({ "notes.txt": "[x](missing.md)\n" }, ({ code }) =>
        code === 2 ? null : `expected exit 2 for an empty scan, got ${code}`,
      ),
  },
];

// ---------------------------------------------------------------------------- entry point

if (process.argv.includes("--self-test")) {
  let failed = 0;
  for (const testCase of SELF_TEST_CASES) {
    let reason;
    try {
      reason = testCase.run();
    } catch (error) {
      reason = `threw: ${error?.stack ?? error}`;
    }
    if (reason) failed++;
    console.log(reason ? `FAIL ${testCase.name} — ${reason}` : `ok   ${testCase.name}`);
  }
  console.log(`Self-test: ${SELF_TEST_CASES.length} cases ran, ${SELF_TEST_CASES.length - failed} passed, ${failed} failed.`);
  process.exit(failed === 0 ? 0 : 1);
}

process.exit(checkLinks(process.cwd(), console));
