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
//   node tools/sync-agents.mjs              copies the definitions, reports what changed
//   node tools/sync-agents.mjs --check      reports only drift, writes nothing (exit 1 on drift or a missing target)
//   node tools/sync-agents.mjs --self-test  runs the built-in contrast cases against temporary
//                                           fixtures and reports which failed (exit 0 only if all pass)
//
// The self-test also runs SILENTLY before every other mode (calibration/README.md, Method 3): a
// validator that has stopped checking anything keeps returning success, so the tool must prove it
// still tells a good input from a bad one before it is trusted with the real repositories. It
// prints nothing when it passes, so the output of the normal modes is unchanged; when it fails,
// the run stops with exit 2 before touching any target. CI runs `--self-test` explicitly, so the
// case list shows up in the log.
//
// Run from the root directory of THIS repository (the process source repository).

import {
  readdirSync,
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  statSync,
  mkdtempSync,
  rmSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const CHECK_ONLY = process.argv.includes("--check");
const SELF_TEST = process.argv.includes("--self-test");

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

// A validation failure is THROWN, not turned into process.exit on the spot, so that the
// self-test can run the very same code path against a bad fixture and observe the refusal. The
// CLI entry point at the bottom turns it back into the old "ERROR: ..." line and exit 2.
class ToolError extends Error {}

function fail(message) {
  throw new ToolError(message);
}

// Definitions are loaded and validated once per source directory, not once per target — two
// targets could point to the same directory, and there's no reason validation should then run
// twice. `root` is the root of the process source repository (the working directory for the CLI,
// a temporary fixture for the self-test).
function loadSources(targets, root) {
  const sources = new Map();

  for (const dir of new Set(targets.map((t) => t.dir))) {
    const sourceDir = resolve(root, dir);
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

  return sources;
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

// The whole sync/check run, parametrised by everything the CLI used to take from globals: the
// target list, the source root, the target subdirectory, the mode, where output goes (`out` has
// log/warn/error like console), how the source revision is described and how "is it ignored by
// git" is answered. Returns the exit code; throws ToolError on invalid source definitions.
function runSync({ targets, root, targetSubdir, checkOnly, out, revision, isIgnored }) {
  const sources = loadSources(targets, root);

  for (const dir of sources.keys()) {
    out.log(`Source ${dir}/: ${revision(dir)}`);
  }

  let drift = 0;
  let copied = 0;
  let total = 0;
  let skipped = 0;

  for (const target of targets) {
    const { sourceDir, definitions } = sources.get(target.dir);

    // A missing target is not "no drift" — it is "nothing checked", and must not end in exit 0.
    if (!existsSync(target.path)) {
      out.error(`SKIPPED ${target.name}: not found: ${target.path}`);
      skipped++;
      continue;
    }
    total += definitions.length;

    // The target directory should stay outside the product repository's version control. The
    // script only warns: editing someone else's .gitignore is a decision for that repository's
    // owner, not for the script.
    const probePath = [...targetSubdir, "probe.md"].join("/");
    const ignored = isIgnored(target.path, probePath);
    if (ignored === false) {
      out.warn(
        `WARNING ${target.name}: git does not ignore ${targetSubdir.join("/")} — role definitions could end up in the product repository.`,
      );
    } else if (ignored === null) {
      out.warn(
        `WARNING ${target.name}: could not determine whether ${targetSubdir.join("/")} is ignored (no git, or not a repository). Check by hand.`,
      );
    }

    const targetDir = join(target.path, ...targetSubdir);
    if (!checkOnly) mkdirSync(targetDir, { recursive: true });

    for (const file of definitions) {
      const source = readFileSync(join(sourceDir, file), "utf8");
      const destination = join(targetDir, file);
      const current = existsSync(destination) ? readFileSync(destination, "utf8") : null;

      if (current === source) continue;

      drift++;
      const what = current === null ? "new" : "changed";
      if (checkOnly) {
        out.log(`DRIFT ${target.name}/${targetSubdir.join("/")}/${file} (${what})`);
      } else {
        writeFileSync(destination, source);
        copied++;
        out.log(`WROTE ${target.name}/${targetSubdir.join("/")}/${file} (${what})`);
      }
    }

    // A definition removed from the source must also disappear from the target, otherwise a
    // retired role keeps running from a stale copy.
    if (existsSync(targetDir)) {
      const orphans = readdirSync(targetDir).filter(
        (f) => f.endsWith(".md") && !definitions.includes(f),
      );
      for (const orphan of orphans) {
        drift++;
        out.log(
          `ORPHANED ${target.name}/${targetSubdir.join("/")}/${orphan} — no source in ${target.dir}/, remove by hand`,
        );
      }
    }
  }

  if (skipped > 0) {
    out.error(`Skipped ${skipped} of ${targets.length} targets — not checked. Fix the TARGETS paths or remove the entries.`);
  }

  if (checkOnly) {
    out.log(drift === 0 ? (skipped === 0 ? "No drift." : "No drift in the targets that were checked.") : `Drifted: ${drift}.`);
    return drift === 0 && skipped === 0 ? 0 : 1;
  }

  out.log(
    copied === 0
      ? `No changes. Definitions: ${total}.`
      : `Wrote ${copied} of ${total} definitions.`,
  );
  return skipped === 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------- self-test
//
// Built-in contrast cases (calibration/README.md, Method 3). Every "should fail" case has a
// "should pass" sibling built from the same fixture minus the defect, so a case can only go green
// because the check under test actually fired — not because the fixture was broken in some other
// way. The expectations look at BOTH the exit code and the specific message: an exit 2 caused by
// a different error (a typo in the fixture, a missing directory) must not count as the check
// working.

function definition(name, { description = "Self-test role.", body = "Body.\n" } = {}) {
  const lines = ["---"];
  if (name !== null) lines.push(`name: ${name}`);
  if (description !== null) lines.push(`description: ${description}`);
  lines.push("---", "", body);
  return lines.join("\n");
}

// Builds a throwaway source repository + one product repository, runs the tool against it, and
// always removes the directory — also when the case throws.
function withFixture({ sources = {}, target = {}, createTarget = true }, run) {
  const root = mkdtempSync(join(tmpdir(), "sync-agents-self-test-"));
  try {
    mkdirSync(join(root, "agents"));
    for (const [file, content] of Object.entries(sources)) writeFileSync(join(root, "agents", file), content);
    const targetPath = join(root, "product");
    if (createTarget) {
      mkdirSync(join(targetPath, ...TARGET_SUBDIR), { recursive: true });
      for (const [file, content] of Object.entries(target)) {
        writeFileSync(join(targetPath, ...TARGET_SUBDIR, file), content);
      }
    }
    return run({ root, targets: [{ name: "fixture", path: targetPath, dir: "agents" }], targetPath });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

// Runs the tool with captured output. `error` is the ToolError message when validation refused.
function invoke({ root, targets, checkOnly }) {
  const lines = [];
  const out = { log: (m) => lines.push(m), warn: (m) => lines.push(m), error: (m) => lines.push(m) };
  try {
    const code = runSync({
      targets,
      root,
      targetSubdir: TARGET_SUBDIR,
      checkOnly,
      out,
      revision: () => "self-test",
      // Not asking git: the fixture is not a repository, and the case list must not depend on
      // whether git is installed on the runner.
      isIgnored: () => true,
    });
    return { code, lines, error: null };
  } catch (error) {
    if (!(error instanceof ToolError)) throw error;
    return { code: 2, lines, error: error.message };
  }
}

const SELF_TEST_CASES = [
  {
    name: "valid definition passes validation and is copied",
    run: () =>
      withFixture({ sources: { "role-a.md": definition("role-a") } }, (f) => {
        const r = invoke({ ...f, checkOnly: false });
        const copied = existsSync(join(f.targetPath, ...TARGET_SUBDIR, "role-a.md"));
        return r.code === 0 && r.error === null && copied && r.lines.includes("Wrote 1 of 1 definitions.")
          ? null
          : `expected exit 0 and one definition written, got exit ${r.code}, error ${r.error}`;
      }),
  },
  {
    name: "definition without frontmatter is refused",
    run: () =>
      withFixture({ sources: { "role-a.md": "# role-a\n\nNo header here.\n" } }, (f) => {
        const r = invoke({ ...f, checkOnly: true });
        return r.code === 2 && /missing YAML frontmatter/.test(r.error ?? "")
          ? null
          : `expected refusal "missing YAML frontmatter", got exit ${r.code}, error ${r.error}`;
      }),
  },
  {
    name: "definition without `name` is refused",
    run: () =>
      withFixture({ sources: { "role-a.md": definition(null) } }, (f) => {
        const r = invoke({ ...f, checkOnly: true });
        return r.code === 2 && /missing field "name"/.test(r.error ?? "")
          ? null
          : `expected refusal 'missing field "name"', got exit ${r.code}, error ${r.error}`;
      }),
  },
  {
    name: "definition without `description` is refused",
    run: () =>
      withFixture({ sources: { "role-a.md": definition("role-a", { description: null }) } }, (f) => {
        const r = invoke({ ...f, checkOnly: true });
        return r.code === 2 && /missing field "description"/.test(r.error ?? "")
          ? null
          : `expected refusal 'missing field "description"', got exit ${r.code}, error ${r.error}`;
      }),
  },
  {
    name: "name different from file name is refused",
    run: () =>
      withFixture({ sources: { "role-a.md": definition("role-b") } }, (f) => {
        const r = invoke({ ...f, checkOnly: true });
        return r.code === 2 && /does not match the file name/.test(r.error ?? "")
          ? null
          : `expected refusal "does not match the file name", got exit ${r.code}, error ${r.error}`;
      }),
  },
  {
    name: "identical target content is not drift",
    run: () =>
      withFixture(
        { sources: { "role-a.md": definition("role-a") }, target: { "role-a.md": definition("role-a") } },
        (f) => {
          const r = invoke({ ...f, checkOnly: true });
          return r.code === 0 && r.lines.includes("No drift.")
            ? null
            : `expected exit 0 and "No drift.", got exit ${r.code}: ${r.lines.join(" | ")}`;
        },
      ),
  },
  {
    name: "changed target content is drift",
    run: () =>
      withFixture(
        {
          sources: { "role-a.md": definition("role-a") },
          target: { "role-a.md": definition("role-a", { body: "Stale body.\n" }) },
        },
        (f) => {
          const r = invoke({ ...f, checkOnly: true });
          const reported = r.lines.some((l) => l.startsWith("DRIFT fixture/") && l.endsWith("role-a.md (changed)"));
          return r.code === 1 && reported
            ? null
            : `expected exit 1 and a DRIFT (changed) line, got exit ${r.code}: ${r.lines.join(" | ")}`;
        },
      ),
  },
  {
    name: "orphaned file in the target is reported",
    run: () =>
      withFixture(
        {
          sources: { "role-a.md": definition("role-a") },
          target: { "role-a.md": definition("role-a"), "retired.md": definition("retired") },
        },
        (f) => {
          const r = invoke({ ...f, checkOnly: true });
          const reported = r.lines.some((l) => l.startsWith("ORPHANED fixture/") && l.includes("retired.md"));
          return r.code === 1 && reported
            ? null
            : `expected exit 1 and an ORPHANED line, got exit ${r.code}: ${r.lines.join(" | ")}`;
        },
      ),
  },
  {
    name: "missing target makes --check exit non-zero, not \"No drift.\"",
    run: () =>
      withFixture({ sources: { "role-a.md": definition("role-a") }, createTarget: false }, (f) => {
        const r = invoke({ ...f, checkOnly: true });
        const skipped = r.lines.some((l) => l.startsWith("SKIPPED fixture:"));
        return r.code !== 0 && skipped && !r.lines.includes("No drift.")
          ? null
          : `expected non-zero exit, a SKIPPED line and no "No drift.", got exit ${r.code}: ${r.lines.join(" | ")}`;
      }),
  },
];

// Returns the list of failures ({ name, reason }); an empty list means every case passed. A case
// that throws counts as failed, with the exception as the reason — a crashing self-test must not
// read as a passing one.
function selfTest() {
  const failures = [];
  for (const testCase of SELF_TEST_CASES) {
    let reason;
    try {
      reason = testCase.run();
    } catch (error) {
      reason = `threw: ${error?.stack ?? error}`;
    }
    if (reason) failures.push({ name: testCase.name, reason });
  }
  return failures;
}

function reportSelfTest(failures, log) {
  for (const failure of failures) log(`SELF-TEST FAILED: ${failure.name} — ${failure.reason}`);
  log(`Self-test: ${SELF_TEST_CASES.length} cases ran, ${SELF_TEST_CASES.length - failures.length} passed, ${failures.length} failed.`);
}

// ---------------------------------------------------------------------------- entry point

if (SELF_TEST) {
  const failures = selfTest();
  for (const testCase of SELF_TEST_CASES) {
    const failed = failures.some((f) => f.name === testCase.name);
    console.log(`${failed ? "FAIL" : "ok  "} ${testCase.name}`);
  }
  reportSelfTest(failures, failures.length === 0 ? console.log : console.error);
  process.exit(failures.length === 0 ? 0 : 1);
}

{
  const failures = selfTest();
  if (failures.length > 0) {
    reportSelfTest(failures, console.error);
    console.error("ERROR: the tool failed its own self-test — refusing to touch the targets.");
    process.exit(2);
  }
}

try {
  process.exit(
    runSync({
      targets: TARGETS,
      root: process.cwd(),
      targetSubdir: TARGET_SUBDIR,
      checkOnly: CHECK_ONLY,
      out: console,
      revision: sourceRevision,
      isIgnored: ignoredByGit,
    }),
  );
} catch (error) {
  if (!(error instanceof ToolError)) throw error;
  console.error(`ERROR: ${error.message}`);
  process.exit(2);
}
