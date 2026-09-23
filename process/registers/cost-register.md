# Role-cost register

> Format description. The register is a **directory, one file per role call**
> (`<cost-register-dir>/<date>_<task>_<phase>_<role>_<n>.json`), written by the task command right
> after each call as its own bookkeeping commit (`../task-command.md`, "After every role invocation").
> One file per row means two parallel tasks never conflict on it.

```json
{
  "date": "2026-09-23",
  "task": "B1-01",
  "phase": "verification",
  "role": "invariant-guardian",
  "model": "<model id the call actually ran on>",
  "invocation": "registered",
  "roles": "<fingerprint from step 0>",
  "complexity": "Medium",
  "tokens": 142318,
  "toolCalls": 27,
  "seconds": 512,
  "reworkCause": null,
  "notes": "boundary check: clean"
}
```

- `tokens`, `toolCalls`, `seconds` come from the call's usage data, never an estimate; missing →
  the string `"no data"`.
- `invocation` is `registered` or `general-purpose` (see the task command, "How you call a role") — calibration holds per mode.
- `complexity` (Low / Medium / High) is the driving agent's judgment, set **before** the call.
- `reworkCause` is filled only on a repeated run: the finding that caused it and which earlier role
  could have caught it.
- A fast-lane skip is a row with `"tokens": 0` and `"notes": "skipped: fast lane"`.

- `roles` is the fingerprint pinned at step 0; two rows of one task with different fingerprints mean
  it ran under two versions of the process.

To read it as one list, aggregate the directory, e.g. `jq -s '.' <cost-register-dir>/*.json`.

## Beyond tokens

Tokens say what the agents cost. Deciding whether to skip, merge or move a role needs what they
**caught** and what they **cost the human** too. Record, in the same directory:

- **Gate rows** — one per gate, when it is entered and when the human decided:
  `{"kind": "gate", "task": "B1-01", "gate": 2, "waitingSince": "<ISO time>", "decidedAt": "<ISO time>", "outcome": "merged"}`.
  Waiting time on the human is usually the longest line in the whole task.
- **Rework** — the `reworkCause` above, per repeated run.
- **Escapes** — a defect found after the merge, as a row naming the task that let it through and
  the role that should have caught it. Without it, skipping a role looks free.
- **Empty runs** — role runs with no finding on a task that later had one in that role's area;
  a cheap run that finds nothing isn't evidence the role is redundant.

Report distributions, not averages: **n, median (p50) and p90** per role and complexity. With the
spread seen in practice (an order of magnitude within one role), an average hides both the typical
run and the expensive tail — and under about ten measurements per cell, say so instead of drawing a
conclusion.
