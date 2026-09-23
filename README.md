# Ninefold

*A starter kit for an AI-agent SDLC process.*

**Why "Ninefold":** the process is carried by nine actors — eight specialized agent roles
(Product Owner, Analyst, Architect, Developer, QA, Invariant Guardian, Reviewer, Security
Auditor) plus the human — and that number is not incidental. It's the structural core the whole
kit is built around: a role that produces something never evaluates it, and every handoff between
roles puts a fresh set of eyes on the result (see `FrameworkDoc.md`, section 3).

An anonymized, portable excerpt from a real SDLC process based on Spec-Driven Development
and Human-in-the-Loop, described in [`FrameworkDoc.md`](FrameworkDoc.md). This directory contains
**working artifacts**, not just a description: agent role definitions, Issue/PR templates, a label
manifest, sync scripts, a pre-push hook, and a guide to reconstructing the whole thing on a new
repository.

All project names, organization, business domain, and specific identifiers (ADR numbers, Issue,
PR, hosts, accounts) have been removed or replaced with placeholders in angle brackets,
e.g. `<repo-backend>`, `<owner>`, `<Entity>`. Substitute the specifics of your own project for them.

## How to read this directory

1. **[`FrameworkDoc.md`](FrameworkDoc.md)** — the philosophy and mechanics of the process: nine
   roles, three human gates, mutation testing as the core of proof, state management, parallel
   work by multiple agents, how role cost is measured. Start here to understand **why** the rest of
   the directory looks the way it looks.
   *Optional:* **[`CASE-STUDY.md`](CASE-STUDY.md)** — the measured numbers and worked examples
   from the source project (token cost per role, two tasks traced from ticket to merge, documented
   tool failures). Not needed to adopt the process; read it to see what the pattern cost in practice.
2. **[`TEAM-CONTRACT-TEMPLATE.md`](TEAM-CONTRACT-TEMPLATE.md)** — the team contract: who does what,
   which tools they don't have, where the boundary lies that can't be expressed in the permission
   declaration itself, how to launch a role. This is the document the role definitions defer to in
   case of discrepancy.
3. **[`agents/`](agents/)** — eight role templates to adapt (Product Owner, Analyst, Architect,
   Developer, QA, Invariant Guardian, Reviewer, Security Auditor). The evaluating roles
   (`invariant-guardian.md`, `reviewer.md`, `security-auditor.md`) have checklists marked as
   EXAMPLE — write your own, concrete rules. `developer.md` combines the backend/frontend variants
   in a single file with two example checklists side by side; if you have two technology stacks,
   split it into two files (see the note at the top of the file).
4. **[`process/`](process/)** — the state machine, label manifest, Issue and PR templates, the
   pre-push hook, minimal register templates (`process/registers/`), the `main` protection
   variant without a paid plan, repository settings, release versioning, the cross-repository gap
   channel.
   **[`task-command.md`](process/task-command.md)** and
   **[`task-status-command.md`](process/task-status-command.md)** — the full content of the
   command that drives one task through the whole lifecycle (the equivalent of
   `/zadanie_be`/`/zadanie_fe`) and its read-only sibling (`/zadanie_stan`) — they belong in the
   product repository, not here (see `FrameworkDoc.md`, section 4).
5. **[`tools/`](tools/)** — `sync-agents.mjs` (copies role definitions from the process repository
   to the `.claude/agents/` of the product repository) and `sync-github.mjs` (distributes Issue/PR
   templates and prints `gh` commands for labels). Both carry a `--self-test` of built-in contrast
   cases (calibration Method 3) that also runs silently before every real run; this repository's
   own CI (`.github/workflows/kit-ci.yml`) runs the self-tests, the label manifest check and
   `check-links.mjs` (relative Markdown links) on every pull request.
6. **[`calibration/`](calibration/)** — how to check that an evaluating role actually evaluates,
   before you start trusting it.
7. **[`process/bootstrap-guide.md`](process/bootstrap-guide.md)** — a step-by-step sequence of
   actions to go from an empty repository to a working pipeline with gates. Start here if you want
   to **act**, not just understand.

**Already installed v0.1.0?** [`UPGRADING.md`](UPGRADING.md) takes a process repository and its
product repositories from v0.1.0 to v0.2.0.

## Minimal set to get started

If you don't have time to read everything: `FrameworkDoc.md` §1–5, one role from `agents/` as a
sample (e.g. `invariant-guardian.md` — it has the most mechanical output format),
`process/sdlc-flow.md`, and `process/bootstrap-guide.md` steps 0–6 (everything up to a working
installation; steps 9–10 before the first real task). `CASE-STUDY.md` can be skipped entirely.

## What this kit deliberately does not contain

- **Specific domain checklists.** The Guardian's rules, the Analyst's criteria, the invariants in
  the PR template — all of this has to be written from scratch for your domain and your stack.
  FrameworkDoc.md §12 states this explicitly: *roles and gates are universal, checklists are not*.
- **CI configuration for a specific runner provider.** `process/ci-and-branch-protection.md` and
  `process/repository-settings.md` describe patterns (path filter versus required check, runner
  watchdog, `runs-on` as an expression) — not ready-made workflow files.
- **A persistent orchestrator.** FrameworkDoc.md §3 describes the entry condition under which it's
  even worth building one. This kit assumes you haven't reached it yet.
