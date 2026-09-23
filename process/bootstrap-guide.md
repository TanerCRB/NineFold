# Guide: bootstrapping the framework on a new repository

> Anonymized synthesis of a real rollout run. Every step has a **check**, because most things
> here fail silently — it looks set up and lets things through. This is an instruction, not a
> story: the reasons why particular things look exactly the way they do are written down only
> where omitting them ends in undoing work.

**Time:** a day for a smooth run up to the pilot, excluding the self-hosted runner (see
section 8) — that one tends to be the longest, not because it's hard, but because every
unrecorded host dependency surfaces separately, and only after the run.

**Two repositories take part.** The **process repository** is your copy of this kit: the source
of truth for roles, templates and labels, with no product code. The **product repository** is
where the work happens: it receives the roles, the commands, the templates and the registers.
Every step says which one it runs in.

**The order is deliberate** (`../FrameworkDoc.md`, section 13): protection first, then the
process in the tracker, then the roles, then calibration of the evaluating roles — and only then
one pilot task from ticket to merge. Don't start producing code with the roles before step 10.

---

## 0. What you need before you start

| Thing | What for | Check |
|---|---|---|
| `git` | everything | `git --version` |
| Node.js 22 or newer | the sync scripts and the pre-push hook | `node --version` |
| `gh` (GitHub CLI) authenticated | labels, templates, PRs, repository settings | `gh auth status` |
| An agent environment that loads roles from a directory (e.g. Claude Code) | running the roles and the commands | Claude Code: `claude --version` |
| Administrator permission on the product repository | branch protection, merge settings | `gh api repos/OWNER/REPO --jq .permissions.admin` |
| A product repository with a `main` branch | everything else assumes this name | — |

`gh` is sometimes installed and yet invisible on PATH — the Windows installer doesn't always
append the directory to the environment variable. Before concluding it's not there, check the
installation directory directly.

---

## 1. Set up the process repository *(1–2 hours)* — process repository

Create your own copy of this kit (a private fork or a fresh repository with its content) next to
the product repository, e.g. `~/src/<repo-process>` beside `~/src/<repo-backend>`: the sync
scripts find product repositories by path relative to the process repository.

1. **Fill in the configuration of both sync scripts.**
   - `tools/sync-agents.mjs`: `TARGETS` — one entry per product repository (`name`, `path`,
     `dir`).
   - `tools/sync-github.mjs`: `OWNER` (your GitHub organization or account) and `TARGETS` —
     remove the example entries you don't have (e.g. `<repo-infra>`,
     `<repo-order-recipient>`).
   Both scripts refuse to run while any `<placeholder>` is left in them, and say which one.
2. **Adapt the roles in `agents/`** before they ever reach a product repository: the domain
   sentence, `<product-repository>`, `<decision-registry-path>`, and above all the checklists
   marked EXAMPLE (`../FrameworkDoc.md`, section 12: *roles and gates are universal, checklists are
   not*). With two technology stacks, split `developer.md` as its header note describes.
3. **Adapt the team contract** — copy `TEAM-CONTRACT-TEMPLATE.md` to `TEAM-CONTRACT.md`, fill in
   the repository names, remove what you don't have. The roles defer to it on any discrepancy.

**Check:**

```bash
node tools/sync-agents.mjs --self-test           # all cases pass
node tools/sync-github.mjs --self-test
node tools/sync-github.mjs --validate            # manifest and templates are valid
grep -rn "<product-repository>\|<decision-registry-path>" agents/   # expected: no output
node tools/sync-agents.mjs --check               # no ERROR about a placeholder; DRIFT is expected before step 4
```

---

## 2. Protect `main` first *(20 minutes)* — product repository

Source: [`branch-protection-without-paid-plan.md`](branch-protection-without-paid-plan.md), [`hooks/pre-push`](hooks/pre-push).

The next steps add files to the product repository. They go in through a branch and a pull
request — that is gate 2 — so the guard against a direct push to `main` goes in **before** them,
not after.

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

**First the `.gitattributes` entry — this is the load-bearing half, without it the hook doesn't
work.** In the product repository's `.gitattributes`:

```
.githooks/** text eol=lf
```

Without this entry, under the rule `* text=auto`, a script checked out on Windows gets CRLF, and
`#!/usr/bin/env sh` with a returned carriage return ends up with a `bad interpreter` on Linux and
macOS. The hook is then **present, wired up, and lets every push through** — exactly the class of
failure it's supposed to protect against. Add the entry **before** copying the hook, so the file is
added with the right line endings; the process repository carries the same rule for
`process/hooks/`.

```bash
mkdir -p .githooks
cp <process-repo>/process/hooks/pre-push .githooks/
git add .gitattributes .githooks/pre-push
git add --renormalize .githooks/            # in case the copy arrived with CRLF
git update-index --chmod=+x .githooks/pre-push
git config core.hooksPath .githooks
```

**Check, in this order:**

```bash
git ls-files --eol .githooks/pre-push       # -> i/lf ... attr/text eol=lf
git config --get core.hooksPath             # -> .githooks
printf 'refs/heads/x 1 refs/heads/main 2\n' | .githooks/pre-push origin url; echo "code=$?"    # 1
printf 'refs/heads/x 1 refs/heads/feature/x 2\n' | .githooks/pre-push origin url; echo "code=$?" # 0
```

The last line is a counter-test — without it "denies on `main`" would also be satisfied by a hook
that always denies, regardless of branch. A real `git push origin main` is proof **only when you
have a commit ahead of `origin/main`**: on a branch that's already up to date, git finishes with
`Everything up-to-date` before it even runs the hook — the response looks like success and says
nothing.

**What the hook doesn't give:** nothing server-side. `--no-verify` goes through, another clone
without `core.hooksPath` doesn't have it at all, it doesn't enforce required checks before
merging. This is a **guard, not a gate**, and should be described that way everywhere it's
mentioned. Every clone — including each machine an agent runs on — needs the
`git config core.hooksPath .githooks` line once.

---

## 3. Labels and templates *(15 minutes)* — process repository → product repository

Source: [`labels.json`](labels.json), [`issue-templates/`](issue-templates/),
[`../tools/sync-github.mjs`](../tools/sync-github.mjs).

Run from the root of the **process** repository:

```bash
node tools/sync-github.mjs --labels | bash          # bash: labels from the manifest, idempotently
node tools/sync-github.mjs --labels-ps1 > labels.ps1 # PowerShell: then Invoke-Expression (Get-Content labels.ps1 -Raw)
node tools/sync-github.mjs                          # templates into the product repo's .github/
```

The templates land as files tracked by the product repository: commit them there on a branch and
merge through a pull request.

**Check:** `gh label list --repo OWNER/REPO` shows the labels from the manifest (without
`--repo`, run from the process repository, it lists the process repository's own labels); a new
Issue from the story template cannot be submitted with an empty "Definition of done" field.

### Pitfalls

**The label manifest must be in pure ASCII — names and descriptions.** The path `manifest → node
→ shell → gh` has places where Windows PowerShell 5.1 re-encodes text via the console code page —
a dash or a diacritical mark comes back from it as multi-byte garbage, and that's in label
descriptions, exactly where nobody looks. The sync script has an assertion that stops the run at
the first non-ASCII character — leave it in, don't work around it.

**The target of the labels is the explicit `--repo`** that the script puts on every generated
`gh` call. Don't remove it: `gh` by default infers the repository from the remote of the current
directory, so without it the labels would land **in the process repository itself**, silently,
without error, because that too is a valid repository.

---

## 4. Roles and commands *(30 minutes)* — product repository

**Roles.** The agent environment loads roles only from the configuration directory of the
repository it runs in (`.claude/agents/` for Claude Code). That directory is **not versioned** in
the product repository — the process repository is the source, the copy is reproducible. First,
in the product repository's `.gitignore`:

```
.claude/agents/
```

Ignore only that directory, not the whole `.claude/` — the commands and the shared settings below
are versioned. Then, from the root of the **process** repository:

```bash
node tools/sync-agents.mjs            # copies the 8 roles; prints the source commit it read
node tools/sync-agents.mjs --check    # afterwards: "No drift."
```

**Commands.** Copy the two commands into the product repository's command directory and adapt
them — remove the template quote at the top (the frontmatter must be the first thing in the
file), fill in `<product-repo>`, `<organization>`, the register paths from step 5, and the local
quality gates in step 9 of the command:

| Source (process repository) | Target (product repository) | Invoked as |
|---|---|---|
| `process/task-command.md` | `.claude/commands/task.md` | `/task #<N>` |
| `process/task-status-command.md` | `.claude/commands/task-status.md` | `/task-status #<N>` |

These are versioned in the product repository and change through review, like code: they carry
that repository's stack and domain (`../FrameworkDoc.md`, section 4).

**Permissions.** Put the permission rules from `../TEAM-CONTRACT-TEMPLATE.md` §2a into the product
repository's shared `.claude/settings.json` — the environment refuses `gh pr merge` and force
pushes for every role and asks before any push.

**Write-boundary check.** Copy `process/scripts/boundary-check.sh` to `scripts/boundary-check.sh`
in the product repository (versioned; add `scripts/*.sh text eol=lf` to `.gitattributes`). The
task command runs it around every role that may write.

**Check:**

```bash
bash scripts/boundary-check.sh --self-test     # every case passes on this machine
git check-ignore -v .claude/agents/qa.md       # -> matched by .gitignore
git status --short --untracked-files=all .claude/   # commands and settings.json show up, agents don't
node <process-repo>/tools/sync-agents.mjs --check   # run from the process repo: "No drift."
```

In a Claude Code session started in the product repository: `/agents` lists the 8 roles, and
`/task-status` is available.

---

## 5. Registers *(1 hour)* — product repository

Source: [`registers/`](registers/).

Copy the templates into the product repository's documentation (e.g. `docs/`) and adapt them: a
plan, a capability register with its mutation table, a decision directory with the decision
template, the list of architecture-sensitive paths, the cost-register directory, and a gap
register if you have a second product repository. [`registers/README.md`](registers/README.md)
says who writes each one and which placeholders in the command and the roles point at them.

A first pass of the capability register that comes out mostly "none" is the correct result: the
register has only started measuring what nobody measured before (`../FrameworkDoc.md`, section 7).

**Check:** every register path named in `.claude/commands/task.md` and in the roles exists:

```bash
grep -rhoE "docs/[A-Za-z0-9_./-]+" .claude/commands/ | sort -u | while read -r p; do [ -e "$p" ] || echo "missing: $p"; done
```

(expected: no output — adapt the `docs/` prefix to where you put them).

---

## 6. State machine and gates *(a record, not a configuration)*

Source: [`sdlc-flow.md`](sdlc-flow.md), [`../TEAM-CONTRACT-TEMPLATE.md`](../TEAM-CONTRACT-TEMPLATE.md).

The one part of the state machine that *is* configuration: copy
[`workflows/label-guard.yml`](workflows/label-guard.yml) into the product repository's
`.github/workflows/` by hand (the sync script deliberately doesn't touch workflows). **Check:** give
a test Issue two `state:*` labels — within a minute it gets a comment and a red run; remove one,
and the next run is green.

Three gates: **1** before code exists (scope and architecture), **2** before entering `main`
(diff, invariant-checking role's report, mutation result), **3** before raising the status in
the project register.

One thing worth repeating, because it looks like a formality: **gate 3 gets its own commit.** The
entry checking off a task or raising a decision's status travels separately from the code it
describes. An agent will always be inclined to treat its own work as evidence, and the entire
credibility of the register rests on the principle "status is raised by evidence".

### 6a. Documentation next to the code, not only in one root file

A single instructions file for the agent (e.g. a root `CLAUDE.md`) scales up to a point, and then
gets so long that an agent working in one module reads every other module's rules just to reach
its own. A pattern that holds up as the codebase grows: **keep the root file short and
navigational**, and give each module/screen/layer its **own local rules file** sitting physically
next to the code it covers — the root indexes them as a list of links, it doesn't copy their
content. An agent opening a specific module finds its rules in the same directory, without reading
everything else. Keeping this up takes discipline (new module = new file plus an index entry), but
the cost is lower than one file that grows without bound.

---

## 7. Merge settings and repository hygiene *(20 minutes)*

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
does not let an author approve their own PR. **Require a pull request with zero approvals**
(`required_approving_review_count: 0`), green checks, and **enforce the rules for administrators
too** — the agents act on your account, so whatever your account may bypass, they may bypass.
Gate 2 is then your conscious click of "Merge" after reading the diff and the reports
(`ci-and-branch-protection.md`, §2).
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
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "enforce_admins": true,
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
| `required_pull_request_reviews` | `required_approving_review_count: 0` (raise it once there are human reviewers) | A pull request is required, an approval is not — a non-zero count with a single author blocks the repository |
| `enforce_admins` | `true` | The agents act on your account — a bypass left to the owner is a bypass left to them. Merging your own PR doesn't need it |
| `required_linear_history` | `false`, `true` only with squash-only | `true` rejects every merge commit, which the merge strategy section recommends for multi-commit PRs |
| `required_conversation_resolution` | `true` | A report from the invariant-checking role, pasted as a comment, must be resolved, not scrolled past |
| `allow_force_pushes` | `false` | A forced push to `main` overwrites the evidence the project register rests on |

**Verification after applying — without it it's just a declaration:**

```bash
gh api repos/OWNER/REPO/branches/main/protection | jq '{
  checks: .required_status_checks.contexts,
  strict: .required_status_checks.strict,
  reviews: .required_pull_request_reviews.required_approving_review_count,
  admins: .enforce_admins.enabled,
  linear: .required_linear_history.enabled
}'
```

Reading the settings back is still a declaration. The proof is a rejected direct push (a real
commit ahead, `--no-verify` so the hook doesn't answer first) and a refused merge of a PR with a red
check, both as the identity the agents use — on a throwaway test repository, never on the
product's `main`. The exact commands: `ci-and-branch-protection.md`, §3.

---

## 8. CI pipeline *(half an hour + pitfalls)*

Beyond build and tests, this is where the mechanical half of the Guardian's checklist belongs:
[`invariant-assertions.md`](invariant-assertions.md) shows how to turn the rules tagged [M] into
assertions with a silent-zero guard and a contrast fixture.

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

## 9. Calibrate the evaluating roles *(half a day)* — before trusting their reports

Source: [`../calibration/README.md`](../calibration/README.md).

A green report from the Guardian, the Reviewer or QA is worth something only once the role has
been shown to find what's there and stay silent on what isn't. Run, per evaluating role:

- **Invariant Guardian** — method 1: a seeded set with decoys (run B) plus one run on real,
  approved code (run A). Build the answer key from your own checklist, independently of the
  examples in the role's definition.
- **Reviewer** — method 2: a historical change with a documented human review, the tree restored
  to its state before the fixes.

Record each result with the date **and the model the role ran on** — roles inherit the calling
session's model, and a result holds only for that model.

**Check:** the calibration log has, for each evaluating role, a result like
`<model-id>: 12/12 detected, 0/5 decoys reported` and a clean-code run with zero findings. A role
without one is not trusted with a real pull request yet.

---

## 10. Pilot: one task, ticket to merge — product repository

Start read-only: `/task-status #<N>` on an existing Issue changes nothing and shows whether the
command can read the Issue, the PR, CI and the registers. Then drive **one** small, real task with
`/task #<N>` all the way through the three gates.

Watch, and note in the run log, what the kit can't check for you:

- the write-boundary check after the Architect and QA leaves a "boundary check: clean" note;
- a cost-register row lands as its own commit on the task branch after every role call;
- the PR description carries the mutation patch and the Guardian's verdict unsmoothed;
- at gate 3 the agent only **proposes** the register entries — you paste them.

**Check:** the pilot task is merged, its plan entry has a `Done <date>:` line with a link to the
test, and the cost register has one row per role call. Count the times you had to step in
**outside** the three gates — that number, falling over the next ten tasks, is the signal that the
process works (`../FrameworkDoc.md`, section 13).

---

## 11. Pre-merge audit — three different questions

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

## 12. Pitfalls that cost the most time

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

## 13. Merge order with several branches at once

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
section 8), nor server-side branch protection for plans that don't provide it — that comes back
only with the appropriate plan, and at that point it **replaces** step 2 rather than supplementing
it.
