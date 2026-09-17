<!--
Gate 2. A human approves the merge — this template exists so they approve
with proof in hand, not from the author's description.

Leave an unfilled field empty and write why. An entry of "not applicable" without justification is
worse than empty, because it looks like it was checked.

Base version (e.g. for backend). The frontend/infra variants have their own invariant lists —
see PULL_REQUEST_TEMPLATE-frontend.md and PULL_REQUEST_TEMPLATE-infra.md in this directory.
-->

Closes #

## What is changing and why

<!-- Why, not just what. One to three sentences. -->

## Definition of done — proof

<!--
Quote the *Definition of done:* line from the story and point to what satisfies it: a test class
name, a query, an artifact. Code that exists but has no passing test does not check off the task.
-->

- Condition:
- Proof:

## Mutation

<!--
Required if the PR carries a strong claim (isolation, idempotency, a database constraint, permissions).
Remove the mechanism, confirm that the test actually fails, and add a line to the mutation register
(e.g. docs/architecture/walking-skeleton.md#checking-that-tests-are-not-empty).
-->

- Removed mechanism:
- Result:
- Line in the mutation register:

## Contrast test

<!--
A negative test without contrast also passes when the mechanism blocks everything.
What case proves that the mechanism does not simply always deny?
-->

## Invariant Guardian report

<!-- Verdict PASS / STOP. On STOP — what was done with the findings. -->

## Invariants affected by this change

<!--
Check what the change affects. Unchecked = not applicable.

The list below is an EXAMPLE (backend with database-level tenant isolation) — replace the items
with your own invariants, derived from your architecture decisions. Keep the format:
one item = one rule checkable in the diff, with a link to the decision that established it.
-->

- [ ] New table — has row-level isolation enabled **and** enforced also for the owner, a policy, and a retention category
- [ ] New foreign key within a tenant — carries the tenant identifier
- [ ] New unique key — starts with the tenant identifier
- [ ] New database access — goes through the wrapper, transaction-local context
- [ ] New state-changing command — has conditional commit (`If-Match`) and a content-bound idempotency key
- [ ] New time column — with timezone or a date, never a type without a timezone
- [ ] New permission — has a denial case in the tests
- [ ] New document in the architecture directory — added to the publication list

## Out of scope for this PR

<!-- What is deliberately left for later, and where that is recorded. -->
