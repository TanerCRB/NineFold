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
//
// Two shells instead of one: if you also work on Windows, pasting bash syntax straight into
// PowerShell already fails on the header. The gh calls themselves are identical; only the header
// and the apostrophe-quoting rule differ.
//
// Run from the root directory of THIS repository (the process source repository).

import { readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, resolve } from "node:path";

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

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(2);
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
function shellQuote(value) {
  return LABELS_PWSH
    ? `'${String(value).replaceAll("'", "''")}'`
    : `'${String(value).replaceAll("'", `'\\''`)}'`;
}

// ---------------------------------------------------------------------------- labels

if (LABELS_ONLY) {
  if (!existsSync(LABEL_MANIFEST)) fail(`not found: ${LABEL_MANIFEST}.`);

  let manifest;
  try {
    manifest = JSON.parse(readFileSync(LABEL_MANIFEST, "utf8"));
  } catch (error) {
    fail(`${LABEL_MANIFEST} is not valid JSON: ${error.message}`);
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

  if (LABELS_PWSH) {
    console.log("# Generated by tools/sync-github.mjs --labels-ps1. Review before running.");
    console.log("# --force overwrites the color and description of an existing label, so the run is idempotent.");
    console.log("#");
    console.log("# Run the WHOLE file at once, not line by line:");
    console.log("#   Invoke-Expression (Get-Content <file> -Raw)");
    console.log("# Get-Content without -Raw feeds the file line by line, and Invoke-Expression rejects");
    console.log("# an empty string, so the blank lines below would throw a parameter-binding error.");
    console.log("#");
    console.log("# We deliberately do NOT set $ErrorActionPreference = 'Stop': gh writes to stderr");
    console.log("# even on success, which Windows PowerShell 5.1 can turn into a");
    console.log("# NativeCommandError. Every call is independent and idempotent");
    console.log("# (--force), so it's better for the run to reach the end and show what actually failed.");
    console.log("");
  } else {
    console.log("#!/usr/bin/env bash");
    console.log("# Generated by tools/sync-github.mjs --labels. Review before running.");
    console.log("# --force overwrites the color and description of an existing label, so the run is idempotent.");
    console.log("set -euo pipefail");
    console.log("");
  }
  // Every call carries its own --repo. Relying on gh inferring the repository from the current
  // directory's remote looks fine with a single target and breaks silently with several: the run
  // only passes from one specific working directory, yet looks correct wherever the first block
  // happens to run.
  let emitted = 0;
  for (const target of TARGETS) {
    const wanted = target.labels ? labels.filter((l) => target.labels.includes(l.name)) : labels;

    // A typo in the subset would be silent: the target would get one label fewer, and a form
    // referencing it would stop applying it.
    for (const missing of (target.labels || []).filter((n) => !seen.has(n))) {
      fail(`target ${target.name} requests label "${missing}", which is not in the manifest.`);
    }

    console.log(`# ---- ${target.name} (${wanted.length} of ${labels.length}) ----`);
    for (const label of wanted) {
      console.log(
        `gh label create ${shellQuote(label.name)} --color ${shellQuote(label.color)} ` +
          `--description ${shellQuote(label.description)} --repo ${OWNER}/${target.name} --force`,
      );
    }
    console.log("");
    emitted += wanted.length;
  }
  console.log(`# Calls emitted: ${emitted}. Labels in manifest: ${labels.length}.`);
  process.exit(0);
}

// ---------------------------------------------------------------------------- templates

if (!existsSync(TEMPLATE_DIR) || !statSync(TEMPLATE_DIR).isDirectory()) {
  fail(`not found: ${TEMPLATE_DIR}. Check the TEMPLATE_DIR path in the configuration at the top of this file.`);
}

// Files that are exclusively an override source are not templates in their own right — they
// must not be distributed under their own name, because .github/ has no place for them.
const OVERRIDE_SOURCES = new Set(TARGETS.flatMap((t) => Object.values(t.overrides || {})));

const templates = readdirSync(TEMPLATE_DIR)
  .filter((f) => f.endsWith(".yml") || f.endsWith(".md"))
  .filter((f) => !OVERRIDE_SOURCES.has(f))
  .sort();

if (templates.length === 0) fail(`directory ${TEMPLATE_DIR} is empty.`);

// An override pointing at a nonexistent source file, or at a target name outside the set, would
// be silent: the target would get the shared template and nobody would find out it was supposed
// to get its own.
for (const target of TARGETS) {
  for (const [destination, source] of Object.entries(target.overrides || {})) {
    if (!templates.includes(destination)) {
      fail(`target ${target.name} overrides "${destination}", which is not in ${TEMPLATE_DIR}.`);
    }
    if (!existsSync(join(TEMPLATE_DIR, source))) {
      fail(`target ${target.name} points at source "${source}", which is not in ${TEMPLATE_DIR}.`);
    }
  }
}

// An Issue form without name and description is rejected by GitHub at render time, not at
// commit time — the form simply stops appearing in the picker, with no error anywhere.
for (const file of templates) {
  if (REPO_ROOT_TEMPLATES.has(file) || file === "config.yml") continue;
  const body = readFileSync(join(TEMPLATE_DIR, file), "utf8");
  for (const field of ["name", "description", "body"]) {
    if (!new RegExp(`^${field}:`, "m").test(body)) {
      fail(`${file}: Issue form is missing field "${field}".`);
    }
  }
}

// Report WHAT was read, not only what was found: a copy from a stale checkout reports success just
// as convincingly as a fresh one (FrameworkDoc.md, section 9).
console.log(`Source: ${sourceRevision("process/issue-templates")}`);

let drift = 0;
let copied = 0;
let skipped = 0;

for (const target of TARGETS) {
  // A missing target is not "no drift" — it is "nothing checked", and must not end in exit 0.
  if (!existsSync(target.path)) {
    console.error(`SKIPPED ${target.name}: not found: ${target.path}`);
    skipped++;
    continue;
  }

  // A target without a templates field gets the full set — the default behavior for production
  // repositories. A typo in the subset would be silent: the script would copy one file fewer and
  // say nothing.
  const wanted = target.templates ? templates.filter((f) => target.templates.includes(f)) : templates;
  for (const missing of (target.templates || []).filter((f) => !templates.includes(f))) {
    fail(`target ${target.name} requests template "${missing}", which is not in ${TEMPLATE_DIR}.`);
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
    const source = readFileSync(join(TEMPLATE_DIR, sourceFile), "utf8");
    const destination = join(targetDir, file);
    const current = existsSync(destination) ? readFileSync(destination, "utf8") : null;

    // Comparison after normalizing line endings, not byte-for-byte. The .github/ directory is
    // tracked by the product repository, so on Windows git checks it out with CRLF, while this
    // script writes LF — a file identical in content would then differ by one byte per line, and
    // --check would stay red indefinitely. A warning that fires when everything is actually fine
    // teaches people to ignore it.
    //
    // Writing stays in LF. Conversion on checkout is git's job (via .gitattributes), not this
    // script's.
    const normalise = (text) => (text === null ? null : text.replace(/\r\n/g, "\n"));
    if (normalise(current) === normalise(source)) continue;

    drift++;
    const what = current === null ? "new" : "changed";
    if (CHECK_ONLY) {
      console.log(`DRIFT ${target.name}/${relative} (${what})`);
    } else {
      mkdirSync(targetDir, { recursive: true });
      writeFileSync(destination, source);
      copied++;
      console.log(`WROTE ${target.name}/${relative} (${what})`);
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
      console.log(
        `ORPHANED ${target.name}/.github/ISSUE_TEMPLATE/${orphan} — no source, remove by hand`,
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
    ? `No changes. Templates: ${templates.length}.`
    : `Wrote ${copied} of ${templates.length} templates. Files are tracked by git — review and commit them yourself.`,
);
process.exit(skipped === 0 ? 0 : 1);
