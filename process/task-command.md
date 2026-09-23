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
  exception is a closed list of commits you make without asking, all local, on the task branch —
  never on `main` — and none pushed without a request:
  - **bookkeeping commits** — the plan-number reservation (step 2) and the role-cost register row
    ("How you talk to the human", point 3); each touches only its one file;
  - **verification checkpoints** — the developer's state before QA (step 10a) and QA's tests after
    QA (step 11a); each holds exactly the paths that role's report lists. A checkpoint is what
    makes the evidence refer to one fixed version of the code: mutations are measured against it
    and every report names its SHA.

  Anything outside this list goes back to the rule.
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
any of the eight roles, record one row: date, role, task, phase, **model**, complexity, tokens,
tool calls, time, **rework cause**, notes.

**One file per row, not one shared table.** Write each row as its own small file, e.g.
`<cost-register-dir>/<date>_<task>_<phase>_<role>_<n>.json`, and build the table from the
directory when you need it. A shared append-only table makes two parallel tasks append at the
same spot and conflict on every merge; separate files never conflict, so the merge step needs no
special rule for them.

**Model** — the model the role actually ran on, from the invocation, not from the role file.
Roles inherit the calling session's model, so the same role can run on different models across
tasks; without this column a cost or quality difference between two runs can't be told apart
from a model difference. A role's calibration result holds only for the model it was run on (see
`../calibration/README.md`).

**Rework cause** — filled only on a run that repeats earlier work (a fix after `STOP`, a
re-verification): which finding caused it and **which earlier role could have caught it** (the
Developer's self-check, the Guardian, the Analyst's criteria, nobody). This is the data for
deciding where to move checks earlier; leave it empty on first runs.

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

**Commit the row file immediately, as its own small commit of just that one file, on the task branch in
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
4. **Architect role** — **unless the fast lane applies** (see "Fast lane: when the Architect is
   skipped" below). Impact map onto architectural decisions. Three outcomes: fits / needs a
   deviation / needs a new decision. A deviation is an Issue with the corresponding label and a
   draft decision in "Draft — pending approval" status. **After the call, run the write-boundary
   check** (see "Write-boundary check" below) with the architecture decisions directory as the
   only allowed path.
5. **GATE 1 — STOP.** Gather in one message: the criteria, the impact map, the open questions
   (each with options and consequences, not "should we do X?"). You wait for the human's decision
   and for the move to the implementation phase. Without this, you don't enter the `code` phase.
   **You don't remove the waiting-on-human label yourself** — removing it is equivalent to making
   the decision. Unassign yourself — you're waiting on the human, not working.

### Fast lane: when the Architect is skipped

Cost should scale with risk, not with the number of tasks — the same principle that makes the
Security Auditor conditional. The Architect is skipped only when **every** trigger below is clean,
checked mechanically against the files the task will touch (from the Analyst's criteria and the
Issue), not judged:

- no file under the schema/migrations directory;
- no new or changed public API surface (endpoint, contract type, event);
- no new or upgraded dependency (package manifest, lock file, container image);
- no path listed in the **architecture-sensitive paths** list — a file in the repository you keep
  up to date, mapping directories to the decisions that govern them
  (`<path-to-architecture-sensitive-paths-list>`);
- the Product Owner raised no deviation label and the Analyst named no "unproven foundation".

If any trigger fires, or you can't tell which files the task will touch, the Architect runs. At
gate 1 you state explicitly: "Architect skipped — triggers checked: <list, each clean>". The human
can require the Architect anyway; that's a gate-1 decision, not a failure of the fast lane.

**Turn the fast lane on only with data.** Before enabling it, count in the cost register how often
the Architect returned "fits, nothing to add" on tasks that would have passed all the triggers.
If that's not nearly always, the triggers are missing something — fix the list before skipping
anyone. Record the fast-lane skip in the cost register as a row with 0 tokens and the note
"skipped: fast lane", so the saving and any later rework it caused are both visible.

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
    this change does not prove" section, the list of paths it changed, and proposed entries for
    gate 3. The Developer doesn't commit and doesn't check anything off.

10a. **Checkpoint and sync — before any verification.** Evidence is only worth something if it
    describes the code that will be merged, so fix that code first:
    ```bash
    git add -- <exactly the paths listed in the developer report>
    git status --short                       # nothing else staged or modified — say it out loud
    git commit -m "checkpoint: <identifier> developer"     # local, not pushed
    git fetch origin main
    git log HEAD..origin/main --oneline      # how many commits main has ahead — say it out loud
    git merge origin/main                    # into the task branch, NOT the other way around
    ```
    Anything left uncommitted that the report doesn't list is a finding — stop and ask, don't
    commit it along. Merge conflicts follow the rules of step 15. A merge that brought something
    in repeats the local gates from step 9. **`CHECKPOINT` = `git rev-parse HEAD`** — every
    verification step below refers to it.

---

## Phase `verification` — before gate 2

11. **QA role**, on the clean checkpoint — adds a contrast test, runs a mutation by removing the
    mechanism, and records whether the test **actually failed**. The mutation label is derived
    from the task identifier, never from a separate counter (see `../FrameworkDoc.md`, section
    9). A mutation that survived is a result to report, not to hide. Rows for the capability
    register are created as a **proposal**. QA restores production files from `HEAD` and returns
    every mutation as a patch against `CHECKPOINT` (`Base: <SHA>`); it goes into the PR's Mutation
    section as is. **Run the write-boundary check around the call** with the test directory as
    the only allowed path — a mutation left un-reverted, staged or committed shows up here, not
    at gate 2.

11a. **QA checkpoint.** Commit QA's test changes — the paths its report lists, all inside the
    test directory — as `checkpoint: <identifier> qa`. **`VERIFIED` = `git rev-parse HEAD`**: the
    one version the reading roles audit and the PR must carry.

12. **Invariant Guardian role** — audits `VERIFIED` against the hard rules. Verdict `PASS` /
    `STOP`. On `STOP` you go back to the `code` phase; the verdict goes into the PR description
    unsmoothed.
13. **Reviewer role** — design flaws outside the rule list: concurrency, retries, load, behavior
    at boundaries.
14. **Security Auditor role** — **conditionally**, when the diff touches an area of elevated risk
    (see the role's definition file, "When to run you" section). Outside that set, you don't run
    it.

Call roles 12–14 **in parallel** — they read, they write nothing. Give each one `VERIFIED` and
the diff `origin/main...VERIFIED`; **every report states the SHA it read**. A report that names
another SHA, or none, doesn't count for gate 2.

### Write-boundary check

A role's `tools` declaration can't restrict writes to a directory (see the team contract, §2a),
so the boundary is checked mechanically by you, around the call, not by a human at the gate. Use
`scripts/boundary-check.sh` (copied from the process repository's
`process/scripts/boundary-check.sh`, see `bootstrap-guide.md`, step 4):

```bash
T=$(mktemp -d)                                         # outside the tree
scripts/boundary-check.sh snapshot "$T/state"          # immediately BEFORE the role call
# ... role call ...
scripts/boundary-check.sh verify "$T/state" tests/     # immediately AFTER; the allowed prefixes
```

It compares `HEAD`, the index and the whole working tree (new files included), so an edit hidden
by `git add` or by a commit during the call is caught too; its `--self-test` shows each of those
cases failing. Exit 1 = **automatic STOP**: report the paths to the human and do not continue
with the role's result. Exit 2 = the check couldn't run — also a STOP, never "clean". You don't
revert the paths yourself — a human decides whether it was a mutation left behind or a
deliberate edit out of role. "boundary check: clean" goes into the role's cost-register notes, so
the check leaves a trace that it ran. It sees what git sees — ignored files and anything outside
the repository are out of its reach.

### Re-verification after a `STOP`

A fix is new code: the Developer's changes go into a new `checkpoint: <identifier> fix`, QA's into
a new QA checkpoint, and the resulting `VERIFIED` replaces the old one. Reports tied to the old SHA
stay valid only for the parts the fix didn't touch.

After the Developer fixes the findings, **don't rerun every evaluating role on the whole change
by default.** Rerun:

- each role that returned `STOP`, given its previous report and the **diff of the fix** (not the
  whole branch) — its question is "are my findings resolved, and did the fix break anything
  nearby";
- the Invariant Guardian on the diff of the fix, always — a fix is new code, and new code can
  break a fixed rule;
- QA, if the fix touched a mechanism a mutation was run against — the old mutation result no
  longer describes the code.

A role that returned `PASS` and whose area the fix didn't touch is not rerun. **Fall back to a
full rerun** when the fix touches files outside the previous findings, or when two roles disagree
on the same facts — then each needs the full picture. Say which variant you chose and why in the
message to the human.

---

## Phase `pr`

15. **Is the evidence still about this code?** `main` may have moved during verification, and a
    change that merges without conflict can still invalidate a mutation or a risk assessment — a
    shared authorization mechanism rewritten on `main` leaves every test green and every old
    report wrong. Check before pushing:
    ```bash
    git fetch origin main
    git log VERIFIED..origin/main --oneline   # what main brought since verification — say it out loud
    git merge origin/main                     # into the task branch, NOT the other way around
    git diff --name-only VERIFIED HEAD        # everything that differs from the audited version
    ```
    If the last command lists **only** bookkeeping files (cost-register rows), the evidence
    stands. If it lists any production, test, schema or configuration file, the reports tied to
    `VERIFIED` no longer cover the code: rerun verification for the incoming diff by the rules of
    "Re-verification after a `STOP`" — the Guardian always, QA when a mutated mechanism or its
    tests changed — and set a new `VERIFIED`. Green CI on the new head does not replace this.
    **No conflict** — carry on.
    **Conflict in the role-cost register** — shouldn't happen with one file per row. If your
    register is still a single shared table, this is the known mechanical pattern: both sides
    appended a row at the same spot, neither is a duplicate. You resolve it **yourself, without a
    gate**: keep BOTH rows (never drop either side), order chronologically from the rows' content
    — and consider moving to one file per row.
    **Conflict in any other file** — STOP. This isn't mechanical; escalate to the human with a
    recommendation (see "How you talk to the human"), don't resolve it yourself.
    A merge that actually brought something in (a non-empty `git log` above) repeats the local
    gates from step 9 — the main branch may have brought a code change, not just a register entry.
16. **Push only on an explicit request.** The code is already in the checkpoint commits; any
    further commit lists paths explicitly, never everything at once. Push from the worktree — if
    the pre-push hook validates the whole tree, someone else's unmerged work blocks the push.
17. **PR with the full template.** Sections: the quoted completion condition and its evidence; the
    mutation result, its patch and base; the contrast test; the Guardian's verdict, unsmoothed;
    the invariants touched by this change; the scope left out of this PR; **`Verified at:
    <VERIFIED SHA>`**. The PR refers to the Issue with **`Refs #<N>`, never a closing keyword** —
    merging this PR must leave the Issue open for gate 3 (see step 21). A field you can't fill
    stays empty with a reason. "N/A" with no justification is worse than empty.
18. **CI.** Wait for the required checks. Before calling red CI a defect, rule out environmental
    causes: missing checks from a merge conflict, a container image pull failure, a timeout on
    the hosting platform's endpoints, an executor that dropped out (a failure with no log, a step
    with a null result), a dependent service alive but not yet ready, secrets not reaching an
    automated bot, a green status computed against a stale base after the main branch moved on.
19. **GATE 2 — STOP.** The human approves the merge. You don't merge yourself. The message names
    `VERIFIED`, the PR head SHA, and every commit between them (expected: bookkeeping only) — if
    anything else is there, the gate is not ready. Unassign yourself.

---

## Phase `closure` — after merge

20. **If you maintain a queryable code index/graph — refresh it before gate 3.** Applies only to
    code files; if the index doesn't exist yet, skip this step — don't set one up from scratch
    here.
21. **GATE 3 — material for the human.** After the merge the Issue is **still open**, in the
    gate-3 state (`state:evidence` + `waiting-on-human`, see `sdlc-flow.md`) — that is what keeps
    it in the one filter the human watches. Prepare ready-to-paste entries, don't paste them
    yourself: checking off the task in the plan with a "Done <date>" row, a row in the
    activity/capability register, mutation rows with links to the patches in the merged PR.
    Status is never raised without a link to a specific test or artifact. The human commits them
    as a documentation PR whose description says **`Closes #<N>`** — that merge, not the code
    merge, closes the Issue.
22. **Ratcheted numeric counters** (e.g. a test counter), if you keep one — write the measured
    values **only on the main branch, after a full run**. On a task branch, report-only mode,
    no write.
23. **Labels** — closing the Issue through the gate-3 documentation PR does not remove process
    labels (see `../FrameworkDoc.md`, section 7). The human sets `state:closed` and removes
    `waiting-on-human` when approving gate 3. Check that the assignment is removed — if it never
    came off at any gate, remove it now.
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
