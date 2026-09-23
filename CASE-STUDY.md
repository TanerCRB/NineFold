# Case Study: Measurements and Worked Examples from the Source Project

This is the companion to [`FrameworkDoc.md`](FrameworkDoc.md). FrameworkDoc describes the **pattern** —
roles, gates, evidence, and the reasoning behind them. This file holds the **case study**: the
anonymized measurements and worked examples from the original project the pattern was extracted
from. All numbers are reproduced exactly as recorded in the source project's registries and logs,
dated as in the source; nothing here was recomputed or rounded. The caveats about what each set of
numbers does not prove are kept next to the numbers they qualify.

You do not need this file to understand or adopt the process — read it when you want to see what
the pattern cost and how it behaved on real tasks. Section references ("section 3", "section 5")
point to the numbered sections of FrameworkDoc.

---

## Actual cost in tokens — only what was actually measured

Every role run ends with an entry in the log: tokens consumed, number of tool calls, wall-clock time.
This is the same kind of evidence field as for code — "the role works" without a cost entry is a
claim without proof. Below are exclusively the numbers actually recorded in the calibration run log;
where the log is silent, the table says so explicitly, instead of estimating.

| Role | Measured cost | Measurement source |
|---|---|---|
| Architect (impact map, one run) | ~137k tokens, 37 tool calls, ~10 min | calibration run |
| Guardian, run A | ~112k tokens, 16 tool calls, ~7 min | calibration run (seeded set) |
| Guardian, run B | ~89k tokens, 15 tool calls, ~6 min | calibration run (clean set) |
| Reviewer (one run) | 208,588 tokens, 35 tool calls, 13 min 12 s | calibration run |

The log summarizes, with its own order of magnitude, only one role: **"one Guardian audit is
~100k tokens and a few minutes."** The same entry adds scale context: at ten pull requests a week,
this is a noticeable line item, but not a dominant one. The day on which the Architect was measured
closes with a total of **~340k tokens across three agent runs combined** — the Architect is described
in the log as more expensive than the Guardian, because it reads more broadly and across many
documents at once.

**What this table does not prove:** for the Product Owner, Analyst, Developer, QA, and Security
Auditor, the log contains no separate cost entries — these roles had (as of this document's writing)
no calibration run of their own with recorded token usage. The four measured values also come from
**calibration runs on prepared test material**, not from averaging many production tasks under
day-to-day working conditions — so they are a reliable reference point for the order of magnitude of
a single run of a given role, not a measured average from the population of real tasks.

**Closing this gap was launched, not just noted.** The permanent cost registry set up for it — fed
automatically from real work, with a complexity column — is described in
[FrameworkDoc section 6](FrameworkDoc.md#measuring-the-cost-of-roles). The next section is what it
showed.

## Results after gathering material from production work

Status as of the date this update was written (2026-09-13). The backend registry has **578 rows**
(571 with a recorded token count, 7 marked `no data` per the rule — instead of guessing), the
frontend registry **535 rows** (525 with a count, 10 `no data`). The ≥3-measurements-per-role
threshold has long been exceeded on both sides — the least-staffed role today is QA on the backend
side (n=53) and the Security Auditor on the frontend side (n=27, a role run conditionally, only when
the change touches authentication, the CI pipeline, dependencies, or secrets) — both far above the
reliability threshold from the previous update (back then n=2).

**Backend repository — 571 measurements, 112,954,564 tokens total, averaging 197,819 per role
call:**

| Role | n | Average (tokens) | Range (min–max) |
|---|---|---|---|
| Developer | 120 | 335,644 | 82,795 – 890,086 |
| Reviewer | 87 | 162,813 | 79,211 – 260,397 |
| Guardian | 80 | 157,685 | 83,041 – 294,522 |
| Analyst | 60 | 151,516 | 59,453 – 258,866 |
| Architect | 60 | 199,065 | 87,783 – 326,118 |
| Security Auditor | 56 | 136,447 | 60,075 – 244,575 |
| Product Owner | 55 | 124,642 | 67,003 – 194,007 |
| QA | 53 | 195,597 | 84,762 – 679,075 |

**Frontend repository — 525 measurements, 80,330,524 tokens total, averaging 153,011 per role
call:**

| Role | n | Average (tokens) | Range (min–max) |
|---|---|---|---|
| Developer | 108 | 281,831 | 62,808 – 1,155,954 |
| Reviewer | 90 | 136,263 | 62,934 – 239,757 |
| Guardian | 75 | 114,351 | 55,560 – 216,039 |
| QA | 65 | 142,404 | 79,095 – 302,270 |
| Architect | 58 | 111,524 | 61,394 – 192,730 |
| Analyst | 57 | 112,447 | 65,512 – 192,665 |
| Product Owner | 45 | 82,098 | 38,783 – 231,446 |
| Security Auditor | 27 | 119,417 | 75,302 – 198,288 |

**Additional breakdown: role × task complexity.** Cells with n below 3 are marked with an asterisk —
the spread in them is not yet distinguishable from single-task noise. At this sample size, only two
such cells remain (nine previously).

Values in the cells are the average number of tokens per run (not thousands).

| Role | Low | Medium | High |
|---|---|---|---|
| Developer (backend) | 211,730 (n=18) | 293,822 (n=30) | 384,048 (n=72) |
| Developer (frontend) | 204,188 (n=39) | 276,214 (n=25) | 353,843 (n=44) |
| Architect (backend) | 143,849 (n=6) | 194,154 (n=3) | 205,850 (n=51) |
| Architect (frontend) | 98,416 (n=18) | 120,148 (n=17) | 115,408 (n=23) |
| Analyst (backend) | 139,272 (n=3) | 137,417 (n=8) | 154,567 (n=49) |
| Analyst (frontend) | 115,312 (n=11) | 107,251 (n=18) | 114,661 (n=28) |
| Guardian (backend) | 159,209 (n=23) | 151,061 (n=26) | 162,109 (n=31) |
| Guardian (frontend) | 105,040 (n=35) | 103,488 (n=10) | 128,834 (n=30) |
| Reviewer (backend) | 154,212 (n=23) | 159,552 (n=19) | 168,586 (n=45) |
| Reviewer (frontend) | 127,334 (n=33) | 138,616 (n=12) | 142,184 (n=45) |
| QA (backend) | 163,214 (n=18) | 157,625 (n=8) | 228,437 (n=27) |
| QA (frontend) | 119,465 (n=19) | 151,540 (n=18) | 152,098 (n=28) |
| Product Owner (backend) | 104,863 (n=1)* | 127,402 (n=13) | 124,249 (n=41) |
| Product Owner (frontend) | 72,819 (n=21) | 77,778 (n=12) | 102,658 (n=12) |
| Security Auditor (backend) | 116,809 (n=9) | 132,761 (n=14) | 143,366 (n=33) |
| Security Auditor (frontend) | 121,213 (n=8) | 127,017 (n=2)* | 117,677 (n=17) |

**What the data shows, that the documentation could not establish before:**

- **The Developer is the most expensive role on both sides, by a large margin** — consistent with the
  role description in [FrameworkDoc section 3](FrameworkDoc.md#3-actors-in-the-process) ("the only role with write access to production code"):
  implementation reads and writes the most of the eight roles.
- **The Product Owner is the cheapest role on both sides** — consistently, not by chance of a single
  measurement.
- **The correlation between complexity and cost, which looked imperfect on a small sample, turned out
  simply monotonic on a larger one.** The previous update described an anomaly: backend Developer at
  Low complexity (334,265, n=8) more expensive than at Medium (258,578, n=12). At n=18/30/72 this
  anomaly disappeared — cost rises in the expected direction (Low 211,730 < Medium 293,822 < High
  384,048), the same on the frontend side (204,188 < 276,214 < 353,843). Conclusion: the spread that
  at n around 10 looked like an inverted relationship was small-sample noise, not a real cost
  feature — exactly what the registry itself warned about from its very first row.
- **The spread within the same role can be larger than the difference between roles.** Backend
  Developer: 82,795–890,086 (nearly an elevenfold range). Frontend Developer: 62,808–1,155,954 (over
  an eighteenfold range, above the previous measurement). This confirms the caveat recorded in the
  registry itself, quoted in [FrameworkDoc section 6](FrameworkDoc.md#measuring-the-cost-of-roles): the spread between rows of the same role is
  expected, not a measurement error — even with a full set of measurements, the spread is often on
  the order of many-fold, not percentages.
- **The order-of-magnitude cost is comparable between repositories for the same role** (e.g.,
  Reviewer: 162,813 backend / 136,263 frontend; Guardian: 157,685 / 114,351), despite the different
  underlying technology stack — suggesting that the cost of these roles is more a function of the
  **volume of material to read and rules to check** than of the specific technology.

## Example: the cost of one task tracked from ticket to merge (backend)

The following run is one specific, real, medium-complexity backend task, chosen from the registry
because it went through **the full set of roles all the way to final approval** — including one
corrective iteration, which in day-to-day work is the norm, not the exception.

| Step | Role | Tokens | Tool calls | Time |
|---|---|---|---|---|
| 1 | Product Owner | 92,561 | 27 | 13 min 16 s |
| 2 | Analyst | 116,077 | 23 | 5 min 34 s |
| 3 | Architect | 109,302 | 16 | 6 min 37 s |
| 4 | Developer (implementation) | 327,994 | 132 | 55 min 26 s |
| 5 | QA (mutations) | 156,189 | 49 | 22 min 42 s |
| 6 | Guardian | 117,809 | 28 | 9 min 25 s |
| 7 | Reviewer → **STOP** (two real findings) | 178,341 | 55 | 16 min 35 s |
| 8 | Developer (fixes after review) | 327,728 | 53 | 51 min 47 s |
| 9 | Guardian (re-audit after fixes) | 126,885 | 31 | 11 min 37 s |
| 10 | Reviewer (re-review) → **PASS** | 175,339 | 42 | 13 min 27 s |

**Total: 1,728,225 tokens, 456 tool calls, about 3 hours 26 minutes** of role time, across ten calls
and seven unique roles — the Security Auditor did not appear, because the task did not touch any of
the conditions triggering it ([FrameworkDoc section 3](FrameworkDoc.md#3-actors-in-the-process)).

This total covers **exclusively the layer of expert roles** called as separate assignments — it does
not include the work of the agent driving the whole task (reading the ticket, writing commits,
calling the tracking system's tools, waiting for automatic CI gates), because that work does not
generate its own row in the cost registry.

**The price of one corrective iteration, counted directly.** Had the Reviewer approved the change the
first time (step 7), the task would have closed at step 7 with a total of **1,098,273 tokens** — one
round of "go back, fix, re-verify" (steps 8–10) added **630k tokens, close to 60% of the task's total
cost**. This is the countable price of what [FrameworkDoc section 5](FrameworkDoc.md#5-the-three-human-gates--why-these-specifically) calls the principle "it's cheaper to stop
earlier than later" — here not as a general claim, but as a concrete difference: finding the same
flaw at the Guardian stage instead of the Reviewer stage, or during implementation altogether, would
have saved more than the cost of the role that would have caught it earlier.

## Example: the cost of one task tracked from ticket to merge (frontend)

A twin run on the frontend side — also a real task, chosen for the same reason (full set of roles,
one corrective iteration). It has an additional feature worth showing: it ends not with clean
agreement, but with an **explicitly named dispute between two evaluating roles**, handed to the human
for resolution instead of being resolved automatically by either of them.

| Step | Role | Tokens | Tool calls | Time |
|---|---|---|---|---|
| 1 | Product Owner | 48,906 | 2 | 24 s |
| 2 | Architect | 82,896 | 6 | 66 s |
| 3 | Analyst | 192,665 | 20 | 268 s |
| 4 | Developer (implementation, 15 files) | 169,208 | 129 | 1617 s |
| 5 | QA (mutations) | 147,427 | 34 | 361 s |
| 6 | Guardian | 112,036 | 25 | 344 s |
| 7 | Reviewer → **STOP** (two medium findings) | 156,153 | 16 | 244 s |
| 8 | Developer (fixes after review) | 80,364 | 21 | 344 s |
| 9 | Reviewer (re-review) → **PASS, one contested point** | 124,262 | 28 | 2126 s |
| 10 | Guardian (re-audit) → **PASS, in disagreement with the Reviewer** | 168,890 | 35 | 2214 s |

**Total: 1,282,807 tokens, 316 tool calls, about 2 hours 7 minutes** of role time, across ten calls
and seven unique roles — the Security Auditor again did not appear, for the same reason as in the
backend example.

**The price of the iteration here is relatively lower, but more costly in time.** Without the
iteration (steps 1–7), the total would have been **909,291 tokens** — steps 8–10 added **373k tokens,
about 29% of the total cost**, less than in the backend example (there ~60%), because the developer's
fix was small (4 files). But those same three steps took **over 44 minutes out of the full 2 hours
7 minutes** — both re-verifying roles read the source UX audit document in full, not just the
fragment they had cited before, in order to resolve the dispute on the merits, not by repeating the
previous assessment.

**A dispute that didn't disappear, it just landed where it should.** The Reviewer and the Guardian
read the same code and the same reference documentation and drew **opposite conclusions** about the
severity of one finding (whether reading a single resource through a mock that returns a uniform
error for everything justifies changing the error message, or not) — both agreed on the facts,
disagreed on the risk assessment. Neither role has the mandate to overrule the other. The registry
records this as an explicitly named dispute, not as a silent resolution in favor of the last opinion —
exactly in line with the rule from [FrameworkDoc section 5](FrameworkDoc.md#5-the-three-human-gates--why-these-specifically): a risk assessment in which two specialized roles reach
different conclusions on the same facts is precisely the kind of decision the process **does not
automate**, but hands to the human with the full context of both positions.

---

## Documented cases: a tool returns success while being wrong

The failure pattern described in [FrameworkDoc section 9](FrameworkDoc.md#failure-pattern-a-tool-returns-success-while-being-wrong) — **a tool finishes with a
success code, despite having done something other than intended** — was derived from these
documented cases:

- A tool copying role definitions (see [FrameworkDoc section 3](FrameworkDoc.md#3-actors-in-the-process)) returned versions a dozen-odd commits older,
  reporting full success — caught only because the process requires the sync report to explicitly
  state what exactly was read, not just whether the operation succeeded.
- A safeguard in the CI pipeline was guarding the wrong event — from the outside it looked deployed
  and active, but it let through exactly what it was supposed to protect against.
- A label manifest lost national characters through triple text re-encoding along the way.
- A writing task's working directory was created under a path excluded from the code formatter's
  reach — the formatting check came back green because it scanned zero files from that task, not
  because the files were actually formatted correctly.
- A one-off text-replacement script in the code **rewrote itself and its own check** — after it ran,
  the check was already looking for the new name instead of the old one, and reported the state as
  clean.
- A text-replacement rule skipped files because of the wrong slash direction in a path, and reported
  "no changes" instead of an error.
