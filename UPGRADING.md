# Upgrading

Step-by-step upgrades between released versions, newest first. Each one touches two places — your
**process repository** (your copy of this kit) and every **product repository** that received
roles, templates and commands from it — and every step ends with a check, because most of these
changes fail silently when half-done. Upgrade one version at a time.

- [v0.3.0 → v0.4.0](#v030--v040)
- [v0.2.0 → v0.3.0](#v020--v030)
- [v0.1.0 → v0.2.0](#v010--v020)

If you are installing from scratch, follow [`process/bootstrap-guide.md`](process/bootstrap-guide.md)
instead.

---

## v0.3.0 → v0.4.0

v0.4.0 licenses the kit and reverses the language rule. The reasons are in the pull requests
[#17](https://github.com/TanerCRB/NineFold/pull/17) (license) and
[#18](https://github.com/TanerCRB/NineFold/pull/18) (language).

**Time:** under an hour per product repository.

**License.** The kit is now under the Apache License 2.0 (`LICENSE`, `NOTICE`). Nothing to do in a
product repository; keep both files in your process repository when you merge the tag.

**Language rule reversed.** Until now the team contract put artifacts in the team's language and
only the technical surface in English. Now the conversation follows the human's language, and
artifacts — commits, pull requests, Issues and comments, registers, documentation, code comments —
are in English unless the human explicitly names another language. Identifiers, error and log
messages and the API surface stay in English, as before.

1. **Process repository:** merge the `v0.4.0` tag, including the new "How to write" section into your contract. If your team
   keeps artifacts in its own language, say so explicitly in that section — otherwise the agents
   switch to English.
2. **Product repositories:** re-sync the roles (`developer.md` changed) and hand-merge section 2
   and the developer step of the task command.
3. **Check:** run one task with the conversation in your language; its Issue comments, commits and
   pull request must come out in the artifact language you set.

Existing artifacts are not translated.

---

## v0.2.0 → v0.3.0

v0.3.0 answers an external review of the process. Its core: the evidence behind a merge must be
about the code that is merged, and a check that can't see something must not report "clean". The
reasons for each change are in the pull requests
[#11](https://github.com/TanerCRB/NineFold/pull/11) (controls),
[#12](https://github.com/TanerCRB/NineFold/pull/12) (consistent instructions) and
[#13](https://github.com/TanerCRB/NineFold/pull/13) (assertions and measurement); #9, #10, #14 and
#15 only touch the kit's own documentation.

**Time:** about half a day per product repository, plus recalibration of all four evaluating roles.

### What changed, in one table

| Area | Change | Action in a product repo |
|---|---|---|
| Verification | The developer's state and QA's tests become local **checkpoint commits**; sync with `main` happens **before** verification; every report names one `VERIFIED` SHA; a later non-bookkeeping change from `main` reruns the affected roles | merge the task command (step 5) |
| Mutations | Taken and restored against the checkpoint; the patch carries `Base: <SHA>`; green → red → green required; four causes of a survived mutation | re-sync roles (step 4) |
| Write-boundary check | A script, `boundary-check.sh`, compares HEAD, the index and the working tree; `--none` for read-only roles; runs around **every** role called through a general-purpose mechanism | copy the script (step 2) |
| Issues and gate 3 | Code PRs say **`Refs #N`**; the Issue stays open in `state:evidence` until a **documentation PR** (`Closes #N`) that the agent prepares and the human merges — that merge is gate 3 | re-sync templates (step 3), migrate Issues (step 6) |
| `label-guard` | Also runs on `closed`; flags an Issue closed before gate 3 | update the workflow (step 3) |
| Verdicts | One high or medium finding is `STOP` unless the human records an exception (owner, reason, date); shared "Verdicts" section in the contract | re-sync roles, update your contract (step 1) |
| Fast lane | An approved fast-lane record replaces the impact map; re-checked against the real diff | merge the task command |
| Branch protection | PR required with **0 approvals**, **`enforce_admins: true`** | change the settings (step 8) |
| `.claude/` | Only `.claude/agents/` and local state are unversioned; commands and shared settings are versioned — now also in the contract | check `.gitignore` (step 4) |
| Assertions | A3 pairs the tenant columns of both sides of a foreign key; a behavior test for cross-tenant references | replace A3 (step 8) |
| CI variant B | The build is skipped only for documentation-only diffs; the gate accepts `skipped` only then | update your filter, if you use it (step 8) |
| Cost register | New fields `invocation`, `roles`; gate rows, escapes, p50/p90 | add fields (step 7) |
| Calibration | Methods for QA (1a) and the Security Auditor (1b); results keyed by definition, model, invocation mode and case set | recalibrate (step 9) |
| Pinning | Step 0 posts session, worktree, branch and a roles fingerprint; a change mid-task stops it | merge the task command |

### 0. Before you start

**Finish or park every task in flight.** The verification flow changed (checkpoints, one `VERIFIED`
SHA, sync before QA), and a task switched halfway has evidence that fits neither version. List them
as in the v0.1.0 → v0.2.0 upgrade, step 0, let them pass gate 2, then upgrade.

Tag the current state of the process repository and each product repository
(`git tag pre-ninefold-v0.3.0`) so there is a way back.

### 1. Process repository: take v0.3.0

```bash
git fetch upstream --tags
git switch -c upgrade/ninefold-v0.3.0
git merge v0.3.0
```

Expect conflicts in:

- **`agents/*.md`** — keep your domain content, take the new mechanics: QA's checkpoint, restore and
  patch rules and the four causes of a survived mutation; the verdict paragraphs in the Guardian,
  the Reviewer and the Security Auditor; the Developer's hard stops 1, 4 and 8 and its cost figures;
  Guardian rule 23.
- **Your `TEAM-CONTRACT.md`** — compare with the new template: §2a rows (boundary check, general-
  purpose invocation), §3 gate 3 as a documentation PR, the new §3a "Verdicts", hard stops 3, 5, 8
  and 10, §5.
- **`tools/check-links.mjs`** — take it whole; it now skips files git ignores.

**Check:**

```bash
node tools/sync-agents.mjs --self-test
node tools/sync-github.mjs --self-test && node tools/sync-github.mjs --validate
node tools/check-links.mjs --self-test && node tools/check-links.mjs
bash process/scripts/boundary-check.sh --self-test     # every case passes on this machine
```

### 2. Product repository: the boundary-check script

```bash
mkdir -p scripts
cp <process-repo>/process/scripts/boundary-check.sh scripts/
grep -q '^scripts/\*\.sh text eol=lf' .gitattributes || echo 'scripts/*.sh text eol=lf' >> .gitattributes
git add .gitattributes scripts/boundary-check.sh && git add --renormalize scripts/
git update-index --chmod=+x scripts/boundary-check.sh
```

**Check:** `bash scripts/boundary-check.sh --self-test` — all cases pass (the mode-change case is
skipped where the filesystem has no executable bit).

### 3. Templates and the label guard

From the process repository: `node tools/sync-github.mjs`. The PR templates now carry `Refs #`,
`Verified at:`, the mutation patch with its base, and "proposed row … entered at gate 3". Copy the
new `process/workflows/label-guard.yml` over `.github/workflows/label-guard.yml` by hand. Commit
both through a PR.

**Check:** `node tools/sync-github.mjs --check` → `No drift.`; in the product repository,
`grep -c "Refs #" .github/PULL_REQUEST_TEMPLATE.md` → 1 and
`grep -c closed .github/workflows/label-guard.yml` → at least 1.

### 4. Roles

From the process repository: `node tools/sync-agents.mjs`, then `--check` → `No drift.`. Make sure
the product repository ignores only `.claude/agents/`, not the whole `.claude/`.

### 5. Task commands

Merge by hand what changed upstream:

```bash
git diff v0.2.0 v0.3.0 -- process/task-command.md process/task-status-command.md
```

Into your `.claude/commands/task.md`:

1. **Overriding rules** — the closed commit list now has verification checkpoints and the gate-3
   documentation commit; the configuration rule (roles, commands, settings change only through
   their own PR); the "Task started / Task stopped" comment.
2. **How you call a role** — the general-purpose call as a weaker mode: boundary check around every
   role, `--none` for read-only ones, `invocation` in the cost row.
3. **Step 0** — pin session, worktree, branch and the roles fingerprint in an Issue comment.
4. **Step 4 and "Fast lane"** — the fast-lane record as a comment approved at gate 1; the entry
   condition of the `code` phase.
5. **Step 10a** — checkpoint and sync before verification; the fast-lane re-check.
6. **Steps 11, 11a, 12–14** — QA on the checkpoint, the QA checkpoint, `VERIFIED`, every report
   naming its SHA; the "Write-boundary check" section now calls `scripts/boundary-check.sh`.
7. **"Re-verification after a STOP"** — fixes become new checkpoints and a new `VERIFIED`.
8. **Steps 15–19** — the freshness check against `VERIFIED`; push only on request; `Refs #N` and
   `Verified at:` in the PR; gate 2 checks the PR head against `VERIFIED`.
9. **Steps 21 and 23** — the gate-3 documentation PR with `Closes #N`; labels set at gate 3.

Into `task-status.md`: the three new rows of the state table (Issue open at gate 3, closed before
gate 3, a report naming a different SHA).

**Check:** `grep -c "VERIFIED\|boundary-check.sh\|Refs #\|fast-lane record" .claude/commands/task.md`
— several lines each; then `/task-status #<N>` on any Issue runs and changes nothing.

### 6. Migrate Issues closed before gate 3

Under v0.2.0 a code PR with `Closes #N` closed the Issue at merge, while it still waited in
`state:evidence`. Reopen those whose register entry is not in place yet:

```bash
gh issue list --repo <owner>/<product-repo> --state closed --label state:evidence --json number,title
gh issue reopen <N> --repo <owner>/<product-repo>
gh issue edit <N> --repo <owner>/<product-repo> --add-label waiting-on-human
```

Then finish their gate 3 the new way — a documentation PR with `Closes #N`. An Issue whose entry is
already in place gets `state:closed` and stays closed.

**Check:** the list above is empty, and so is the label-invariant query from the v0.1.0 → v0.2.0
upgrade, step 6.

### 7. Registers

Add `invocation` and `roles` to new cost rows (old rows keep "no data" — don't backfill from
memory), and start recording gate rows (`"kind": "gate"`) and escapes as
[`process/registers/cost-register.md`](process/registers/cost-register.md) describes. The capability
register's mutation rows link patches with their base SHA.

### 8. Settings, CI and assertions

- **Branch protection (paid plan):** a required pull request with `required_approving_review_count:
  0`, required status checks, `enforce_admins: true` — then the acceptance test from
  [`process/ci-and-branch-protection.md`](process/ci-and-branch-protection.md) §3 on a throwaway
  repository, never on the product's `main`.
- **Invariant assertions:** replace A3 with the paired version, add the swapped-key case to your
  fixture and the cross-tenant behavior test ([`process/invariant-assertions.md`](process/invariant-assertions.md)).
- **CI variant B**, if you use it: the documentation-only allowlist and the new gate.

### 9. Recalibrate the evaluating roles

All four changed: the verdict semantics (Guardian, Reviewer, Security Auditor) and QA's mutation
method. Run the methods from [`calibration/README.md`](calibration/README.md) — 1 for the Guardian, 2
for the Reviewer, **1a for QA and 1b for the Security Auditor** (new) — and key each result by
definition, model, invocation mode and case set. Until then, a `PASS` from them is unconfirmed at
gate 2.

### 10. Confirm on one task

Drive one small task with the updated `/task`. What should be visibly different:

- a "Task started" comment with the roles fingerprint on the Issue;
- two checkpoint commits (`developer`, `qa`) on the task branch, and every report naming `VERIFIED`;
- "boundary check: clean" after each role that was checked;
- a PR that says `Refs #N` and `Verified at: <SHA>`;
- after the merge the Issue **still open** in `state:evidence`, and a documentation PR with
  `Closes #N` — its merge is your gate 3.

When that holds, delete the `pre-ninefold-v0.3.0` tags.

---

## v0.1.0 → v0.2.0

> For teams that installed the kit at **v0.1.0** (the initial commit `4a726f3`, 2026-09-17) and want
> to move to **v0.2.0** (2026-09-23). If you are installing from scratch, follow
> [`process/bootstrap-guide.md`](process/bootstrap-guide.md) instead.

The upgrade touches two places: your **process repository** (your copy of this kit) and every
**product repository** that received roles, templates and commands from it. Nothing in it is
automatic — like the rest of the process, each step ends with a check, because most of these
changes fail silently when half-done.

**Time:** about half a day per product repository, plus recalibration of the evaluating roles.

---

### What changed, in one table

| Area | Change | Action in a product repo |
|---|---|---|
| Roles | `model: opus` → `model: inherit`; Architect gets `Write, Edit`; Developer self-check; Guardian rules tagged [M]/[J]; QA records mutations as patches; Product Owner output headings match the Story form | re-sync (step 4) + recalibrate (step 9) |
| State machine | PR opened after verification, not after implementation; new gate-3 state `state:evidence` between merge and closed | migrate open Issues (step 6) |
| Labels | new `state:evidence`, `role:reviewer`, `role:security-auditor`; `state:qa` description | re-run the label script (step 3) |
| Templates | PR templates get a mutation-patch block; Issue form field `id`s translated to English (field labels unchanged) | re-sync templates (step 3) |
| Task command | pre-authorized bookkeeping commits; worktree created at recon; write-boundary check; scoped re-verification; fast lane; cost register one file per row with `model` and `reworkCause` | merge by hand (step 5) |
| Registers | templates in `process/registers/`, incl. a new list of architecture-sensitive paths | add what's missing (step 7) |
| New files | `process/workflows/label-guard.yml`, `.claude/settings.json` permissions, `.gitignore` for `.claude/agents/`, `.gitattributes` for the hook | copy (step 8) |
| Merge settings | `required_linear_history` recommended `false` unless you are squash-only | check (step 8) |
| Sync tools | `sync-github.mjs` path bug fixed; missing target → exit 1; `<placeholder>` refused; `--self-test` before every run; new `--validate` | re-apply config (step 1) |

The full list of reasons is in the pull requests:
[#1](https://github.com/TanerCRB/NineFold/pull/1) ·
[#2](https://github.com/TanerCRB/NineFold/pull/2) ·
[#3](https://github.com/TanerCRB/NineFold/pull/3) ·
[#4](https://github.com/TanerCRB/NineFold/pull/4) ·
[#5](https://github.com/TanerCRB/NineFold/pull/5) ·
[#6](https://github.com/TanerCRB/NineFold/pull/6) ·
[#7](https://github.com/TanerCRB/NineFold/pull/7).

---

### 0. Before you start

**Pick a moment between tasks.** A task already in flight finishes under the command it started
with: the old flow opens the PR at the end of implementation, the new one at the end of
verification, and switching halfway leaves the Issue in a state neither version expects. List what
is in flight:

```bash
gh issue list --repo <owner>/<product-repo> --state open --label state:implementation
gh issue list --repo <owner>/<product-repo> --state open --label state:qa
gh issue list --repo <owner>/<product-repo> --state open --label state:merge
```

Let these reach gate 2 (or park them), then upgrade.

**Keep a way back.** Tag the current state of the process repository and each product repository
before changing anything (`git tag pre-ninefold-upgrade`).

---

### 1. Process repository: take the new version

Your process repository is a copy of this kit with your own edits — adapted roles, a filled-in
configuration. Bring the new version in as a merge on a branch, not by overwriting files:

```bash
git remote add upstream <url-of-this-kit>      # once
git fetch upstream --tags
git switch -c upgrade/ninefold
git merge v0.2.0                               # the release, not a moving branch
```

Expect conflicts in three places:

- **`agents/*.md`** — your adapted text against the new sections. Keep your domain content
  (checklists, the domain sentence, paths) and take the new mechanics: the `[M]`/`[J]` tags and
  their explanation in the Guardian, the patch rules in QA, the self-check section and report
  field in the Developer, the `Write, Edit` tools and the boundary note in the Architect, the
  renamed output headings in the Product Owner. `model: inherit` replaces `model: opus`; keep an
  explicit model only if you deliberately want one — and then read the model note in
  [`calibration/README.md`](calibration/README.md).
- **`tools/sync-agents.mjs`, `tools/sync-github.mjs`** — both were restructured. **Take the new
  files whole** and copy your `TARGETS` and `OWNER` back into their configuration blocks; don't try
  to merge the logic line by line.
- **`TEAM-CONTRACT.md`** (your adapted copy, if you made one) — compare it with the new
  `TEAM-CONTRACT-TEMPLATE.md`: classification of QA and the Architect, hard stops 3, 7 and 8, the
  §2a boundary checks and permissions, the §8 log fields.

If you used `sync-github.mjs` before, note that in v0.1.0 it only worked when run from
`tools/` with adjusted paths. Run it from the repository root now.

**Check:**

```bash
node tools/sync-agents.mjs --self-test
node tools/sync-github.mjs --self-test
node tools/sync-github.mjs --validate
node tools/check-links.mjs
node tools/sync-agents.mjs --check     # DRIFT is expected here — the product repos have the old roles
```

No `ERROR` about a placeholder: if one appears, your configuration didn't survive the merge.
Merge the branch through a pull request. The kit's own CI (`.github/workflows/kit-ci.yml`) comes
with the merge — enable Actions for the process repository if they're off.

---

### 2. Product repository: protect the hook's line endings

If the product repository already has the pre-push hook, make sure it can't be checked out with
CRLF (the initial guide added this rule after copying the hook, which could leave it CRLF):

```bash
grep -q '^.githooks/\*\* text eol=lf' .gitattributes || echo '.githooks/** text eol=lf' >> .gitattributes
git add .gitattributes && git add --renormalize .githooks/
git ls-files --eol .githooks/pre-push      # -> i/lf ... attr/text eol=lf
```

Replace `.githooks/pre-push` with the new `process/hooks/pre-push` only if you changed nothing in
it; it is unchanged in content, so usually there is nothing to replace.

---

### 3. Labels and templates

From the process repository root:

```bash
node tools/sync-github.mjs --labels | bash             # or --labels-ps1 on PowerShell
node tools/sync-github.mjs                             # templates into the product repo's .github/
```

`--force` in the generated script makes the run idempotent: existing labels keep their names and
only get the new description; the three new labels are created.

In the product repository, commit the changed `.github/` files on a branch and merge them through a
pull request.

**Check:** `gh label list --repo <owner>/<product-repo> | grep -E 'state:evidence|role:reviewer|role:security-auditor'`
shows three lines, and `node tools/sync-github.mjs --check` in the process repository reports
`No drift.`

The Issue forms changed only their field `id`s. If anything of yours addresses the fields by id
(a prefilled issue URL such as `?gotowe-gdy=…`, an automation reading the form), switch it to the
new ids: `task-id`, `what-and-why`, `definition-of-done`, `out-of-scope`, `documentation-basis`,
`confirmations` (Story) — the rest are listed in the form files.

---

### 4. Roles

From the process repository root:

```bash
node tools/sync-agents.mjs
node tools/sync-agents.mjs --check          # "No drift."
```

If the script warns `git does not ignore .claude/agents`, add `.claude/agents/` to the product
repository's `.gitignore`. If you had ignored the whole `.claude/` directory instead, narrow it to
`.claude/agents/`: the commands and `.claude/settings.json` are meant to be versioned (step 5, 8).

**Check:** in a Claude Code session in the product repository, `/agents` lists the eight roles,
and `.claude/agents/architect.md` shows `tools: Read, Write, Edit, Grep, Glob`.

---

### 5. Task commands

Your `.claude/commands/task.md` and `task-status.md` are adapted copies, so they are merged by
hand. See exactly what changed upstream:

```bash
# in the process repository
git diff v0.1.0 v0.2.0 -- process/task-command.md
git diff v0.1.0 v0.2.0 -- process/task-status-command.md   # no changes
```

Carry these into your `task.md`:

1. **Overriding rules** — the closed list of bookkeeping commits (plan-number reservation,
   cost-register row) that need no request.
2. **Step 0** — the task's worktree is created right after recon, before the first role call;
   step 6 only confirms it.
3. **Cost register** — one file per row, the `model` and `reworkCause` fields, the commit on the
   task branch; the conflict rule in the `pr` phase is now only a fallback.
4. **Write-boundary check** after the Architect (step 4) and QA (step 11), with the snippet from
   the "Write-boundary check" section.
5. **Re-verification after a `STOP`** — the scoped rerun.
6. **Fast lane** — copy the section, but leave it **off** until the cost register shows the
   Architect adds nothing on such tasks; fill in `<path-to-architecture-sensitive-paths-list>`.
7. **QA step** — mutations come back as patches and go into the PR as is.
8. **Gate 3** — a merged task sits in `state:evidence`, not `state:closed`.

**Check:**

```bash
grep -c "Write-boundary check\|Re-verification after a\|bookkeeping commit\|state:evidence" .claude/commands/task.md
```

(four or more; the exact count depends on your wording). Then `/task-status #<N>` on any Issue
runs and changes nothing.

---

### 6. Migrate open Issues to the new state machine

In the old machine, merging a PR moved a task straight toward `state:closed`. Now a merged task
waits in `state:evidence` for the gate-3 documentation commit. Find tasks that were merged but whose
status was never raised:

```bash
# merged (Issue closed by the PR) but still carrying a working state
gh issue list --repo <owner>/<product-repo> --state closed --label state:merge --json number,title
# closed and marked closed, but the evidence was never provided
gh issue list --repo <owner>/<product-repo> --state all --label state:closed --label evidence:missing --json number,title
```

For each one whose register entry is still missing:

```bash
gh issue edit <N> --repo <owner>/<product-repo> \
  --remove-label state:merge --remove-label state:closed \
  --add-label state:evidence --add-label waiting-on-human
```

Tasks whose register entry is already in place get `state:closed` and no `waiting-on-human`.

**Check:** the label-guard rules (step 8) hold on every open Issue — exactly one `state:*` label,
`waiting-on-human` on each of `state:decision`, `state:merge`, `state:evidence`:

```bash
gh issue list --repo <owner>/<product-repo> --state open --limit 500 --json number,labels \
  --jq '.[] | [.labels[].name] as $l
        | select(any($l[]; test("^(state:|role:)|^waiting-on-human$")))
        | select([$l[] | select(startswith("state:"))] | length != 1) | .number'
```

(expected: no output). Like the guard itself, it skips Issues with no process label at all.

---

### 7. Registers

Compare what you have with [`process/registers/`](process/registers/README.md) and add what's
missing. Two changes matter for existing registers:

- **Cost register → one file per row.** Keep the existing table as it is (rename it, e.g.
  `cost-register-until-<date>.md`) — its numbers stay valid history. New calls write
  `<cost-register-dir>/<date>_<task>_<phase>_<role>_<n>.json` per
  [`cost-register.md`](process/registers/cost-register.md). Rows before the upgrade have no
  `model`; don't backfill it from memory — "no data" is the honest value.
- **Architecture-sensitive paths** — a new file, read by the fast lane. Create it even while the
  fast lane is off, so the Architect can maintain it from the start.

If your capability register keeps mutations, add a `Patch` column for the links to mutation patches.

---

### 8. New files and settings

| What | Where in the product repo | Source |
|---|---|---|
| Label guard workflow | `.github/workflows/label-guard.yml` | `process/workflows/label-guard.yml` |
| Shared permissions | `.claude/settings.json` | `TEAM-CONTRACT-TEMPLATE.md` §2a |
| Invariant assertions for [M] rules | your CI | `process/invariant-assertions.md` |

Check the merge settings against the new recommendation — `required_linear_history` should be
`false` unless you merge with squash only:

```bash
gh api repos/<owner>/<product-repo>/branches/main/protection --jq .required_linear_history.enabled
```

(on a free private repository this call returns `403` — there is no protection to check).

**Check:** give a test Issue two `state:*` labels — within a minute `label-guard` comments and the
run is red; remove one and the next run is green.

---

### 9. Recalibrate before trusting the reports

The Guardian's and QA's definitions changed, and every role now runs on the calling session's
model instead of a fixed one. By the kit's own rule both are a definition change
([`calibration/README.md`](calibration/README.md), "When to repeat it"):

- **Invariant Guardian** — method 1 again (seeded set + clean run). With [M] rules backed by CI
  assertions, the answer key for those rules becomes "cites the green assertion run".
- **Reviewer** — method 2 again, if the model it now inherits differs from the one it was
  calibrated on.
- Record the model with every result.

Until then, treat an evaluating role's `PASS` as unconfirmed at gate 2.

---

### 10. Confirm on one task

Run one small task with the updated `/task` from start to finish, as in
[`bootstrap-guide.md`](process/bootstrap-guide.md) step 10. What should be visibly different from
before:

- the worktree exists from the first role call, and the analysis roles' cost rows are commits on
  its branch;
- "boundary check: clean" in the notes after the Architect and QA;
- the PR opens after verification and carries the mutation patch;
- after the merge the Issue sits in `state:evidence` with `waiting-on-human` until you paste the
  register entries.

When that holds, the upgrade is done — delete the `pre-ninefold-upgrade` tags when you no longer
need the way back.
