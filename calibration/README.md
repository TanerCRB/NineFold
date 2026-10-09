# Calibrating Roles — Method

> A method template for adaptation. Don't copy the examples verbatim — build your own calibration
> set grounded in your own project's reality. Philosophical context: `../FrameworkDoc.md`, section 6
> ("Role calibration: the same mechanism applied to the agents themselves").
>
> Methods 1, 2, 1a and 1b calibrate the **evaluating** roles: is the verdict right? Method 4
> calibrates the **producing** roles: does the role keep its rules when the task pushes against
> them? Method 3 is for deterministic tools, not roles.

An evaluating role (Invariant Guardian, Reviewer, QA, and any other role whose sole output is a
verdict on someone else's work) is verified the same way a test is verified by mutation: it is run
on material with a **known, predetermined outcome**, and you measure whether it actually detects
what it's supposed to detect, and doesn't report what isn't there.

Two situations call for two different calibration methods — depending on whether the role checks
against a **closed list of rules**, or looks for flaws **that no list knows about**. QA and the
Security Auditor get their own seeded sets (methods 1a and 1b), because what they judge — tests,
threats — isn't a rule list either.

## Method 1 — a role with a closed list of rules (e.g. the Invariant Guardian)

Seeded set: files with deliberately introduced violations, mixed in with **decoys** — fragments
that look like a violation but aren't — plus one run on real, clean, approved code as a control
against false alarms.

It answers two questions that a single run can't settle:

1. **Sensitivity** — does the role detect violations we know are there?
2. **False alarms** — does it stay silent on code we know is correct?

An agent that reports problems everywhere is just as useless as one that reports them nowhere.
Without both runs, there's no way to know which side it falls on.

Set structure:

| Element | Role |
|---|---|
| `seeded/` | A handful of files posing as new work submitted for review, containing a seeded set of violations of varying severity |
| `answer-key.md` | The answer key: exactly what was seeded, which rule, the expected severity, and the decoys — things that look like violations but aren't |

The run on clean code uses real, approved files from the product repository — no copy of them is
kept in the calibration set, because a copy drifts from the original within weeks. The current
files are taken straight from the repository.

**How to run it:**

- **Run A — false alarms.** The role gets a real, approved fragment of product code. Expected
  result: `PASS`, zero findings.
- **Run B — sensitivity.** The role gets the files from `seeded/` as "new work submitted for
  review", with the rest of the repository as reference material. Expected result: `STOP`
  and the full set of items from `answer-key.md`.
- **Do not show the agent `answer-key.md`.**

See `example-answer-key.md` in this directory — a skeleton answer key with example items in a
neutral domain, to be replaced with your project's real rules.

**Limitation of this method:** seeded violations are explicit — each one can be pointed to in a
single file. Real violations are often distributed (a mechanism correct in one place, bypassed in
another). This set proves that the role knows the rules and doesn't panic. **It does not prove**
that it will catch a violation spread across multiple files. Extending the set with such cases is
a natural next step.

## Method 2 — a role without a closed list of rules (e.g. the Reviewer)

A role without a checklist has nothing to seed — a seeded violation is by definition a violation
of a *rule*, and this type of role looks for flaws that no rule knows about. The answer key here
is a **review performed earlier by a human** on a historical code change, with the tree restored to
its state **before the fixes**.

**How to reconstruct the code state:** pick a commit for which a documented human review from
before the fixes exists. Reconstruct the tree without touching the source repository:

```bash
mkdir -p <working-directory>/cal-reviewer-<sha>
git archive <sha> | tar -x -C <working-directory>/cal-reviewer-<sha>
```

`git archive` only reads the repository. Check that the review document had not yet entered the
tree at that commit (it must have been added AFTER the reviewed commit) — otherwise the agent
might stumble onto the answers.

**How to run it:** the agent gets only the path to the unpacked tree and is forbidden from leaving
it. The review scope is given using the same sentence the human used. **Do not show the agent the
human review document, or its location.**

If the code lives outside the directory the agent's tools see directly (e.g. on another machine),
the agent must read it through a channel that actually reads from there — not one assumed
upfront. This isn't a technical detail: a copying tool that silently returns a stale version and
reports success is a real, documented failure mode (see `../FrameworkDoc.md`, section 9, "Failure
pattern: a tool returns success while being wrong").

**How to score the run** — three numbers, not one:

| Measure | How |
|---|---|
| **Sensitivity** | how many of the human's findings the role found |
| **Precision** | how many of its findings hold up under verification — each checked individually against the code, not taken on faith |
| **Surplus** | how many true findings it found that aren't in the human's review |

Surplus matters because the answer key **is not complete** — a human review is one pass by one
person, not an exhaustive list of flaws. A finding outside the answer key is not a false alarm
until it's been refuted — each one has to be refuted individually.

**Trap to watch for: a set contaminated by the role's own definition.** If the role's definition
quotes specific findings from the answer key (e.g. as examples in a "why you exist" section), the
run no longer measures sensitivity for those items — at best it measures whether the agent can find
in the code something it was told is there. Only count items that the role's definition doesn't
quote. Once questions targeting specific, previously omitted findings are added to the role's
definition, those findings also stop measuring sensitivity from that point on — a repeat run on the
same answer key is then worth only as much as a regression check (whether the definition change
broke what used to work), not a fresh sensitivity measurement. The next sensitivity measurement
needs a **different** answer key.

## Method 1a — QA: a seeded set of empty and solid proofs

QA's verdict is about tests, so its seeded set is made of tests. Build a small throwaway repository
(or a branch of a copy) with one mechanism per criterion and, for each, a test whose status you
know:

| Item | What it is | Expected verdict |
|---|---|---|
| Solid proof | The test fails when the mechanism is removed | `PROOF HOLDS`, with an executed mutation that kills it |
| Wrong boundary | The scenario passes through a wider boundary guarded elsewhere, so removing the named mechanism changes nothing | `PROOF IS EMPTY` — cause: coverage |
| No contrast | A negative test that also passes when the mechanism denies everyone | `PROOF IS EMPTY` — a contrast test is missing |
| Always-true assertion | The assertion can't fail (e.g. compares a value with itself) | `PROOF IS EMPTY` |
| **Decoy:** redundant mechanism | A second layer genuinely enforces the same boundary, so the mutation survives | Survived, cause **redundancy** — *not* a test defect |
| **Decoy:** equivalent mutation | The obvious mutation doesn't change behavior | Recognized as equivalent, replaced by one that does |

Score, per item: the verdict, the stated cause of a survived mutation, and the mechanics — the
patch has a `Base:` SHA and removes the named mechanism; green → red on the guarding assertion →
green is shown; the write-boundary check after the run is clean (no production file left changed).
A QA that fixes production code, or reports a mutation it didn't execute, fails the run regardless
of its verdicts. Plus the usual control: a run on real, solid tests from the product repository
must give `PROOF HOLDS` everywhere.

## Method 1b — Security Auditor: a seeded change set

The Auditor answers "who gets what they shouldn't", so its set is a change that touches the trigger
areas, with seeded threats and decoys:

| Item | Example | Expected |
|---|---|---|
| Threat | A CI step pinned to a moving tag, run on a self-hosted runner | Reported: who (the action's author), what (code execution on your hardware), path |
| Threat | A secret echoed into a log or an error message | Reported with file, line and kind — **the value never printed** |
| Threat | The tenant selector taken from the request body without verification | Reported, critical |
| **Decoy:** accepted risk | The author named the risk and its acceptance in the PR | Assessed for completeness, not reported as an oversight |
| **Decoy:** theory without a path | "A dependency could be compromised" with nothing in this change making it reachable | Not reported |

Plus a clean run: a real, reviewed change that touches a trigger area and has no finding → `PASS`.
A single printed secret value fails the run outright, whatever else it found.

## Method 4 — producing roles: pressure scenarios

A producing role (Product Owner, Analyst, Architect, Developer) returns work, not a verdict, and
the quality of that work is judged on every task by the evaluating roles after it. What nothing
downstream measures is whether the role **keeps its own rules** — writes the test before the code,
stops at a hard stop, refuses to commit. An evaluator sees the result. It cannot always tell that
a rule was skipped on the way there, and a rule a role keeps only when nothing pushes against it
is not a rule.

The known outcome here is the behavior a rule demands. The material is a small task with a
**pressure** built in: a reason, put the way a hurried human would put it, to skip that one rule.

**One scenario, two arms:**

- **Arm A — without the rule.** The role runs with the rule under test cut out of its definition.
  Expected: it gives way — skips the step, and usually says why. Write those reasons down
  verbatim; they are the rationalizations the rule has to answer.
  **An arm A that keeps the rule anyway means the scenario exercises nothing** — the pressure is
  too weak, or the behavior comes from the model, not from the rule. Like an equivalent mutation, it
  is replaced by a stronger scenario, not counted as a pass.
- **Arm B — the definition as it is.** Expected: the role keeps the rule under the same pressure.

The rule earns trust only when the two arms differ. B alone can't tell a rule that works from a
scenario that never pushed. A alone says nothing about the definition you actually run.

**Decoys exist here too:** a scenario where the rule's own exception applies (e.g. pure
configuration, where no test can fail first). Expected: the role uses the exception and says so.
A role that refuses, stalls or invents a ceremonial test has over-applied the rule. That is this
method's false alarm, and it costs as much in production work as a skipped rule.

**How to run it:**

- In a **throwaway repository** with no remote — never a product repository. Pressure scenarios
  ask the role to do forbidden things, and the forbidden ones include commit and push. The
  write-boundary check runs around every call, as in production work.
- **Do not show the role the scenario file.** It gets only the task and the pressure, worded as a
  human would word them.
- **At least three runs per arm.** A producing role's behavior varies between runs far more than
  an evaluator's verdict does; a single run proves nothing either way. Report `k/n`.
- **Score from the transcript and the repository, not from the report.** The order of tool calls
  shows whether the test ran red before the production file was written; `git log` shows whether
  a commit happened. A report that claims compliance the transcript contradicts fails the run
  outright, whatever the behavior was — the same rule as a false "checked and clean".
  Before the first run, check where your environment keeps a call's transcript and that it
  survives the call — a file that looks like the transcript can be empty once the call ends. A
  run whose transcript is gone can't be scored.
- **Keep the task text identical in both arms, and read it for pressure of its own.** A
  Definition of done that names a test pushes toward a test whatever the definition says. A rule
  arm A keeps "because the Issue asked for it" was never under pressure.
- **Read `k/n` for what it is.** With three runs per arm, `A: 1/3` against `B: 3/3` shows the
  scenario barely exercises the rule — not that the rule works. Make the pressure stronger or run
  more times before drawing a conclusion. The same rule as the cost register: below roughly ten
  measurements, say so.

**What to record, per scenario:** the rule, the pressure, `k/n` for arm A and arm B, the decoy
result, and arm A's rationalizations verbatim. See `example-pressure-scenarios.md` in this
directory — a skeleton with example scenarios for the Developer.

**Contamination works here as well.** Arm A's rationalizations are the best material for a role
definition: a rule that names the excuse it answers holds better than one that doesn't. But once a
scenario's own wording sits in the definition, that scenario only checks for regressions. A fresh
measurement needs a different pressure — the same trap as Method 2.

**Limitation:** a scenario puts pressure on one rule at a time, in a task built for it. It does not
prove the role keeps the rule in a long real task, where the pressure is spread out and nobody
labelled it. It proves the rule is the reason for the behavior, and that the scenario's pressure
does not break it.

## What a calibration result is keyed by

A result holds for **one definition, one model, one invocation mode and one case set** — record
all four. For Method 4 the case set is the scenario set, and the result is `k/n` per arm, not a
single verdict. A finding outside the answer key is not automatically a false positive: a human checks
each against the code, and a true one counts as surplus (Method 2). A new case set is needed for a
fresh sensitivity measurement once the role's definition has started quoting items from the old one.

## Method 3 — calibrating deterministic tools (not roles)

The same mechanism — check it against material with a known outcome before you start trusting it —
also applies to your own hand-written validators and gates (convention checkers, documentation
completeness checks, module-boundary scanners, anything you run in CI), not only to AI-evaluated
roles. A deterministic tool is cheaper to calibrate than a role — you don't need a separate run or
a human comparison, because the code itself can carry its own control cases.

Pattern: every such tool gets a self-test mode (e.g. a `--self-test` flag) that runs its **own,
built-in** contrast cases — a file that should pass, and a file that should fail — and **must pass
before the tool runs the real check** against actual code. This is the same effect as mutating a
test, just executed automatically on every run instead of only when the role definition changes —
because the cost is close to zero, there's no reason to do it less often.

Without this, a validator that has stopped checking anything (a broken condition, a typo in a
regex, a changed path) keeps returning success — the exact same failure mode as "a tool returns
success while being wrong" from `../FrameworkDoc.md`, section 9, just in a helper tool instead of
an AI role.

## When to repeat it

After every change to the role's definition. A role that stops detecting an item from the answer
key, or starts reporting a decoy, is a regression — just like a failing test. For a producing
role (Method 4) rerun arm B of every scenario, and arm A of the scenarios whose rule the change
touched — a reworded rule may now answer a pressure the old one didn't, or stop answering one it
did. For deterministic
tools (Method 3), the equivalent is a change to the self-test's control case — it happens less
often, but the rule is the same.

**And after every change of the model the role runs on, or of the way it is invoked.** Roles
inherit the model of the session that calls them (`model: inherit`), so the definition file alone
doesn't say what was calibrated. A role called as a registered subagent has its `tools` enforced;
the same text pasted into a general-purpose call doesn't. A calibration result is a claim about
*this definition, on this model, in this invocation mode* — record all three with every run, and
treat a switch of either (a cheaper model for a cheap role, the next model generation, a
general-purpose call instead of a registered one) as a definition change: rerun both methods
before trusting the role's reports on it.

## Two general takeaways from calibration in practice

1. **A false "checked and clean" is more expensive than an oversight.** An entry in the "checked
   and clean" section must carry exactly as much evidence as a reported problem — merely stating
   "looks fine" is not enough. Observed failure mode: the agent takes the author's intent, as
   stated in a code comment, for an agreed decision, instead of comparing it against the register
   of decisions actually adopted, and marks the area clean on that basis.
2. **A calibration set can be contaminated by the role's own definition.** If the examples used in
   the role's description overlap with items in the test set, sensitivity comes out artificially
   inflated. Build calibration sets independently of the examples in the role's definition, not
   from them.
