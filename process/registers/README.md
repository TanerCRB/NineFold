# Registers — minimal templates

> Templates to copy into the product repository (e.g. under `docs/`) and adapt. They are the
> files the roles and the task command read and propose entries for; without them the first task
> stops at the Product Owner, who has no plan to check against. Keep the structure, replace the
> example rows.

The process keeps **what was decided**, **what the system can actually do**, and **what it cost**
in separate places on purpose (`../../FrameworkDoc.md`, section 7): an accepted decision is a
direction, not a capability, and a status is raised by evidence, not by conviction.

| Template | Holds | Who writes it | Who reads it |
|---|---|---|---|
| [`plan.md`](plan.md) | Tasks with a *Done when* condition and an explicit *Out of scope* | Human, at gate 3 (roles only propose entries) | Product Owner, Analyst, task command |
| [`capability-register.md`](capability-register.md) | What the system can do and what proves it, plus the mutation table | Human, at gate 3 | Analyst, Architect, Developer, QA, Guardian |
| [`decision-template.md`](decision-template.md) | One architectural decision; copy per decision into your decision directory | Architect drafts, human accepts | Architect, Product Owner, Reviewer |
| [`architecture-sensitive-paths.md`](architecture-sensitive-paths.md) | Which directories are governed by which decisions, and which risk classes they carry | Architect proposes, human merges | Task command (fast lane, Auditor trigger, gate 2) through `scripts/risk-check.sh`, Architect |
| [`cost-register.md`](cost-register.md) | Format of the per-call cost rows (one file per row) | Task command, as a bookkeeping commit | Whoever tunes the process |
| [`exception-register.md`](exception-register.md) | Findings let through gate 2 on purpose, each with an owner and a date after which it blocks again | Human, at gate 3 (the task command moves live exceptions from the PR) | `/task-status`, `scripts/exception-check.sh` |
| [`gap-register.md`](gap-register.md) | Why this repository looks the way it does because the other side hasn't delivered yet | Developer proposes, human merges | Everyone reading the code |

After copying, replace the matching placeholders in the task command (`<cost-register-dir>`,
`<path-to-architecture-sensitive-paths-list>`, `<exception-register>`, the register names in step
21; `<exception-register>` in the task status command too) and in the role
definitions (`<decision-registry-path>`), so every role reads the same files.
