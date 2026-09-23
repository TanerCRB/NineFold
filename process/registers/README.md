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
| [`architecture-sensitive-paths.md`](architecture-sensitive-paths.md) | Which directories are governed by which decisions | Architect proposes, human merges | Task command (fast lane), Architect |
| [`cost-register.md`](cost-register.md) | Format of the per-call cost rows (one file per row) | Task command, as a bookkeeping commit | Whoever tunes the process |
| [`gap-register.md`](gap-register.md) | Why this repository looks the way it does because the other side hasn't delivered yet | Developer proposes, human merges | Everyone reading the code |

After copying, replace the matching placeholders in the task command (`<cost-register-dir>`,
`<path-to-architecture-sensitive-paths-list>`, the register names in step 21) and in the role
definitions (`<decision-registry-path>`), so every role reads the same files.
