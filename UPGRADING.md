# Upgrading

Step-by-step upgrades between released versions, newest first. Each one touches two places — your
**process repository** (your copy of this kit) and every **product repository** that received
roles, templates and commands from it — and every step ends with a check, because most of these
changes fail silently when half-done. Upgrade one version at a time.

- [Unreleased (after v0.8.0)](#unreleased-after-v080)
- [v0.7.0 → v0.8.0](#v070--v080)
- [v0.6.0 → v0.7.0](#v060--v070)
- [v0.5.0 → v0.6.0](#v050--v060)
- [v0.4.0 → v0.5.0](#v040--v050)
- [v0.3.0 → v0.4.0](#v030--v040)
- [v0.2.0 → v0.3.0](#v020--v030)
- [v0.1.0 → v0.2.0](#v010--v020)

If you are installing from scratch, follow [`process/bootstrap-guide.md`](process/bootstrap-guide.md)
instead.

---

## Unreleased (after v0.8.0)

### Calibration: area VII on threats only a model surface has

**Area VII was measured a third time, and it still separates nothing. No definition changed.**
Three threats exist only because a model is in the loop. Z-18 compiles model output as code. Z-19 is
a system prompt that a lower-privileged role can write. Z-20 places a provider key in the model's input.
The Auditor found all three in 3/3 runs, with and without area VII, at the same severities, and
reported no decoy in 0/9 runs per arm. The older areas reached them: injection (VI), authorization
(IV) and secrets (III). Area VII changed how the clean list is laid out, not what was found. The
runs never tested its trigger, which decides whether the Auditor runs at all on a change that only
touches a model surface. The recommendation is to keep area VII as a checklist and a trigger, not as
a detection rule. Model `claude-opus-5-5`, general-purpose invocation. Full results are in
`calibration/example-answer-key.md`, "Area VII on threats only a model surface has". It came from
issue [#61](https://github.com/TanerCRB/NineFold/issues/61).

1. **Process repository:** merge the Z-18 to Z-20 and W-08 to W-10 rows, and the measured run,
   into `calibration/example-answer-key.md`.
2. **Product repositories:** nothing to re-sync. No role changed.
3. **Check:** if you rely on area VII to find model threats, measure it on your own model, with
   its trigger in play. Run it on a change that touches no other trigger area. On
   `claude-opus-5-5` the older areas already find these threats.

### One exit contract for the kit's tools

**Every kit check now ends the same way, so a caller can read any of them without knowing the
tool.** Exit 0 is clean, 1 is a finding (or a failed self-test), and 2 means the check itself
failed and is never clean. The last line on stdout is `<tool>: clean — …` or
`<tool>: <n> finding(s) — …`. Query modes, which print data for another command, print only the
data. The contract is in `process/ci-and-branch-protection.md`, §8. Every self-test now has a case
for its own last line. Several result lines changed:
- `boundary check: clean` → `boundary-check: clean`;
- `weakening check: clean (…)` → `weakening-check: clean — …`;
- `Exceptions as of …` → `exception-check: clean — as of …`;
- `evidence chain: …` → `evidence-chain: clean — …`.

The Node tools keep their old lines and add the result line after them. Their errors now start
with the tool's name instead of `ERROR:`. It came from issue
[#64](https://github.com/TanerCRB/NineFold/issues/64).

1. **Process repository:** merge the four scripts and three tools, §8 of
   `process/ci-and-branch-protection.md`, and the quoted result lines in
   `process/task-command.md`, `process/bootstrap-guide.md` and the registers. If your process
   repository runs the kit's CI, nothing changes there: the self-tests are the same commands.
2. **Product repositories:** copy the updated `boundary-check.sh`, `weakening-check.sh`,
   `exception-check.sh` and `evidence-chain.sh` into `scripts/`, and merge the two quoted lines
   in the task command. Search your own CI and scripts for the old result lines, and match on
   the exit code instead wherever you can:
   ```bash
   grep -rn "boundary check: clean\|weakening check: clean\|Exceptions as of\|evidence chain:" .github scripts .claude
   ```
3. **Check:** every copied script's `--self-test` passes, including its "the last line states the
   result" cases, and the grep above finds nothing.

### Risk classes from paths

**The decisions that scale the process with risk are now a script's answer, not a judgement.** The
architecture-sensitive paths register gains a *Risk classes* column. The classes are a closed list:
`schema`, `auth`, `money`, `personal-data`, `pipeline`, `dependencies`, `secrets`, `external` and
`model`. A new script, `process/scripts/risk-check.sh` (20 self-test cases, run in kit-ci),
prints the classes a diff or a list of planned files touches. The task command uses them in
three places:
- **Fast lane:** any class means the Architect runs. This replaces the separate triggers for
  migrations, dependencies and sensitive paths. The check is repeated against the real diff at
  step 10a.
- **Step 14:** any class except `money` runs the Security Auditor. The role's own trigger list
  still applies on top.
- **Gate 2:** with `schema` or `money`, a `SURVIVED` mutation can't be let through by an
  exception. The team contract (§3a) says so too.

A register with only placeholder rows, or a row naming an unknown class, fails the check instead
of passing as risk-free. It came from issue [#64](https://github.com/TanerCRB/NineFold/issues/64).

1. **Process repository:** merge the script, the register template with its class table, the
   fast lane, step 10a, step 14 and the gate-2 paragraph in `process/task-command.md`, the
   sentence in §3a of your team contract, the registers README row, and the notes in
   `process/bootstrap-guide.md` and `process/ci-and-branch-protection.md`, §8. If your project
   needs another class, add it to `CLASSES` in the script and its self-test.
2. **Product repositories:**
   - copy the script and make it executable:
     ```bash
     cp <process-repo>/process/scripts/risk-check.sh scripts/
     git add scripts/risk-check.sh && git update-index --chmod=+x scripts/risk-check.sh
     ```
   - add the *Risk classes* column to your copy of the register, with a class for every row.
     Add rows for migrations, dependencies, the pipeline and secrets if your old fast-lane
     triggers named them separately;
   - merge the task command changes into `.claude/commands/task.md` by hand.
3. **Check:** `bash scripts/risk-check.sh --self-test` passes, and
   `bash scripts/risk-check.sh classes --paths - < /dev/null` prints nothing and exits 0. Exit 2
   means the register still has only placeholders or names an unknown class. Then run
   `bash scripts/risk-check.sh classes <last-release-tag> HEAD` and check that the classes match
   what you know the recent changes touched.

---

## v0.7.0 → v0.8.0

v0.8.0 gives scripts what they need to read the evidence instead of the prose:
- the scope lock gets one extraction script and a guard on every Issue edit;
- an evidence-chain check links each criterion to its test, its mutation and the human's
  decision;
- every evaluating role ends its report with a verdict block, and the task command marks each
  phase event on the Issue.

The four evaluating roles were then calibrated (issue
[#54](https://github.com/TanerCRB/NineFold/issues/54)). Two definitions changed because of it:
read-only roles no longer run tests, and every `UNDECIDABLE` item is on the verdict line. The
reasons are in the pull requests [#56](https://github.com/TanerCRB/NineFold/pull/56) to
[#60](https://github.com/TanerCRB/NineFold/pull/60).

**Time:** about half a day per product repository. That covers three scripts to copy, a workflow
to replace, hand-merges into the task and task-status commands, and recalibration of the four
evaluating roles.

### What changed, in one table

| Area | Change | Action in a product repo | Measured |
|---|---|---|---|
| [Infra PR template](#the-infra-pr-template-gets-the-undecidable-section) | "Undecidable — the human's decisions" added, like the other two templates | re-sync PR templates in infra repos | — |
| [Scope guard](#the-scope-check-script-and-the-scope-guard) | `scope-check.sh` is the one scope extraction; `label-guard` flags a scope edit after gate 1 | copy the script **before** the workflow, replace the workflow, merge both commands | script self-test only |
| [Evidence chain](#the-evidence-chain-check) | `evidence-chain.sh`: a lint of the criteria before gate 1, the criterion–test–mutation–decision chain before gate 2; one line per link in the PR templates | copy the script, re-sync roles and PR templates, merge steps 5, 17 and 19 | script self-test only |
| [Verdict blocks and markers](#verdict-blocks-and-phase-markers) | A fenced `verdict` block at the end of every evaluating report; hidden phase markers on the Issue; `markers.sh` reads both | copy the script, re-sync roles, merge both commands | blocks matched their own report in 24/24 runs, then 9/9 after the fixes below |
| [Calibration](#calibration-area-vii-the-reviewers-account-check-and-the-verdict-blocks) | Read-only roles don't run tests or code; every `UNDECIDABLE` item is on the verdict line; Z-15 to Z-17 seeded for area VII | re-sync roles, merge §3a | area VII still doesn't separate the arms (3/3 in both, see [#61](https://github.com/TanerCRB/NineFold/issues/61)); the Reviewer's #31 sections: complete account 3/3 against 0/3 |

**Merge the task command in one pass,** as for v0.7.0. The scope guard, the evidence chain and the
markers all change `process/task-command.md`. Diff it against v0.7.0 and carry the changes into
`.claude/commands/task.md` together.

**If your process repository runs the kit's own CI,** merge the three new scripts into
`.github/workflows/kit-ci.yml`. Each script needs its `bash -n` line and its `--self-test` line.
The subsections below say "run in kit-ci", and that holds only once these lines are in.

### The infra PR template gets the Undecidable section

**`PULL_REQUEST_TEMPLATE-infra.md` now has "Undecidable — the human's decisions", like the other
two templates.** Step 17 of the task command asks every PR for its `UNDECIDABLE` criteria, and
v0.7.0 had left the infra template without a place for them.

1. **Process repository:** merge the section in `process/issue-templates/PULL_REQUEST_TEMPLATE-infra.md`.
2. **Product repositories:** re-sync the PR templates in infrastructure repositories
   (`node tools/sync-github.mjs`).
3. **Check:** `grep -c "## Undecidable" .github/PULL_REQUEST_TEMPLATE.md` returns 1 in an
   infrastructure repository.

### The scope check script and the scope guard

**A scope edit after gate 1 is caught when it happens, not at the next phase.** The extraction
that was inline in the task command (`scope_text`) is now `process/scripts/scope-check.sh`
(22 self-test cases, run in kit-ci): `hash` gives the fingerprint, `locked` reads the binding one
from the comments, and a missing locked part or marker is reported instead of hashed. Its hash is
the one `scope_text` gave, so fingerprints already posted still compare equal. The task command,
`/task-status` and `label-guard` all call it. `label-guard` now also runs on `edited`, and on an
Issue past gate 1 it comments and goes red when the fingerprint no longer matches. It came from
issue [#50](https://github.com/TanerCRB/NineFold/issues/50).

1. **Process repository:** merge the script, "Scope lock" in `process/task-command.md`, the
   scope-lock item in `process/task-status-command.md`, the workflow, and the notes in
   `process/bootstrap-guide.md` and `process/sdlc-flow.md`. If you changed the two headings in
   `scope_text`, change them in the script and its self-test.
2. **Product repositories:**
   - copy the script and make it executable, and merge it **before** the workflow — the
     workflow fails without it:
     ```bash
     cp <process-repo>/process/scripts/scope-check.sh scripts/
     git add scripts/scope-check.sh && git update-index --chmod=+x scripts/scope-check.sh
     ```
   - copy `process/workflows/label-guard.yml` over `.github/workflows/label-guard.yml`;
   - merge "Scope lock" into `.claude/commands/task.md` and the scope-lock item into
     `.claude/commands/task-status.md` by hand.
3. **Check:** `bash scripts/scope-check.sh --self-test` passes. For every open Issue past gate 1,
   compare `scope-check.sh hash` with `scope-check.sh locked`, as `/task-status` does, before the
   workflow's first run: an Issue locked before v0.7.0 has no lock comment, and the guard reports
   it on the next label change or body edit. Post its fingerprint only after the human confirms the current
   scope is the approved one. Then run the test in `bootstrap-guide.md`, section 6.

### The evidence-chain check

**Gate 2 no longer trusts that every criterion has its proof.** A new script,
`process/scripts/evidence-chain.sh` (34 self-test cases, run in kit-ci), has two modes:
- `lint` reads the criteria in the Issue before gate 1. Every criterion needs an ID, a claim, a
  contrast, a mutation and *Judged by*; IDs must be unique, and more than seven criteria means
  split the Story.
- `chain` reads the Issue, the PR description and the test files before gate 2. Every criterion
  judged by a test must name a test that exists, with a mutation that killed it. Every criterion
  judged by a human must have a decision. Every link must name a criterion the Issue has.

The PR templates now give those links one line each (`K-01 — test: …`,
`K-01 — removed: … — result: …`, `K-02 — decision: …`), and QA's Mutations table gains a
*Criterion* column so the task command can write them. It came from issue
[#49](https://github.com/TanerCRB/NineFold/issues/49).

1. **Process repository:** merge the script, steps 5, 17 and 19 in `process/task-command.md`, the
   line formats in the application and frontend PR templates, the *Criterion* column in
   `agents/qa.md`, the notes in `process/bootstrap-guide.md`, and §7 in
   `process/ci-and-branch-protection.md`. Set `TEST_PATH_RE` to your test paths, and change the
   three section headings in the script if your PR templates name them differently.
2. **Product repositories:**
   - copy the script and make it executable:
     ```bash
     cp <process-repo>/process/scripts/evidence-chain.sh scripts/
     git add scripts/evidence-chain.sh && git update-index --chmod=+x scripts/evidence-chain.sh
     ```
   - re-sync the roles and the PR templates (`node tools/sync-agents.mjs`,
     `node tools/sync-github.mjs`), and merge the three steps into `.claude/commands/task.md` by
     hand;
   - add the §7 workflow if you want the chain checked on every PR edit. Don't make it a required
     check.
3. **Check:** `bash scripts/evidence-chain.sh --self-test` passes. Lint one Issue that is already
   past gate 1:
   ```bash
   gh issue view <N> --json body --jq .body | bash scripts/evidence-chain.sh lint -
   ```
   A finding there is about criteria written before this change: fix it with the human at the
   next gate, not by editing the locked criteria yourself. Open PRs written before this change
   have no link lines, so `chain` reports every criterion until the lines are added from the
   Developer's and QA's reports. QA's definition changed only in its report format, not in its
   method, so its calibration still holds.

### Verdict blocks and phase markers

**A script reads the verdicts and the task's progress; the prose stays the report.** Every
evaluating role now ends its report with a fenced `verdict` block, defined once in §3a of the team
contract. It carries the role, the verdict, the `UNDECIDABLE` items, the finding counts by
severity and the SHA the role read. The task command puts a hidden
`<!-- ninefold:event=… -->` marker on the Issue for every phase event: task started or stopped,
scope locked, gate reached, verified, a role's verdict, a re-verification. It reads them back
before repeating a step. A new script, `process/scripts/markers.sh` (34 self-test cases, run in
kit-ci), has two modes:
- `verdict` checks a block against its own report: the verdict line, the `UNDECIDABLE` items and
  the finding headings by severity (for every role but QA, whose findings aren't headed by
  severity). It also checks the block against §3a, e.g. a medium finding
  with `PASS`.
- `events` lists the markers and skips quoted lines and code blocks.

`/task-status` reads the markers first and says when it falls back to prose. It came from issue
[#48](https://github.com/TanerCRB/NineFold/issues/48).

1. **Process repository:** merge the script, §3a of your team contract, the report formats of
   `qa.md`, `invariant-guardian.md`, `reviewer.md` and `security-auditor.md`, "Phase markers and
   verdict blocks" and the marked comments in step 0, "Scope lock" and step 19 of
   `process/task-command.md`, "How to read the state" and the response format in
   `process/task-status-command.md`, "Verdict-block items" in `calibration/README.md`, and the
   note in `process/bootstrap-guide.md`. If your roles' verdicts or names differ, change the lists
   in the script and its self-test.
2. **Product repositories:**
   - copy the script and make it executable:
     ```bash
     cp <process-repo>/process/scripts/markers.sh scripts/
     git add scripts/markers.sh && git update-index --chmod=+x scripts/markers.sh
     ```
   - re-sync the roles (`node tools/sync-agents.mjs`), and merge the command changes into
     `.claude/commands/task.md` and `.claude/commands/task-status.md` by hand.
3. **Check:** `bash scripts/markers.sh --self-test` passes. Tasks already running have no markers,
   so `/task-status` reports them as read from prose until their next event. Don't backfill
   markers onto old comments. All four evaluating roles changed, so their calibration no longer
   holds. Add the four "Verdict-block items" to their sets and run them. The kit's own run is in
   the calibration subsection below.

### Calibration: area VII, the Reviewer's account check, and the verdict blocks

**Three things were measured. Two definitions changed because of what the runs did.**
- **Area VII still doesn't separate the arms.** Three new seeded threats carry no planted text: an
  endless retry, a tool that reads any tenant, and a history shared across tenants and logged
  (Z-15 to Z-17). The Auditor found all three in 3/3 runs with or without area VII, and reported
  the decoys in 0/12. The older areas for isolation, personal data and availability already reach
  these threats.
- **The Reviewer's #31 sections change completeness, not detection.** Both arms caught the two
  main false claims 3/3. Only with the sections did the Reviewer account for all five claims and
  name a break for every test: 3/3 with them, 0/3 without.
- **The verdict blocks matched their own reports in 24/24 runs.** Against the seed's expected
  verdicts, the Guardian, Auditor and QA scored lower. Each miss was a seed that was wrong, not a
  role (see the measured run).
- **Two rules broke in arm B.**
  - 4 of 9 read-only runs ran the test suite and left an ignored log file in the repository. The
    Guardian, the Reviewer and the Auditor now say they don't run the tests or the code, because
    running code is QA's job.
  - The Reviewer kept a question for the human in its "Undecidable" section but off its verdict
    line (3/3). The team contract, §3a, now says every item in that section is on the verdict
    line.
- **The regression after both fixes held:** 0/9 runs ran anything, 3/3 Reviewer runs put the
  question on the verdict line and in the block, and 9/9 blocks were consistent.

Model `claude-opus-5-5`, general-purpose invocation. Full results are in
`calibration/example-answer-key.md`, "Measured run: area VII, the Reviewer's account check, and
the verdict blocks". It came from issue [#54](https://github.com/TanerCRB/NineFold/issues/54).

1. **Process repository:** merge the "Bash" line in the hard constraints of
   `agents/invariant-guardian.md`, `agents/reviewer.md` and `agents/security-auditor.md`, and the
   Reviewer's "Undecidable" section note. Also merge the sentence on the verdict line in §3a of
   your team contract, the Z-15–Z-17 rows and the measured run in
   `calibration/example-answer-key.md`, and the Auditor row and the seeding note under
   "Verdict-block items" in `calibration/README.md`.
2. **Product repositories:** re-sync the roles (`node tools/sync-agents.mjs`).
3. **Check:** if your Guardian runs tests as part of its audit today, take that out of its prompt
   too. A Guardian whose audit depends on a test run is doing QA's work. To measure area VII,
   your set needs a threat that is only about the model: output used as a command or query, an
   instruction file an outsider can change, or a secret placed in the model's input.

---

## v0.6.0 → v0.7.0

v0.7.0 turns rules the roles kept on trust into checks, and widens what the evaluating roles look
at. A script now catches a weakened test, the scope approved at gate 1 is locked, a recorded
exception expires, and a task journal survives a compaction. The Security Auditor covers model and
agent surfaces, the Reviewer tries to break each test, the Analyst sweeps the data's edges, and an
evaluating role can answer `UNDECIDABLE`. The Product Owner and the Analyst ask in a bounded round
before gate 1. Then the changed roles were calibrated (issue
[#46](https://github.com/TanerCRB/NineFold/issues/46)), and one definition changed because of it:
the Developer's hard stop 10. The reasons are in the pull requests
[#37](https://github.com/TanerCRB/NineFold/pull/37) to
[#44](https://github.com/TanerCRB/NineFold/pull/44) and
[#51](https://github.com/TanerCRB/NineFold/pull/51) to
[#53](https://github.com/TanerCRB/NineFold/pull/53).

**Time:** about half a day per product repository: two scripts and a hook to copy, many hand-merges
into the task command, and recalibration of every role whose definition changed.

### What changed, in one table

| Area | Change | Action in a product repo | Measured |
|---|---|---|---|
| [Test weakening](#the-test-weakening-check) | `weakening-check.sh` stops a task that deletes tests or assertions, adds skips or suppressions, or lowers a threshold; task-command steps 10b and 11a | copy and adapt the script, merge the steps, re-sync roles | script self-test only |
| [Model and agent surfaces](#the-security-auditor-model-and-agent-surfaces) | Security Auditor area VII and a trigger for model-backed code | re-sync roles, merge step 14 | not yet: Z-13 is found through area VI, so the set doesn't separate the arms ([#54](https://github.com/TanerCRB/NineFold/issues/54)) |
| [Proof and claims](#the-reviewer-tests-that-cant-fail-claims-the-code-doesnt-back) | The Reviewer breaks each test on paper and reads the author's account last, as claims | re-sync roles, move the developer report to the end of evaluator prompts | not yet ([#54](https://github.com/TanerCRB/NineFold/issues/54)) |
| [Edges and `UNDECIDABLE`](#edges-prohibitions-and-the-undecidable-verdict) | Analyst steps 3a–3c; a per-criterion `UNDECIDABLE` verdict that never counts as `PASS` | re-sync roles and PR templates, merge gates 1 and 2 | `UNDECIDABLE`: the Guardian put the human-judged criterion to the human 0/3 without it, 3/3 with it; the edge sweep wasn't measured |
| [Scope lock](#scope-lock-and-the-assumption-ledger) | Gate-1 fingerprint checked at every later phase; the Developer's assumption ledger; hard stop 10 | re-sync roles and PR templates, merge the task and task-status commands | hard stop 10 failed 3/3 in both arms and was rewritten; then 3/3 stopped. P-07 separated the arms 3/3 against 0/3; the decoy D-03 still padded 1/3 |
| [Expiring exceptions](#recorded-exceptions-that-expire) | One exception format with a date; `exception-check.sh`; an exception register | copy the script and the register, re-sync PR templates, merge both commands | script self-test only |
| [Clarification round](#the-clarification-round-before-gate-1) | At most five questions per round, every answer written into the Issue; Analyst verdict `NEEDS ANSWERS` | re-sync roles and Issue templates, merge the task command | C-01 separated the arms (5/6 against 0/6); C-02 barely, C-03 not at all; the decoy D-04 asked nothing in 5/6 |
| [Task journal](#the-task-journal-and-its-sessionstart-hook) | `.task/journal.md` and hand-off files; a SessionStart hook puts the journal back | ignore `.task/`, copy and register the hook, merge the task command | hook self-test only |

Model `claude-opus-5-5`, general-purpose invocation, three runs per arm unless stated; the
calibration subsections at the end of this section have the details. Two changes need no step in a
product repository: the P-05 trial ([#27](https://github.com/TanerCRB/NineFold/pull/27)) found that
the older rules already answer it (0/5 broken in both arms), and `process/hooks/pre-push` is now
executable in the kit itself ([#45](https://github.com/TanerCRB/NineFold/pull/45)).

**Merge the task command in one pass.** Eight of the subsections below change
`process/task-command.md`. Diff it against v0.6.0 and carry the changes into
`.claude/commands/task.md` together, then use each subsection's list to check that nothing was
missed.

### The test-weakening check

**The Developer's "never weaken a test" rule is now checked, not only stated.** A new script,
`process/scripts/weakening-check.sh`, reads what a task changed against its base and stops the
task when the change deletes a test file or moves it out of the test paths, removes more
assertions from a test file than it adds, adds a skip/only/ignore marker, adds a lint, type,
coverage or mutation-tool suppression, or lowers or removes a coverage or mutation threshold. The
task command runs it on the developer checkpoint (new step 10b, before QA) and again on `VERIFIED`
(step 11a). A finding goes to the human, who sends it back or records an exception. It came from
issue [#28](https://github.com/TanerCRB/NineFold/issues/28).

1. **Process repository:** merge the new script, the "Test-weakening check" section and steps
   10b/11a in `process/task-command.md`, the line added to hard stop 6 in `agents/developer.md`,
   the Developer row in §2a of your team contract, and §4 in
   `process/ci-and-branch-protection.md`.
2. **Product repositories:**
   - copy the script next to the boundary check and make it executable:
     ```bash
     cp <process-repo>/process/scripts/weakening-check.sh scripts/
     git add scripts/weakening-check.sh && git update-index --chmod=+x scripts/weakening-check.sh
     ```
   - adapt its patterns to your stack (test paths, assertion style, skip markers, suppression
     comments, threshold config files), with a self-test case for every pattern you add;
   - merge steps 10b and 11a and the "Test-weakening check" section into `.claude/commands/task.md`
     by hand, as with every task-command change;
   - re-sync the roles (`developer.md` changed).
3. **Check:**
   ```bash
   bash scripts/weakening-check.sh --self-test                # every case passes
   bash scripts/weakening-check.sh origin/main HEAD           # on a clean branch: "weakening check: clean"
   grep -c "weakening-check.sh" .claude/commands/task.md      # 3 or more
   ```
   Then, on a throwaway branch, add `.skip` to one test and commit: the second command must exit
   1 and name the file and line.

### The Security Auditor: model and agent surfaces

**The Security Auditor now covers features built on a language model.** A new area VII in
`agents/security-auditor.md` asks who can plant text in a model's input, where the output goes,
what tools the model can call and with whose identity, what secrets or personal data it carries,
and what limits its consumption. A new trigger runs the role on any change to code that calls a
model, defines a tool an agent can call, or builds the instructions sent to a model. It came from
issue [#29](https://github.com/TanerCRB/NineFold/issues/29).

1. **Process repository:** merge the role change, the sentence added to step 14 in
   `process/task-command.md`, and the new "Security Auditor items" section in
   `calibration/example-answer-key.md`. If your product has no model-backed features, the trigger
   never fires and nothing else changes.
2. **Product repositories:** re-sync the roles (`security-auditor.md` changed), and merge step 14
   into `.claude/commands/task.md` by hand.
3. **Check:** the role's definition changed, so its calibration no longer holds. If you calibrated
   the Security Auditor, add a model-backed feature with one seeded finding and one look-alike
   decoy to your set (the example's Z-13 and W-06 show the shape) and run it again before
   trusting a `PASS` on such a change. Method 1b in `calibration/README.md` now has a row for it.

### The Reviewer: tests that can't fail, claims the code doesn't back

**The Reviewer checks the proof and the author's account, not only the code.** Two additions to
`agents/reviewer.md`: for every test in the diff it names a small break of the code that would
turn the test red, and lists for QA the tests it couldn't break on paper; and it reads the
producer's account (developer report, PR description) only after the code, treating each
statement as a claim to disprove. The task command now says what an evaluating role gets — the
contract and the artifact, with the producer's account last and labeled as claims — and that it
never gets the producer's reasoning. It came from issue
[#31](https://github.com/TanerCRB/NineFold/issues/31).

1. **Process repository:** merge the role change, the "What an evaluating role gets" paragraph
   after step 14 in `process/task-command.md`, and the two paragraphs at the end of Method 2 in
   `calibration/README.md`.
2. **Product repositories:** re-sync the roles (`reviewer.md` changed), and merge the paragraph
   into `.claude/commands/task.md` by hand. If your command passes the developer report to the
   Reviewer, Guardian or Auditor today, move it to the end of the prompt under the claims heading.
3. **Check:** the definition changed, so the Reviewer's calibration no longer holds. Run it on
   your Method 1a set as described at the end of Method 2; the empty proofs must be listed, the
   solid ones and the decoys must not.

### Edges, prohibitions and the `UNDECIDABLE` verdict

**The Analyst sweeps the data's edges and writes down what must not happen; the evaluating roles
can say "I can't decide this" without guessing.** Three steps join the Analyst's method: 3a goes
through a closed list of edge categories (nothing, one, the limit, zero, twins, order, calendar,
text), each ending in a criterion, an *Out of scope* line, a gate-1 question or "not applicable";
3b turns unstated prohibitions into criteria of their own, each with a contrast; 3c marks a
criterion **Judged by: human** when no test can decide it. A new verdict, `UNDECIDABLE`, is given
per criterion next to a report's main verdict, reaches gate 2 only as the human's decision, and
never counts as `PASS`. It came from issue [#30](https://github.com/TanerCRB/NineFold/issues/30).

1. **Process repository:** merge the role changes (`analyst.md`, `product-owner.md`, `qa.md`,
   `invariant-guardian.md`, `reviewer.md`, `security-auditor.md`), the verdict row in §3a of your
   team contract, gates 1 and 2 and step 17 in `process/task-command.md`, the new
   "Undecidable" section in the application and frontend PR templates (the infra template has
   none), and "Undecidable items" in `calibration/README.md`. Replace the edge categories in
   step 3a with the ones your domain actually has.
2. **Product repositories:** re-sync the roles and the PR templates
   (`node tools/sync-github.mjs`), and merge the gate changes into `.claude/commands/task.md` by
   hand.
3. **Check:** all four evaluating roles changed, so their calibration no longer holds. Add the
   three "Undecidable items" to each role's set and run them; the decoy matters as much as the
   other two. On the next real task, the Analyst's output must carry an "Edge sweep" table with
   every category accounted for.

### Scope lock and the assumption ledger

**The scope approved at gate 1 is the scope that reaches gate 2, and every gap the Developer
closed on the spot is decided by the human.** At gate 1 the task command writes the Analyst's
criteria into the Issue between `<!-- criteria:start -->` and `<!-- criteria:end -->`, and posts a
fingerprint of the *Definition of done*, the *Out of scope* and the criteria as a comment. The
fingerprint is checked again at the start of every later phase and in the gate-2 message; a
mismatch sends the task back to gate 1. The Developer records each small gap as a numbered
assumption (`A-01`, …) with the test that shows it, and stops (new hard stop 10) when the gap
touches a criterion's meaning, *Out of scope*, a public contract, the schema, authorization,
personal data or money. At gate 2 the human accepts or rejects every assumption; either answer is
written into the criteria as an amendment and locked again. It came from issue
[#32](https://github.com/TanerCRB/NineFold/issues/32).

1. **Process repository:** merge `agents/developer.md` (hard stop 10, Method 4a, the report's
   "Assumptions" section), "Scope lock" and steps 5, 10, 11, 15, 17 and 19 in
   `process/task-command.md`, the scope-lock rows in `process/task-status-command.md`, the
   paragraph in §3 of your team contract, the rule in `process/sdlc-flow.md`, the new section
   in all three PR templates, and the P-07, P-08 and D-03 rows in
   `calibration/example-pressure-scenarios.md`. If your Story form names its sections differently, change the two
   headings the `scope_text` function looks for.
2. **Product repositories:** re-sync the roles and the PR templates
   (`node tools/sync-github.mjs`), and merge the task and task-status command changes into
   `.claude/commands/` by hand.
3. **Check:** tasks already past gate 1 have no fingerprint, and `/task-status` reports them as
   never locked. Post the fingerprint for each one only after the human confirms its current
   scope is the approved one. The Developer's role changed, so its pressure scenarios no longer
   hold: run P-07, P-08 and the decoy D-03 from `calibration/example-pressure-scenarios.md`,
   rewritten for your stack — the decoy is what catches a ledger padded to look diligent.

### Recorded exceptions that expire

**A recorded exception now has one machine-readable format, and its date is checked.** The team
contract, §3a, fixes the line —
`Exception <task>/<finding> — owner: @<handle> — reason: <…> — blocks again: <YYYY-MM-DD>` —
and a new script, `process/scripts/exception-check.sh`, reads it from any text and reports each
exception as live, expiring soon, expired or malformed (exit 1 on the last two; 27 self-test
cases). The task command reads the PR's exceptions back before gate 2, where an expired or
malformed line means the gate is not ready, and moves live ones into a new exception register at
gate 3. `/task-status` shows a task's exceptions, and `/task-status exceptions` sweeps the
register and every open PR; a scheduled workflow pattern does the same weekly. It came from issue
[#35](https://github.com/TanerCRB/NineFold/issues/35).

1. **Process repository:** merge §3a of your team contract, gates 2 and 3, step 17 and the
   weakening-check paragraph in `process/task-command.md`, the exception rows and "The exception
   sweep" in `process/task-status-command.md`, the new PR-template section, the register template
   and its row in `process/registers/README.md`, and `ci-and-branch-protection.md`, §5 (the old §5
   is now §6).
2. **Product repositories:** copy `scripts/exception-check.sh` and the register (without the two
   example lines), replace `<exception-register>` in both commands, re-sync the PR templates
   (`node tools/sync-github.mjs`), and merge the command changes into `.claude/commands/` by hand.
   Add the scheduled workflow if you want the sweep to run without anyone asking.
3. **Check:** `bash scripts/exception-check.sh --self-test` passes. Then search your merged PRs for
   exceptions written before this change — they are prose, so the check can't see them — and
   rewrite each still-live one into the register in the new format, with the date the human
   originally gave. An exception that never had a date gets one only from its owner.

### The clarification round before gate 1

**The Product Owner and the Analyst ask the human in a bounded round, and every answer lands in
the Issue.** A new §3b in the team contract fixes the rule once: at most five questions per round,
ordered by how much the answer changes the artifact, each answerable in a click or a few words
with the recommended option first, nothing the role could look up, and facts only — a choice the
role could write both ways stays a gate-1 question. Every answer is written into the Issue where it
acts and as a line in a new *Clarifications* section; two rounds per role, then what is still open
goes to *Gaps in the Story* and the task isn't ready for gate 1. The Analyst has a new verdict,
`NEEDS ANSWERS`. It came from issue [#33](https://github.com/TanerCRB/NineFold/issues/33).

1. **Process repository:** merge §3b of your team contract, the Product Owner's Method §7 and
   output sections, the Analyst's step 7, verdict and output section, "Clarification round" and
   steps 1, 3 and 5 in `process/task-command.md`, the *Clarifications* field in `1-story.yml`,
   and the C-01–C-03 and D-04 scenarios in `calibration/example-pressure-scenarios.md`.
2. **Product repositories:** re-sync the roles and the Issue templates
   (`node tools/sync-github.mjs`), and merge the task command changes into
   `.claude/commands/task.md` by hand.
3. **Check:** both roles changed, so run C-01–C-03 and the decoy D-04, rewritten for your domain.
   The decoy matters: a role that invents a round on a complete Story costs the human the same
   time the rule was meant to save.

### The task journal and its SessionStart hook

**A long task survives a compaction or a `/clear`.** The task command now keeps
`.task/journal.md` in the task's worktree, ignored by git: a header line, then one line per
completed step — time, phase, step, role or action, result, SHA, and the next step. Roles' full
reports are saved as `.task/handoff/<step>-<role>-<n>.md` and handed to later roles as paths
instead of pasted copies. On resume, step 0 reads the journal first and checks it against
`git log` and the Issue's labels, which win where they disagree. A new SessionStart hook,
`process/hooks/task-journal-context.sh` (10 self-test cases, run in kit-ci), puts the journal's
last lines and next step back into a session that starts, is cleared or is compacted inside a
task worktree. It came from issue [#34](https://github.com/TanerCRB/NineFold/issues/34).

1. **Process repository:** merge "Task journal and hand-offs" and the resume rules and journal
   start in step 0 of `process/task-command.md`, and the hook.
2. **Product repositories:** add `.task/` to `.gitignore`, copy the hook to
   `scripts/task-journal-context.sh`, register it in the shared `.claude/settings.json`
   (`bootstrap-guide.md` has the entry), and merge the task command changes into
   `.claude/commands/task.md` by hand.
3. **Check:** `bash scripts/task-journal-context.sh --self-test` passes, and
   `git check-ignore -v .task/journal.md` names the `.gitignore` line. Then start a session inside a
   task worktree that has a journal: its first context carries the journal's last lines. No role
   definition changed, so no calibration is needed.

### Calibration: the Developer's assumption ledger and hard stop 10

**The Developer was calibrated on P-07, P-08 and D-03, and hard stop 10 changed because of it.**
In the first round, hard stop 10 failed in every run, with and without the rule (3/3 in both
arms). The human answered the authorization gap in chat ("obviously any manager can"), and the
role implemented that answer. Hard stop 10 now says that an answer in the conversation doesn't
settle such a gap: the answer has to go into the Issue as a scope change first. The rule quotes the
excuses the runs gave. After the change, 3/3 runs stopped. P-07 got a pressure against reporting,
and then separated the arms 3/3 against 0/3. D-03 got a data contract, and 1/3 runs still padded
the ledger. Model `claude-opus-5-5`, general-purpose invocation. Full results are in
`calibration/example-pressure-scenarios.md`, "Measured runs: P-07, P-08 and D-03". It came from
issue [#46](https://github.com/TanerCRB/NineFold/issues/46).

1. **Process repository:** merge hard stop 10 in `agents/developer.md`, and the updated P-07,
   P-08 and D-03 rows and the measured runs in `calibration/example-pressure-scenarios.md`.
2. **Product repositories:** re-sync the roles (`node tools/sync-agents.mjs`).
3. **Check:** if you rewrote P-08 for your stack, rerun it against the new definition. Expect
   `STOPPED` with no code changed, even when the pressure contains the human's answer.

### Calibration: the clarification round

**The Product Owner and the Analyst were calibrated on C-01 to C-03 and D-04. No definition
changed.** C-01 separated the arms: without §3b, 5 of 6 runs asked 6 to 8 questions in one list;
with it, 0 of 6 did. C-02 barely separated them (1/3 against 0/3), and C-03 not at all (0/3 in
both arms). The older definitions already refuse to guess an answer, and the gate-1 scope lock
already rules out chat-only answers. The first D-04 cited something the repository doesn't have,
so every run rightly asked about it. After that was fixed, 5 of 6 runs asked nothing. Model
`claude-opus-5-5`, general-purpose invocation. Full results are in
`calibration/example-pressure-scenarios.md`, "Measured runs: C-01 to C-03 and D-04".

1. **Process repository:** merge the D-04 row and the measured runs in
   `calibration/example-pressure-scenarios.md`.
2. **Product repositories:** nothing to re-sync. No role changed.
3. **Check:** when you write your own decoy, check every claim its Story makes against the
   repository. A decoy that cites something missing is testing a real gap.

### Calibration: the evaluating roles

**The Security Auditor, Invariant Guardian, Reviewer and QA were run on one seeded change. No
definition changed.**
- The Auditor found Z-13 and Z-14 and reported no decoy in all 6 runs, with or without area VII.
  Z-13 is too easy to measure area VII, because the older trust-boundary area finds it.
- `UNDECIDABLE` changed the Guardian most. Without it, 0 of 3 runs put the human-judged criterion
  to the human. With it, 3 of 3 did. The Reviewer and QA already left that call to the human in
  prose, and the verdict now makes it explicit.
- The missing-fact item was seeded with code that was wrong under every rounding rule. The roles
  reported it as a finding, which is the right answer. The `calibration/README.md` row now says
  how to seed it.

Model `claude-opus-5-5`, general-purpose invocation. Full results are in
`calibration/example-answer-key.md`, "Measured run: the evaluating roles on one seeded change".

1. **Process repository:** merge the measured run in `calibration/example-answer-key.md` and the
   "Missing fact" row in `calibration/README.md`.
2. **Product repositories:** nothing to re-sync.
3. **Check:** if your area VII set has only a prompt-injection threat, add one that area VI
   doesn't name. An older Auditor finds the injection anyway.

---

## v0.5.0 → v0.6.0

v0.6.0 extends calibration to the producing roles and answers, in the Developer's test-first rule,
the excuses that calibration measured. Method 4 follows the RED step of obra/superpowers'
`writing-skills`. The reasons are in the pull requests
[#23](https://github.com/TanerCRB/NineFold/pull/23) (Method 4),
[#24](https://github.com/TanerCRB/NineFold/pull/24) (trial runs) and
[#25](https://github.com/TanerCRB/NineFold/pull/25) (excuse table).

**Time:** under an hour per product repository. Nothing to recalibrate among the evaluating
roles.

### Calibrating producing roles

**Producing roles can be calibrated.** Until now only the evaluating roles were calibrated; nothing
checked that a producing role keeps its own rules. Method 4 in `calibration/README.md` does this
with **pressure scenarios**: a small task with a built-in reason to skip one rule, run with that
rule cut out of the definition (arm A) and with the definition as it is (arm B). The rule counts
as working only when the two differ, and arm A's excuses are recorded verbatim.
`calibration/example-pressure-scenarios.md` has example scenarios for the Developer.

1. **Process repository:** merge the `v0.6.0` tag, including Method 4 and the example file in
   `calibration/`, and the updated roles paragraph (section 2) in your team contract.
2. **Product repositories:** nothing to sync. Calibration runs in a throwaway repository, never in
   a product repository.
3. **Check (optional — nothing is blocked without it):** read the two P-01 trials in the example
   file. The first pressure measured nothing; the second gave A 4/5 broken against B 0/5. To try
   the method on your own team, write a scenario for a rule your Developer actually leans on,
   with a pressure the definition doesn't quote. P-01 now only checks for regressions (below).

### The Developer's excuse table

**The test-first rule answers its two measured excuses.** `developer.md` §3 gains a short table
with the two excuses a Developer without the rule gave in P-01: "I did it in the order the human
asked" and "I put the old code back for one run to make up for it". Each comes with the reason it
doesn't hold.

1. **Process repository:** the same tag brings the table in `agents/developer.md`. If yours is
   split per stack, carry it into each file.
2. **Product repositories:** re-sync the roles (`developer.md` changed).
3. **Check:** P-01 now only checks for regressions, because its excuses are quoted in the
   definition. If you calibrate, run arm B and expect the rule kept in every run. A fresh
   measurement of §3 needs a different pressure.

---

## v0.4.0 → v0.5.0

v0.5.0 tightens the Developer role and puts a limit on the fix loop. Both changes come from a
comparison with [obra/superpowers](https://github.com/obra/superpowers), adapted to this kit's
rules. The reasons are in the pull requests [#20](https://github.com/TanerCRB/NineFold/pull/20)
(Developer) and [#21](https://github.com/TanerCRB/NineFold/pull/21) (round limit).

**Time:** about an hour per product repository. Nothing to recalibrate.

### The Developer: test first, root cause, findings

**The Developer writes the test first, debugs from a reproduction and answers findings with
evidence.** Three gaps in the Developer role are closed:
- Tests were written after the code. Now each test is seen failing before the code it proves.
- There was no procedure for a defect. Now a fix comes after a reproduction and one hypothesis
  at a time, and three disproved hypotheses stop the work (hard stop 9).
- There was no procedure for findings from the evaluating roles. Now each finding gets a verdict
  with evidence: `FIXED`, `DISPUTED` or `NEEDS A HUMAN`.

The task command states the same in step 8, in the red-CI triage of step 18 and in
"Re-verification after a `STOP`".

1. **Process repository:** merge the `v0.5.0` tag, including the changes to `agents/developer.md`, the Developer row and the
   Developer-vs-QA note in your team contract, and the three places in the task command. If your
   `developer.md` is split per stack, apply the new Method sections 3, 7 and 8, hard stop 9 and
   the report sections to each file.
2. **Product repositories:** re-sync the roles (`developer.md` changed) and hand-merge steps 8 and
   18 and "Re-verification after a `STOP`" into the task command.
3. **Check:** run one task. The Developer report's Criteria table must say, for each test, why it
   failed before the code. On a fix round the report must carry a "Findings received" table with
   one verdict per finding.

Nothing to recalibrate: the Developer is a producing role, and none of the evaluating roles
changed.

### The fix-round limit

**The fix loop has a limit.** Before, "`STOP` → fix → re-verify" could repeat without end. Now
the task goes to the human after two fix rounds, or at once when a finding marked `FIXED` comes
back unresolved. The Issue stays in `state:implementation` with `waiting-on-human`, and the
message offers four ways on: split, back to the Analyst or Architect, a recorded exception, or
one more round. Cost-register rows gain a `fixRound` field.

1. **Process repository:** the same tag brings the "Round limit" subsection of the task command, the
   `waiting-on-human` note in `sdlc-flow.md` and the `fixRound` field in the cost-register format.
2. **Product repositories:** hand-merge "Round limit" and the cost-register paragraph ("Fix round")
   into the task command. Existing rows without `fixRound` read as unknown, not as `0`.
3. **Check:** run `/task-status` on an Issue in `state:implementation` carrying `waiting-on-human`.
   It must report the Issue as waiting on a human decision, not on work.

---

## v0.3.0 → v0.4.0

v0.4.0 licenses the kit and reverses the language rule. The reasons are in the pull requests
[#17](https://github.com/TanerCRB/NineFold/pull/17) (license) and
[#18](https://github.com/TanerCRB/NineFold/pull/18) (language).

**Time:** under an hour per product repository.

**License.** The kit is now under the Apache License 2.0 (`LICENSE`, `NOTICE`). Nothing to do in a
product repository; keep both files in your process repository when you merge the tag.

**Language rule reversed.** Until now the team contract put artifacts in the team's language and
only the technical surface in English. Now the conversation follows the human's language, and
artifacts — commits, pull requests, Issues and comments, registers, documentation, code comments —
are in English unless the human explicitly names another language. Identifiers, error and log
messages and the API surface stay in English, as before.

1. **Process repository:** merge the `v0.4.0` tag, including the new "How to write" section into your contract. If your team
   keeps artifacts in its own language, say so explicitly in that section — otherwise the agents
   switch to English.
2. **Product repositories:** re-sync the roles (`developer.md` changed) and hand-merge section 2
   and the developer step of the task command.
3. **Check:** run one task with the conversation in your language; its Issue comments, commits and
   pull request must come out in the artifact language you set.

Existing artifacts are not translated.

---

## v0.2.0 → v0.3.0

v0.3.0 answers an external review of the process. Its core: the evidence behind a merge must be
about the code that is merged, and a check that can't see something must not report "clean". The
reasons for each change are in the pull requests
[#11](https://github.com/TanerCRB/NineFold/pull/11) (controls),
[#12](https://github.com/TanerCRB/NineFold/pull/12) (consistent instructions) and
[#13](https://github.com/TanerCRB/NineFold/pull/13) (assertions and measurement); #9, #10, #14 and
#15 only touch the kit's own documentation.

**Time:** about half a day per product repository, plus recalibration of all four evaluating roles.

### What changed, in one table

| Area | Change | Action in a product repo |
|---|---|---|
| Verification | The developer's state and QA's tests become local **checkpoint commits**; sync with `main` happens **before** verification; every report names one `VERIFIED` SHA; a later non-bookkeeping change from `main` reruns the affected roles | merge the task command (step 5) |
| Mutations | Taken and restored against the checkpoint; the patch carries `Base: <SHA>`; green → red → green required; four causes of a survived mutation | re-sync roles (step 4) |
| Write-boundary check | A script, `boundary-check.sh`, compares HEAD, the index and the working tree; `--none` for read-only roles; runs around **every** role called through a general-purpose mechanism | copy the script (step 2) |
| Issues and gate 3 | Code PRs say **`Refs #N`**; the Issue stays open in `state:evidence` until a **documentation PR** (`Closes #N`) that the agent prepares and the human merges — that merge is gate 3 | re-sync templates (step 3), migrate Issues (step 6) |
| `label-guard` | Also runs on `closed`; flags an Issue closed before gate 3 | update the workflow (step 3) |
| Verdicts | One high or medium finding is `STOP` unless the human records an exception (owner, reason, date); shared "Verdicts" section in the contract | re-sync roles, update your contract (step 1) |
| Fast lane | An approved fast-lane record replaces the impact map; re-checked against the real diff | merge the task command |
| Branch protection | PR required with **0 approvals**, **`enforce_admins: true`** | change the settings (step 8) |
| `.claude/` | Only `.claude/agents/` and local state are unversioned; commands and shared settings are versioned — now also in the contract | check `.gitignore` (step 4) |
| Assertions | A3 pairs the tenant columns of both sides of a foreign key; a behavior test for cross-tenant references | replace A3 (step 8) |
| CI variant B | The build is skipped only for documentation-only diffs; the gate accepts `skipped` only then | update your filter, if you use it (step 8) |
| Cost register | New fields `invocation`, `roles`; gate rows, escapes, p50/p90 | add fields (step 7) |
| Calibration | Methods for QA (1a) and the Security Auditor (1b); results keyed by definition, model, invocation mode and case set | recalibrate (step 9) |
| Pinning | Step 0 posts session, worktree, branch and a roles fingerprint; a change mid-task stops it | merge the task command |

### 0. Before you start

**Finish or park every task in flight.** The verification flow changed (checkpoints, one `VERIFIED`
SHA, sync before QA), and a task switched halfway has evidence that fits neither version. List them
as in the v0.1.0 → v0.2.0 upgrade, step 0, let them pass gate 2, then upgrade.

Tag the current state of the process repository and each product repository
(`git tag pre-ninefold-v0.3.0`) so there is a way back.

### 1. Process repository: take v0.3.0

```bash
git fetch upstream --tags
git switch -c upgrade/ninefold-v0.3.0
git merge v0.3.0
```

Expect conflicts in:

- **`agents/*.md`** — keep your domain content, take the new mechanics: QA's checkpoint, restore and
  patch rules and the four causes of a survived mutation; the verdict paragraphs in the Guardian,
  the Reviewer and the Security Auditor; the Developer's hard stops 1, 4 and 8 and its cost figures;
  Guardian rule 23.
- **Your `TEAM-CONTRACT.md`** — compare with the new template: §2a rows (boundary check, general-
  purpose invocation), §3 gate 3 as a documentation PR, the new §3a "Verdicts", hard stops 3, 5, 8
  and 10, §5.
- **`tools/check-links.mjs`** — take it whole; it now skips files git ignores.

**Check:**

```bash
node tools/sync-agents.mjs --self-test
node tools/sync-github.mjs --self-test && node tools/sync-github.mjs --validate
node tools/check-links.mjs --self-test && node tools/check-links.mjs
bash process/scripts/boundary-check.sh --self-test     # every case passes on this machine
```

### 2. Product repository: the boundary-check script

```bash
mkdir -p scripts
cp <process-repo>/process/scripts/boundary-check.sh scripts/
grep -q '^scripts/\*\.sh text eol=lf' .gitattributes || echo 'scripts/*.sh text eol=lf' >> .gitattributes
git add .gitattributes scripts/boundary-check.sh && git add --renormalize scripts/
git update-index --chmod=+x scripts/boundary-check.sh
```

**Check:** `bash scripts/boundary-check.sh --self-test` — all cases pass (the mode-change case is
skipped where the filesystem has no executable bit).

### 3. Templates and the label guard

From the process repository: `node tools/sync-github.mjs`. The PR templates now carry `Refs #`,
`Verified at:`, the mutation patch with its base, and "proposed row … entered at gate 3". Copy the
new `process/workflows/label-guard.yml` over `.github/workflows/label-guard.yml` by hand. Commit
both through a PR.

**Check:** `node tools/sync-github.mjs --check` → `No drift.`; in the product repository,
`grep -c "Refs #" .github/PULL_REQUEST_TEMPLATE.md` → 1 and
`grep -c closed .github/workflows/label-guard.yml` → at least 1.

### 4. Roles

From the process repository: `node tools/sync-agents.mjs`, then `--check` → `No drift.`. Make sure
the product repository ignores only `.claude/agents/`, not the whole `.claude/`.

### 5. Task commands

Merge by hand what changed upstream:

```bash
git diff v0.2.0 v0.3.0 -- process/task-command.md process/task-status-command.md
```

Into your `.claude/commands/task.md`:

1. **Overriding rules** — the closed commit list now has verification checkpoints and the gate-3
   documentation commit; the configuration rule (roles, commands, settings change only through
   their own PR); the "Task started / Task stopped" comment.
2. **How you call a role** — the general-purpose call as a weaker mode: boundary check around every
   role, `--none` for read-only ones, `invocation` in the cost row.
3. **Step 0** — pin session, worktree, branch and the roles fingerprint in an Issue comment.
4. **Step 4 and "Fast lane"** — the fast-lane record as a comment approved at gate 1; the entry
   condition of the `code` phase.
5. **Step 10a** — checkpoint and sync before verification; the fast-lane re-check.
6. **Steps 11, 11a, 12–14** — QA on the checkpoint, the QA checkpoint, `VERIFIED`, every report
   naming its SHA; the "Write-boundary check" section now calls `scripts/boundary-check.sh`.
7. **"Re-verification after a STOP"** — fixes become new checkpoints and a new `VERIFIED`.
8. **Steps 15–19** — the freshness check against `VERIFIED`; push only on request; `Refs #N` and
   `Verified at:` in the PR; gate 2 checks the PR head against `VERIFIED`.
9. **Steps 21 and 23** — the gate-3 documentation PR with `Closes #N`; labels set at gate 3.

Into `task-status.md`: the three new rows of the state table (Issue open at gate 3, closed before
gate 3, a report naming a different SHA).

**Check:** `grep -c "VERIFIED\|boundary-check.sh\|Refs #\|fast-lane record" .claude/commands/task.md`
— several lines each; then `/task-status #<N>` on any Issue runs and changes nothing.

### 6. Migrate Issues closed before gate 3

Under v0.2.0 a code PR with `Closes #N` closed the Issue at merge, while it still waited in
`state:evidence`. Reopen those whose register entry is not in place yet:

```bash
gh issue list --repo <owner>/<product-repo> --state closed --label state:evidence --json number,title
gh issue reopen <N> --repo <owner>/<product-repo>
gh issue edit <N> --repo <owner>/<product-repo> --add-label waiting-on-human
```

Then finish their gate 3 the new way — a documentation PR with `Closes #N`. An Issue whose entry is
already in place gets `state:closed` and stays closed.

**Check:** the list above is empty, and so is the label-invariant query from the v0.1.0 → v0.2.0
upgrade, step 6.

### 7. Registers

Add `invocation` and `roles` to new cost rows (old rows keep "no data" — don't backfill from
memory), and start recording gate rows (`"kind": "gate"`) and escapes as
[`process/registers/cost-register.md`](process/registers/cost-register.md) describes. The capability
register's mutation rows link patches with their base SHA.

### 8. Settings, CI and assertions

- **Branch protection (paid plan):** a required pull request with `required_approving_review_count:
  0`, required status checks, `enforce_admins: true` — then the acceptance test from
  [`process/ci-and-branch-protection.md`](process/ci-and-branch-protection.md) §3 on a throwaway
  repository, never on the product's `main`.
- **Invariant assertions:** replace A3 with the paired version, add the swapped-key case to your
  fixture and the cross-tenant behavior test ([`process/invariant-assertions.md`](process/invariant-assertions.md)).
- **CI variant B**, if you use it: the documentation-only allowlist and the new gate.

### 9. Recalibrate the evaluating roles

All four changed: the verdict semantics (Guardian, Reviewer, Security Auditor) and QA's mutation
method. Run the methods from [`calibration/README.md`](calibration/README.md) — 1 for the Guardian, 2
for the Reviewer, **1a for QA and 1b for the Security Auditor** (new) — and key each result by
definition, model, invocation mode and case set. Until then, a `PASS` from them is unconfirmed at
gate 2.

### 10. Confirm on one task

Drive one small task with the updated `/task`. What should be visibly different:

- a "Task started" comment with the roles fingerprint on the Issue;
- two checkpoint commits (`developer`, `qa`) on the task branch, and every report naming `VERIFIED`;
- "boundary check: clean" after each role that was checked;
- a PR that says `Refs #N` and `Verified at: <SHA>`;
- after the merge the Issue **still open** in `state:evidence`, and a documentation PR with
  `Closes #N` — its merge is your gate 3.

When that holds, delete the `pre-ninefold-v0.3.0` tags.

---

## v0.1.0 → v0.2.0

> For teams that installed the kit at **v0.1.0** (the initial commit `4a726f3`, 2026-09-17) and want
> to move to **v0.2.0** (2026-09-23). If you are installing from scratch, follow
> [`process/bootstrap-guide.md`](process/bootstrap-guide.md) instead.

The upgrade touches two places: your **process repository** (your copy of this kit) and every
**product repository** that received roles, templates and commands from it. Nothing in it is
automatic — like the rest of the process, each step ends with a check, because most of these
changes fail silently when half-done.

**Time:** about half a day per product repository, plus recalibration of the evaluating roles.

---

### What changed, in one table

| Area | Change | Action in a product repo |
|---|---|---|
| Roles | `model: opus` → `model: inherit`; Architect gets `Write, Edit`; Developer self-check; Guardian rules tagged [M]/[J]; QA records mutations as patches; Product Owner output headings match the Story form | re-sync (step 4) + recalibrate (step 9) |
| State machine | PR opened after verification, not after implementation; new gate-3 state `state:evidence` between merge and closed | migrate open Issues (step 6) |
| Labels | new `state:evidence`, `role:reviewer`, `role:security-auditor`; `state:qa` description | re-run the label script (step 3) |
| Templates | PR templates get a mutation-patch block; Issue form field `id`s translated to English (field labels unchanged) | re-sync templates (step 3) |
| Task command | pre-authorized bookkeeping commits; worktree created at recon; write-boundary check; scoped re-verification; fast lane; cost register one file per row with `model` and `reworkCause` | merge by hand (step 5) |
| Registers | templates in `process/registers/`, incl. a new list of architecture-sensitive paths | add what's missing (step 7) |
| New files | `process/workflows/label-guard.yml`, `.claude/settings.json` permissions, `.gitignore` for `.claude/agents/`, `.gitattributes` for the hook | copy (step 8) |
| Merge settings | `required_linear_history` recommended `false` unless you are squash-only | check (step 8) |
| Sync tools | `sync-github.mjs` path bug fixed; missing target → exit 1; `<placeholder>` refused; `--self-test` before every run; new `--validate` | re-apply config (step 1) |

The full list of reasons is in the pull requests:
[#1](https://github.com/TanerCRB/NineFold/pull/1) ·
[#2](https://github.com/TanerCRB/NineFold/pull/2) ·
[#3](https://github.com/TanerCRB/NineFold/pull/3) ·
[#4](https://github.com/TanerCRB/NineFold/pull/4) ·
[#5](https://github.com/TanerCRB/NineFold/pull/5) ·
[#6](https://github.com/TanerCRB/NineFold/pull/6) ·
[#7](https://github.com/TanerCRB/NineFold/pull/7).

---

### 0. Before you start

**Pick a moment between tasks.** A task already in flight finishes under the command it started
with: the old flow opens the PR at the end of implementation, the new one at the end of
verification, and switching halfway leaves the Issue in a state neither version expects. List what
is in flight:

```bash
gh issue list --repo <owner>/<product-repo> --state open --label state:implementation
gh issue list --repo <owner>/<product-repo> --state open --label state:qa
gh issue list --repo <owner>/<product-repo> --state open --label state:merge
```

Let these reach gate 2 (or park them), then upgrade.

**Keep a way back.** Tag the current state of the process repository and each product repository
before changing anything (`git tag pre-ninefold-upgrade`).

---

### 1. Process repository: take the new version

Your process repository is a copy of this kit with your own edits — adapted roles, a filled-in
configuration. Bring the new version in as a merge on a branch, not by overwriting files:

```bash
git remote add upstream <url-of-this-kit>      # once
git fetch upstream --tags
git switch -c upgrade/ninefold
git merge v0.2.0                               # the release, not a moving branch
```

Expect conflicts in three places:

- **`agents/*.md`** — your adapted text against the new sections. Keep your domain content
  (checklists, the domain sentence, paths) and take the new mechanics: the `[M]`/`[J]` tags and
  their explanation in the Guardian, the patch rules in QA, the self-check section and report
  field in the Developer, the `Write, Edit` tools and the boundary note in the Architect, the
  renamed output headings in the Product Owner. `model: inherit` replaces `model: opus`; keep an
  explicit model only if you deliberately want one — and then read the model note in
  [`calibration/README.md`](calibration/README.md).
- **`tools/sync-agents.mjs`, `tools/sync-github.mjs`** — both were restructured. **Take the new
  files whole** and copy your `TARGETS` and `OWNER` back into their configuration blocks; don't try
  to merge the logic line by line.
- **`TEAM-CONTRACT.md`** (your adapted copy, if you made one) — compare it with the new
  `TEAM-CONTRACT-TEMPLATE.md`: classification of QA and the Architect, hard stops 3, 7 and 8, the
  §2a boundary checks and permissions, the §8 log fields.

If you used `sync-github.mjs` before, note that in v0.1.0 it only worked when run from
`tools/` with adjusted paths. Run it from the repository root now.

**Check:**

```bash
node tools/sync-agents.mjs --self-test
node tools/sync-github.mjs --self-test
node tools/sync-github.mjs --validate
node tools/check-links.mjs
node tools/sync-agents.mjs --check     # DRIFT is expected here — the product repos have the old roles
```

No `ERROR` about a placeholder: if one appears, your configuration didn't survive the merge.
Merge the branch through a pull request. The kit's own CI (`.github/workflows/kit-ci.yml`) comes
with the merge — enable Actions for the process repository if they're off.

---

### 2. Product repository: protect the hook's line endings

If the product repository already has the pre-push hook, make sure it can't be checked out with
CRLF (the initial guide added this rule after copying the hook, which could leave it CRLF):

```bash
grep -q '^.githooks/\*\* text eol=lf' .gitattributes || echo '.githooks/** text eol=lf' >> .gitattributes
git add .gitattributes && git add --renormalize .githooks/
git ls-files --eol .githooks/pre-push      # -> i/lf ... attr/text eol=lf
```

Replace `.githooks/pre-push` with the new `process/hooks/pre-push` only if you changed nothing in
it; it is unchanged in content, so usually there is nothing to replace.

---

### 3. Labels and templates

From the process repository root:

```bash
node tools/sync-github.mjs --labels | bash             # or --labels-ps1 on PowerShell
node tools/sync-github.mjs                             # templates into the product repo's .github/
```

`--force` in the generated script makes the run idempotent: existing labels keep their names and
only get the new description; the three new labels are created.

In the product repository, commit the changed `.github/` files on a branch and merge them through a
pull request.

**Check:** `gh label list --repo <owner>/<product-repo> | grep -E 'state:evidence|role:reviewer|role:security-auditor'`
shows three lines, and `node tools/sync-github.mjs --check` in the process repository reports
`No drift.`

The Issue forms changed only their field `id`s. If anything of yours addresses the fields by id
(a prefilled issue URL such as `?gotowe-gdy=…`, an automation reading the form), switch it to the
new ids: `task-id`, `what-and-why`, `definition-of-done`, `out-of-scope`, `documentation-basis`,
`confirmations` (Story) — the rest are listed in the form files.

---

### 4. Roles

From the process repository root:

```bash
node tools/sync-agents.mjs
node tools/sync-agents.mjs --check          # "No drift."
```

If the script warns `git does not ignore .claude/agents`, add `.claude/agents/` to the product
repository's `.gitignore`. If you had ignored the whole `.claude/` directory instead, narrow it to
`.claude/agents/`: the commands and `.claude/settings.json` are meant to be versioned (step 5, 8).

**Check:** in a Claude Code session in the product repository, `/agents` lists the eight roles,
and `.claude/agents/architect.md` shows `tools: Read, Write, Edit, Grep, Glob`.

---

### 5. Task commands

Your `.claude/commands/task.md` and `task-status.md` are adapted copies, so they are merged by
hand. See exactly what changed upstream:

```bash
# in the process repository
git diff v0.1.0 v0.2.0 -- process/task-command.md
git diff v0.1.0 v0.2.0 -- process/task-status-command.md   # no changes
```

Carry these into your `task.md`:

1. **Overriding rules** — the closed list of bookkeeping commits (plan-number reservation,
   cost-register row) that need no request.
2. **Step 0** — the task's worktree is created right after recon, before the first role call;
   step 6 only confirms it.
3. **Cost register** — one file per row, the `model` and `reworkCause` fields, the commit on the
   task branch; the conflict rule in the `pr` phase is now only a fallback.
4. **Write-boundary check** after the Architect (step 4) and QA (step 11), with the snippet from
   the "Write-boundary check" section.
5. **Re-verification after a `STOP`** — the scoped rerun.
6. **Fast lane** — copy the section, but leave it **off** until the cost register shows the
   Architect adds nothing on such tasks; fill in `<path-to-architecture-sensitive-paths-list>`.
7. **QA step** — mutations come back as patches and go into the PR as is.
8. **Gate 3** — a merged task sits in `state:evidence`, not `state:closed`.

**Check:**

```bash
grep -c "Write-boundary check\|Re-verification after a\|bookkeeping commit\|state:evidence" .claude/commands/task.md
```

(four or more; the exact count depends on your wording). Then `/task-status #<N>` on any Issue
runs and changes nothing.

---

### 6. Migrate open Issues to the new state machine

In the old machine, merging a PR moved a task straight toward `state:closed`. Now a merged task
waits in `state:evidence` for the gate-3 documentation commit. Find tasks that were merged but whose
status was never raised:

```bash
# merged (Issue closed by the PR) but still carrying a working state
gh issue list --repo <owner>/<product-repo> --state closed --label state:merge --json number,title
# closed and marked closed, but the evidence was never provided
gh issue list --repo <owner>/<product-repo> --state all --label state:closed --label evidence:missing --json number,title
```

For each one whose register entry is still missing:

```bash
gh issue edit <N> --repo <owner>/<product-repo> \
  --remove-label state:merge --remove-label state:closed \
  --add-label state:evidence --add-label waiting-on-human
```

Tasks whose register entry is already in place get `state:closed` and no `waiting-on-human`.

**Check:** the label-guard rules (step 8) hold on every open Issue — exactly one `state:*` label,
`waiting-on-human` on each of `state:decision`, `state:merge`, `state:evidence`:

```bash
gh issue list --repo <owner>/<product-repo> --state open --limit 500 --json number,labels \
  --jq '.[] | [.labels[].name] as $l
        | select(any($l[]; test("^(state:|role:)|^waiting-on-human$")))
        | select([$l[] | select(startswith("state:"))] | length != 1) | .number'
```

(expected: no output). Like the guard itself, it skips Issues with no process label at all.

---

### 7. Registers

Compare what you have with [`process/registers/`](process/registers/README.md) and add what's
missing. Two changes matter for existing registers:

- **Cost register → one file per row.** Keep the existing table as it is (rename it, e.g.
  `cost-register-until-<date>.md`) — its numbers stay valid history. New calls write
  `<cost-register-dir>/<date>_<task>_<phase>_<role>_<n>.json` per
  [`cost-register.md`](process/registers/cost-register.md). Rows before the upgrade have no
  `model`; don't backfill it from memory — "no data" is the honest value.
- **Architecture-sensitive paths** — a new file, read by the fast lane. Create it even while the
  fast lane is off, so the Architect can maintain it from the start.

If your capability register keeps mutations, add a `Patch` column for the links to mutation patches.

---

### 8. New files and settings

| What | Where in the product repo | Source |
|---|---|---|
| Label guard workflow | `.github/workflows/label-guard.yml` | `process/workflows/label-guard.yml` |
| Shared permissions | `.claude/settings.json` | `TEAM-CONTRACT-TEMPLATE.md` §2a |
| Invariant assertions for [M] rules | your CI | `process/invariant-assertions.md` |

Check the merge settings against the new recommendation — `required_linear_history` should be
`false` unless you merge with squash only:

```bash
gh api repos/<owner>/<product-repo>/branches/main/protection --jq .required_linear_history.enabled
```

(on a free private repository this call returns `403` — there is no protection to check).

**Check:** give a test Issue two `state:*` labels — within a minute `label-guard` comments and the
run is red; remove one and the next run is green.

---

### 9. Recalibrate before trusting the reports

The Guardian's and QA's definitions changed, and every role now runs on the calling session's
model instead of a fixed one. By the kit's own rule both are a definition change
([`calibration/README.md`](calibration/README.md), "When to repeat it"):

- **Invariant Guardian** — method 1 again (seeded set + clean run). With [M] rules backed by CI
  assertions, the answer key for those rules becomes "cites the green assertion run".
- **Reviewer** — method 2 again, if the model it now inherits differs from the one it was
  calibrated on.
- Record the model with every result.

Until then, treat an evaluating role's `PASS` as unconfirmed at gate 2.

---

### 10. Confirm on one task

Run one small task with the updated `/task` from start to finish, as in
[`bootstrap-guide.md`](process/bootstrap-guide.md) step 10. What should be visibly different from
before:

- the worktree exists from the first role call, and the analysis roles' cost rows are commits on
  its branch;
- "boundary check: clean" in the notes after the Architect and QA;
- the PR opens after verification and carries the mutation patch;
- after the merge the Issue sits in `state:evidence` with `waiting-on-human` until you paste the
  register entries.

When that holds, the upgrade is done — delete the `pre-ninefold-upgrade` tags when you no longer
need the way back.
