# Guide: bootstrapping the framework on a new repository

> Anonymized synthesis of a real rollout run. Every step has a **check**, because most things
> here fail silently — it looks set up and lets things through. This is an instruction, not a
> story: the reasons why particular things look exactly the way they do are written down only
> where omitting them ends in undoing work.

**Time:** half a day for a smooth run, excluding the section on a self-hosted runner (see
section 5) — that one tends to be the longest, not because it's hard, but because every
unrecorded host dependency surfaces separately, and only after the run.

---

## 0. What you need before you start

| Thing | What for | Check |
|---|---|---|
| `gh` (GitHub CLI) authenticated | labels, templates, PRs, repository settings | `gh auth status` |
| Repository administrator permission | branch protection, merge settings | `gh api repos/OWNER/REPO --jq .permissions.admin` |
| Repository with a `main` branch | everything else assumes this name | — |

`gh` is sometimes installed and yet invisible on PATH — the Windows installer doesn't always
append the directory to the environment variable. Before concluding it's not there, check the
installation directory directly.

---

## 1. Labels and templates *(15 minutes)*

Source: [`labels.json`](labels.json), [`issue-templates/`](issue-templates/),
[`../tools/sync-github.mjs`](../tools/sync-github.mjs).

```bash
node tools/sync-github.mjs --labels | bash     # labels from the manifest, idempotently
node tools/sync-github.mjs                     # templates into .github/ — files tracked by git
```

**Check:** `gh label list` shows the labels from the manifest; a new Issue from the story
template cannot be submitted with an empty "Definition of Done" field.

### Pitfalls

**The label manifest must be in pure ASCII — names and descriptions.** The path `manifest → node
→ shell → gh` has places where Windows PowerShell 5.1 re-encodes text via the console code page —
a dash or a diacritical mark comes back from it as multi-byte garbage, and that's in label
descriptions, exactly where nobody looks. The sync script has an assertion that stops the run at
the first non-ASCII character — leave it in, don't work around it.

**Run both commands from the root directory of the process source repository** — that's where
the script looks for `process/` and resolves the `TARGETS` paths. The target of the labels is set
by an explicit `--repo` that the script puts on every generated `gh` call. Don't remove it: `gh`
by default infers the repository from the remote of the current directory, so without it the
labels would land **in the process repository itself**, silently, without error, because that too
is a valid repository.

---

## 2. State machine and gates *(a record, not a configuration)*

Source: [`sdlc-flow.md`](sdlc-flow.md), [`../TEAM-CONTRACT-TEMPLATE.md`](../TEAM-CONTRACT-TEMPLATE.md).

Three gates: **1** before code exists (scope and architecture), **2** before entering `main`
(diff, invariant-checking role's report, mutation result), **3** before raising the status in
the project register.

One thing worth repeating, because it looks like a formality: **gate 3 gets its own commit.** The
entry checking off a task or raising a decision's status travels separately from the code it
describes. An agent will always be inclined to treat its own work as evidence, and the entire
credibility of the register rests on the principle "status is raised by evidence".

### 2a. Documentation next to the code, not only in one root file

A single instructions file for the agent (e.g. a root `CLAUDE.md`) scales up to a point, and then
gets so long that an agent working in one module reads every other module's rules just to reach
its own. A pattern that holds up as the codebase grows: **keep the root file short and
navigational**, and give each module/screen/layer its **own local rules file** sitting physically
next to the code it covers — the root indexes them as a list of links, it doesn't copy their
content. An agent opening a specific module finds its rules in the same directory, without reading
everything else. Keeping this up takes discipline (new module = new file plus an index entry), but
the cost is lower than one file that grows without bound.

---

## 3. Protecting `main` without a paid plan *(20 minutes)*

Source: [`branch-protection-without-paid-plan.md`](branch-protection-without-paid-plan.md), [`hooks/pre-push`](hooks/pre-push).

Branch protection and GitHub rulesets **are not enforced on a private repository on the free
plan** — the API responds `403` to an attempt to set branch protection both through the classic
mechanism and through rulesets, with a message suggesting a paid plan.

### Why not "switch to public, set it up, switch back to private"

This is a natural reflex and it is wrong for two reasons:

- **The rules stop being enforced, but they don't disappear from the interface.** After switching
  back to private, GitHub leaves the configuration in place and stops applying it. You're left
  with the worst possible state: protection looks set up, and a direct push goes through.
- **A public repository, even for a minute, is irreversible.** Crawlers, forks, cached copies —
  if there is anything in the repository you don't want made public (a data model, architectural
  decisions, business logic), that risk is not worth saving a dozen or so minutes.

### The choice

| Variant | What it gives | Cost |
|---|---|---|
| Paid organizational plan | Real server-side protection: required checks, push ban, linear history | Subscription; grows with the number of people |
| `pre-push` hook | Denies a direct push to `main` on the machines where it's installed | Zero |
| Nothing | Discipline | Zero, until the first mistake |

Recommendation: **the hook now, the paid plan before letting in the first person other than
you.** The hook is enough as long as the only one committing is you and agents acting on your
account. It stops being enough once a second person shows up or agents get their own technical
account — then protection must live server-side, not in the configuration of one clone.

### Installing the hook

```bash
mkdir -p .githooks
cp <framework>/process/hooks/pre-push .githooks/
git add .githooks/pre-push
git update-index --chmod=+x .githooks/pre-push
git config core.hooksPath .githooks
```

**Into the target repository's `.gitattributes` — this is the load-bearing half, without it the
hook doesn't work:**

```
.githooks/** text eol=lf
```

Without this entry, under the rule `* text=auto`, a script written on Windows gets CRLF, and
`#!/usr/bin/env sh` with a returned carriage return ends up with a `bad interpreter`. The hook is
then **present, wired up, and lets every push through** — exactly the class of failure it's
supposed to protect against.

**Check, both commands, in this order:**

```bash
git config --get core.hooksPath     # -> .githooks
git push origin main                # -> refusal
```

The second is proof **only when you have a commit ahead of `origin/main`**. On a branch that's
already up to date, git finishes with `Everything up-to-date` before it even runs the hook — the
response looks like success and says nothing. Without a commit, test the hook's logic directly,
feeding it reference lines the way git does:

```bash
printf 'refs/heads/x 1 refs/heads/main 2\n' | .githooks/pre-push origin url; echo "code=$?"    # 1
printf 'refs/heads/x 1 refs/heads/feature/x 2\n' | .githooks/pre-push origin url; echo "code=$?" # 0
```

The second line is a counter-test — without it "denies on `main`" would also be satisfied by a
hook that always denies, regardless of branch.

**What the hook doesn't give:** nothing server-side. `--no-verify` goes through, another clone
without `core.hooksPath` doesn't have it at all, it doesn't enforce required checks before
merging. This is a **guard, not a gate**, and should be described that way everywhere it's
mentioned.

---

## 4. Merge settings and repository hygiene *(20 minutes)*

Source: [`repository-settings.md`](repository-settings.md), [`ci-and-branch-protection.md`](ci-and-branch-protection.md).

### Squash, merge commit, or rebase

**Squash merge alone looks tidy — one commit per task, a clean line in `main` — but it has a
hidden cost, visible only once another, still-open branch lives alongside it.** Squash creates a
**new commit that is not an ancestor of the branch** it came from. The work is in `main`, but git
doesn't know it. Consequences, observed in practice:

1. **Merging `main` into a live branch produces a conflict on every file from a previously
   merged PR** — not because anyone changed them, but because git sees two independent histories
   of the same content. Resolving "in favor of main" then silently reverts work done later on
   that branch.
2. **`git branch --merged` lies.** A branch fully merged via squash still shows commits "ahead
   of `main`", so it can't be safely deleted based on that command alone — you have to compare
   content (`git diff main branch`).
3. **Squash takes the branch head as remembered when the merge window was opened.** A commit
   pushed in the meantime can vanish without a trace — the pull request looks fully merged, and
   isn't.

A merge commit has none of these three properties. Its only cost is a denser history.

**Rule of thumb:** merge commit for pull requests carrying more than one commit or open longer
than one day; squash for one-off, minor fixes. Rebase merge is usually worth disabling entirely
— the third method doesn't give anything the first two don't, and it multiplies the ways history
can come out differently than someone expected, and it rewrites SHAs (a reference from an Issue
or an audit starts pointing to a commit no longer in `main`).

If your process depends on **linear history** (e.g. a backward-compatibility harness assumes
that `HEAD^` is the previous version of the application, not the other side of a merge) — stick
to squash and only squash, consciously accepting the three costs above, instead of mixing
strategies.

```bash
gh api -X PATCH repos/OWNER/REPO \
  -F allow_merge_commit=true -F allow_rebase_merge=false -F allow_squash_merge=true \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true -F allow_update_branch=true -F allow_auto_merge=false
```

**`squash_merge_commit_message=PR_BODY` matters.** With the default `COMMIT_MESSAGES`, squash
concatenates the messages of **all** commits on the branch, including ones that reverted earlier
commits on that same branch — the justification for a decision that never actually held enters
`main`.

**`allow_auto_merge=false`** — merging is gate 2, a human decision after reading the diff and the
role reports, not an automatic consequence of a green status.

### `delete_branch_on_merge` only works from the next merge onward

Branches merged earlier have to be deleted manually, after checking they carry no commits beyond
`main`:

```bash
git log origin/main..origin/BRANCH --oneline | wc -l    # must be 0
gh api -X DELETE repos/OWNER/REPO/git/refs/heads/BRANCH
```

As long as there are squashes in the history, `ahead_by` from the API and `git branch --merged`
don't reliably answer the question "does this branch carry anything `main` doesn't have" — only
content answers that:

```bash
git diff --stat origin/main origin/<branch>     # empty = safe to delete
```

### Who cannot approve a pull request

If agents operate within your own session/account, you are the author of every PR — and GitHub
does not let an author approve their own PR. **Do not require formal approval
(`required_pull_request_reviews`) in this situation** — require only a pull request and green
checks; gate 2 is then your conscious click of "Merge" after reading the diff and the reports.
Return to the approval requirement once a second person joins, or once agents start operating on
their own technical account — then you are the reviewer, not the author, and the requirement
becomes a real gate.

### Branch protection, when you have access to it (paid plan)

```bash
gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["<job-name-1>", "<job-name-2>"]
  },
  "required_pull_request_reviews": null,
  "enforce_admins": false,
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
```

| Field | Value | Why |
|---|---|---|
| `contexts` | names of **jobs**, not workflows | GitHub identifies a check by job name, not by file name or the workflow's `name:` field |
| `strict` | `true` | The branch must be up to date with `main` before merging — otherwise green checks pertain to a state that won't be the one that lands |
| `required_pull_request_reviews` | `null` (or configured, if you have human reviewers) | See above — an approval requirement with a single author blocks the repository |
| `enforce_admins` | `false` | You must be able to merge your own PR — this is gate 2, not a workaround of the rule |
| `required_linear_history` | `false`, `true` only with squash-only | `true` rejects every merge commit, which the merge strategy section recommends for multi-commit PRs |
| `required_conversation_resolution` | `true` | A report from the invariant-checking role, pasted as a comment, must be resolved, not scrolled past |
| `allow_force_pushes` | `false` | A forced push to `main` overwrites the evidence the project register rests on |

**Verification after applying — without it it's just a declaration:**

```bash
git push origin main        # expected: rejected by branch protection
gh api repos/OWNER/REPO/branches/main/protection | jq '{
  checks: .required_status_checks.contexts,
  strict: .required_status_checks.strict,
  reviews: .required_pull_request_reviews,
  linear: .required_linear_history.enabled
}'
```

---

## 5. CI pipeline *(half an hour + pitfalls)*

Elements worth having in every workflow job:

```yaml
runs-on: ubuntu-latest       # or a conditional expression, see pitfall below
timeout-minutes: 60
```

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Plus a step at the start announcing which runner the job is executing on and why — so the answer
to "where did this run" lives in the run log, not in a reconstruction from a file.

### Rules whose breach costs the most

**No `paths` filter on the `pull_request` trigger, if the check is required for merging.** A
workflow skipped by a path filter **reports no status at all** — neither success nor failure.
GitHub waits forever for a status that will never come, and shows "Expected — Waiting for status
to be reported". A pull request touching only documentation stops being mergeable — it looks
like a GitHub outage, not a misconfiguration. Details and both solution variants:
[`ci-and-branch-protection.md`](ci-and-branch-protection.md) §1.

**Never a literal runner label (`runs-on: [self-hosted, ...]`) written directly into a job, if
you might ever want to switch between a hosted and a self-hosted runner.** A literal label is
what the next person copies into the next job without deciding whose code it will execute — and
it cements the lack of a fallback route for the day the device is down. Use a conditional
expression controlled by a repository variable, e.g.
`runs-on: ${{ vars.CI_RUNNER == 'github' && 'ubuntu-latest' || fromJSON('["self-hosted","linux","X64"]') }}`.
The only sensible exception is the runner-availability sentinel job (see below).

**Actions pinned to commit identifiers, not to version labels** (`uses: actions/checkout@<sha>`,
not `@v4`). A label points to whatever its author has currently put under it at any given moment.

**Default workflow token permissions on `read`**, not write — raise them selectively, only
where a job actually needs it.

### Availability sentinel (relevant only to a self-hosted/own runner)

With a single self-hosted runner, device unavailability doesn't produce red, it produces
silence — the check reports nothing, and the PR waits with no explanation. A separate, lightweight
job run **at the provider** (not on the observed device) waits a set amount of time for the
remaining jobs to leave the queue, and turns red if they don't. This is the one place where a
literal runner label is deliberate: a sentinel run on the machine it's watching stays silent
exactly when the machine is the problem.

**Optional: a self-hosted runner instead of a hosted one.** If free CI minutes stop being enough,
or you want to run the pipeline on your own hardware for other reasons, that's a separate, larger
topic — it includes, among other things, a container image with build dependencies (browser,
a Node version matching the build steps, Docker-in-Docker), rotating registration credentials,
cleaning disk after tests that run their own containers, and an architectural decision about the
trust class of such a machine (it has full repository access and, if it shares a container daemon
with the host, effectively host administrator privileges). It is not expanded here — treat it as
a separate project with its own gate 1, not a bullet on this list.

---

## 6. Pre-merge audit — three different questions

Sources: [`../agents/invariant-guardian.md`](../agents/invariant-guardian.md),
[`../agents/security-auditor.md`](../agents/security-auditor.md),
[`../agents/reviewer.md`](../agents/reviewer.md).

| Role | Question | When |
|---|---|---|
| Invariant Guardian | which **hard, previously established rule** of the project is broken | every PR touching code or the data schema |
| Security Auditor | what **threat** does this change introduce, regardless of whether it breaks a known rule | conditionally: CI/CD pipeline, dependencies, authentication, secrets, personal data |
| Reviewer | where will the code **fail** under load, under concurrency, under retry, with bad input | PR touching production code or tests |

A change that at first glance looks like configuration (e.g. moving something to another
machine, changing a helper tool) often turns out in practice to be a case for the **Auditor**,
not the Guardian — the Guardian has a closed list of rules and won't catch a fact that list didn't
anticipate (e.g. that a new machine shares a failure domain with something critical). An order
that works well in such cases: **auditor → architect (decision design) → implementation →
Invariant Guardian before gate 2.**

**Also audit fixes, not just the first version of a change.** A second and third round of
auditing the same change regularly find something the previous round couldn't have seen, because
it didn't exist yet — e.g. a defect introduced by the fix to the previous issue itself.

---

## 7. Pitfalls that cost the most time

Collected separately, because each of them takes an hour unrecognized, and a minute recognized.

**A test red for a few hours a day, unrelated to the code.** An assertion counting "tomorrow" by
universal clock (UTC) while business logic decides by local calendar/time zone — in the
timezone-shift window, "tomorrow by UTC" can be today locally, so an operation gets **correctly**
accepted or rejected contrary to the test's expectation. Detectable only by a run executed within
that time window, not by mutation. Look for use of the universal clock in tests touching the day
boundary.

**Multi-line literals versus CRLF.** An assertion comparing a raw text literal against a value
joined with the `"\n"` character passes on a system with LF line endings and fails on a system
with CRLF (and vice versa). The same the other way around: `.` in a regular expression by default
doesn't match `\r`, so a parser operating on a CRLF file can fail to recognize any entry and
report it as a format error — i.e. point to the wrong cause.

**Two copies of one file.** A working/temporary directory with a "proposal" for something that
already actually sits in the target repository is byte-for-byte the same file and will go stale
within a day. A copy without a clear owner always loses to the original — remove it as soon as it
has served its purpose.

**The same number (e.g. test count, coverage threshold) established independently in two
places.** One of them drifts without warning. If a number carries control significance, let it
have one source of truth, with everything else citing it or checking it automatically.

**Backward-compatibility/regression evidence cited for a change it's supposed to cover, but
generated BEFORE that change.** The number is true and pertains to something else. Check the
date/commit of the run the evidence comes from against the change it's supposedly covering.

**A lock file (`index.lock` and similar) after an interrupted process.** Before deleting: check
the file's age and whether any relevant process is still running. A fresh lock file with an
active process is not garbage.

**Credentials pasted into a conversation with an agent or into a log.** A short-lived token
(e.g. a registration token) limits the damage by its expiry; a personal/long-lived token **does
not expire on its own**. If it landed anywhere it shouldn't have — revoke it before doing
anything else.

---

## 8. Merge order with several branches at once

Branches stacked one on top of another (each next one branching off the previous) should be
merged **starting from the oldest**. Merging in a different order shifts the base, and the diff
in the interface stops matching what was actually audited.

If one of the branches carries a fix for a defect that breaks the pipeline on `main`, move that
fix into the branch merged first — a change unrelated to that defect shouldn't be held hostage by
it, and identical content on both sides doesn't produce a merge conflict.

---

## What this guide does not cover

Setting up an account/organization in the code-hosting system, granting permissions in it, or
rotating access tokens — those are actions in the provider's interface, performed by the project
owner. It also does not cover full configuration of a self-hosted runner (see the caveat in
section 5), nor server-side branch protection for plans that don't provide it — that comes back
only with the appropriate plan, and at that point it **replaces** step 3 rather than supplementing
it.
