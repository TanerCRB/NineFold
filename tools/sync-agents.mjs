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
// `agentsMd` — optional: a file in the product repository, usually "AGENTS.md", that gets a
//          generated role index between two markers, for agent tools that read AGENTS.md and
//          can't load subagents. Text outside the markers stays the team's. Unlike the role
//          copies, the file is versioned, so a change to it goes through a pull request.
const TARGETS = [
  { name: "<repo-backend>", path: resolve("..", "<repo-backend>"), dir: "agents" },
  { name: "<repo-frontend>", path: resolve("..", "<repo-frontend>"), dir: "agents" },
];

const TARGET_SUBDIR = [".claude", "agents"];
// ---------------------------------------------------------------------------------------------

// A validation failure is THROWN, not turned into process.exit on the spot, so that the
// self-test can run the very same code path against a bad fixture and observe the refusal. The
// CLI entry point at the bottom turns it into a "sync-agents: failed — ..." line and exit 2.
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
    const roles = [];
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
      const description = front[1].match(/^description:\s*(.+)$/m)[1].trim().replace(/^(["'])(.*)\1$/, "$2");
      roles.push({ name: declared, description });
    }

    sources.set(dir, { sourceDir, definitions, roles });
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
// An unfilled `<placeholder>` in TARGETS is a configuration nobody finished, not a target that
// happens to be missing. Reported as SKIPPED it would read like a path typo; refused, it says
// exactly what to do (process/bootstrap-guide.md, step 1).
function rejectPlaceholders(targets) {
  for (const target of targets) {
    for (const [field, value] of [["name", target.name], ["path", target.path]]) {
      const placeholder = String(value).match(/<[^<>]+>/);
      if (placeholder) {
        fail(
          `TARGETS still contains the placeholder "${placeholder[0]}" (field "${field}"). ` +
            `Replace it with your product repository before running — see process/bootstrap-guide.md, step 1.`,
        );
      }
    }
  }
}

const INDEX_BEGIN = "<!-- ninefold:roles:begin -->";
const INDEX_END = "<!-- ninefold:roles:end -->";

// The generated part of an AGENTS.md. A tool that can't load subagents gets what the task command
// does in its general-purpose mode: read the role's file and follow it, and keep to its tools line
// by hand, because nothing enforces it there.
function rolesBlock(roles, targetSubdir, eol) {
  const cell = (text) => text.replace(/\|/g, "\\|");
  return [
    INDEX_BEGIN,
    "<!-- Generated by tools/sync-agents.mjs in the process repository. Edit the role files there, not this block. -->",
    "## Roles",
    "",
    "This repository runs the Ninefold process. Each role is defined in its own file. To work as a role,",
    "read its file in full and follow it as your instructions for that task. Its `tools` line says what the",
    "role may use; if your agent tool doesn't enforce it, keep to it yourself.",
    "",
    "| Role | Definition | When to use it |",
    "|---|---|---|",
    ...roles.map((r) => `| ${r.name} | \`${targetSubdir.join("/")}/${r.name}.md\` | ${cell(r.description)} |`),
    INDEX_END,
  ].join(eol);
}

// The index file as it should be: the block replaced in place, appended to a file without one, or
// a new file. Broken markers are refused — guessing where the team's text ends would overwrite it.
function plannedIndex(current, roles, targetSubdir, label) {
  const eol = current?.includes("\r\n") ? "\r\n" : "\n";
  const block = rolesBlock(roles, targetSubdir, eol);
  if (current === null) return { content: block + eol, what: "new" };
  const begins = current.split(INDEX_BEGIN).length - 1;
  const ends = current.split(INDEX_END).length - 1;
  if (begins === 0 && ends === 0) {
    return { content: current.replace(/\s*$/, "") + eol + eol + block + eol, what: "block added" };
  }
  const begin = current.indexOf(INDEX_BEGIN);
  const end = current.indexOf(INDEX_END);
  if (begins !== 1 || ends !== 1 || end < begin) {
    fail(`${label}: broken role-index markers (${begins} begin, ${ends} end) — fix them by hand, then run again.`);
  }
  return { content: current.slice(0, begin) + block + current.slice(end + INDEX_END.length), what: "changed" };
}

function runSync({ targets, root, targetSubdir, checkOnly, out, revision, isIgnored }) {
  rejectPlaceholders(targets);
  const sources = loadSources(targets, root);

  for (const dir of sources.keys()) {
    out.log(`Source ${dir}/: ${revision(dir)}`);
  }

  // Every index file is planned before anything is written, so broken markers in the second target
  // don't leave the first one half-synced.
  const indexes = new Map();
  for (const target of targets) {
    if (!target.agentsMd || !existsSync(target.path)) continue;
    if (/^([\\/]|[A-Za-z]:)/.test(target.agentsMd) || target.agentsMd.split(/[\\/]/).includes("..")) {
      fail(`${target.name}: agentsMd must be a path inside the product repository, got "${target.agentsMd}".`);
    }
    const file = join(target.path, target.agentsMd);
    const current = existsSync(file) ? readFileSync(file, "utf8") : null;
    const label = `${target.name}/${target.agentsMd}`;
    indexes.set(target, { file, current, label, ...plannedIndex(current, sources.get(target.dir).roles, targetSubdir, label) });
  }

  let drift = 0;
  let copied = 0;
  let total = 0;
  let skipped = 0;
  let indexed = 0;

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

    const index = indexes.get(target);
    if (index && index.content !== index.current) {
      drift++;
      if (checkOnly) {
        out.log(`DRIFT ${index.label} (role index ${index.what})`);
      } else {
        writeFileSync(index.file, index.content);
        indexed++;
        out.log(`WROTE ${index.label} (role index ${index.what}) — versioned: commit it through a pull request`);
      }
    }
  }

  if (skipped > 0) {
    out.error(`Skipped ${skipped} of ${targets.length} targets — not checked. Fix the TARGETS paths or remove the entries.`);
  }

  // The exit contract (process/ci-and-branch-protection.md, "Exit contract"): the last line is the result.
  if (checkOnly) {
    out.log(drift === 0 ? (skipped === 0 ? "No drift." : "No drift in the targets that were checked.") : `Drifted: ${drift}.`);
    out.log(drift + skipped === 0
      ? `sync-agents: clean — no drift in ${targets.length} target(s)`
      : `sync-agents: ${drift + skipped} finding(s) — ${drift} drifted, ${skipped} target(s) not checked`);
    return drift === 0 && skipped === 0 ? 0 : 1;
  }

  out.log(
    copied === 0
      ? `No changes. Definitions: ${total}.`
      : `Wrote ${copied} of ${total} definitions.`,
  );
  if (indexed > 0) out.log(`Wrote ${indexed} role index file(s).`);
  out.log(skipped === 0
    ? `sync-agents: clean — ${copied} of ${total} definitions written`
    : `sync-agents: ${skipped} finding(s) — target(s) not reached`);
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
function withFixture({ sources = {}, target = {}, createTarget = true, agentsMd, index }, run) {
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
      if (index !== undefined) writeFileSync(join(targetPath, "AGENTS.md"), index);
    }
    const indexPath = join(targetPath, "AGENTS.md");
    const readIndex = () => (existsSync(indexPath) ? readFileSync(indexPath, "utf8") : null);
    return run({ root, targets: [{ name: "fixture", path: targetPath, dir: "agents", agentsMd }], targetPath, readIndex });
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
    name: "the last line states the result (exit contract)",
    run: () =>
      withFixture(
        { sources: { "role-a.md": definition("role-a") }, target: { "role-a.md": definition("role-a") } },
        (f) => {
          const r = invoke({ ...f, checkOnly: true });
          return r.lines.at(-1) === "sync-agents: clean — no drift in 1 target(s)"
            ? null
            : `expected the result as the last line, got '${r.lines.at(-1)}'`;
        },
      ),
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
  {
    name: "AGENTS.md: a missing file is created with one row per role",
    run: () =>
      withFixture(
        { sources: { "role-a.md": definition("role-a", { description: "Does A." }), "role-b.md": definition("role-b") }, agentsMd: "AGENTS.md" },
        (f) => {
          const r = invoke({ ...f, checkOnly: false });
          const text = f.readIndex() ?? "";
          const rows = ["| role-a | `.claude/agents/role-a.md` | Does A. |", "| role-b | `.claude/agents/role-b.md` | Self-test role. |"];
          return r.code === 0 && text.startsWith(INDEX_BEGIN) && rows.every((row) => text.includes(row)) &&
            r.lines.some((l) => l.startsWith("WROTE fixture/AGENTS.md (role index new)"))
            ? null
            : `expected a new index with both rows, got exit ${r.code}: ${text}`;
        },
      ),
  },
  {
    name: "AGENTS.md: the team's text stays when the block is appended",
    run: () =>
      withFixture(
        { sources: { "role-a.md": definition("role-a") }, agentsMd: "AGENTS.md", index: "# Team notes\n\nBuild with make.\n" },
        (f) => {
          invoke({ ...f, checkOnly: false });
          const text = f.readIndex() ?? "";
          return text.startsWith("# Team notes\n\nBuild with make.\n\n" + INDEX_BEGIN) && text.endsWith(INDEX_END + "\n")
            ? null
            : `expected the team's text first and the block after it, got: ${text}`;
        },
      ),
  },
  {
    name: "AGENTS.md: a stale block is drift, and is replaced in place",
    run: () =>
      withFixture(
        {
          sources: { "role-a.md": definition("role-a") },
          agentsMd: "AGENTS.md",
          index: `Before.\r\n${INDEX_BEGIN}\r\n| retired | gone |\r\n${INDEX_END}\r\nAfter.\r\n`,
        },
        (f) => {
          const check = invoke({ ...f, checkOnly: true });
          if (check.code !== 1 || !check.lines.includes("DRIFT fixture/AGENTS.md (role index changed)")) {
            return `expected --check to report the stale block, got exit ${check.code}: ${check.lines.join(" | ")}`;
          }
          invoke({ ...f, checkOnly: false });
          const text = f.readIndex() ?? "";
          return text.startsWith(`Before.\r\n${INDEX_BEGIN}\r\n`) && text.endsWith(`${INDEX_END}\r\nAfter.\r\n`) &&
            !text.includes("retired") && text.includes("| role-a |")
            ? null
            : `expected the block replaced between the team's lines with CRLF kept, got: ${JSON.stringify(text)}`;
        },
      ),
  },
  {
    name: "AGENTS.md: an up-to-date block is clean in --check",
    run: () =>
      withFixture(
        {
          sources: { "role-a.md": definition("role-a") },
          target: { "role-a.md": definition("role-a") },
          agentsMd: "AGENTS.md",
          index: `Notes.\n\n${rolesBlock([{ name: "role-a", description: "Self-test role." }], TARGET_SUBDIR, "\n")}\n`,
        },
        (f) => {
          const r = invoke({ ...f, checkOnly: true });
          return r.code === 0 && r.lines.at(-1) === "sync-agents: clean — no drift in 1 target(s)"
            ? null
            : `expected exit 0 and a clean last line, got exit ${r.code}: ${r.lines.join(" | ")}`;
        },
      ),
  },
  {
    name: "AGENTS.md: broken markers are refused before anything is written",
    run: () =>
      withFixture(
        { sources: { "role-a.md": definition("role-a") }, createTarget: true, agentsMd: "AGENTS.md", index: `Notes.\n${INDEX_BEGIN}\nno end\n` },
        (f) => {
          const r = invoke({ ...f, checkOnly: false });
          const written = existsSync(join(f.targetPath, ...TARGET_SUBDIR, "role-a.md"));
          return r.code === 2 && /broken role-index markers \(1 begin, 0 end\)/.test(r.error ?? "") && !written &&
            f.readIndex() === `Notes.\n${INDEX_BEGIN}\nno end\n`
            ? null
            : `expected exit 2, nothing written and the file untouched, got exit ${r.code}, error ${r.error}, written ${written}`;
        },
      ),
  },
  {
    name: "AGENTS.md: a | in a description doesn't break the table",
    run: () =>
      withFixture(
        { sources: { "role-a.md": definition("role-a", { description: "Reads A | B." }) }, agentsMd: "AGENTS.md" },
        (f) => {
          invoke({ ...f, checkOnly: false });
          return (f.readIndex() ?? "").includes("| role-a | `.claude/agents/role-a.md` | Reads A \\| B. |")
            ? null
            : `expected the | escaped, got: ${f.readIndex()}`;
        },
      ),
  },
  {
    name: "AGENTS.md: a target without agentsMd gets no index file",
    run: () =>
      withFixture({ sources: { "role-a.md": definition("role-a") } }, (f) => {
        const r = invoke({ ...f, checkOnly: false });
        return r.code === 0 && f.readIndex() === null ? null : `expected no AGENTS.md, got exit ${r.code}, file ${f.readIndex()}`;
      }),
  },
  {
    name: "AGENTS.md: a path outside the product repository is refused",
    run: () =>
      withFixture({ sources: { "role-a.md": definition("role-a") }, agentsMd: "../AGENTS.md" }, (f) => {
        const r = invoke({ ...f, checkOnly: false });
        return r.code === 2 && /must be a path inside the product repository/.test(r.error ?? "")
          ? null
          : `expected a refusal, got exit ${r.code}, error ${r.error}`;
      }),
  },
  {
    name: "unfilled <placeholder> in TARGETS is refused before anything is written",
    run: () =>
      withFixture({ sources: { "role-a.md": definition("role-a") } }, (f) => {
        const targets = [{ ...f.targets[0], name: "<repo-backend>" }];
        const r = invoke({ ...f, targets, checkOnly: false });
        const written = existsSync(join(f.targetPath, ...TARGET_SUBDIR, "role-a.md"));
        return r.code === 2 && /placeholder "<repo-backend>"/.test(r.error ?? "") && !written
          ? null
          : `expected refusal naming the placeholder and nothing written, got exit ${r.code}, error ${r.error}, written ${written}`;
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
    console.error("sync-agents: failed — the tool failed its own self-test; refusing to touch the targets.");
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
  console.error(`sync-agents: failed — ${error.message}`);
  process.exit(2);
}
