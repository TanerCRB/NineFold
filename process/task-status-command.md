---
description: <product-repo> — reports where a task stands: gate, evidence, CI, blockers. Read-only, touches nothing
argument-hint: <Issue link or #N or a plan task identifier> | exceptions
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
from the plan register and derive the Issue number from it. With `exceptions` there is no task:
run the exception sweep instead (see "The exception sweep" below).

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
- whether anyone has an open working directory (worktree) on this task;
- the scope lock, once the task is past gate 1: recompute the scope fingerprint from the Issue
  body exactly as `task-command.md` does ("Scope lock") and compare it with the fingerprint in the
  latest "Scope for gate 1" or "Scope amended at gate 2" comment. Reading the Issue and hashing
  locally is still read-only;
- the recorded exceptions — the PR description, and the task's lines in the exception register —
  read through the exception check, which only reads:
  ```bash
  gh pr view <M> --repo <organization>/<product-repo> --json body --jq .body \
    | scripts/exception-check.sh -
  grep -E '^[-*+ ]*Exception <identifier>/' <exception-register> | scripts/exception-check.sh -
  ```

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
| PR merged, plan not checked off, Issue open | **gate 3**, waiting on the documentation PR |
| Issue closed, but not in the closed state label | closed before gate 3 — a finding; the task has dropped out of the waiting filter |
| a verification report names a SHA other than the PR's `Verified at:` | evidence about different code — a finding, re-verification needed |
| plan checked off with no link to a test/artifact | status raised without evidence — a finding |
| past gate 1, the scope fingerprint differs from the latest recorded one | **scope changed after approval** — a finding; the task goes back to gate 1, whatever phase it is in |
| past gate 1, no fingerprint comment at all | scope never locked — a finding; gate 1 approved something nobody can compare against |
| an exception the check reports `EXPIRED` | **the finding blocks again** — whatever phase the task is in, merged or not; the owner renews it or it becomes a Story |
| an exception the check reports `MALFORMED` | not an exception — the finding it meant to cover was never let through |
| an exception in the merged PR, but not in the exception register after gate 3 | an exception nobody will check again — a finding |

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
- Scope lock: <holds / broken — the Issue's edit history shows what changed / not locked yet — before gate 1>
- Exceptions: <each one: id, owner, live until / expiring <date> / EXPIRED since <date> — blocks again / malformed — or "none">
- Mutations: <list, result> — <none, if there aren't any>
- CI: <list of red checks or "green">

Blockers
- <blocker and what it blocks — or "none">

Next action: <one sentence, who and what>
```

Always give a recommendation — one action with a reason, not a list of options. If the task is
sitting at a human gate, say explicitly **whose decision** it needs and what question has to be
resolved. The full process is run by `task-command.md`.

## The exception sweep

`/task-status exceptions` answers a question no single task asks: **which findings that a human
let through are blocking again today?** An exception outlives its PR — the task can be merged and
closed for months when its date passes — so the sweep reads every place an exception can live:

```bash
scripts/exception-check.sh <exception-register>
for pr in $(gh pr list --repo <organization>/<product-repo> --state open --json number --jq '.[].number'); do
  gh pr view "$pr" --repo <organization>/<product-repo> --json body --jq .body \
    | scripts/exception-check.sh - | sed "s|^|#$pr |"
done
```

It still only reads. Response:

```
Exceptions as of <date>             register: <n> • open PRs: <n>

Blocking again
- <id> — owner <@handle> — expired <date> (<n> days ago) — <register line / PR #M>

Expiring within 14 days
- <id> — owner <@handle> — holds through <date>

Malformed
- <file:line or PR #M> — <what is missing>

Next action: <one sentence — usually: the owner of the oldest expired exception renews it or files a Story>
```

An empty sweep is reported as such, with the counts — "nothing expired" is a result only when you
can show what was read. Exit 2 from any run is a failed sweep, not a clean one: say which source
couldn't be read.

The sweep can also run on a schedule, so nobody has to remember it — see
`ci-and-branch-protection.md`, §5.
