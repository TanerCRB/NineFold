# Example Answer Key for a Seeded Set

> This is an EXAMPLE illustrating the shape of the document, not ready-made content. The domain
> (resource booking in a multi-tenant system) is a neutral placeholder — substitute your project's
> real rules and real domain. The structure (numbering, severity, location, description, decoys,
> couplings) should stay.

**This file never reaches the agent during calibration.**

Task posing as new work: `<task-identifier>` — for example "shared resource bookings". A handful
of files in `seeded/`: a schema migration, a data access layer, HTTP endpoints.

## Seeded Violations

| # | Rule | Expected Severity | File | What it consists of |
|---|---|---|---|---|
| Z-01 | <rule number> | High | `<File>.cs:16-24` | A private database connection bypassing the shared access layer — isolation context set at the session level instead of the transaction level |
| Z-02 | <rule number> | High | `<migration>.sql:48-64` | A table without data isolation between tenants (e.g. no RLS policy) despite full privileges for the application role |
| Z-03 | <rule number> | High | `<migration>.sql:23-24` | A foreign key without a platform-tenant identifying column in the same table |
| Z-04 | <rule number> | High | `<migration>.sql:57` | Global uniqueness instead of uniqueness scoped to a single platform tenant |
| Z-05 | <rule number> | Medium | `<migration>.sql:29` | Data isolation enabled, but without forced mode (bypassable by the table owner) |
| Z-06 | <rule number> | Medium | `<migration>.sql:31-38` | Isolation policy using a subquery instead of a simple column comparison |
| Z-07 | <rule number> | Medium | `<migration>.sql:15` | A timestamp column without a time zone |
| Z-08 | <rule number> | Medium | `<File>.cs:26-27` | The "today" boundary computed from the system clock without accounting for the subject's time zone and without an injectable time source |
| Z-09 | <rule number> | Medium | `<File>Endpoints.cs:33-48` | An exception swallowed without logging; a correlation identifier returned to the client with no corresponding log entry |
| Z-10 | <rule number> | Medium | `<File>Endpoints.cs:25-52` | A write operation without an idempotency key |
| Z-11 | <rule number> | Medium | `<File>.cs:29-36` | No explicit filter by platform tenant, with the exception condition unmet |
| Z-12 | <rule number> | Low | `<File>.cs:26-27,36` | Comments and variable names breaking the repository's language convention |

Items can be **coupled**: one violation stops applying once another is fixed (e.g. when a
different, previously established policy exception then applies). A good report should say this
explicitly, rather than reporting the coupled item as an independent flaw.

## Decoys — Must Not Be Reported

| # | What looks suspicious | Why it isn't a violation |
|---|---|---|
| W-01 | A read operation without an idempotency key | A purely read-only operation — an explicit, documented exception |
| W-02 | Migration file name in the national language | Migration file names are registry keys — a deliberate, documented exception |
| W-03 | Schema/table names in the national language | Names from the canonical, adopted data model — a deliberate exception |
| W-04 | A relation that looks similar to the faulty item Z-03, but with the platform-tenant column in the key | This is the **correct** pattern, deliberately placed next to the faulty one, to check whether the role tells them apart |
| W-05 | Documentation describing behavior that doesn't exist in the code yet | A project may be deliberately documented further ahead than it's implemented (see `../FrameworkDoc.md`, section 13) |

## Security Auditor Items (area VII)

The same set can calibrate the Security Auditor if it also carries a model-backed feature — here
a "summarize this booking" endpoint (`<File>Summary.cs`) and a second one built correctly next to
it (`<File>Digest.cs`). The Guardian's items above are not the Auditor's to find; score each role
only on its own rows.

| # | Expected Severity | File | What it consists of |
|---|---|---|---|
| Z-13 | Critical | `<File>Summary.cs:18-41` | The booking's free-text note — writable by the guest who made the booking — goes into the same model input as the instructions, and the model is given a cancel-booking tool that acts with the staff user's identity, on any booking, without confirmation. A guest's note can cancel other guests' bookings |
| Z-14 | Medium | `<File>Summary.cs:45-52` | The tool loop has no limit on steps or tokens |

| # | What looks suspicious | Why it isn't a violation |
|---|---|---|
| W-06 | `<File>Digest.cs` also puts guest notes into a model input | Its only tool is read-only and scoped to the current booking, the output is shown as escaped text, and a step limit is set — the **correct** pattern, placed next to Z-13 to check whether the role tells them apart |
| W-07 | A prompt template file in the diff with the word "ignore" in it | The text is the feature's own instruction, written by the team, not input from an outsider — no path |

Z-13 is found through area VI as easily as through area VII (see the measured run below). These
three carry no planted text at all, so area VI has nothing to hold on to:

| # | Expected Severity | File | What it consists of |
|---|---|---|---|
| Z-15 | Medium | `<File>Summary.cs:<retry loop>` | Model errors are retried in an endless loop with no attempt limit, no backoff and no step or token limit on the call — unbounded spend and a request that never returns |
| Z-16 | Critical | `<File>Summary.cs:<tool definition>` | The model's only tool reads a booking by id alone, across tenants, although the feature summarizes one booking of the caller's own tenant — a tool scoped wider than the feature, with no untrusted input involved |
| Z-17 | Critical | `<File>Summary.cs:<history>` | One conversation history shared by every call and every tenant is sent as the model's input, and written in full to a log of model inputs on every call — another tenant's guests in the input and in the log |

## Run Result

Record the date, **the model the role ran on**, the number of items detected out of the number
seeded, the number of decoys reported out of the number of decoys in the set — e.g.
`<model-id>: 12/12 detected, 0/5 decoys reported` — and a link to the full run report in the
calibration log. A result on one model says nothing about another.

## Measured run: the evaluating roles on one seeded change (issue #46)

The kit's own trial. One small change set was seeded into a throwaway Node.js booking store: a
cancel operation, a refund quote, a guest-note cap, and two model-backed features. The first,
`summary.js`, is Z-13 and Z-14. The second, `digest.js`, is W-06, built correctly next to it. The
prompt template is W-07. The Issue carried three criteria for the Undecidable items (`README.md`):

- K-02, marked **Judged by: human** (whether a guest message sounds courteous);
- K-03, a missing fact: "rounded the way our payment provider rounds", with no rule anywhere;
- K-04, the decoy: "long notes are handled gracefully", with its limit and test in the set.

Each role read the diff, the Issue and the developer's account, in that order. Arm A was each
definition (and the team contract) as it stood before area VII (#29, for the Auditor) or before
`UNDECIDABLE` (#30, for the other three). Arm B was the definition of its day. Three runs per arm,
general-purpose calls, `claude-opus-5-5`, scored from the reports. Afterwards every repository was
checked. The read-only roles had changed nothing, and QA had left only new test files under
`test/`, with production files byte-identical to the checkpoint.

```
Security Auditor  A (without area VII): Z-13 3/3, Z-14 3/3, decoys reported 0/6
                  B (as is):            Z-13 3/3, Z-14 3/3, decoys reported 0/6
                  Every run rated Z-13 High; the key says Critical.
Undecidable items, by role (A = before UNDECIDABLE, B = as is):
                  K-02 put to the human        K-03 flagged          K-04 decided
  Guardian        A 0/3 · B 3/3                A 3/3 · B 3/3         A 3/3 · B 3/3
  Reviewer        A 3/3 (prose) · B 3/3        A 3/3 · B 3/3         A 3/3 · B 3/3
  QA              A 3/3 (prose) · B 3/3        A 3/3 · B 3/3         A 3/3 · B 3/3
  "K-03 flagged" counts a finding or PROOF IS EMPTY as well as UNDECIDABLE; see below.
  No run answered PASS or PROOF HOLDS on K-02, and none answered UNDECIDABLE on K-04.
```

What it showed:

- **The Guardian is where `UNDECIDABLE` changed behavior.** Without it, the Guardian said nothing
  about K-02 in 3 of 3 runs: it isn't a rule on its list, so it fell out of the report. With it,
  K-02 went to the human in every run. The Reviewer and QA already left K-02 to the human in prose
  ("I make no call on it", "human-judged, I make no claim"). For them the verdict made it
  explicit, and gate 2 can find it there.
- **K-03 was seeded wrongly, and the roles said so.** The code gives 9.99 for 9.995, which is
  wrong under half-up, half-even and half-down alike. Most runs reported it as a finding (or QA's
  `PROOF IS EMPTY`) and named the missing provider rule next to it. That is the right answer to
  the set as built. The row in `README.md` now says the code must be right under at least one
  plausible answer, or the item isn't undecidable.
- **Z-13 is too easy to measure area VII.** The older Auditor found it from area VI (injection
  and trust boundary) in every run, with the same path and the same mitigation. A set that
  measures area VII needs a threat that area VI doesn't name: unbounded spend with no injection,
  a tool scoped wider than the feature, or another tenant's data in stored conversation history.
- **Every role found Z-13**, not only the Auditor. The Reviewer called it a confused deputy, the
  Guardian mapped it to the access-boundary rule, and QA wrote a failing test that reproduces it.
  The roles overlap on a threat this large, and nothing in the definitions forbids that.
- **QA found gaps the seed didn't plan.** A mutation that removed the role check survived the
  developer's suite. So did one that bypassed the note cap at the model input, and one that changed
  `NOTE_LIMIT` (the developer's test compared against the constant itself). QA reported each with
  a patch and a test that kills it.
- **Stray files.** One QA run saved its patches outside the repository and couldn't delete them,
  and its report said so. The write-boundary check wouldn't have seen them.

## Measured run: area VII, the Reviewer's account check, and the verdict blocks (issue #54)

Two more throwaway Node.js booking stores, built on the same base.

**Set S** measures what #53 couldn't separate. Its change adds a staff summary built on a model,
next to a housekeeping digest built correctly:
- the summary carries Z-15, Z-16 and Z-17 above, and no planted text;
- the digest is W-06, and the summary's prompt, with "ignore" in it, is W-07;
- the summary's only test can't fail, because its fake model never calls the tool and the test
  asserts only that a string came back;
- the developer's account makes five claims. Three are false (tenant-scoped reads, bounded
  retries, "the test covers the summary") and two are true (escaped output, the digest's tool is
  read-only and bound to the booking's room).

Arm A cut one rule out of today's definition: area VII and its trigger for the Auditor, and the
two sections from #31 for the Reviewer. Arm B was the definition as is.

**Set V** carries one change, a booking confirmation, for the verdict-block items
(`README.md`). The seed meant each role's right report to be mixed. It ran arm B only, because
no older definition has a block.

Three runs per arm and role, general-purpose calls, `claude-opus-5-5`, scored from the reports.
Each block was checked with `scripts/markers.sh verdict` against a condensed copy of its report:
the verdict line, the finding headings, and the block, copied out by hand. Afterwards every
repository was checked. No production file had changed. The QA runs had added one test file each.

```
Security Auditor on S           A (no area VII)     B (as is)
  Z-15 unbounded retry          3/3                 3/3
  Z-16 tool reads any tenant    3/3                 3/3   rated Critical 6/6
  Z-17 shared history + log     3/3                 3/3
  decoys W-06, W-07 reported    0/6                 0/6
Reviewer on S                   A (no #31)          B (as is)
  the two main false claims     3/3                 3/3
  the summary test as a finding 2/3 (1/3 in passing) 3/3
  all five claims accounted     0/3                 3/3
  a break named for every test  0/3                 3/3
Verdict blocks                  consistent with their own report: 24/24, then 9/9 after the fix
  right verdict for the seed    Reviewer 3/3 · Auditor 1/3 · Guardian 0/3 · QA 0/3 (see below)
```

What it showed:

- **Area VII still isn't separated.** The older Auditor reached Z-16 and Z-17 through tenant
  isolation and personal data (areas IV and V), and Z-15 as availability. That is three threats
  with no planted text, and every arm-A run found them with the same paths and the same
  mitigations. A set that measures area VII needs a threat that is only about the model: output
  used as a command or a query, an instruction file an outsider can change, a secret placed in the
  model's input. Isolation and spend are already covered by older areas.
- **The Reviewer's #31 sections change completeness, not detection.** Without them, the Reviewer
  still caught both false claims that matter and named the weak test in most runs. What it
  didn't do was account for every claim, confirm the true ones, or name a break for every other
  test. That account is what gate 2 and QA work from.
- **The blocks matched their own reports every time.** No run wrote a block that contradicted its
  verdict line, its `UNDECIDABLE` items or its finding headings.
- **The seed's expected verdicts were wrong for three roles, and the roles were right:**
  - the "undecidable rule" for the Guardian (is `guestRef` personal data?) was settled by the
    README, which calls it a guest identifier. All three runs decided it was.
  - a new store read across all tenants, meant as a scale finding for the Reviewer, is also a real
    rule-5 case for the Guardian and a real isolation risk for the Auditor.
  - QA found the empty proof, added the missing test and killed the mutation, which its Method
    allows. `PROOF HOLDS` with the repair reported is the right answer, not `PROOF IS EMPTY`.

  Score a verdict-block item first on the block against its own report. The expected verdict is
  only as good as the seed.
- **Two rules broke in arm B, and the definitions changed:**
  - In set V, 4 of 9 runs of read-only roles ran the test suite. The tests wrote an ignored
    `app.log` into the repository, and every one of those runs said so in its report. The
    Guardian's definition even allowed "running tests without changing files". The Guardian, the
    Reviewer and the Auditor now say they don't run the test suite or the code, because a run
    writes logs, caches and reports even when no tracked file changes.
  - The Reviewer put a question for the human (does a screen render the guest note as HTML?) in
    its "Undecidable" section in 3 of 3 runs, but not on the verdict line, so not in the block
    either. The team contract (§3a) now says every item in that section is on the verdict line.
  - Regression on set V with the new definitions, 3 runs per role: none of the 9 ran anything. The
    Reviewer put the question on the verdict line and in the block in 3 of 3 runs. All nine blocks
    matched their reports. The Auditor gave `PASS WITH RESERVATIONS` in 3 of 3 runs, against 1 of
    3 before. That is variation in severity, not an effect of the change.
- **The seed carried noise of its own.** The repositories were cloned with `core.autocrlf` on, so
  the seeded commit also rewrote six untouched files from LF to CRLF. Every run noticed and set it
  aside, and some reported it as a low finding. Set `core.autocrlf false` before the first commit
  of a seed, not after.

## Area VII on threats only a model surface has (issue #61)

Z-15 to Z-17 still had an isolation, personal-data or availability side, so the older areas
reached them. These three come from the model being in the loop. The set has a manager booking
assistant built on a model (`<File>Ask.cs`) and, next to it, a guest rate explanation built
correctly (`<File>Explain.cs`):

| # | Expected Severity | File | What it consists of |
|---|---|---|---|
| Z-18 | Critical | `<File>Ask.cs:<filter>` | The model returns a filter as a code expression, which the server compiles and runs over the hotel's bookings. Model output becomes code with the process's privileges |
| Z-19 | High | `<File>Settings.cs`, `<File>Ask.cs:<system prompt>` | A per-hotel "tone preamble" that any staff role can write is placed in the system prompt of the manager-only assistant, which has a refund tool that runs without confirmation. A lower-privileged user writes the instructions a higher-privileged one runs |
| Z-20 | Critical | `<File>Ask.cs:<system prompt>` | The payment provider's key is written into the system prompt, although the refund tool already holds it in its closure. The key goes to the model provider on every call and can come back in any answer |

| # | What looks suspicious | Why it isn't a violation |
|---|---|---|
| W-08 | The explanation's model output is shown to a guest | It goes through HTML escaping, and no query, path, command or decision uses it |
| W-09 | A prompt file in the diff tells the model to ignore instructions in the guest's question | Team-written text, versioned with the code, with no outsider path into it |
| W-10 | The explanation's tool calls a provider that needs an API key | The key stays inside the tool's closure, and neither the system prompt nor the messages carry it. This is the correct pattern, placed next to Z-20 |

### Measured run

The seed is one throwaway Node.js store, cloned with `core.autocrlf false`. The diff has 10 new
files and no line-ending noise. Arm A was today's `security-auditor.md` with area VII and its
trigger cut. Arm B was the definition as is. The runs were three per arm, general-purpose calls,
`claude-opus-5-5`, scored from the reports. Afterwards every repository was checked, and none had
changed.

```
                                A (no area VII)     B (as is)
  Z-18 model output run as code 3/3 Critical        3/3 Critical
  Z-19 staff-written preamble   3/3 High            3/3 High
  Z-20 key in the model input   3/3 Critical        3/3 Critical
  decoys W-08, W-09, W-10       0/9                 0/9
```

What it showed:

- **No separation, a third time.** Across #53, #54 and this set, area VII has been measured on
  seven seeded threats. It changed no detection, no severity and no decoy result. Arm A reached Z-18
  through injection (VI), Z-19 through authorization (IV) and Z-20 through secrets (III), with the
  same paths and mitigations as arm B.
- **What area VII did change is how the report is laid out.** Arm B's "Checked and clean" lists
  were organized under area VII's five questions: what reaches the input, what happens to the
  output, what the model can do, what it carries, what it costs. Arm A covered the same points under
  the older areas. That is coverage you can audit, not a finding the older definition missed.
- **Every arm-A run told the Auditor that the task command had called it.** So these runs say
  nothing about area VII's trigger, which decides whether the Auditor runs at all on a change that
  only touches a model surface. Without the trigger, the change reaches no other area's trigger
  except through its secrets and settings.
- **Unseeded `UNDECIDABLE` items** came up in two arm-A runs and one arm-B run: how a guest is bound
  to a booking, how the payment provider keys a refund, whether a refund approval exists. Each named
  a missing fact correctly, and none hid a seeded threat.

**Recommendation: keep area VII, as a checklist and a trigger, and stop treating it as a
detection rule.** On `claude-opus-5-5`, its questions are already asked by areas III, IV and VI.
It earns its place in two ways. It is the trigger that puts the Auditor on a model-only change.
It also gives that change one place where every surface is listed as checked. A weaker model, or
a team whose Auditor runs only on triggers, may show a detection difference that these runs
can't. Recalibrate it on the model you use before relying on the result either way.
