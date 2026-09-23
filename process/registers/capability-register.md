# Capability register

> Template. Answers one question only: **what can the system actually do, and what proves it.**
> Architectural decisions say what was agreed; this register says what exists. A first pass that
> comes out mostly "no evidence" is the correct result, not a failure (`../../FrameworkDoc.md`,
> section 7).

Allowed evidence values — nothing else:

- **mutation-tested** — a test that was shown to fail when the mechanism is removed (row below);
- **test** — a test exists, but no mutation has shown it can fail;
- **manual <YYYY-MM-DD>** — checked by hand on that date;
- **none**.

| Capability | Evidence | Where | What this does not prove |
|---|---|---|---|
| <e.g. A user of one tenant cannot read another tenant's orders> | mutation-tested | `<test name>` | <e.g. says nothing about exports, which bypass the API> |
| <capability> | none | — | — |

## Mutations

One row per mutation QA ran. A survived mutation stays in the table with how the test was fixed —
that record shows what the test really guards.

| Task | Removed mechanism | Result | Patch |
|---|---|---|---|
| <B1-01> | <what was removed, specifically> | <N tests failed — what that means; or SURVIVED — why, and the fix> | <link to the patch in the PR> |
