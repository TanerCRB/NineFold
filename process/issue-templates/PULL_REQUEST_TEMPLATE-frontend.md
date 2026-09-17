<!--
Gate 2. A human approves the merge — this template exists so they approve
with proof in hand, not from the author's description.

Leave an unfilled field empty and write why. An entry of "not applicable" without justification is
worse than empty, because it looks like it was checked.

This is the version for the frontend repository. The backend has its own, with an invariant list
about data isolation and migrations — the source of both is in the process source repository,
process/issue-templates/.
-->

Closes #

## What is changing and why

<!-- Why, not just what. One to three sentences. -->

## Definition of done — proof

<!--
Quote the _Definition of done:_ line from the story or from a phase in the frontend roadmap and point to
what satisfies it: a test name, an artifact, a command result. Code that exists but has no passing
test does not check off the task.

A screenshot is not proof. It shows one theme, one locale, one data state, and one
window width — and it is usually the other half of each pair that breaks.
-->

- Condition:
- Proof:

## Mutation

<!--
Required if the PR carries a strong claim: that a screen does NOT show something, that it denies,
that it does not miscalculate, that it does not drop the locale. Remove the mechanism, confirm that
the test actually fails, and add a line to the frontend state register.

The mutation should target the layer the criterion is about. Removing a key from the translation
catalog is not a mutation for a claim computed by the date library.
-->

- Removed mechanism:
- Result:
- Line in the frontend state register:

## Contrast test

<!--
An assertion without contrast also passes when the mechanism blocks everything. A screen rendering
an empty list satisfies "no items outside scope are visible" flawlessly and forever.

What case proves that the mechanism does not simply always deny? A 200 response gives a table where
a 403 gives a screen with no buttons.
-->

## Invariant Guardian report

<!-- Verdict PASS / STOP. On STOP — what was done with the findings. -->

## Dependency on the backend

<!--
What this PR takes from the backend repository, and how you know it actually looks that way — the date
and method of verification in the integration document, not just "the contract is in src/contracts/."

If the PR exposes a gap: is there an entry in the gap register with a **Reported:** field, and is
there a corresponding Issue in the backend repository. An entry on your own side orders nothing.
-->

## Invariants affected by this change

<!--
Check what the change affects. Unchecked = not applicable.

The list below is an EXAMPLE — replace the items with your own frontend invariants. They all
share one trait worth preserving when adapting this: breaking them still renders
correctly. Nothing throws an exception, so the only defense is this list and a test.
-->

- [ ] New color — through a theme token, no hex outside the centralized source
- [ ] Change in theme determination — the bootstrap script stays before hydration
- [ ] New API response type — only in the contracts layer, nowhere else
- [ ] Contract tied to a real resource — date and method of verification in the integration document
- [ ] New UI text — in the translation catalog, not in the component
- [ ] New spot with a date/amount — through the shared formatting library, not by hand
- [ ] A set spanning multiple currencies/timezones — no single combined total without a warning
- [ ] New navigation — through the shared routing wrapper, not directly through the framework's API
- [ ] New deep link — read once, as a mount effect, not on every refresh
- [ ] New menu item or tab without a route — `disabled` with a tooltip, not hidden
- [ ] New denial code — in the list of known codes with a translation
- [ ] New data-reading screen — denial on the preflight request gives a screen with no action buttons
- [ ] New section in the gap register — carries a `**Reported:**` field with a link, or with `no — <reason>`

## Out of scope for this PR

<!-- What is deliberately left for later, and where that is recorded. -->
