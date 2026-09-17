# Product repository settings

A list of things that must be the same in every production repository, and those that
**deliberately** differ. A GitHub setting leaves no trace in the repository and can't be reviewed
in a diff — that's why this document describes the **target state**, and the "check" column says
how to tell it apart from the actual state.

---

## 1. Merging and housekeeping

| Setting | Value | Why |
|---|---|---|
| `delete_branch_on_merge` | **`true`** | Without it branches remain after merging, and after a week you can't tell which carry work and which are trash. |
| `allow_merge_commit` | **`true`** | See below — a trade-off worked out after real squash mishaps. |
| `allow_squash_merge` | `true` | For minor things: one commit, one fix. |
| `allow_rebase_merge` | `false` | The third method doesn't add anything the first two don't, and it multiplies the ways history can come out differently than someone expected. |
| `allow_auto_merge` | `false` | Merging is gate 2 — a human decision, not the result of a green status. |

```bash
gh api repos/<owner>/<repo> -q '"delete_branch_on_merge="+(.delete_branch_on_merge|tostring)+" merge="+(.allow_merge_commit|tostring)+" squash="+(.allow_squash_merge|tostring)+" rebase="+(.allow_rebase_merge|tostring)'
gh api -X PATCH repos/<owner>/<repo> -f delete_branch_on_merge=true -f allow_merge_commit=true -F allow_rebase_merge=false
```

### Why merge commit, not squash alone

Squash-only looks tidy: one commit per task, a clean line in `main`. The cost isn't visible until
another branch lives alongside it.

Squash creates a **new commit that is not an ancestor of the branch** it came from. The work is
in `main`, but git doesn't know it. Consequences worth knowing before choosing:

1. **Merging `main` into a live branch produces a conflict on every file from the previous pull
   request.** Not because anyone changed them — because git sees two independent histories of the
   same content. Resolving "in favor of main" then silently reverts work done later on the
   branch.
2. **`git branch --merged` lies.** A fully merged branch shows commits "ahead of `main`", so it
   can't be safely deleted based on that command alone — you have to compare content
   (`git diff main branch`), which happens manually or not at all.
3. **Squash takes the head remembered when the merge window was opened.** A commit pushed in the
   meantime disappears without a trace from the pull request — it looks merged, because the PR is
   closed.

Merge commit has none of these three properties. The history is denser, and that's its only cost.

**Rule of thumb:** merge commit for a pull request carrying more than one commit or open longer
than one day; squash for one-off fixes.

If linear history matters to you more than the three pitfalls above (e.g. you have
backward-compatibility harnesses assuming `HEAD^` == previous version), squash-only remains a
valid choice — just make sure to set `squash_merge_commit_message=PR_BODY`, because the default
`COMMIT_MESSAGES` concatenates **all** of the branch's commit messages, including ones that
reverted earlier commits on that same branch.

### Before deleting a branch after squashing

As long as there are squashes in the history, `ahead_by` from the API and `git branch --merged`
don't answer the question "does this branch carry anything `main` doesn't have". Content answers
it:

```bash
git diff --stat origin/main origin/<branch>     # empty = safe to delete
git diff origin/main origin/<branch> | grep '^+' | grep -v '^+++'   # what the branch has that main doesn't
```

---

## 2. Branch protection

**Unavailable on the free plan for private repositories.** The API responds
`403 Upgrade to GitHub Pro` both for `branches/main/protection` and for `rulesets`.

The substitute is the `pre-push` hook (section 4, and
[`branch-protection-without-paid-plan.md`](branch-protection-without-paid-plan.md) in full). It
must say this outright, and it does: it can be bypassed with `--no-verify`, and it doesn't work
for anyone who hasn't installed it.

When the plan changes, the settings to apply are: required status checks, a ban on force-pushing
`main`, a ban on deleting `main`. Required status checks have one precondition — see
[`ci-and-branch-protection.md`](ci-and-branch-protection.md) §1.

---

## 3. Pipeline

| Thing | Value | Why |
|---|---|---|
| `runs-on` | an expression using `vars.CI_RUNNER`, never a literal label | A literal label gets copied to the next job without a decision about where it should run — and it kills the emergency fallback to the provider when your own hardware is down |
| path filter on `push` | yes | Saves time on the shared runner |
| path filter on `pull_request` | **no, deliberately** | A workflow skipped by the filter reports **no** status at all. A required check then waits forever, and the symptom looks like a GitHub outage rather than a misconfiguration |
| `workflow_dispatch` | yes | A webhook can fail to arrive. Without this there's no run to retry, and the only recourse is closing and reopening the pull request |
| `permissions` | `contents: read` | The repository's default `GITHUB_TOKEN` permissions should also be `read` |
| `concurrency` | cancels PR runs, doesn't cancel `main` | The `main` run is evidence for the merged state |
| actions | pinned to commit identifiers | A label points to whatever its author has currently put under it, and the action runs inside our run |
| "announce runner" step | first in every job | The log, not a reconstruction from a file, should answer "where did this run" |

```bash
gh api repos/<owner>/<repo>/actions/permissions/workflow -q '.default_workflow_permissions'   # read
gh workflow list -R <owner>/<repo> --all
```

### Splitting into workflows

A separate workflow for documentation validation, a separate one for build and tests. The reason
isn't aesthetic: a pull request touching only `docs/` has no reason to run a build or browsers,
and with **one shared self-hosted runner**, every job queues behind the previous one.

### Runner watchdog — mandatory with self-hosted

A repository moved to a self-hosted runner **must** get a separate watchdog workflow, which
**must** run at the provider (not on the same self-hosted runner it's watching). A watchdog on
the observed machine stays silent exactly when that machine is the problem — and without an
external witness, a runner can go down in a way that it fails to deregister: GitHub keeps showing
it as present for many hours, and checks report **no status**, not failure.

Requires a token with read access to organization runners. `GITHUB_TOKEN` can't do this — it's
scoped to the repository, while the runner is registered at the organization level, so the API
responds 403 and the watchdog would report a failure that doesn't exist. Permission: *Organization
→ Self-hosted runners → Read-only*. This is **not** the same token as the runner's registration
token — that one needs *Read and write* and has its own, separate expiration date.

Set yourself a reminder for the watchdog token's expiration date — after that date the watchdog
will start failing with a missing-secret message and — deliberately — **will not create an
Issue**, because a missing secret is not a runner failure. Symptom without a reminder: a red
"Runner watchdog" run every few hours and silence in Issues.

With multiple repositories on one runner: **each one gets its own watchdog**, because that's
where the pull requests that stopped getting a status are standing. Schedules offset from one
another detect an outage on average faster than one shared poll, at the same cost per repository.

---

## 4. Hooks

One source: [`hooks/pre-push`](hooks/pre-push). The refusal to push to `main` is shared; the
block running tests turns itself on wherever the root `package.json` declares a `test` script.
The condition is on the presence of the script, not the repository name — a name would require
updating for every new repository and would silently skip whichever one gets forgotten.

Installation is the one difference that can't be hidden in the file:

| Repository | Mechanism | Installation |
|---|---|---|
| without npm | `core.hooksPath` | `git config core.hooksPath .githooks` |
| with husky | `prepare` in `package.json` | the file ends up at `.husky/pre-push`, husky wires itself in |

The hook must be executable (`100755` in the index) and have LF line endings. `#!/usr/bin/env sh`
with a returned carriage return ends up with "bad interpreter" — the hook present, wired up, and
letting every push through.

---

## 5. Distributed from the process source repository

| What | Tool | Notes |
|---|---|---|
| Issue forms | `tools/sync-github.mjs` | Shared, repository-independent by design |
| Pull request template | `tools/sync-github.mjs` | **Per repository** — override in the `overrides` field. The invariants checklist must be checkable, otherwise it teaches people to scroll to the end |
| Labels | `tools/sync-github.mjs --labels-ps1` | Subset in the `labels` field. A label describing a state a repository doesn't carry isn't harmless — an Issue will get stuck in it |
| Role definitions | `tools/sync-agents.mjs` | **Per repository** — directory in the `dir` field. A role has the same name, differs in what it watches over |
| `pre-push` hook | manually | See section 4 |

---

## 6. Deliberate differences that should stay

- **The agent tool's config directory does not enter the product repository** and is not subject
  to its checks. A content check reading a git-ignored directory reports things that aren't
  there.
- **The pull request template and role definitions differ in content**, not mechanism. Backend
  watches over data isolation and migrations, frontend over theme tokens and the navigation
  boundary. A shared list where half the fields can't be checked is worse than two lists.
- **The frontend hook may run tests, the backend hook doesn't have to.** Not out of neglect:
  backend may have no `package.json` in its root directory, and its tests may need containers and
  take minutes. Changing this is a separate decision.

---

## Checklist for a new repository

1. `delete_branch_on_merge=true`, `allow_merge_commit=true`, `allow_rebase_merge=false`.
2. Default `GITHUB_TOKEN` permissions on `read`, without pull-request approval rights.
3. `tools/sync-github.mjs` — add the target, set `templates`/`labels`/`overrides`, run it.
4. `tools/sync-github.mjs --labels-ps1` and execute the generated script.
5. `tools/sync-agents.mjs` — add the target with its own definitions directory, if the repository
   is a production one.
6. The hook from `hooks/pre-push`, mechanism per section 4; check the executable bit and line
   endings.
7. Workflow: `runs-on` as an expression, `workflow_dispatch`, path filter only on `push`.
8. With self-hosted: a watchdog workflow at the provider plus a secret with a runner read token.
9. Check that `.gitattributes` forces LF on everything copied from this repository.
