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

To read it as one list, aggregate the directory, e.g. `jq -s '.' <cost-register-dir>/*.json`.
