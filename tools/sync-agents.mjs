#!/usr/bin/env node
// Copies role definitions from the process source repository (this framework) to the
// product repository's configuration directory, from where the agent environment loads them
// (e.g. .claude/agents/ for Claude Code).
//
// This repository is the source of truth and is version-controlled. The target directory in the
// product repository is DELIBERATELY excluded from its version control (this concerns the tool,
// not the product code) — so the copy must be reproducible from here at any time, not maintained
// by hand on the other side.
//
// Usage:
//   node tools/sync-agents.mjs           copies the definitions, reports what changed
//   node tools/sync-agents.mjs --check   reports only drift, writes nothing (exit 1 on drift or a missing target)
//
// Run from the root directory of THIS repository (the process source repository).

import { readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, resolve } from "node:path";

const CHECK_ONLY = process.argv.includes("--check");

// ---------------------------------------------------------------------------- CONFIGURATION
//
// Substitute for your own project's reality. This framework keeps roles as ONE shared set of
// generic templates in `agents/` — each file carries checklists for both example stacks
// (backend/frontend) explicitly marked as EXAMPLE TO REPLACE. If you leave it that way, all
// product repositories point to the same `dir: "agents"`.
//
// If your two technology stacks differ enough that you'd rather have separate files per stack
// (as in this framework's original source project — `agents/` for the backend,
// `agents-frontend/` for the frontend, each file trimmed to a single checklist), split the
// `agents/` directory into two and give each target its own `dir`. The role is then named the
// same in both places, differing only in what it guards.
//
// `dir`  — the directory in THIS repository that the given target's definitions come from; may
//          be shared between targets.
// `path` — the path to the product repository, relative to this repository.
// `targetSubdir` — the target directory INSIDE the product repository that the definitions land
//          in (default ".claude/agents" — swap for your own agent environment).
const TARGETS = [
  { name: "<repo-backend>", path: resolve("..", "<repo-backend>"), dir: "agents" },
  { name: "<repo-frontend>", path: resolve("..", "<repo-frontend>"), dir: "agents" },
];

const TARGET_SUBDIR = [".claude", "agents"];
// ---------------------------------------------------------------------------------------------

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(2);
}

// Definitions are loaded and validated once per source directory, not once per target — two
// targets could point to the same directory, and there's no reason validation should then run
// twice.
const sources = new Map();

for (const dir of new Set(TARGETS.map((t) => t.dir))) {
  const sourceDir = resolve(dir);
  if (!existsSync(sourceDir) || !statSync(sourceDir).isDirectory()) {
    fail(`directory not found: ${sourceDir}. Run this script from the root of the process source repository.`);
  }

  const definitions = readdirSync(sourceDir)
    .filter((f) => f.endsWith(".md"))
    .sort();

  if (definitions.length === 0) fail(`directory ${sourceDir} contains no role definitions (*.md).`);

  // A definition without a YAML header carrying name and description fields can't be loaded by
  // most agent environments. Better to abort here than to have a role that silently never runs.
  for (const file of definitions) {
    const body = readFileSync(join(sourceDir, file), "utf8");
    const front = body.match(/^---\r?\n([\s\S]*?)\r?\n---/);
    if (!front) fail(`${dir}/${file}: missing YAML frontmatter (--- ... ---).`);
    for (const field of ["name", "description"]) {
      if (!new RegExp(`^${field}:\\s*\\S`, "m").test(front[1])) {
        fail(`${dir}/${file}: YAML frontmatter is missing field "${field}".`);
      }
    }
    const declared = front[1].match(/^name:\s*(\S+)/m)[1];
    const expected = file.replace(/\.md$/, "");
    if (declared !== expected) {
      fail(`${dir}/${file}: field name="${declared}" does not match the file name "${expected}".`);
    }
  }

  sources.set(dir, { sourceDir, definitions });
}

// We ask git whether the path is ignored, instead of matching the .gitignore pattern ourselves.
// Returns true when ignored, false when not, null when the question can't be resolved
// (the directory isn't a git repository, or git isn't available).
function ignoredByGit(repoPath, relativePath) {
  try {
    execFileSync("git", ["check-ignore", "-q", "--", relativePath], {
      cwd: repoPath,
      stdio: "ignore",
    });
    return true;
  } catch (error) {
    if (error.status === 1) return false;
    return null;
  }
}

// The commit of THIS repository the definitions are read from, plus whether the source directory
// carries uncommitted changes. Reporting what was read is the remedy for the documented case of a
// copy several commits stale that reported full success (FrameworkDoc.md, section 9).
function sourceRevision(path) {
  try {
    const sha = execFileSync("git", ["rev-parse", "--short", "HEAD"], { encoding: "utf8" }).trim();
    const dirty = execFileSync("git", ["status", "--porcelain", "--", path], { encoding: "utf8" }).trim();
    return dirty ? `${sha} + uncommitted changes in ${path}/` : sha;
  } catch {
    return "unknown (not a git checkout, or git unavailable)";
  }
}

for (const dir of sources.keys()) {
  console.log(`Source ${dir}/: ${sourceRevision(dir)}`);
}

let drift = 0;
let copied = 0;
let total = 0;
let skipped = 0;

for (const target of TARGETS) {
  const { sourceDir, definitions } = sources.get(target.dir);

  // A missing target is not "no drift" — it is "nothing checked", and must not end in exit 0.
  if (!existsSync(target.path)) {
    console.error(`SKIPPED ${target.name}: not found: ${target.path}`);
    skipped++;
    continue;
  }
  total += definitions.length;

  // The target directory should stay outside the product repository's version control. The script
  // only warns: editing someone else's .gitignore is a decision for that repository's owner, not
  // for the script.
  const probePath = [...TARGET_SUBDIR, "probe.md"].join("/");
  const ignored = ignoredByGit(target.path, probePath);
  if (ignored === false) {
    console.warn(
      `WARNING ${target.name}: git does not ignore ${TARGET_SUBDIR.join("/")} — role definitions could end up in the product repository.`,
    );
  } else if (ignored === null) {
    console.warn(
      `WARNING ${target.name}: could not determine whether ${TARGET_SUBDIR.join("/")} is ignored (no git, or not a repository). Check by hand.`,
    );
  }

  const targetDir = join(target.path, ...TARGET_SUBDIR);
  if (!CHECK_ONLY) mkdirSync(targetDir, { recursive: true });

  for (const file of definitions) {
    const source = readFileSync(join(sourceDir, file), "utf8");
    const destination = join(targetDir, file);
    const current = existsSync(destination) ? readFileSync(destination, "utf8") : null;

    if (current === source) continue;

    drift++;
    const what = current === null ? "new" : "changed";
    if (CHECK_ONLY) {
      console.log(`DRIFT ${target.name}/${TARGET_SUBDIR.join("/")}/${file} (${what})`);
    } else {
      writeFileSync(destination, source);
      copied++;
      console.log(`WROTE ${target.name}/${TARGET_SUBDIR.join("/")}/${file} (${what})`);
    }
  }

  // A definition removed from the source must also disappear from the target, otherwise a retired
  // role keeps running from a stale copy.
  if (existsSync(targetDir)) {
    const orphans = readdirSync(targetDir).filter(
      (f) => f.endsWith(".md") && !definitions.includes(f),
    );
    for (const orphan of orphans) {
      drift++;
      console.log(
        `ORPHANED ${target.name}/${TARGET_SUBDIR.join("/")}/${orphan} — no source in ${target.dir}/, remove by hand`,
      );
    }
  }
}

if (skipped > 0) {
  console.error(`Skipped ${skipped} of ${TARGETS.length} targets — not checked. Fix the TARGETS paths or remove the entries.`);
}

if (CHECK_ONLY) {
  console.log(drift === 0 ? (skipped === 0 ? "No drift." : "No drift in the targets that were checked.") : `Drifted: ${drift}.`);
  process.exit(drift === 0 && skipped === 0 ? 0 : 1);
}

console.log(
  copied === 0
    ? `No changes. Definitions: ${total}.`
    : `Wrote ${copied} of ${total} definitions.`,
);
process.exit(skipped === 0 ? 0 : 1);
