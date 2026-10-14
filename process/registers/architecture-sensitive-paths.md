# Architecture-sensitive paths

> Template. The task command reads it through `scripts/risk-check.sh` (`../task-command.md`,
> "Fast lane: when the Architect is skipped", step 14 and gate 2). A task touching any path below
> always goes through the Architect, and its risk classes decide whether the Security Auditor runs
> and whether a surviving mutation may be let through. A path missing from this list is a path
> the fast lane will wave through — when in doubt, add it.

| Path (glob) | Risk classes | Governing decisions | Why it's sensitive |
|---|---|---|---|
| `<src/Data/**>` | <schema, personal-data> | <ADR-0003, ADR-0007> | <data isolation between tenants> |
| `<src/Auth/**>` | <auth> | <ADR-0005> | <permission pipeline> |
| `<migrations/**>` | <schema> | <ADR-0002> | <expand → deploy → contract> |
| `<src/Billing/**>` | <money> | <ADR-0009> | <invoices and refunds> |
| `<package-lock.json>` | <dependencies> | — | <the lock file> |
| `<.github/workflows/**>` | <pipeline> | <ADR-0004> | <who runs what, with which secrets> |

**One glob per row**, in backticks; `*` and `**` both match across directories. **Classes** are a
closed list, comma-separated:

| Class | Covers | The Security Auditor runs | A `SURVIVED` mutation may be excepted |
|---|---|---|---|
| `schema` | migrations, the data schema | yes | no — it is fixed |
| `auth` | authentication, authorization, isolation context, permission catalog | yes | yes |
| `money` | prices, invoices, payments, refunds | no | no — it is fixed |
| `personal-data` | files that read, store or send personal data | yes | yes |
| `pipeline` | CI/CD configuration, the runner | yes | yes |
| `dependencies` | package manifests, lock files, container images | yes | yes |
| `secrets` | configuration, environment variables, anything that looks like a secret | yes | yes |
| `external` | the adapter layer to external systems | yes | yes |
| `model` | code that calls a language model or defines its tools, prompt templates | yes | yes |

A class the script doesn't know fails the check (exit 2) instead of being ignored. If you add a
class, add it to `CLASSES` (and, where it applies, `AUDITOR_CLASSES` or `NO_EXCEPTION_CLASSES`) in
`scripts/risk-check.sh`, and a self-test case for it.
