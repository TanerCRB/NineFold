---
description: <product-repo> — drives a task through the full process, from Issue to PR, with stops at the human gates
argument-hint: <Issue link or #N> [phase: analysis|code|verification|pr|closure]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, TodoWrite
---

> Template to adapt — remove this quote before use. This is the **full content** of the command
> that drives one task through the whole lifecycle — the equivalent of `/zadanie_be` / `/zadanie_fe`
> from `FrameworkDoc.md`, section 4. It lives in the product repository, in your agent
> environment's command directory (e.g. `.claude/commands/task.md` for Claude Code — the
> frontmatter above this paragraph has to stay the first thing in the file), **not** in the
> process source repository — it carries the specifics of one stack and one domain, so it can't be
> shared as-is between two product repositories (see `../FrameworkDoc.md`, section 4, the
> paragraph on the two layers that can drift apart).
>
> Substitute `<product-repo>`, `<organization>`, the names of your own tools/registers, and the
> step-7 checklist (it's an example — your list of local quality gates will differ). If you have
> two product repositories on different stacks, keep two separate copies of this command, the same
> way you keep two variants of a role in `../agents/` — same structure, different checklist
> content.

# Task: $1

You are driving **one** task through the process. Argument `$1` points at the Issue (full URL or
`#N`). Optional `$2` says which phase to start from — without it, you determine the phase yourself
from the Issue's state, the branch, and open PRs.

<!-- Example of an environment-specific pitfall — keep a section like this, adapt the content:
The repository is private, `gh` is sometimes off PATH — call it by full path. `WebFetch` on an
Issue returns 404, don't use it. -->

## Overriding rules

- **Status is raised by evidence, not conviction.** You don't check off the task and you don't
  raise its status.
- **You don't commit or push without an explicit request.** Never merge a pull request. The only
  exception is a closed list of **bookkeeping commits** you make without asking: the plan-number
  reservation (step 2) and the role-cost register row ("How you talk to the human", point 3).
  Each touches only its one file, lands on the task branch — never on `main` — and is not pushed
  without a request. Anything outside this list goes back to the rule.
- **Gates 1, 2 and 3 belong to the human.** You work up to them, prepare the material, and
  **stop**.
- The agent tool's configuration directory and any directory explicitly marked as outside the
  repository (e.g. a prototype with live credentials) are out of reach.
- A task that writes code works in its own working directory (worktree). The main checkout stays
  on the main branch.
- **Assignment for the duration of the work.** You start working a task → you assign the Issue to
  yourself. You stop working it — a STOP gate, a collision, a merged PR, anything else — → you
  unassign yourself, even when the Issue stays open and unclosed.
- **If you maintain a queryable code index/graph** (built without an LLM, e.g. an AST) — use it
  first for questions about code relationships (what calls X, where is Y used, a module map, the
  impact of a change) instead of manual searching. Questions about documentation/architecture are
  usually outside what such an index covers.

Keep a TODO list with the steps below — one entry per step, so it's visible where the process
currently stands.

## How you call a role

Roles (`analyst`, `architect`, `developer`, `qa`, `invariant-guardian`, `reviewer`,
`security-auditor`, `product-owner`) **may not be a registered subagent type** in the session you
launch this command from — the agent environment reads the role-definition directory from the
current session's working directory, and the session may have started somewhere else (see
`../FrameworkDoc.md`, section 4). Check this before the first call; if the subagent type doesn't
exist:

Call the role through the environment's general-purpose execution mechanism (e.g.
`subagent_type: general-purpose` in Claude Code), and take the role's content (system prompt) from
its definition file — read it and paste it as the first part of the prompt, ahead of the task
context (Issue, impact map, criteria). This applies to **every** role invocation in this process.

**Subagent model — the same as yours**, if you're calling the role through the general-purpose
mechanism: the model field in the role definition file does not apply automatically in this mode.
**Raising the model requires the human's consent** — treat it like any other question: say which
role and why (task complexity, risk of missing something), and wait for the decision instead of
silently escalating based on the field in the role file alone.

## How you talk to the human

This process stops on the human three times. Each stop costs their time — that's why every message
to them has two mandatory properties.

### 1. Every question and every decision comes with a recommendation

Never a bare list of options. Shape:

```
Question: <what needs to be decided>
Options:  A — <consequence>.  B — <consequence>.
Recommendation: A, because <reason>.
What would change it: <what I don't know>
```

A list of options with no pick shifts the thinking work back onto the human — that's the opposite
of what a gate is for. Base the recommendation on evidence from this task (a test, a measurement,
a register row, an architectural decision), not on general best practice. When there's no
evidence, say so plainly and recommend **how to get it**.

A recommendation **is not a decision** — you still stop and wait. This applies everywhere you ask:
gates 1, 2 and 3, choosing an implementation variant, a mutation that survived, red CI of uncertain
cause, a collision with someone else's work.

### 2. Keep the conversation with the human terse, keep artifacts in full language

If your environment has a compressed-communication mode (no filler, no pleasantries, no hedging,
all technical content kept verbatim) — turn it on for messages to the human in this window.

**The boundary is hard: the compression applies ONLY to the conversation in the window.** You
always write Issue and comment content, commit messages, pull request descriptions,
documentation, architectural decisions, and code comments in full, careful language. Those are
artifacts someone else reads, six months from now.

You also drop the compression anywhere it creates ambiguity: a warning about an irreversible
action, a step order where a dropped conjunction changes the meaning, anything touching security
or personal data. After such a passage, go back to the compressed mode.

### 3. After every role invocation — a row in the cost register

If you keep a role-cost register (see `../FrameworkDoc.md`, section 6) — after every invocation of
any of the eight roles, append a row: date, role, task, phase, complexity, tokens, tool calls,
time, notes.

Take the numbers (tokens, tool calls, time) from the invocation's usage field — never estimate. If
a given invocation doesn't return a number, write "no data" in that column instead of guessing: an
empty field with a reason is better than a made-up number — the same rule as with the completion
proof.

**Complexity is different — it's your judgment call, not a measured number.** Set it *before* the
call (number of files in scope / number of acceptance criteria / number of open questions / whether
there's a schema change or a new architectural decision): Low, Medium, or High. Don't confuse this
column with the evidence columns next to it — it's deliberately subjective.

The entry doesn't block any gate and isn't part of the task's completion criteria — it's a
separate, parallel process-cost register.

**Commit the row immediately, as its own small commit of just that one file, on the task branch in
the task's worktree** — don't wait for the `pr` phase. This is one of the two pre-authorized
bookkeeping commits (see "Overriding rules"); it never goes to `main` directly and is not pushed
without a request. Reason: an uncommitted file on a shared checkout isn't evidence — it's just the
belief that something was written down, and it disappears the moment someone else's parallel work
switches that checkout. A single small commit doesn't get in the way of further work, and it
survives removing the worktree and other people's operations on other checkouts. The row reaches
`main` together with the task's pull request.

---

## Step 0 — Recon

```bash
gh issue view <N> --repo <organization>/<product-repo> --json number,title,body,labels,state,assignees,comments
gh pr list --repo <organization>/<product-repo> --state open --json number,title,headRefName,isDraft
git branch -a --list '*<identifier>*'
ls <parent-dir>/tmp/<repo>-* 2>/dev/null
```

Determine and **say out loud**, before you go any further:

- the task's identifier from the plan and whether it exists in the plan register,
- labels: state, role, deviation from an architectural decision, waiting-on-human,
- whether work is already in progress — an open PR, a branch, someone else's worktree.

**Work already in progress elsewhere = stop.** A PR with a merge conflict looks abandoned, but
usually isn't (see `../FrameworkDoc.md`, section 4, "Phase 0 — Recon"). You don't delete working
directories you didn't create. If you yourself have a stale assignment on this Issue from a
previous session — unassign it, you're not working it now.

**The "analysis" state label does not automatically mean "needs new work."** It happens that the
described problem was already fixed by earlier, unrelated work, and the submission simply was
never closed. Before you start implementation, check whether the *Definition of done* condition is
already met by the current code. If it is — the right reaction is to close the submission with
evidence (a quoted test/code reference), not to reimplement the same thing.

Once the above rules out a collision and you're moving ahead, assign the Issue to yourself and
**create the task's worktree on its own branch now**, before the first role call (the rules for
where to create it are in step 6). Until gate 1 the branch carries only bookkeeping commits — the
number reservation and the cost-register rows of the analysis roles; code enters it only after
gate 1. If gate 1 rejects the task, the branch and worktree are removed like at closure.

---

## Phase `analysis` — up to gate 1

1. **Is the Story complete?** The Issue should have: a task identifier, *What and why*,
   *Definition of done* (an observable condition), *Out of scope (explicit)*, a basis in the
   documentation. The Product Owner role fills gaps — it creates/fixes the Issue with the initial
   state label and **doesn't** move on.
2. **Plan task number** — if the task isn't in the plan yet, reserve a number through the dedicated
   mechanism (see `../FrameworkDoc.md`, section 9, on identifiers as a shared resource), as a
   separate bookkeeping commit on the task branch, before the actual work.
3. **Analyst role** — acceptance criteria and the *Definition of done* row. Every criterion has an
   observable carrier, a contrast, and a named mutation meant to kill it. Verdict: `READY FOR GATE
   1` or `STORY NEEDS MORE WORK`.
4. **Architect role** — impact map onto architectural decisions. Three outcomes: fits / needs a
   deviation / needs a new decision. A deviation is an Issue with the corresponding label and a
   draft decision in "Draft — pending approval" status.
5. **GATE 1 — STOP.** Gather in one message: the criteria, the impact map, the open questions
   (each with options and consequences, not "should we do X?"). You wait for the human's decision
   and for the move to the implementation phase. Without this, you don't enter the `code` phase.
   **You don't remove the waiting-on-human label yourself** — removing it is equivalent to making
   the decision. Unassign yourself — you're waiting on the human, not working.

---

## Phase `code` — implementation

Entry condition: an impact map **and** criteria exist, the Issue carries the implementation-phase
label. Either missing = go back to the `analysis` phase.

6. **Working directory.** Already created in step 0 — confirm you're working in it. A task that
   writes: its own worktree on its own branch, the branch name carries the task identifier. A
   task that only reads stays on the main branch. **Only ever
   create the worktree somewhere your quality tools (formatter, linter) actually scan** — a
   directory excluded from their reach by default (e.g. because it holds the agent tool's own
   configuration) hands back a green check that checked nothing (see `../FrameworkDoc.md`, section
   9).
7. **Developer role** with the Issue, impact map, and criteria. It follows a domain-dependent
   order — **EXAMPLE to replace** with your stack's reality:
   - schema change before code, backward compatible, in stages (expand → deploy code → contract);
   - a new data resource is complete: isolation mechanism enabled and enforced, retention
     category, keys carrying the isolation-boundary column, time type with a zone;
   - isolation context local to the operation, an explicit condition in the query, the
     sub-boundary guarded by the application;
   - a state-changing command: a version and an idempotency key tied to the request content;
   - time from an injected clock source, formatting in an invariant culture;
   - the language used to talk to the human differs from the language of the technical surface
     (see the team contract, "How to write" section);
   - a new configuration threshold / new rule comes with an entry in the relevant register, if you
     keep one.
8. **Tests per criterion**, against real infrastructure wherever a fake has no credible
   equivalent. The test count before and after the change belongs in the report; an unexplained
   drop is a finding.
9. **Local quality gates** (from the repository root) — **EXAMPLE, replace with your own**:
   ```bash
   <build command and full test suite>
   <documentation validation command>      # if docs/ was touched
   <your own scanner/assertion commands>   # if relevant to the change's scope
   ```
   If the full test run sometimes gets killed in the background before the result is written —
   run it so you actually wait for it to finish, not unattended in the background.
10. **Developer report** in the format from the role's definition file, with a mandatory "What
    this change does not prove" section and proposed entries for gate 3. No commit, no
    check-off.

---

## Phase `verification` — before gate 2

11. **QA role** — adds a contrast test, runs a mutation by removing the mechanism, and records
    whether the test **actually failed**. The mutation label is derived from the task identifier,
    never from a separate counter (see `../FrameworkDoc.md`, section 9). A mutation that survived
    is a result to report, not to hide. Rows for the capability register are created as a
    **proposal**. Don't run the mutation with an operation that can discard uncommitted work
    (e.g. a hard checkout) — restore state from a patch/diff instead.
12. **Invariant Guardian role** — audits the diff against the hard rules. Verdict `PASS` /
    `STOP`. On `STOP` you go back to the `code` phase; the verdict goes into the PR description
    unsmoothed.
13. **Reviewer role** — design flaws outside the rule list: concurrency, retries, load, behavior
    at boundaries.
14. **Security Auditor role** — **conditionally**, when the diff touches an area of elevated risk
    (see the role's definition file, "When to run you" section). Outside that set, you don't run
    it.

Call roles 12–14 **in parallel** — they read, they write nothing.

---

## Phase `pr`

15. **Sync with the main branch before the PR.** The worktree may have been created hours/days
    earlier — parallel roles and sessions have been appending to the same files in the meantime,
    most often the role-cost register. A stale starting point means a risk of a merge conflict
    that today only the human discovers on a finished PR. Check and align **before**
    committing/pushing:
    ```bash
    git fetch origin main
    git log HEAD..origin/main --oneline      # how many commits main has ahead — say it out loud
    git merge origin/main                    # into the worktree, NOT the other way around
    ```
    **No conflict** — carry on.
    **Conflict only in the role-cost register (append-only, one row per call)** — this is a known,
    mechanical pattern: both sides appended a row at the same spot in the table, neither is a
    duplicate. You resolve it **yourself, without a gate**: keep BOTH rows (never drop either
    side), order chronologically/logically from the rows' content.
    **Conflict in any other file** — STOP. This isn't mechanical; escalate to the human with a
    recommendation (see "How you talk to the human"), don't resolve it yourself.
    A merge that actually brought something in (a non-empty `git log` above) repeats the local
    gates from step 9 — the main branch may have brought a code change, not just a register entry.
16. **Commit and push only on an explicit request.** List paths explicitly, never add everything
    at once. Push from the worktree — if the pre-push hook validates the whole tree, someone
    else's unmerged work blocks the push.
17. **PR with the full template.** Sections: the quoted completion condition and its evidence; the
    mutation result and the row in the mutation register; the contrast test; the Guardian's
    verdict, unsmoothed; the invariants touched by this change; the scope left out of this PR. A
    field you can't fill stays empty with a reason. "N/A" with no justification is worse than
    empty.
18. **CI.** Wait for the required checks. Before calling red CI a defect, rule out environmental
    causes: missing checks from a merge conflict, a container image pull failure, a timeout on
    the hosting platform's endpoints, an executor that dropped out (a failure with no log, a step
    with a null result), a dependent service alive but not yet ready, secrets not reaching an
    automated bot, a green status computed against a stale base after the main branch moved on.
19. **GATE 2 — STOP.** The human approves the merge. You don't merge yourself. Unassign yourself.

---

## Phase `closure` — after merge

20. **If you maintain a queryable code index/graph — refresh it before gate 3.** Applies only to
    code files; if the index doesn't exist yet, skip this step — don't set one up from scratch
    here.
21. **GATE 3 — material for the human.** The merged task sits in the gate-3 state (e.g.
    `state:evidence`, see `sdlc-flow.md`), not in the closed one. Prepare ready-to-paste entries, don't paste them
    yourself: checking off the task in the plan with a "Done <date>" row, a row in the
    activity/capability register, mutation rows. Status is never raised without a link to a
    specific test or artifact.
22. **Ratcheted numeric counters** (e.g. a test counter), if you keep one — write the measured
    values **only on the main branch, after a full run**. On a task branch, report-only mode,
    no write.
23. **Labels** — closing the Issue via merge does not remove process labels automatically (see
    `../FrameworkDoc.md`, section 7). Remove them by hand and set the final state. Check that the
    assignment is removed — if it never came off at any gate, remove it now.
24. **Notify the other repository**, if you have more than one product repository under the shared
    process: the other side reported this task, or the change affects them and requires action on
    their end → notify through an Issue in THEIR repository (see `cross-repo-gaps.md`). One form,
    not both: a comment on an existing Issue, or a new one — check first whether there's already a
    match. When the change is purely internal and the other side can't see it — skip this step,
    don't file an Issue "just in case."
25. **Clean up the working directory** — release any held handles/build-process servers first,
    only then remove the worktree.

---

## Result

At the end of every phase, one message: what passed, what's pending, whose decision it's waiting
on, and what the next action is. Compressed per the "How you talk to the human" section — no
spelling out options, every question with a recommendation and a reason.
