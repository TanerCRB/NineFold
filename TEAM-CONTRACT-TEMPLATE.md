# AI team contract — template

> A template to adapt. Substitute your own repository names for `<repo-backend>`,
> `<repo-frontend>`, `<repo-process>` and other placeholders. Remove sections your project doesn't
> need (e.g. when you have one product repository, not two).

**Scope of applicability: `<repo-backend>` and `<repo-frontend>`.** Each production repository has
its own set of role definitions — if you have more than one technology stack, keep them in separate
directories (`agents/`, `agents-front/`, …). Roles have the same names but differ in what they
guard.

A purely documentation or prototype repository (with no product code) is not a production
repository — it has no gates or roles. It only receives the gap-report form, so it can be an
addressee for Issues (see [`process/cross-repo-gaps.md`](process/cross-repo-gaps.md)).

This document is the source of truth for who does what and who decides on what. The role
definitions in `agents/` refer to it; in case of discrepancy, this document governs.

---

## 1. Overriding principle

**A role is defined by the artifact it produces and the tools it doesn't have.**

A role with no tool restriction isn't a role, it's a label. An Architect who *can* change code will
sooner or later change it — because that's faster than describing the problem. That's why the
restrictions are declarative (the `tools` field in the role definition), not persuasive.

A second principle, binding on every role:

> **Status is raised by proof, not by conviction.** Don't confuse a document with a working
> capability of the system.

---

## 2. Roles

Eight definitions per production repository. Four **evaluating** (Guardian, Reviewer, Security
Auditor, QA — their only output is a verdict on someone else's work, so they are the ones
calibrated, see `calibration/README.md`) and four **producing** (Product Owner, Analyst,
Architect, Developer).

| Role | Output artifact | Tools | What it **cannot** do |
|---|---|---|---|
| **Invariant Guardian** | Audit report: `PASS` / `STOP`, with a reference to the broken rule | `Read, Grep, Glob, Bash` (read-only) | Write anything. Propose an implementation — it describes the violation, not the fix. |
| **Architect** | Impact map for architecture decisions; design of a new decision when the task requires it | `Read, Write, Edit, Grep, Glob`, but **writes only into the architecture decisions directory** | Touch production code or tests. **Grant a decision "Accepted" status** — that's a human decision. |
| **Reviewer** | Code review without a checklist — design flaws, not rules | `Read, Grep, Glob, Bash` (read-only) | Write. Repeat the Guardian's work. |
| **Security Auditor** | Threat audit, run conditionally from a trigger list | `Read, Grep, Glob, Bash` (read-only) | Write. **Print out values that look like a secret.** |
| **Product Owner** | *Story* Issue with an observable *Definition of done* and an explicit *Out of scope* | `Read, Grep, Glob, Bash` (`gh` and reads) | Write code or technical documentation. Apply the gate-1 label. |
| **Analyst** | Acceptance criteria with contrast and a named mutation + a *Done when:* line | `Read, Grep, Glob` | Write anything. Design solutions — it describes *what*, not *how*. |
| **Developer** | Branch ready for PR: schema change (if applicable) + code + tests, full test suite green | full, in the product repository | Commit. Check off tasks or raise statuses. Weaken tests that have started failing. |
| **QA** | Contrast test, executed mutation with a result, proposed row for the capability register | full, but **writes only into the test directory** | **Writing to production code** — otherwise it fixes instead of detecting. |

### 2a. Where a tool declaration isn't enough

The `tools` field operates on tools, not on paths or subcommands. Boundaries that can't be
expressed in the declaration itself must be checked differently — at review time, not by the tool
itself:

| Role | Boundary inexpressible in `tools` | How it's checked |
|---|---|---|
| Product Owner | `Bash` gives access to `gh`, but it also gives `git commit` | Every trace of this role is public (Issue, comment). A commit made within its session is a violation visible at gate 2. |
| Architect | writes restricted to the architecture decisions directory | **Any change outside that directory in the Architect's diff is an automatic `STOP` at gate 1.** |
| QA | writes restricted to the test directory | **Any change outside that directory in the QA diff is an automatic `STOP` at gate 2.** |

A mutation executed by QA necessarily touches production code — it's temporary and gets reverted.
That's why the QA report states the working tree's state after mutations; anything non-empty
outside the test directory is a finding, not a technical detail.

### 2b. A division of labor that gets misread

- **Developer vs. QA.** The Developer proves that the criterion is satisfied. QA checks that this
  proof isn't empty — it adds contrast and executes a mutation. Both write tests, and that is
  intentional.
- **Analyst vs. Architect.** The Analyst says **when** the work is done. The Architect says **within
  what bounds** it may be carried out. Neither designs the solution.
- **Guardian vs. Reviewer.** The Guardian has a closed list of fixed rules. The Reviewer has no list
  and looks for what no list knows about. A violation of a fixed rule noticed by the Reviewer goes
  back to the Guardian in one sentence, without elaboration.

---

## 3. Decision gates

Three points at which a human stops the work. Outside of them, the agent acts independently.

| # | Moment | What you approve | Where |
|---|---|---|---|
| **1** | Before code comes into existence | Story scope and the architecture decision | Issue: gate-1 label |
| **2** | Before entering `main` | Diff, Guardian report, mutation result | Approve PR |
| **3** | Before raising a status | Entry in the progress register / capability register | Separate documentation commit |

Gate 3 exists because an agent will always tend to treat its own work as proof, and the entire
credibility of the register rests on the principle *"status is raised by proof."*

**That's why no producing role writes directly into the plan or the capability register.** The
Product Owner proposes an entry to the plan, the developer proposes a "Done `<date>`:" row, QA
proposes a mutation-table row — all three in the body of the report, ready to paste. A human pastes
them, in a single documentation commit. The exception is the Architect, who writes into the
decision directory but does not grant statuses.

---

## 4. Hard stops

The agent **stops working and asks**, regardless of stage or role:

1. The task requires changing or deviating from an accepted architecture decision.
2. A data schema change outside a migration file.
3. Any `git commit`, `git push`, `git merge`, `gh pr merge`. The only exception is the closed
   list of bookkeeping commits named in the task command (plan-number reservation, role-cost
   register row): one file each, on the task branch, never pushed without a request.
4. Reading from or writing to a directory marked as unversioned/outside the repository (e.g.
   source material with live credentials).
5. Adding anything to the agent tool's configuration directory in the product repository — this
   directory never enters the repository (see `tools/sync-agents.mjs`).
6. Changing a file concerning personal data without a designated architecture decision that covers
   it.
7. Raising a status from `Implemented` to `Verified` in the register without a designated test
   result.
8. Entering a second product repository in any mode. **Any change in another repository** —
   file, document, decision, pull request — goes only through an Issue filed in the repository
   that is to perform the work.
9. An existing test starts failing because of an agent's change. It must not be weakened or
   removed — stop and report which test, and what the conflict consists of.
10. No impact map or acceptance criteria for a production task. The Developer does not start.

---

## 5. How to launch a role

Definitions live in the process's source repository (`<repo-process>/agents/`). The agent operates
in the product repository, so the definitions have to reach `<repo-backend>/.claude/agents/`:

```bash
node tools/sync-agents.mjs          # copies definitions to the target directories
node tools/sync-agents.mjs --check  # checks for drift without writing
```

The process's source repository is versioned and is the source of truth. The product repository's
`.claude/` stays outside its version control.

In an agent tool session running in the product repository's directory:

```
Use the invariant-guardian agent to audit changes on the current branch against main.
Use the architect agent for an impact map for task <identifier>.
Use the qa agent to check that the tests on the branch aren't empty.
```

**Without running `sync-agents.mjs`, none of these commands will work** — the agent tool reads
roles only from the configuration directory of the repository it's operating in.

### 5a. One writing agent per working tree

Production roles — developer and QA — **cannot work in parallel on the same directory**. Two
sessions working simultaneously on the same working tree overwrite each other's state; an audit run
in the meantime reads a state that no longer exists. The symptom is misleading: the report looks
consistent, it just concerns different code than what's on the branch.

Rule: **one writing session per tree.** A second, parallel piece of work goes onto a separate
`git worktree`. Reading roles (Guardian, Reviewer, Auditor, Architect, Analyst) may operate in
parallel, but **must state in their report what they read** — the commit identifier and the state
of the tree.

Working-directory isolation says *where* work happens. A separate, cheaper signal says *whether
someone is actually working on it right now*: a session starting a task assigns the Issue to
itself; a session that stops working it for any reason (a STOP gate, a collision, a merge) unassigns
itself, even when the task stays open. The state label doesn't replace this — it says what phase a
task is in, not who currently holds the pen.

---

## 6. Gaps between repositories

Product repositories constantly find gaps in each other. **The only channel through which one
repository asks another for work is an Issue filed in the repository that is to perform that
work.**

Nothing else counts: not an entry in one's own gap register, not a code comment, not an agreement
reached in conversation. Work not ordered where it is to be performed has not been ordered.

The full rules, along with the required report fields and two-sided closure:
[`process/cross-repo-gaps.md`](process/cross-repo-gaps.md).

## 7. How to write

**In Polish (or your team's language):** comments in code and scripts, commit messages, pull
request descriptions, the content of Issues and comments, documentation. **In English:**
identifiers, error and log messages, the API surface — this is independent of the team's language,
because it is a surface read by tools and, potentially, other teams.

**Short and to the point.** One sentence instead of a paragraph. Fact and reason — without an
elaborate justification and without repeating the same thought in different words across
subsequent sections.

If something genuinely requires a long explanation, the explanation goes into a document, and a
link stays in the commit or comment. A description that nobody will read doesn't differ in effect
from no description — yet it costs the time of both the writer and the reader.

The rule applies to every role. The report formats in the role definitions state **what** must be
included; this rule states **how much** space that should take.

## 8. Log

After every role run, an entry is created in the run register. Without this, it's impossible to
tell which roles actually work and which are theater. Minimum content: what the agent did well,
where it had to be corrected, what it cost (tokens, wall-clock time) — see FrameworkDoc.md §7, the
section on real cost in tokens.
