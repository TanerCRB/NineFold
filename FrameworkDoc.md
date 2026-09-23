# SDLC Framework Based on Spec-Driven Development and Human-in-the-Loop

## About this document

This material describes a software development process (SDLC) used in a real project — a
multi-tenant B2B SaaS platform, built across four separate repositories: a **backend** repository
(.NET, a relational database with row-level data isolation), a **frontend** repository (Next.js,
TypeScript), an **infrastructure** repository (environments, CI, deployments), and one repository
that contains no product code at all — only **the process itself**: role definitions, templates,
synchronization scripts, a calibration registry. The first three have independent codebases and
independent tooling teams, but **the same process skeleton** — designed from the ground up for
working with AI agents as the primary executors of engineering tasks, with a human acting as the
decision architect and final approver. The fourth repository is the source of this skeleton and
distributes it to the others.

All proper names, organization identifiers, specific ticket numbers, and the business domain have
been removed or generalized. What remains is the mechanics: roles, gates, evidence, sequencing.

This document is not a deployment guide for a specific tool. It is a description of a **pattern**
that can be carried over to a different project, a different technology stack, and a different
domain.

The measured numbers and worked examples from the original project (token costs per role, one task
traced from ticket to merge, the full list of documented tool failures) live in a separate file,
[`CASE-STUDY.md`](CASE-STUDY.md). This document keeps only the key takeaways from them, with links.

---

## 1. Two ideas the whole process stands on

### Spec-Driven Development (SDD)

Before a single line of code is written, a **verifiable specification** is produced. Not a
descriptive document, but a set of statements in the form: *"how will we know this works"* and
*"how will we know our way of knowing this is not empty"*. Implementation is a translation of the
specification into code, not the other way around — code does not define the requirement, it either
satisfies it or it doesn't.

In this project, SDD has three layers, each with a separate process owner:

1. **Story (business need)** — what needs to be built and who is hurt by its absence.
2. **Acceptance criteria** — observable conditions: a test name, a query, an artifact. Not "it
   works," but something that can be mechanically verified.
3. **Architectural impact map** — whether the task fits within already-adopted design decisions, or
   requires changing them.

None of these layers is written by the same performer as the next one — and **none is written by
the one who later implements it**. This is a deliberate division of labor, described in section 3.

### Human-in-the-Loop (HIL)

The process is automated from the reporting of a need all the way to the pull request — but **three
specific moments belong exclusively to the human**, and no agent has the right to skip or speed them
up:

1. Approval of scope and approach, before code is written.
2. Approval of merging the change into the main branch.
3. Confirmation that the evidence of task completion has actually reached the project's registries.

Outside these three points agents work independently — but **every question directed at the human
has a mandatory shape**: not a list of options, but a recommendation with a rationale and
information about what would change it. The reason is practical: a list of variants without a
pick shifts the thinking work back onto the human, which is the opposite of what the gate exists
for. A recommendation is not a decision — the process still stops and waits for the human, but it
waits with a ready proposal, not an empty question.

---

## 2. Why combine SDD and HIL, not use them separately

Tests and quality gates alone do not protect against one specific failure mode that this project has
caught repeatedly in practice: **a test that passes for the wrong reason**. A negative test checking
"you can't see other people's data" passes flawlessly and forever if the endpoint simply always
returns an empty list. The code looks safe, the proof is false.

SDD on its own does not solve this problem — a specification without verification of whether the
proof actually proves anything is just more nicely worded code. That's why the process closes the
loop with **mutation testing** (section 6) as part of the standard flow, not as an optional audit.

HIL on its own does not scale — a human approving every line of code is a bottleneck. That's why
human gates are **deliberately few and concentrated on decisions that cannot be automated** (scope,
risk, ultimate responsibility for merging), while everything else — rule compliance, presence of
evidence, design quality — is taken off the human and handed to specialized roles.

---

## 3. Actors in the process

The process staffs nine roles in every product repository. Eight of them are specialized agents —
each with a narrow scope of responsibility, its own set of permissions, and a hard ban on stepping
into other roles' competencies. The ninth role is the human.

Key design principle: **a role that creates something does not evaluate itself**. The same agent
never writes both the specification and the criteria for meeting it. The same agent never writes
both the code and the proof that the tests for that code are not empty. This division of labor
exists so that at every handoff between roles, someone else looks at the result with fresh eyes.

| Role | What it does | What it doesn't do | What it produces |
|---|---|---|---|
| **Product Owner** | Turns a business need into a ticket with an observable completion condition and an explicitly named excluded scope | Does not design the solution, does not write code, does not approve its own work | A ticket ready for the first gate |
| **Analyst** | Turns the ticket into acceptance criteria, each of which has: an observable carrier, a contrasting scenario (the same situation with one changed variable, opposite result), and a named mutation that should invalidate it if the mechanism disappears | Does not design the implementation, writes nothing down itself — passes the text along | Acceptance criteria + an explicit list of what the criteria do NOT prove |
| **Architect** | Checks the task's compliance with adopted architectural decisions; for each affected decision, resolves: fits / needs supplementing / needs a new human decision | Does not write code, does not grant decisions the status "adopted" — only prepares the design for approval | A map of impact on architectural decisions + a list of resolving questions |
| **Developer** | The only role with write access to production code. Implements the approved task: data schema change, logic, tests proving each criterion | Does not commit, does not push, does not raise the task's status, does not change criteria it cannot meet — reports this as a finding | A branch ready for review + a report containing a mandatory "what this change does NOT prove" section |
| **QA** | Checks whether the developer's evidence is not empty: adds a contrasting scenario, **physically removes the mechanism from the code and checks whether the test actually then fails** (mutation testing) | Does not fix production code — not even a minor line. A role that can fix stops verifying | Mutation result (killed / survived), contrasting test, defect reports |
| **Invariant Guardian** | Audits the code diff exclusively against a closed list of hard, previously established rules (data isolation between clients, API contracts, time handling, write uniqueness) | Does not evaluate style, architecture, or performance — only the checklist | Verdict: pass / stop, with location, damage path, and the condition that would overturn the ticket |
| **Reviewer** | Reads the change without a checklist and looks for flaws no rule list would catch: behavior under load, under concurrency, under retried operations, with bad input data | Does not repeat the Guardian's work | List of design flaws with rationale |
| **Security Auditor** | Runs conditionally — only when the change touches the CI/CD pipeline, dependencies, authentication, personal data, configuration, or secrets. Assesses: who can get what from this change, and what they shouldn't | Does not run on every change — audit cost is meant to scale with risk, not with the number of tickets | Threat assessment, not a rule list |
| **Human** | Approves scope and approach (gate 1), approves merging (gate 2), confirms that evidence has been entered into the registries (gate 3). The only role that can make an irreversible decision | — | Decision |

### Where role definitions come from

Role definitions are not written separately in each product repository. There exists a **fourth
repository**, dedicated exclusively to the process — without product code — which is the source of
truth for roles, commands, ticket templates, and state labels. Product repositories **inherit** from
it; they do not maintain their own separate copies.

The distribution mechanism is mechanical, not manual:

- A sync script copies role definitions into the product repository's configuration directory —
  this directory is, on principle, **not versioned** in the product repository (because it concerns
  the tool, not the code), so copying does not violate the "product code separate from process"
  boundary. The same script has a check-only mode: it compares without writing and returns an error
  if the product repository has drifted from the source definition — this is a **compliance
  assertion**, not a repair action.
- A separate script synchronizes ticket templates and **prints out** (does not execute itself) the
  commands for assigning labels in the code-hosting system — because a label in such a system is not
  a file, and the tool deliberately does not hold direct credentials for it.
- Changes to the CI/CD pipelines of product repositories are **not** distributed by this
  mechanism — they have their own, separate review path, because an error in them blocks everyone's
  work, not just one task's.

**The source repository has its own lifecycle for changes to the roles themselves.** A change to a
role definition (e.g., extending the Guardian's checklist with a new rule) requires repeating that
role's calibration run (section 6) — this is the equivalent of a regression test, but for the role
definition instead of code. Tasks concerning the process itself do not have tickets in the tracking
system — they live as rows in the plan with an explicit completion condition, with progress noted in
the run log. A deliberate decision: for a handful of such tasks, a separate tracker would be a tool
with no work to do. Tickets and pull requests concerning the product itself always live in the
product repository, never in the process repository — because the mechanism that closes a ticket via
merging only works within a single repository, not across them. That is a fact of the code-hosting
platform, not a matter of preference.

The source repository also prepares **drafts** of architectural decisions for product repositories —
before they land in that repository's proper decision registry. The source repository itself has no
right to grant a decision the status "adopted" — only to prepare it for approval, exactly the way the
Architect role does within a single repository (section 3).

**Three tooling layers, with an explicit criterion for when to add another.** The process
distinguishes: the execution layer (a role as a text file run by the agent environment), the process
and memory layer (a system tracking tickets/PRs/CI — state encoded in labels, surviving a session
restart or a break), and the persistent orchestrator layer — **deliberately not built**, with an
explicit entry condition: only once the same process flow has been run manually at least ten times,
the result is repeatable, and a specific step is already shown to be worth running unsupervised.
Before that condition is met, building a persistent orchestrator would be premature abstraction.

**The scope of applicability of role permission declarations.** A role's permissions are declared at
the tool level (e.g., "has access to the system shell"), not at the level of a specific path or
subcommand — it is not possible to declare "has shell access, but without the file-writing command."
Where the boundary is inexpressible in the declaration itself, the process moves control to the
review stage: a role with shell access operates under the rule "every trace it leaves in the system
is explicit and visible"; a role with full write access but domain-restricted (e.g., only the test
directory) operates under the rule "any change outside that directory in its code diff is an
automatic stop," checked at review time, not enforced by the tool itself.

### Why this particular division

Every boundary between roles answers a specific failure mode observed in the project:

- **The Analyst does not design the solution**, because an acceptance criterion derived from a
  finished implementation is always satisfied — it checks nothing.
- **The Developer does not evaluate its own work**, because every performer has a tendency to treat
  their own code as proof. This is not a matter of competence — it is a structural conflict of
  interest that cannot be eliminated by discipline, only by separating roles.
- **QA does not fix code**, because a role that can fix stops verifying — it would then be checking
  its own fix.
- **The Guardian and the Reviewer have disjoint tasks** (fixed rules versus contextual flaws), so as
  not to duplicate work and not to create an illusion of double coverage where both look at the same
  thing.

---

## 4. Task lifecycle

### Invocation interface: three commands

The process is launched with three text commands of the agent environment, not a sequence of manual
commands issued one after another:

- **`/zadanie_be <identifier> [phase]`** — the full lifecycle described below, for the backend
  repository. The phase argument is optional and is used to resume an interrupted task without
  starting from scratch.
- **`/zadanie_fe <identifier> [phase]`** — exactly the same invocation shape and the same state
  machine, a different technology stack underneath (differences described in section 12).
- **`/zadanie_stan [repository prefix] <identifier>`** — the reporting command from section 7:
  read-only only, maps the ticket's state to one position in the lifecycle and finishes with a
  recommendation for the nearest action.

**Where the content lives, and where just the pointer does.** The full content of each command
(steps, gates, domain rules) lives **in the product repository it concerns** — versioned and going
through code review like any other change. A working session that is meant to drive tasks in both
product repositories at once, without switching the working directory, additionally gets a **thin
pointer** (a few lines: which repository, where the full content lives, what the working directory
is) kept outside the product repositories themselves — this pointer concerns local session
configuration, not product code, so it is not versioned; anyone who wants to use it sets it up once,
manually. Hence the prefixed names (`/zadanie_be`, `/zadanie_fe`) are visible only from the level
that spans both repositories at once — from inside a single product repository, the same command is
visible under the name without the prefix.

**A side effect of this split, observed in practice: an agent role's definition and the mechanism
that invokes it are two separate layers that can drift independently of each other.** The agent
environment registers available roles exclusively from its current working directory — a session
launched above both product repositories does not see that directory's roles at all, even though the
full-cycle command it just ran lives in a product repository and explicitly names roles by name at
every step. The fix is not to move role definitions closer to the parent session — the same role
names carry different content in the two product repositories, so they cannot be merged into one
place without collision. Instead, the command launches the role through a universal, generic
execution mechanism and pastes the specific role's content in as the first part of the assignment —
a solution functionally equivalent to the original intent, just not relying on the environment
guessing on its own where to look for a definition from a level that can't see it.

The same invocation mechanism carries one more rule, added after the same finding: a role launched
this way **inherits the language model of the session that calls it** — regardless of what model was
recorded in the original role definition. Upgrading to a more expensive model is a decision requiring
human consent, the same as any other question without ready evidence (section 2) — not something the
command does quietly based on a field in the definition file.

Every task goes through five phases, always in this order, with three mandatory human stops.

```
Reported need
        │
        ▼
 [Phase: Analysis]
  Product Owner → Analyst → Architect
        │
        ▼
 ══════ GATE 1: HUMAN ══════
  Approves scope, criteria, and architectural approach
        │
        ▼
 [Phase: Implementation]
  Developer (separate worktree/branch per task)
        │
        ▼
 [Phase: Verification]
  QA (mutations) ── Guardian ── Reviewer ── Security Auditor (conditional)
  the last three run in parallel, because they only read
        │
        ▼
 [Phase: Pull Request]
  Template with evidence sections + automatic CI gates
        │
        ▼
 ══════ GATE 2: HUMAN ══════
  Approves merging into the main branch
        │
        ▼
 [Phase: Closure]
  Updating progress registries, cleaning up the working environment
        │
        ▼
 ══════ GATE 3: HUMAN ══════
  Confirms that the completion evidence has actually reached the registry
```

### Phase 0 — Reconnaissance

Before anything starts, the process checks whether the task is already in progress: whether an open
pull request exists, whether a branch exists, whether someone else has already set up a working
environment for this task. **Work already in progress by someone else is a hard stop** — a pull
request with a merge conflict looks abandoned, but rarely is.

### Analysis phase — up to gate 1

1. The Product Owner checks whether the ticket has the full set: what and why, completion condition,
   explicitly named excluded scope, grounding in existing documentation.
2. The Analyst translates this into acceptance criteria — each with an observable carrier, a
   contrasting scenario, and a named mutation.
3. The Architect checks compliance with adopted design decisions and prepares the impact map.
4. The human gets one message: criteria, impact map, resolving questions with a recommendation —
   and either approves or sends it back for revision. Without this approval, the implementation
   phase does not start.

### Implementation phase

A task that changes files gets its **own, isolated working environment** (a separate git working
directory on a separate branch) — because several agents work on the repository in parallel, and
without isolation they would overwrite each other's working state. Purely reading tasks (explain,
find, compare) stay on the main branch, because they don't modify it.

The Developer implements in a domain-dependent, fixed order (e.g., for the backend: first the
backward-compatible data schema change, then the code), writes tests — one per acceptance criterion
— and runs local quality gates (compilation, tests, documentation validation, change-specific
scanners). It finishes with a report containing a mandatory section: **what this change does NOT
prove**.

### Verification phase — before gate 2

QA does not check whether the code works — the developer's green test run already showed that. QA
answers the question a green run doesn't ask: **can these tests fail at all?** It does this by
physically removing the mechanism from the code (a mutation) and checking whether the corresponding
test actually then fails. Details in section 6.

In parallel (because they only read, they write nothing) come: the Guardian with a checklist of hard
rules, the Reviewer looking for design flaws outside the checklist, and, conditionally, the Security
Auditor — only if the change touches areas of elevated risk.

### Pull Request phase

Commit and push happen **only at the human's explicit request** — never automatically, even when it
seems like the obvious next step. The pull request description follows the full, required template:
the quoted completion condition with evidence, mutation result, contrasting test result, the
Guardian's unvarnished verdict, the list of invariants the change touches, and an explicitly named
scope outside this pull request. An unfilled field is left blank with a stated reason — "n/a" without
a justification is worse than an empty field, because it pretends to be a resolution.

Automatic CI gates must pass (section 8) before the process reaches the second human gate. An agent
never merges a pull request itself.

### Closure phase

After merging, the process **does not raise the task's status automatically**. It prepares entries
ready to paste into the progress registries — but the human pastes them, as the third gate. Only this
closes the loop: working labels are removed manually, the working environment is cleaned up.

---

## 5. The three human gates — why these specifically

The gates are not spread evenly through the process. They are placed where automation structurally
cannot make the decision for the human:

**Gate 1 (before implementation)** — because scope and architectural approach are decisions with
consequences that cannot be cheaply undone. It's cheaper to stop before writing code than after.

**Gate 2 (before merging)** — because merging into the main branch is a shared operation: it affects
the work of other agents and other people in the same repository. No agent has the autonomy to decide
about impact on someone else's work.

**Gate 3 (after merging)** — because project status ("this is done") is a public claim on which
further decisions rest. The rule holding throughout the project is: **status is raised by evidence,
not conviction**. No agent raises it on its own, even after green tests — because in this process,
"green tests" and "task complete" are deliberately separate claims.

Every question directed at the human at any gate has a mandatory format: variants with consequences,
a recommendation with a rationale, and an explicitly named "what would change this recommendation."
A recommendation is never substituted for a decision — the process still waits.

---

## 6. Mutation testing as the core of the evidence

This is the mechanism that distinguishes this process from the standard "green tests = done." The
motivation is empirical, not theoretical — the project has documented, real cases of tests that
passed for the wrong reason:

- A test was supposed to prove data isolation between two **platform clients** (a boundary guarded by
  the database at the lowest level), but the test scenario actually checked something no one
  questioned — an application-level mechanism the test never touched at all. Removing that mechanism
  from the code **did not break the test**. The test looked like proof, but proved something else.
- A pagination test renamed a record to a value that still sorted before the cursor — the direction
  of the change was not enforced by the test, so the mutation survived.
- A test critical to business logic turned out to be red for two hours a day, every day, because of a
  time-boundary condition — discovered not by mutation, but by a regular run at a specific time of
  day.

The rule derived from these cases: **every test carrying a strong claim is checked with a mutation**
— the mechanism the test supposedly guards is removed, and it is checked whether the test actually
then fails. A mutation is an **action, not a piece of reasoning** — the conviction "this test would
surely fail" does not count as a performed mutation.

Process rules that follow from this:

- The mutation is named by the Analyst, **before** implementation — this is the only moment when no
  one yet knows the shape of the solution, so the mutation can't be tailored to whatever ended up
  being built.
- The mutation is performed by QA, not the developer — because a role that can fix the code stops
  testing it impartially.
- If the mutation **survived** (the test still passes despite the removed mechanism), that is a test
  defect, not a reason to hide the result. The result goes into the registry along with information
  on how the test was fixed.
- The mutation result is a mandatory field in the pull request description — not as a formality, but
  as the only proof that the proof is not empty.

The same mechanism protects against a contrasting test without contrast: a negative test checking
"no access" always passes if the mechanism simply denies everyone unconditionally. That's why every
acceptance criterion has a pair: a claim, and the same situation with one changed element, where the
result is expected to be the opposite.

### The chain of evidence as a formal sequence

The whole mechanism can be written as a single chain, in which the absence of any link zeroes out the
rest:

```
Decision → observable criterion → test + contrasting scenario → mutation → only now, status
```

The task's status must not be raised if any link of this chain is empty — even if all the others are
complete. A green test without a mutation is not proof of completion, only proof that the code
compiled and checked something.

### Role calibration: the same mechanism applied to the agents themselves

Since a test is checked with a mutation, an evaluating role (Guardian, Reviewer, QA) is checked
analogously — through **calibration**: running the role on material with a known, previously
established outcome, to measure whether it actually detects what it's supposed to detect, and does
not flag what isn't there. The project uses two calibration methods, depending on the role type:

- **A role checking against a closed list of rules** (Guardian) is calibrated with a seeded set:
  files with explicitly introduced violations mixed with "decoys" — code fragments that look like a
  violation but aren't — plus one run on real, clean code as a control against false alarms. The
  documented result of one such calibration: a complete set of detected violations, zero decoys
  wrongly flagged, zero false alarms on clean code.
- **A role without a closed list of rules** (Reviewer) has nothing to seed — it is calibrated against
  a **review previously performed by a human** on a historical code change, with the tree restored to
  its state before the fixes. The measures are: sensitivity to findings that were not explicitly
  listed in the role definition, sensitivity to those that were, precision (the share of findings
  that are actually valid), and surplus beyond what the human found.

Two conclusions were drawn from the calibration runs, both named as general, not one-off:

1. **A false "checked and clean" is more expensive than an oversight.** In one run, the most serious
   missed finding was explicitly recorded by the role as a clean area — because the agent took the
   intent declared in a code comment by the author as an agreed-upon decision, instead of comparing
   it against the registry of actually adopted decisions. Process consequence: an entry in the
   "checked and clean" section must carry as much evidence as a reported problem — a mere "looks
   good" is not enough.
2. **A calibration set can be contaminated by the role's own definition.** If the examples used in
   the role description overlap with items in the test set, sensitivity comes out artificially
   inflated — the agent gets the answer along with the question. Calibration sets must be built
   independently of the examples in the role definition, not from them.

A change to a role definition (a new rule, a reworded scope) requires repeating both calibration
methods before the changed role returns to production work — the exact equivalent of a regression
test.

### Measuring the cost of roles

Every role run ends with an entry in the log: tokens consumed, number of tool calls, wall-clock time.
This is the same kind of evidence field as for code — "the role works" without a cost entry is a
claim without proof. Only numbers that were actually recorded count; where the log is silent, the
report says so explicitly, instead of estimating.

**A permanent cost registry fed from real work.** Calibration runs on prepared test material give a
reliable order of magnitude for a single run of a role, but not an average over real tasks. Instead
of patching in numbers with one synthetic run on an artificial task, the process keeps a separate,
permanent registry — in the source project `docs/architecture/koszt-rol-agentowych.md` in the
backend repository and `docs/KOSZT-ROL-AGENTOWYCH.md` in the frontend repository — fed
**automatically from real work**: after every call to any of the eight roles, the command driving the task appends a row with numbers
taken directly from the call's output (tokens, tool calls, time), never from an estimate. The goal is
3–5 measurements per role before the order of magnitude is considered reliable — below that
threshold, the spread between individual tasks can easily be mistaken for a pattern.

Each row additionally carries the **task complexity** (Low / Medium / High) — but this is explicitly
marked as an **assessment by the driving agent**, issued before the role is called, based on the
number of files in scope, the number of acceptance criteria, and the number of open architectural
questions, not a measured quantity like tokens or time. The reason for adding this column: without
it, the cost spread between two runs of the same role is indistinguishable from the role's own
instability — with it, you can see whether an expensive run was expensive because the task was large,
or because the role read more than the task required.

**What the measurements showed in the source project** (full tables, dates, and caveats in
[`CASE-STUDY.md`](CASE-STUDY.md)):

- In calibration runs, the log's own order of magnitude was **"one Guardian audit is ~100k tokens
  and a few minutes"** ([details](CASE-STUDY.md#actual-cost-in-tokens--only-what-was-actually-measured)).
- In production work (status as of 2026-09-13), the registries averaged **197,819 tokens per role call on the backend** (571
  measurements) and **153,011 on the frontend** (525 measurements). The Developer is the most
  expensive role on both sides, the Product Owner the cheapest; cost rises with task complexity
  once the sample is large enough; and the spread within one role can be larger than the difference
  between roles ([details](CASE-STUDY.md#results-after-gathering-material-from-production-work)).
- One task tracked from ticket to merge through all roles cost 1,728,225 tokens (backend) and
  1,282,807 tokens (frontend) of expert-role time. **One corrective iteration** — a Reviewer STOP,
  a fix, and re-verification — added **close to 60%** and **about 29%** of the task's total cost
  respectively: the countable price of "it's cheaper to stop earlier than later" (section 5). The
  frontend run also ended with an explicitly named dispute between two evaluating roles, handed to
  the human instead of being resolved automatically
  ([backend example](CASE-STUDY.md#example-the-cost-of-one-task-tracked-from-ticket-to-merge-backend),
  [frontend example](CASE-STUDY.md#example-the-cost-of-one-task-tracked-from-ticket-to-merge-frontend)).

---

## 7. Task state management

A task's progress is not tracked in anyone's head — it is encoded in visible, verifiable signals:

- **State labels** on the ticket (equivalents: "in analysis," "waiting for human decision," "in
  implementation," "waiting to merge," "closed") — each changed by a specific process step, never by
  guesswork.
- **Action registry** in the project documentation, with a limited set of statuses (open / decision /
  in progress / closed) — the status "closed" always requires a link to a specific test or artifact,
  never just a note.
- **Mutation registry** — a table: which mechanism was removed, what the result was, how many tests
  failed.
- **Capability registry, separate from the decision registry.** It answers exclusively the question
  "what the system actually can do, and what proves it" — with four allowed evidence values: a test
  checked by mutation, a test without mutation, manual verification with a date, or no evidence.
  Deliberately kept separate from the architectural decision registry, because an adopted decision
  means only an accepted direction, not an existing capability — project documentation **may run
  ahead** of implementation, and this registry is the only place that says what of it actually works.
  The first population of such a registry for one of the repositories yielded "no evidence" for most
  items — which is described as the **correct result of a first pass**, not a process flaw: the
  registry had only just started measuring what no one had measured before.
- **A separate, read-only reporting command** — it changes nothing, sets up no working environment,
  calls no executing agent. It gathers the state of the ticket, the associated pull request, the
  result of automatic checks, and the documentation registries, then maps this onto a single position
  in the lifecycle (e.g., "waiting for gate 2 — for the human's merge decision"). It always ends with
  a recommendation of the single nearest action, never a list of possibilities.

An important, deliberate rule: **closing a ticket by merging the pull request does not automatically
remove process labels**. The code-hosting platform's mechanism closes the ticket itself, but labels
like "in progress" or "waiting for decision" remain — because whether the process actually finished
(gate 3) is decided by the evidence entered into the registry, not by the mere fact that the code was
merged.

---

## 8. Automatic quality gates

Beyond the agent roles, the process relies on a layer of mechanical checks run locally and in the
CI/CD pipeline. They fall into several functional categories:

- **Functional correctness** — a full suite of automated tests against real infrastructure (not
  mocks, where it matters — e.g., data-isolation tests run against a real database, because database
  mechanisms have no reliable equivalent in emulation).
- **Backward compatibility and data migration** — a separate run checking that a data schema change
  does not break the previous version during a rolling deployment (two application versions running
  simultaneously against one schema).
- **Documentation consistency** — a validator checking that every architectural decision has the
  full set of required fields, that every plan entry has a completion condition, that a new document
  is wired into the publication process.
- **Module boundaries and domain rules** — domain-specific checks: whether new code doesn't cross
  established boundaries between modules, whether a new text column has a defined length limit,
  whether a new configuration threshold has a documented source for its value.
- **Supply-chain security** — a dependency vulnerability scan (with an established severity
  threshold, with no open-ended exceptions — every exception carries an owner and a deadline, after
  which the gate blocks again).
- **Layer-specific visual/quality conventions** (e.g., on the frontend: a ban on hardcoded colors
  outside a single, centralized token source).
- **Numeric ratchets** — mechanisms guarding that certain numbers (e.g., number of tests, code
  coverage threshold) only ever increase, or are deliberately and explicitly lowered, never silently
  drop.

A common trait of all these gates: **each has an exception mode, but no exception is open-ended.** An
entry disabling a check always requires: a rationale, an owner, and a date after which the gate starts
blocking again despite the entry. This is a deliberate response to an observed failure pattern: an
exception without a deadline stays forever, and after enough time no one remembers whether it was a
decision or an oversight.

### Rules for designing the assertions themselves

Automatic gates only have value when they are themselves correctly designed. The project holds to
three rules, derived from real mishaps:

1. **Every assertion is checked with a mutation, the same as a test.** One of the decision-registry
   validators went through nine documented mutations of its own logic before it was deemed reliable.
2. **A warning that lights up on a correct system state teaches people to ignore it.** Example: a
   byte-by-byte file comparison check was lit red permanently because of a line-ending difference
   between operating systems — it detected no actual failure, it just conditioned people to treat a
   red status as normal.
3. **Missing material to check must end in an error, not a silent zero.** A security audit found
   three silent exits of this kind in a single compliance-checking script — situations where the
   script had nothing to check and, instead of reporting an error, silently returned a positive
   result.

---

## 9. Multiple agents working in parallel

Because several agents (and sometimes several human sessions) work on the same repository at once,
the process contains a separate layer of rules protecting against collisions over shared resources:

- **An isolated working environment per task.** Every task that modifies files gets its own git
  working directory on a separate branch. Purely reading tasks stay on the main branch. Without this
  separation, agents would overwrite each other's working state, and the pre-push check (looking at
  the whole tree, not just the commit) would block pushes due to someone else's unmerged work. Only
  ever create the working directory somewhere your quality tools (formatter, linter) actually scan
  — a directory that's excluded from their reach by default (e.g. because it holds the agent tool's
  own configuration) hands back a green check that checked nothing.
- **Issue assignment as a lightweight coordination signal, alongside working-directory isolation.**
  A session starting work on a task assigns the Issue to itself; a session that stops working it —
  a STOP gate, a collision, a merge, anything else — unassigns itself, even when the task stays
  open. This answers a question the state label doesn't: not just *what phase* the task is in, but
  *whether anyone is actually working it right now*.
- **An explicit split of the task queue between parallel sessions** — e.g., the rule "session A only
  takes odd numbers, session B only even numbers," checked **before** starting the analysis, not
  after. Without this, two sessions reach for the same "next" queue item and duplicate work. A
  session takes the next queue item **only after merging** the current task, not after merely
  opening the pull request or getting green CI — otherwise the same session ends up with two tasks
  in flight at once, which defeats the point of the split. A queue item blocked on something
  outside the repository (a human decision, an external dependency) is skipped when picking the
  next one, regardless of parity, until the block clears.
- **Identifiers as a shared resource.** A task number in the plan, a mutation's label, a data
  migration file name — all these identifiers can collide when two parallel pieces of work try to
  assign the same number independently. The solution is **reservation via a dedicated mechanism,
  recorded as a separate commit before the actual work begins** — this way, a collision between two
  reservations shows up as an ordinary, visible merge conflict, rather than a silent bug that only
  surfaces at review time.
- **Test data as a shared resource.** In an environment where many test classes share one database,
  an identifier used by two independent test classes (e.g., the same customer ID document number in
  two scenarios) can generate an assertion collision that doesn't show up when running a single class
  — only on a full run, in an unlucky order. Hence a separate, automatic check for the uniqueness of
  such identifiers across the whole test suite.

The philosophy underlying this section: **any resource that can collide between two parallel pieces
of work is, by definition, a shared resource** — and requires either reservation or an automatic
check, never mere participant discipline.

### Failure pattern: a tool returns success while being wrong

A separate, repeatedly observed class of defect, deemed repeatable enough to become its own point in
the design process for helper tools: **a tool finishes with a success code, despite having done
something other than intended.** The source project documented six such cases — among them a
tool copying role definitions (see section 3) that returned versions a dozen-odd commits older while
reporting full success, a CI safeguard guarding the wrong event, a formatting check that came back
green because it scanned zero files, and a one-off replacement script that rewrote its own check
and then reported the state as clean. The full list is in [`CASE-STUDY.md`](CASE-STUDY.md#documented-cases-a-tool-returns-success-while-being-wrong).

Remedies derived from these cases, now applied as a standard for every new helper tool: the tool
excludes itself from the scan it runs; matching patterns are assembled from fragments, so they don't
accidentally match the tool's own code; every run reports **what it read**, not just what it found —
because "nothing found" and "nothing checked" look identical if the report doesn't distinguish these
two states.

---

## 10. Process for infrastructure tasks

Tasks concerning environments, deployments, and CI have a separate repository — and a **structurally
different** process than product repositories, not just a different checklist.

**No agent roles of its own and no decision registry of its own.** This repository does not define
its own agents — it inherits from the process's source repository only the process layer (labels,
ticket templates, the pre-push hook), not the roles layer. It also has no architectural decision
registry of its own: decisions about environments and the CI executor live in the backend
repository's decision registry. The justification, explicitly stated in the repository's
documentation: a second, separate registry would drift out of sync with that one within a month —
so it was deliberately not created, rather than maintaining consistency between two copies later.

**Three caveats at the very top of the documentation, not in a footnote.** This repository's test
environment is explicitly and clearly marked as: not a production or working environment in the
sense of adopted decisions, not containing any real customer data (only generator-produced data —
because the only available key store is a plain file, and personal-data protection requires a key
management service the environment doesn't have), and not raising any status in the backend
repository's capability registry. Reason for placing these caveats at the very top, not in a
footnote: an explicitly named social failure mode, in which the first screenshot from a working test
environment starts living a life of its own as evidence of production readiness, even though no one
intended that.

**Gate 2 is weaker here than in product repositories — and this is named explicitly as a limitation,
not an oversight.** Branch protection against merging without review does not work on a private
repository on a free hosting plan. As a result, the pre-merge gate here is a **manual click after
reading the code diff**, not an enforced assertion — a red automatic-check result does not physically
block the merge button, it is only meant to be checked before the human presses it.

**Safeguards specific to operations on machines and secrets**, confirmed in the repository's
operational documentation:

- Automatically generated passwords **never leave the machine** on which they were created; the
  password for authentication at the internet-facing edge goes into a configuration file only as a
  hash, never as plain text.
- An explicit, documented warning against one specific class of leak: printing an address containing
  credentials on the command line, because it then ends up in the terminal and in the command history
  the terminal collects. The warning accompanies the description of an **actual incident** — not a
  hypothetical risk — that required a password rotation after the fact.
- There is deliberately no container image registry — images are moved manually between machines.
  This decision forces an additional safeguard: the version/revision must be visible from within the
  running application itself, because the file describing the version on the device "lies" after the
  first manual image upload that no one recorded in the file.
- The deployment readiness gate is a separate, one-off script polling a readiness checkpoint **after**
  the process starts, and does not announce success on a response meaning "not ready yet."
  Deliberately kept separate from the container liveness check (on which automatic restart depends) —
  because previously a process missing required keys could start up and respond with an error instead
  of not starting at all, which twice led to real incidents.

**The rest of the process is shared with the product repositories**: the same ticket forms (including
the form for "gap from the other repository," see section 11), the same pull request template, the
same pre-push hook — copied from the process source repository, but requiring one-time local
configuration, without which it sits on disk and protects nothing. This is an explicitly named trap
in the repository's documentation, not an assumption that everyone remembers it.

---

## 11. Points of contact between repositories

The four repositories are not isolated from one another, but the rules of contact between them are
just as explicitly designed as the rules within a single repository.

**Process source repository → product repositories.** Full inheritance of roles, gates, labels, and
templates via the sync mechanism with its check-only mode (section 3).

**Process source repository → infrastructure repository.** Inheritance of the process itself (labels,
forms, pre-push hook), but **not** the agent-roles layer — the infrastructure repository has no agents
of its own, and its architectural decisions live elsewhere (section 10).

**Between the two product repositories.** The only permissible channel for ordering work from the
other team is a **ticket in the performing team's repository** — never a pull request in someone
else's repository, never editing someone else's documentation or architectural decisions, never
unilaterally setting the priority of someone else's work. Separately from this, each repository has a
local gap registry, answering a different question: the gap registry explains **why this repository
looks the way it does** (what workaround was applied, because the other side hasn't delivered
something yet); a ticket in the other side's repository answers the question of **what the other side
needs to do**. These are two different questions, deliberately kept separate, so that the local
registry does not become an informal ordering channel bypassing the tracking system.

Closing such an order is **two-sided**, not one-sided: three states — reported, delivered, closed by
the requester. Closing the ticket on the performing side does **not** automatically close the gap on
the requesting side — only removing the workaround and confirmation by the requester closes the loop.
A rule verified empirically: one and the same defect (missing assignment of an action to a specific
user in the audit log) was found independently from two sides — once as an entry in the other
repository's gap registry, once by the Reviewer reading the backend code directly — which confirmed in
practice that a channel without a formal ticket does actually lose work, not just theoretically might.

**Between a product repository and the infrastructure repository.** The same ordering channel as
between the product repositories: a documented case in which an infrastructure-related task stage was
ordered via a comment on an already-existing ticket in the infrastructure repository, deliberately
without creating a new, duplicate ticket.

---

## 12. Differences between the backend and frontend contexts

The process skeleton (roles, gates, mutations, registries) is identical in both product repositories.
What differs is the content of the rules the individual roles use — because the domain risks differ.
(The infrastructure repository differs more deeply — structurally, not just in rule content — see
section 10.)

| Dimension | Backend | Frontend |
|---|---|---|
| Biggest risk | Data leak between platform clients at the database level | An error that renders correctly — nothing throws an exception, the only defense is a test |
| What the "Guardian" role checks | Data isolation, write contracts, idempotency, time types | Single source of truth for UI colors/text, API contract shape in one place, navigation |
| Limit of E2E test power | Integration tests run against a real database | End-to-end tests run against a backend mock — they prove the presentation layer's behavior, not compliance with the real API contract |
| Additional dependency type | — | Dependency on functionality from the other repository: an entry in the "what's missing on the other side" registry, with a required "reported" field and an actual ticket on the other side |
| Version management | — | Bumping the last segment of the version number, a changelog entry, checked automatically before tagging a release |

Key takeaway for anyone wanting to carry this pattern to a different stack: **roles and gates are
universal, checklists are domain-specific and must be written from scratch for each technical
environment.** The infrastructure repository demonstrates this most clearly: what gets carried over
from it is the process, not role definitions — because there simply are no roles there.

---

## 13. Underlying principles (operating philosophy)

A few sentences that function in this project as overarching principles, quoted for every role:

- **"Status is raised by evidence, not conviction."** No process step raises a task's status based
  on the performer's gut feeling — always based on a link to a specific test or artifact.
- **"Green tests are not task completion."** Task completion requires proof that the tests are not
  empty — and that proof is supplied by a different role than the one that wrote the code.
- **"A silent deviation from a decision lets the registry drift from reality."** Every change to a
  previously adopted design decision is an explicit, dated addendum — never a silent edit of the old
  entry.
- **"Manual upkeep is replaced by an assertion."** If something is supposed to always be true, it is
  checked by an automatic query or test — not by the author's discipline. In practice, this pattern
  has caught real defects that no prior review ever caught.
- **A classification read from more than one place lives in one register or one function, never in
  two independent lists.** An observed failure mode: a list of "protected categories" maintained
  separately in two places in the code silently drifted apart — one of them knew two of the other's
  five entries. Both lists passed their own tests, because no test ever compared them against each
  other. The answer is the same as the previous rule: one source that every consumer reads from,
  not N copies someone has to remember to keep in sync.
- **Documentation may run ahead of implementation — and this is deliberate, explicitly stated.** The
  project is deliberately documented further than it is implemented; an adopted architectural
  decision means only an accepted direction, not an existing capability of the system. The source of
  truth about what actually works is a separate, narrower registry of verified facts — not the
  conceptual documentation.

### The order in which this process was built

The process was not rolled out in one step — the rollout order is described as deliberate and
counter-intuitive, verified empirically:

1. **Read-only roles first** (e.g., the state-reporting role) — immediate payoff, zero risk, because
   they write nothing.
2. **Process in the tracking system** — ticket forms, labels, branch protection — before any agent
   started writing code.
3. **Calibration of evaluating roles** (section 6) — before anyone started trusting their reports.
4. **Producing roles plus a pilot of one task from start to finish** — the first week of work
   **did not once** go through a full product task from ticket to merge, even though the evaluating
   roles were already working correctly.
5. **Repeatability** — only after about ten tasks, measured by whether the number of human
   interventions **outside** the three formal gates starts to drop.
6. **Only then, expansion to the second product repository.**

The rule derived from this order, stated explicitly as universal: what gets carried between
repositories is the **process**, not the **rules**. Checklist content (e.g., specific data-isolation
rules) is domain-specific — carrying it over directly to a different context without rethinking it
would be, quoting the source documentation, "theater" instead of real control.

---

## 14. The cost of this approach — an honest accounting

The Framework is not free, and it's worth saying so directly, because that's part of what defines it:

- Every task passes through three human stops — each costs the human's time, which is why
  communication at each of them is maximally compressed and always carries a recommendation, never a
  bare list of questions.
- Mutation testing is an extra step on top of standard test writing — it requires deliberately
  removing a mechanism and interpreting the result, and cannot be fully automated without oversight.
  Role calibration (section 6) is the same cost moved up to the process level — every role definition
  change requires a fresh calibration run before the role returns to production work.
- The layer of rules protecting against shared-resource collisions (number reservations, queue
  splitting, uniqueness checks) exists solely because many agents work on the repository at once — in
  a project with a single performer it would be needless overhead.
- Gates without deadlines on exceptions mean technical debt cannot be silently swept aside — but this
  also means a regular, enforced obligation to pay it down or deliberately extend it with a rationale.
- Not every repository gets the full version of the process — the infrastructure repository
  deliberately forgoes its own roles and a hard merge gate, because the cost of maintaining the full
  set there would be disproportionate to the scale of work. This too is part of the honest accounting:
  the process scales its own cost down where risk and frequency of work don't justify it.

In return, the project gets something a standard "code plus review" process does not guarantee:
**proof that the proof of task completion is not empty**, and clearly assigned responsibility for
every decision that could not be automated.
