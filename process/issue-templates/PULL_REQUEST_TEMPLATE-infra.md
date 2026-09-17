<!--
Gate 2. A human approves the merge — this template exists so they approve
with proof in hand, not from the author's description.

Leave an unfilled field empty and write why. An entry of "not applicable" without justification is
worse than empty, because it looks like it was checked.

This is the version for the infrastructure repository. The backend and frontend have their own, with
invariant lists about data isolation, migrations, and theming — the source of all three is
in the process source repository, process/issue-templates/.

The difference that gives rise to a separate template: here there are no unit tests and nothing to
mutate in code. The proof is an **executed run on the environment**, and the most dangerous defects in this
repository do not break the build — they expose a service, leak a secret into history, or deploy a
version nobody can identify.
-->

Closes #

## What is changing and why

<!-- Why, not just what. One to three sentences. -->

## Definition of done — proof

<!--
Quote the *Definition of done:* line from the story and point to what satisfies it. The proof is
a command result or an artifact from the run — not a description of what should happen.

A screenshot of the running application proves that something is up. It does not prove that what is up
is what you think: without a visible revision of both parts, it is a screenshot of an unknown version.
-->

- Condition:
- Proof:

## A run performed, not described

<!--
A deployment is verified by deploying. Paste the result: bringing up the composition, a smoke
test run, response codes. A runbook nobody has walked through start to finish is
a proposal for a runbook.
-->

- Command:
- Result:
- Revisions on the environment (BE / FE):

## Counter-case

<!--
A check that always passes is not a check. The smoke test must fail when the service is
stopped; the network rule must deny a connection from outside the allowed network; composition
validation must stop a file with a typo.

What did you do to see red?
-->

## Invariants of this repository

<!--
Check what the change affects. Unchecked = not applicable.

The list below is an EXAMPLE — replace it with your own infrastructure invariants. They all
share one trait: breaking them **does not knock anything over**. The composition comes up, the service
responds, and the leak or irreproducibility surfaces weeks later.
-->

- [ ] New secret or password — in a file outside the repository (`*.env`), never in the composition file
- [ ] New service with a port — bound to the correct interface, not to all of them (`0.0.0.0`)
- [ ] New image in the composition — pinned by revision tag or digest, never `latest`
- [ ] Version change on the environment — revision of both parts visible in the UI, not only in a file
- [ ] New data — from the generator only; no customer data, not even "for a moment"
- [ ] Change touching the pipeline runner — no credentials within reach of the run
- [ ] New document describing the environment — also states **what it does not prove**

## What this deployment does not prove

<!--
Mandatory. The team's test environment does not raise statuses in the product repository's
register: it is not proof of the target deployment, it does not measure performance (it measures different
hardware), it does not prove uptime, and it does not lift compliance/data-retention blocks.

If this PR does prove something after all — write what, narrowly.
-->

## Out of scope for this PR

<!-- What is deliberately left for later, and where that is recorded. -->
