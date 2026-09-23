# Architecture-sensitive paths

> Template. Read by the task command's fast lane (`../task-command.md`, "Fast lane: when the
> Architect is skipped"): a task touching any path below always goes through the Architect. A path
> missing from this list is a path the fast lane will wave through — when in doubt, add it.

| Path (glob) | Governing decisions | Why it's sensitive |
|---|---|---|
| `<src/Data/**>` | <ADR-0003, ADR-0007> | <data isolation between tenants> |
| `<src/Auth/**>` | <ADR-0005> | <permission pipeline> |
| `<migrations/**>` | <ADR-0002> | <expand → deploy → contract> |
