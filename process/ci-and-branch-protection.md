# Branch protection and CI on pull request

Concerns running CI on `pull_request` and (when the plan allows it) protecting the `main` branch.

`tools/sync-github.mjs` deliberately does not touch the `workflows/` directory: changes there and
in repository settings are decisions with consequences, so they go through review, not through a
script.

---

## 1. Pitfall one: path filter versus required check

This is the single reason branch protection isn't just a click in settings.

A workflow with a `paths` filter on the `pull_request` trigger works fine, until someone marks
its jobs as required checks. **The moment you do that, a PR touching only paths outside the
filter stops being mergeable** — and not with an error, just hanging forever.

Mechanism: a workflow skipped by a path filter **reports no status at all**. It doesn't report
success, it doesn't report failure — it simply stays silent. GitHub waits for a status that will
never come, and shows `Expected — Waiting for status to be reported`. GitHub's documentation says
this outright: *"If a workflow is skipped due to path filtering (…) checks associated with that
workflow will remain in a »Pending« state. A pull request that requires those checks to be
successful will be blocked from merging."*

### Solution variants

**Variant A — remove the path filter from `pull_request`. Recommended for small teams.**

A change of a few lines: removing the `paths` key from the `pull_request` section. The `push`
section can stay unchanged — `push` isn't subject to required checks, so the filter still saves
runs there.

```yaml
on:
  push:
    paths:
      - 'src/**'
      # ... unchanged
  pull_request:          # no paths filter — the required check must always report a status
```

Cost: a PR changing only documentation runs the full test suite. A few minutes of machine time
per PR, at a scale of a dozen to several dozen PRs a month.

Benefit: no extra machinery to maintain. The check either passed or it didn't — there is no third
state.

**Variant B — the filter moved from the trigger to the jobs.**

The workflow always runs, the first job computes what changed, and the heavy jobs are gated by
`if:`. A job skipped by `if:` **reports a `skipped` status**, which GitHub counts as success —
unlike a workflow skipped by `paths`.

It has its own pitfall, though, which needs to be closed explicitly: a job skipped because **its
dependency failed** also reports `skipped`. Without an extra gating job, a run in which the
change-detection step blew up would look like a clean run.

```yaml
on:
  pull_request:          # no paths filter

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      code: ${{ steps.detect.outputs.code }}
      docs: ${{ steps.detect.outputs.docs }}
    steps:
      - uses: actions/checkout@<sha> # pinned to a commit identifier, not a tag
        with:
          fetch-depth: 0
      # No third-party action here: a path filter is three lines of git, and every external
      # action is one more immutable identifier to keep watch over.
      - id: detect
        run: |
          git fetch --no-tags --depth=1 origin "${{ github.base_ref }}"
          changed=$(git diff --name-only "origin/${{ github.base_ref }}...HEAD")
          code=false; docs=false
          grep -qE '^(src/|tests/)' <<<"$changed" && code=true
          grep -qE '^(docs/|tools/)' <<<"$changed" && docs=true
          echo "code=$code" >> "$GITHUB_OUTPUT"
          echo "docs=$docs" >> "$GITHUB_OUTPUT"

  build-and-test:
    needs: changes
    if: needs.changes.outputs.code == 'true'
    # ... rest unchanged

  # The only required check. Without it, a job skipped because `changes` FAILED
  # would report `skipped` and count as success — the run would look green exactly
  # when it broke.
  gate:
    needs: [changes, build-and-test]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: Fail when any required job did not succeed or skip cleanly
        run: |
          [[ "${{ needs.changes.result }}" == "success" ]] || exit 1
          [[ "${{ needs.build-and-test.result }}" =~ ^(success|skipped)$ ]] || exit 1
```

In variant B, the required check is **only `gate`**, never `build-and-test`.

### Recommendation

**Variant A**, as long as the full test run takes a reasonably short time and the team is small.
Variant B saves machine minutes at the cost of several places where a silent mistake can be made
— and each of them fails in the direction of "looks green". Variant B starts to make sense only
once the full run reaches a quarter of an hour and genuinely gets in the way.

---

## 2. Pitfall two: you cannot approve your own pull request

The natural branch-protection setting is "require one approval before merging". **With a single
author (you plus agents operating on your account), this will lock the repository.**

GitHub does not let an author approve their own PR. If agents operate within your session, on
your account, you will be the author of every PR. A one-approval requirement means you won't
merge anything until a second person shows up, or you'll start working around your own rule — and
a rule that's routinely worked around stops being a rule and starts being noise.

**Solution: don't require approval. Require a pull request and green checks.**

Gate 2 is then your conscious click of "Merge" — after reading the diff, the Invariant Guardian's
report, and the mutation result from the PR template. Formal approval would add nothing beyond
the click.

Return to the approval requirement once one of two things happens: a second person joins, or
agents start operating on their own technical account (at that point you are the reviewer, not
the author, and the requirement becomes a real gate).

---

## 3. Commands to run

Require `gh auth login` with repository administrator rights. Substitute `<owner>/<repo>`.

```bash
# 1. Labels — from the manifest, idempotently
node tools/sync-github.mjs --labels | bash

# 2. Issue and PR templates — files tracked by git, review and commit yourself
node tools/sync-github.mjs

# 3. main branch protection (requires a paid plan on a private repository — see
#    branch-protection-without-paid-plan.md if you get a 403)
gh api -X PUT repos/<owner>/<repo>/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["build-and-test", "validate"]
  },
  "required_pull_request_reviews": null,
  "enforce_admins": false,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
```

What each field means and why exactly that:

| Field | Value | Why |
|---|---|---|
| `contexts` | names of **jobs**, not workflows | GitHub identifies a check by job name, not by file name or the workflow's `name:` field |
| `strict` | `true` | The branch must be up to date with `main` before merging — otherwise green checks pertain to a state that won't land |
| `required_pull_request_reviews` | `null` | See §2 — an approval requirement would lock the repository with a single author |
| `enforce_admins` | `false` | Deliberately: you must be able to merge your own PR. This is gate 2, not a workaround |
| `required_linear_history` | `true` | Backward-compatibility harnesses typically assume that a commit's parent is the previous version of the application, not the other side of a merge |
| `required_conversation_resolution` | `true` | A Guardian report pasted as a comment must be resolved, not scrolled past |
| `allow_force_pushes` | `false` | A forced push to `main` overwrites the evidence the register rests on |

**Verification after applying** — without it it's just a declaration:

```bash
git push origin main        # expected: protected branch hook declined

gh api repos/<owner>/<repo>/branches/main/protection | jq '{
  checks: .required_status_checks.contexts,
  strict: .required_status_checks.strict,
  reviews: .required_pull_request_reviews,
  linear: .required_linear_history.enabled
}'
```

`required_linear_history: true` requires that **squash merge** or **rebase merge** be enabled in
repository settings — with merge commit alone, nothing can be merged. See
[`repository-settings.md`](repository-settings.md) §1 for the trade-off between squash and merge
commit, worked out in practice.

---

## 4. Definition of Done (example)

| Criterion | Condition | How to check |
|---|---|---|
| Issue template enforces fields | A new Issue has *Definition of Done* and *Out of scope* as required fields | Create an Issue and try to submit with empty fields — the form won't let it through |
| `main` protection works | An attempt to push directly to `main` is rejected | `git push origin main` returns `protected branch hook declined` |
| Documentation validation blocks | A PR breaking validation has a red status and cannot be merged | A PR adding a document without a publication-list entry — the build must abort |

The last condition is worth carrying out literally, as a mutation: it's the only way to tell
"the check is required" from "the check works".

---

## Sources

- [Troubleshooting required status checks — GitHub Docs](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)
- [Linking a pull request to an issue — GitHub Docs](https://docs.github.com/en/enterprise-cloud@latest/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue)
- [About issue and pull request templates — GitHub Docs](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/about-issue-and-pull-request-templates)
