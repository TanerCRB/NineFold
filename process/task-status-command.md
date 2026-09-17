---
description: <product-repo> — reports where a task stands: gate, evidence, CI, blockers. Read-only, touches nothing
argument-hint: <Issue link or #N or a plan task identifier>
allowed-tools: Read, Grep, Glob, Bash
---

> Template to adapt — remove this quote before use. The equivalent of `/zadanie_stan` from
> `FrameworkDoc.md`, section 4 — a read-only command that maps a submission's state to a single
> point in the lifecycle. Lives next to `task-command.md` in the same product repository.

# Task status: $1

A report on **where the task stands**. You change nothing: no writes to files, no commit, no
worktree, no calling roles, no writes through the issue-tracker tool. You work in the main checkout
on the main branch — it's a reference point, not a place to work.

Argument `$1` accepts an Issue URL, `#N`, or a plan task identifier. With a plan identifier, start
from the plan register and derive the Issue number from it.

## What to gather

Run the queries **in parallel**, in one message — they don't depend on each other.

```bash
gh issue view <N> --repo <organization>/<product-repo> --json number,title,state,labels,assignees,updatedAt,comments
gh pr list --repo <organization>/<product-repo> --state all --search "<N>" --json number,title,state,isDraft,headRefName,reviewDecision,mergedAt,updatedAt

# CI checks, when a PR exists (no wait mode — this is a report, not a wait)
gh pr checks <PR number> --repo <organization>/<product-repo>
```

From the repository (read-only):

- the plan register — the task's row: checked off or not, *Definition of done*, blockers, a
  "Done <date>" row;
- the activity/capability register — the activity's row, status, both evidence fields;
- the mutation register — whether mutation rows exist for this task and whether any of them
  **survived**;
- `git log --oneline -15 main -- <task paths>` and `git branch -a --list '*<identifier>*'`;
- whether anyone has an open working directory (worktree) on this task.

## How to read the state

Determine **one** position in the process, from these signals:

| Signal | Where the task stands |
|---|---|
| Issue missing *Definition of done* or *Out of scope* | before analysis — Story incomplete |
| "analysis" state label, no impact map or criteria | analysis, before gate 1 |
| "decision" state label, an architectural-decision deviation, or "waiting-on-human" | **waiting on a human decision**, not on work |
| "implementation" state label, no branch and no PR | ready for the `code` phase, nobody has started |
| branch/worktree exists, no PR | code in progress |
| PR open, no Mutation section in the description | before the `verification` phase |
| PR open, CI red | see below — rule out the environment first |
| PR open, CI green, no approval | **gate 2**, waiting on the human |
| PR merged, plan not checked off | **gate 3**, waiting on the documentation commit |
| plan checked off with no link to a test/artifact | status raised without evidence — a finding |

Before calling red CI a defect, rule out environmental causes: missing checks from a merge
conflict, a container image pull failure, a timeout on the hosting platform's endpoints, a failure
with no log and a step with a null result (an executor that dropped out), a dependent service alive
but not yet ready, secrets not reaching an automated bot, a green status computed against a stale
base after the main branch moved on, a coverage ratchet tripped by someone else's merge.

## Response format

Short, no spelling out options:

```
<identifier> — <title>            Issue #<N> (<state>) • PR #<M> (<state>)
Position: <phase / gate>          Waiting on: <human / CI / author / nobody>

Evidence
- Definition of done: <condition> — <satisfied by what / missing>
- Mutations: <list, result> — <none, if there aren't any>
- CI: <list of red checks or "green">

Blockers
- <blocker and what it blocks — or "none">

Next action: <one sentence, who and what>
```

Always give a recommendation — one action with a reason, not a list of options. If the task is
sitting at a human gate, say explicitly **whose decision** it needs and what question has to be
resolved. The full process is run by `task-command.md`.
