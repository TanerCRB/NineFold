#!/usr/bin/env node
// Distributes process configuration from the source repository to the product repositories:
// Issue and pull request templates as files, labels as gh commands to review and run by hand.
//
// Why labels are only PRINTED, not applied: a label is a repository setting on GitHub's side,
// not a file in the tree. This script has no credentials and shouldn't have any — it prints the
// commands so they can be reviewed before anything touches the remote repository.
//
// Unlike the directory with role definitions (see sync-agents.mjs), the .github/ directory IS
// tracked by the product repository. Files written here show up in `git status` and are
// committed deliberately, by a human. This script never commits by itself.
//
// Deliberately does not touch .github/workflows/ — a change to the CI pipeline is a decision
// with consequences; it goes through code review, not through a sync run.
//
// Usage:
//   node tools/sync-github.mjs              copies templates, reports what changed
//   node tools/sync-github.mjs --check      reports only drift, writes nothing (exit 1 on drift or a missing target)
//   node tools/sync-github.mjs --labels     prints gh commands for labels (bash), writes nothing
//   node tools/sync-github.mjs --labels-ps1 same, for PowerShell
//   node tools/sync-github.mjs --self-test  runs the built-in contrast cases against temporary
//                                           fixtures and reports which failed (exit 0 only if all pass)
//
// Two shells instead of one: if you also work on Windows, pasting bash syntax straight into
// PowerShell already fails on the header. The gh calls themselves are identical; only the header
// and the apostrophe-quoting rule differ.
//
// The self-test also runs SILENTLY before every other mode (calibration/README.md, Method 3): a
// validator that has stopped checking anything keeps returning success, so the tool must prove it
// still tells a good input from a bad one before it is trusted with the real manifest and
// repositories. It prints nothing when it passes, so the output of the normal modes (including
// the --labels script meant to be piped into a shell) is unchanged; when it fails, the run stops
// with exit 2 before printing or writing anything. CI runs `--self-test` explicitly, so the case
// list shows up in the log.
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

const SELF_TEST = process.argv.includes("--self-test");
const CHECK_ONLY = process.argv.includes("--check");
const LABELS_BASH = process.argv.includes("--labels");
const LABELS_PWSH = process.argv.includes("--labels-ps1");
const LABELS_ONLY = LABELS_BASH || LABELS_PWSH;

// ---------------------------------------------------------------------------- CONFIGURATION
//
// Substitute for your own project's reality and your GitHub organization/account.
const OWNER = "<organization-or-account>";

// Each entry is one target repository. By default (without `templates`/`labels` fields) a target
// gets the FULL SET of templates and labels — that's the right behavior for a production
// repository with the full process (roles, gates, decision log).
//
// A repository without the full process (e.g. an infrastructure-only repository, or a repository
// used purely to order work from another team) gets a SUBSET — see the example entries below.
//
// `overrides` — overrides the content of ONE file in this set with a different source name, while
//   keeping the target name (because GitHub only reads a fixed name, e.g.
//   .github/PULL_REQUEST_TEMPLATE.md — you can't have two versions under different names and pick
//   which one you get).
// `templates` — restricts the set of copied Issue/PR templates to the listed file names.
// `labels` — restricts the set of labels to the listed names from the manifest.
const TARGETS = [
  {
    name: "<repo-backend>",
    path: resolve("..", "<repo-backend>"),
  },
  {
    name: "<repo-frontend>",
    path: resolve("..", "<repo-frontend>"),
    // Example: the PR template's invariant checklist differs between stacks — the backend asks
    // about things the frontend doesn't have (and vice versa), and a template with fields that
    // can't be checked teaches people to scroll to the end without reading. An override instead
    // of a separate file, because the target name has to stay the same.
    overrides: { "PULL_REQUEST_TEMPLATE.md": "PULL_REQUEST_TEMPLATE-frontend.md" },
  },
  {
    // Example of a repository WITHOUT the full process: it has gate 2 and pull requests, but
    // doesn't define its own agent roles or its own architectural decision log (it inherits that
    // from the backend repository or the process source repository — see FrameworkDoc.md,
    // section 10).
    name: "<repo-infra>",
    path: resolve("..", "<repo-infra>"),
    // No architectural decision form — this type of repository doesn't keep its own decision
    // log. The QA report stays: an environment is a place where defects are found through use,
    // and it needs somewhere to go.
    templates: [
      "1-story.yml",
      "3-qa-report.yml",
      "4-gap-from-other-repo.yml",
      "config.yml",
      "PULL_REQUEST_TEMPLATE.md",
    ],
    overrides: { "PULL_REQUEST_TEMPLATE.md": "PULL_REQUEST_TEMPLATE-infra.md" },
    // The full set of states without the "state:design" label (the map of impact on architectural
    // decisions isn't produced here) and without labels for code-writing roles (nobody writes
    // product code here).
    labels: [
      "state:analysis",
      "state:decision",
      "state:implementation",
      "state:qa",
      "state:merge",
      "state:evidence",
      "state:closed",
      "role:po",
      "role:analyst",
      "role:architect",
      "role:qa",
      "role:invariant-guardian",
      "role:reviewer",
      "role:security-auditor",
      "waiting-on-human",
      "blocked",
      "evidence:missing",
      "severity:high",
      "severity:medium",
      "severity:low",
      "gap:reported-by-frontend",
      "gap:reported-by-backend",
      "gap:awaiting-contract",
    ],
  },
  {
    // Example of a repository that is EXCLUSIVELY an order recipient (e.g. a design team, an
    // external vendor) — no gates, roles, or decision log. Gets only what's needed to be able to
    // be a target of the "gap from the other repository" channel (FrameworkDoc.md, section 11).
    name: "<repo-order-recipient>",
    path: resolve("..", "<repo-order-recipient>"),
    templates: ["4-gap-from-other-repo.yml", "config.yml"],
    labels: [
      "state:analysis",
      "state:closed",
      "waiting-on-human",
      "blocked",
      "gap:reported-by-frontend",
      "gap:reported-by-backend",
      "gap:awaiting-contract",
    ],
  },
];

// Relative to the root of THIS repository — the same working directory sync-agents.mjs expects.
const TEMPLATE_DIR = resolve("process", "issue-templates");
const LABEL_MANIFEST = resolve("process", "labels.json");
// ---------------------------------------------------------------------------------------------

// Everything else in the templates directory is an Issue form and lands under ISSUE_TEMPLATE/.
const REPO_ROOT_TEMPLATES = new Set(["PULL_REQUEST_TEMPLATE.md"]);

// A validation failure is THROWN, not turned into process.exit on the spot, so that the
// self-test can run the very same code path against a bad fixture and observe the refusal. The
// CLI entry point at the bottom turns it back into the old "ERROR: ..." line and exit 2.
class ToolError extends Error {}

function fail(message) {
  throw new ToolError(message);
}

// The commit of THIS repository the files are read from, plus whether the source path carries
// uncommitted changes. "unknown" instead of failing: the report must say it, not hide it.
function sourceRevision(path) {
  try {
    const sha = execFileSync("git", ["rev-parse", "--short", "HEAD"], { encoding: "utf8" }).trim();
    const dirty = execFileSync("git", ["status", "--porcelain", "--", path], { encoding: "utf8" }).trim();
    return dirty ? `${sha} + uncommitted changes in ${path}` : sha;
  } catch {
    return "unknown (not a git checkout, or git unavailable)";
  }
}

// Both shells use single quotes for the literal, but escape an apostrophe inside it
// differently: bash closes and reopens the quote, PowerShell doubles the apostrophe.
function shellQuote(value, pwsh) {
  return pwsh
    ? `'${String(value).replaceAll("'", "''")}'`
    : `'${String(value).replaceAll("'", `'\\''`)}'`;
}

// ---------------------------------------------------------------------------- labels

// Reads and validates the manifest AND every target's label subset, before a single line of the
// script is printed. (The subset check used to run while the script was being emitted, which left
// a half-printed script on stdout ahead of the error — useless, and dangerous if piped into a
// shell.) Returns the flat list of labels.
function loadLabels(manifestPath, targets) {
  if (!existsSync(manifestPath)) fail(`not found: ${manifestPath}.`);

  let manifest;
  try {
    manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  } catch (error) {
    fail(`${manifestPath} is not valid JSON: ${error.message}`);
  }

  const labels = [];
  const seen = new Set();
  for (const [group, value] of Object.entries(manifest)) {
    if (group.startsWith("$") || !value?.labels) continue;
    for (const label of value.labels) {
      for (const field of ["name", "color", "description"]) {
        if (!label?.[field]) fail(`a label in group "${group}" is missing field "${field}".`);
      }
      // A duplicate name would mean a later definition silently wins on the remote repo.
      if (seen.has(label.name)) fail(`label "${label.name}" is defined more than once.`);

      // Pure ASCII, enforced by an assertion, not by trust. The path from this file to GitHub
      // is node -> shell -> gh, and on Windows PowerShell 5.1 every hop can re-encode the text
      // through the console code page. A dash made that trip once and came back as three bytes
      // of garbage: the label existed, looked like it had been created, and the description was
      // wrong. Nothing failed loudly — and that is exactly the class of defect this project
      // answers with an assertion, not with carefulness.
      for (const field of ["name", "description"]) {
        const offending = [...label[field]].find((c) => c.charCodeAt(0) > 127);
        if (offending) {
          fail(
            `label "${label.name}", field "${field}": character outside ASCII ` +
              `"${offending}" (U+${offending.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")}). ` +
              `The label manifest must be pure ASCII.`,
          );
        }
      }
      if (!/^[0-9a-f]{6}$/.test(label.color)) {
        fail(`label "${label.name}": color "${label.color}" is not a six-character hex value without #.`);
      }
      seen.add(label.name);
      labels.push(label);
    }
  }

  if (labels.length === 0) fail("the manifest contains no labels.");

  // A typo in the subset would be silent: the target would get one label fewer, and a form
  // referencing it would stop applying it.
  for (const target of targets) {
    for (const missing of (target.labels || []).filter((n) => !seen.has(n))) {
      fail(`target ${target.name} requests label "${missing}", which is not in the manifest.`);
    }
  }

  return labels;
}

// Returns the script as a list of lines; the caller prints them.
function renderLabelScript({ labels, targets, owner, pwsh }) {
  const lines = [];
  if (pwsh) {
    lines.push("# Generated by tools/sync-github.mjs --labels-ps1. Review before running.");
    lines.push("# --force overwrites the color and description of an existing label, so the run is idempotent.");
    lines.push("#");
    lines.push("# Run the WHOLE file at once, not line by line:");
    lines.push("#   Invoke-Expression (Get-Content <file> -Raw)");
    lines.push("# Get-Content without -Raw feeds the file line by line, and Invoke-Expression rejects");
    lines.push("# an empty string, so the blank lines below would throw a parameter-binding error.");
    lines.push("#");
    lines.push("# We deliberately do NOT set $ErrorActionPreference = 'Stop': gh writes to stderr");
    lines.push("# even on success, which Windows PowerShell 5.1 can turn into a");
    lines.push("# NativeCommandError. Every call is independent and idempotent");
    lines.push("# (--force), so it's better for the run to reach the end and show what actually failed.");
    lines.push("");
  } else {
    lines.push("#!/usr/bin/env bash");
    lines.push("# Generated by tools/sync-github.mjs --labels. Review before running.");
    lines.push("# --force overwrites the color and description of an existing label, so the run is idempotent.");
    lines.push("set -euo pipefail");
    lines.push("");
  }
  // Every call carries its own --repo. Relying on gh inferring the repository from the current
  // directory's remote looks fine with a single target and breaks silently with several: the run
  // only passes from one specific working directory, yet looks correct wherever the first block
  // happens to run.
  let emitted = 0;
  for (const target of targets) {
    const wanted = target.labels ? labels.filter((l) => target.labels.includes(l.name)) : labels;
    lines.push(`# ---- ${target.name} (${wanted.length} of ${labels.length}) ----`);
    for (const label of wanted) {
      lines.push(
        `gh label create ${shellQuote(label.name, pwsh)} --color ${shellQuote(label.color, pwsh)} ` +
          `--description ${shellQuote(label.description, pwsh)} --repo ${owner}/${target.name} --force`,
      );
    }
    lines.push("");
    emitted += wanted.length;
  }
  lines.push(`# Calls emitted: ${emitted}. Labels in manifest: ${labels.length}.`);
  return lines;
}

// ---------------------------------------------------------------------------- templates

// Lists and validates the templates in `templateDir` against the targets' overrides. Returns the
// list of distributable template file names.
function loadTemplates(templateDir, targets) {
  if (!existsSync(templateDir) || !statSync(templateDir).isDirectory()) {
    fail(`not found: ${templateDir}. Check the TEMPLATE_DIR path in the configuration at the top of this file.`);
  }

  // Files that are exclusively an override source are not templates in their own right — they
  // must not be distributed under their own name, because .github/ has no place for them.
  const overrideSources = new Set(targets.flatMap((t) => Object.values(t.overrides || {})));

  const templates = readdirSync(templateDir)
    .filter((f) => f.endsWith(".yml") || f.endsWith(".md"))
    .filter((f) => !overrideSources.has(f))
    .sort();

  if (templates.length === 0) fail(`directory ${templateDir} is empty.`);

  // An override pointing at a nonexistent source file, or at a target name outside the set, would
  // be silent: the target would get the shared template and nobody would find out it was supposed
  // to get its own.
  for (const target of targets) {
    for (const [destination, source] of Object.entries(target.overrides || {})) {
      if (!templates.includes(destination)) {
        fail(`target ${target.name} overrides "${destination}", which is not in ${templateDir}.`);
      }
      if (!existsSync(join(templateDir, source))) {
        fail(`target ${target.name} points at source "${source}", which is not in ${templateDir}.`);
      }
    }
  }

  // An Issue form without name and description is rejected by GitHub at render time, not at
  // commit time — the form simply stops appearing in the picker, with no error anywhere.
  for (const file of templates) {
    if (REPO_ROOT_TEMPLATES.has(file) || file === "config.yml") continue;
    const body = readFileSync(join(templateDir, file), "utf8");
    for (const field of ["name", "description", "body"]) {
      if (!new RegExp(`^${field}:`, "m").test(body)) {
        fail(`${file}: Issue form is missing field "${field}".`);
      }
    }
  }

  return templates;
}

// The whole template sync/check run, parametrised by everything the CLI used to take from
// globals. Returns the exit code; throws ToolError on an invalid source set.
function runTemplates({ targets, templateDir, checkOnly, out, revision }) {
  const templates = loadTemplates(templateDir, targets);

  // Report WHAT was read, not only what was found: a copy from a stale checkout reports success
  // just as convincingly as a fresh one (FrameworkDoc.md, section 9).
  out.log(`Source: ${revision("process/issue-templates")}`);

  let drift = 0;
  let copied = 0;
  let skipped = 0;

  for (const target of targets) {
    // A missing target is not "no drift" — it is "nothing checked", and must not end in exit 0.
    if (!existsSync(target.path)) {
      out.error(`SKIPPED ${target.name}: not found: ${target.path}`);
      skipped++;
      continue;
    }

    // A target without a templates field gets the full set — the default behavior for production
    // repositories. A typo in the subset would be silent: the script would copy one file fewer
    // and say nothing.
    const wanted = target.templates ? templates.filter((f) => target.templates.includes(f)) : templates;
    for (const missing of (target.templates || []).filter((f) => !templates.includes(f))) {
      fail(`target ${target.name} requests template "${missing}", which is not in ${templateDir}.`);
    }

    for (const file of wanted) {
      const atRepoRoot = REPO_ROOT_TEMPLATES.has(file);
      const targetDir = atRepoRoot
        ? join(target.path, ".github")
        : join(target.path, ".github", "ISSUE_TEMPLATE");
      const relative = atRepoRoot ? `.github/${file}` : `.github/ISSUE_TEMPLATE/${file}`;

      // The target name stays the same — the source content differs. The opposite of the
      // `templates` subset, where the file simply doesn't ship.
      const sourceFile = target.overrides?.[file] ?? file;
      const source = readFileSync(join(templateDir, sourceFile), "utf8");
      const destination = join(targetDir, file);
      const current = existsSync(destination) ? readFileSync(destination, "utf8") : null;

      // Comparison after normalizing line endings, not byte-for-byte. The .github/ directory is
      // tracked by the product repository, so on Windows git checks it out with CRLF, while this
      // script writes LF — a file identical in content would then differ by one byte per line,
      // and --check would stay red indefinitely. A warning that fires when everything is actually
      // fine teaches people to ignore it.
      //
      // Writing stays in LF. Conversion on checkout is git's job (via .gitattributes), not this
      // script's.
      const normalise = (text) => (text === null ? null : text.replace(/\r\n/g, "\n"));
      if (normalise(current) === normalise(source)) continue;

      drift++;
      const what = current === null ? "new" : "changed";
      if (checkOnly) {
        out.log(`DRIFT ${target.name}/${relative} (${what})`);
      } else {
        mkdirSync(targetDir, { recursive: true });
        writeFileSync(destination, source);
        copied++;
        out.log(`WROTE ${target.name}/${relative} (${what})`);
      }
    }

    // A form removed from the source stays in the picker until it's removed by hand at the target.
    const issueDir = join(target.path, ".github", "ISSUE_TEMPLATE");
    if (existsSync(issueDir)) {
      const orphans = readdirSync(issueDir).filter(
        (f) => (f.endsWith(".yml") || f.endsWith(".md")) && !templates.includes(f),
      );
      for (const orphan of orphans) {
        drift++;
        out.log(
          `ORPHANED ${target.name}/.github/ISSUE_TEMPLATE/${orphan} — no source, remove by hand`,
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
      ? `No changes. Templates: ${templates.length}.`
      : `Wrote ${copied} of ${templates.length} templates. Files are tracked by git — review and commit them yourself.`,
  );
  return skipped === 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------- self-test
//
// Built-in contrast cases (calibration/README.md, Method 3). Every "should fail" case differs
// from a "should pass" sibling by exactly one defect, and the expectation checks the specific
// message, not just a non-zero exit — an exit 2 caused by some other error (a broken fixture, a
// missing directory) must not count as the check under test working.

const VALID_LABEL = { name: "state:ok", color: "0e3454", description: "A valid label" };

// A syntactically complete Issue form; `omit` drops one top-level field.
function issueForm({ omit = null, title = "Story" } = {}) {
  const fields = {
    name: `name: ${title}`,
    description: "description: Self-test form",
    body: "body:\n  - type: textarea\n    id: what\n    attributes:\n      label: What",
  };
  return Object.entries(fields)
    .filter(([key]) => key !== omit)
    .map(([, text]) => text)
    .join("\n") + "\n";
}

// Builds a throwaway source directory (manifest + templates) and one product repository, runs the
// case, and always removes the directory — also when the case throws.
function withFixture({ manifest, templates = {}, target = null, createTarget = true, targetOptions = {} }, run) {
  const root = mkdtempSync(join(tmpdir(), "sync-github-self-test-"));
  try {
    const manifestPath = join(root, "labels.json");
    if (manifest !== undefined) writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    const templateDir = join(root, "issue-templates");
    mkdirSync(templateDir);
    for (const [file, content] of Object.entries(templates)) writeFileSync(join(templateDir, file), content);
    const targetPath = join(root, "product");
    if (createTarget) {
      mkdirSync(targetPath);
      for (const [relative, content] of Object.entries(target || {})) {
        const full = join(targetPath, ...relative.split("/"));
        mkdirSync(resolve(full, ".."), { recursive: true });
        writeFileSync(full, content);
      }
    }
    const targets = [{ name: "fixture", path: targetPath, ...targetOptions }];
    return run({ manifestPath, templateDir, targets, targetPath });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

// Runs one of the two tool paths with captured output. `error` is the ToolError message when
// validation refused.
function capture(fn) {
  const lines = [];
  const out = { log: (m) => lines.push(m), warn: (m) => lines.push(m), error: (m) => lines.push(m) };
  try {
    return { result: fn(out), lines, error: null };
  } catch (error) {
    if (!(error instanceof ToolError)) throw error;
    return { result: 2, lines, error: error.message };
  }
}

function expectRefusal(pattern) {
  return (r) =>
    r.error !== null && pattern.test(r.error)
      ? null
      : `expected refusal matching ${pattern}, got ${r.error === null ? "success" : `error "${r.error}"`}`;
}

const templatesRun = (checkOnly) => (f) =>
  capture((out) => runTemplates({ targets: f.targets, templateDir: f.templateDir, checkOnly, out, revision: () => "self-test" }));

const SELF_TEST_CASES = [
  {
    name: "valid label manifest passes and renders one call per label",
    run: () =>
      withFixture({ manifest: { states: { labels: [VALID_LABEL] } } }, (f) => {
        const r = capture(() => loadLabels(f.manifestPath, f.targets));
        if (r.error !== null) return `expected success, got error "${r.error}"`;
        const script = renderLabelScript({ labels: r.result, targets: f.targets, owner: "o", pwsh: false });
        return script.filter((l) => l.startsWith("gh label create 'state:ok'")).length === 1
          ? null
          : `expected exactly one gh call for state:ok, got: ${script.join(" | ")}`;
      }),
  },
  {
    name: "label with a non-ASCII character is refused",
    run: () =>
      withFixture(
        { manifest: { states: { labels: [{ ...VALID_LABEL, description: "Gate 1 – decision" }] } } },
        (f) => expectRefusal(/character outside ASCII/)(capture(() => loadLabels(f.manifestPath, f.targets))),
      ),
  },
  {
    name: "duplicate label name is refused",
    run: () =>
      withFixture(
        { manifest: { states: { labels: [VALID_LABEL] }, roles: { labels: [{ ...VALID_LABEL, color: "ffffff" }] } } },
        (f) => expectRefusal(/defined more than once/)(capture(() => loadLabels(f.manifestPath, f.targets))),
      ),
  },
  {
    name: "label color that is not six lowercase hex digits is refused",
    run: () =>
      withFixture(
        { manifest: { states: { labels: [{ ...VALID_LABEL, color: "#0e3454" }] } } },
        (f) => expectRefusal(/not a six-character hex value/)(capture(() => loadLabels(f.manifestPath, f.targets))),
      ),
  },
  {
    name: "target label subset naming an unknown label is refused",
    run: () =>
      withFixture(
        { manifest: { states: { labels: [VALID_LABEL] } }, targetOptions: { labels: ["state:ok", "state:typo"] } },
        (f) => expectRefusal(/requests label "state:typo"/)(capture(() => loadLabels(f.manifestPath, f.targets))),
      ),
  },
  {
    name: "valid template set is copied, then --check reports no drift",
    run: () =>
      withFixture({ templates: { "1-story.yml": issueForm(), "config.yml": "blank_issues_enabled: false\n" } }, (f) => {
        const write = templatesRun(false)(f);
        const check = templatesRun(true)(f);
        return write.result === 0 && write.error === null && check.result === 0 && check.lines.includes("No drift.")
          ? null
          : `expected write exit 0 then "No drift.", got write ${write.result} (${write.error}), check ${check.result}: ${check.lines.join(" | ")}`;
      }),
  },
  {
    name: "Issue form without `body:` is refused",
    run: () =>
      withFixture({ templates: { "1-story.yml": issueForm({ omit: "body" }) } }, (f) =>
        expectRefusal(/1-story\.yml: Issue form is missing field "body"/)(templatesRun(true)(f)),
      ),
  },
  {
    name: "CRLF copy of an identical template is not drift",
    run: () =>
      withFixture(
        {
          templates: { "1-story.yml": issueForm() },
          target: { ".github/ISSUE_TEMPLATE/1-story.yml": issueForm().replace(/\n/g, "\r\n") },
        },
        (f) => {
          const r = templatesRun(true)(f);
          return r.result === 0 && r.lines.includes("No drift.")
            ? null
            : `expected exit 0 and "No drift.", got exit ${r.result}: ${r.lines.join(" | ")}`;
        },
      ),
  },
  {
    name: "changed template is drift",
    run: () =>
      withFixture(
        {
          templates: { "1-story.yml": issueForm() },
          target: { ".github/ISSUE_TEMPLATE/1-story.yml": issueForm({ title: "Old story" }) },
        },
        (f) => {
          const r = templatesRun(true)(f);
          return r.result === 1 && r.lines.includes("DRIFT fixture/.github/ISSUE_TEMPLATE/1-story.yml (changed)")
            ? null
            : `expected exit 1 and a DRIFT (changed) line, got exit ${r.result}: ${r.lines.join(" | ")}`;
        },
      ),
  },
  {
    name: "orphaned Issue form in the target is reported",
    run: () =>
      withFixture(
        {
          templates: { "1-story.yml": issueForm() },
          target: {
            ".github/ISSUE_TEMPLATE/1-story.yml": issueForm(),
            ".github/ISSUE_TEMPLATE/9-retired.yml": issueForm(),
          },
        },
        (f) => {
          const r = templatesRun(true)(f);
          return r.result === 1 && r.lines.some((l) => l.startsWith("ORPHANED fixture/.github/ISSUE_TEMPLATE/9-retired.yml"))
            ? null
            : `expected exit 1 and an ORPHANED line, got exit ${r.result}: ${r.lines.join(" | ")}`;
        },
      ),
  },
  {
    name: "missing target makes --check exit non-zero, not \"No drift.\"",
    run: () =>
      withFixture({ templates: { "1-story.yml": issueForm() }, createTarget: false }, (f) => {
        const r = templatesRun(true)(f);
        return r.result !== 0 && r.lines.some((l) => l.startsWith("SKIPPED fixture:")) && !r.lines.includes("No drift.")
          ? null
          : `expected non-zero exit, a SKIPPED line and no "No drift.", got exit ${r.result}: ${r.lines.join(" | ")}`;
      }),
  },
];

// Returns the list of failures ({ name, reason }); an empty list means every case passed. A case
// that throws counts as failed — a crashing self-test must not read as a passing one.
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
    console.error("ERROR: the tool failed its own self-test — refusing to run.");
    process.exit(2);
  }
}

try {
  if (LABELS_ONLY) {
    const labels = loadLabels(LABEL_MANIFEST, TARGETS);
    for (const line of renderLabelScript({ labels, targets: TARGETS, owner: OWNER, pwsh: LABELS_PWSH })) {
      console.log(line);
    }
    process.exit(0);
  }

  process.exit(
    runTemplates({
      targets: TARGETS,
      templateDir: TEMPLATE_DIR,
      checkOnly: CHECK_ONLY,
      out: console,
      revision: sourceRevision,
    }),
  );
} catch (error) {
  if (!(error instanceof ToolError)) throw error;
  console.error(`ERROR: ${error.message}`);
  process.exit(2);
}
