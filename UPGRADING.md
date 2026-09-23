# Upgrading from the initial release

> For teams that installed the kit from the initial commit `4a726f3` (2026-09-17) and want to move
> to the version after PR #6 (`859be9e`, 2026-09-23). If you are installing from scratch, follow
> [`process/bootstrap-guide.md`](process/bootstrap-guide.md) instead.

The upgrade touches two places: your **process repository** (your copy of this kit) and every
**product repository** that received roles, templates and commands from it. Nothing in it is
automatic — like the rest of the process, each step ends with a check, because most of these
changes fail silently when half-done.

**Time:** about half a day per product repository, plus recalibration of the evaluating roles.

---

## What changed, in one table

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
[#6](https://github.com/TanerCRB/NineFold/pull/6).

---

## 0. Before you start

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

## 1. Process repository: take the new version

Your process repository is a copy of this kit with your own edits — adapted roles, a filled-in
configuration. Bring the new version in as a merge on a branch, not by overwriting files:

```bash
git remote add upstream <url-of-this-kit>      # once
git fetch upstream
git switch -c upgrade/ninefold
git merge upstream/main
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

If you used `sync-github.mjs` before, note that in the initial version it only worked when run from
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

## 2. Product repository: protect the hook's line endings

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

## 3. Labels and templates

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

## 4. Roles

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

## 5. Task commands

Your `.claude/commands/task.md` and `task-status.md` are adapted copies, so they are merged by
hand. See exactly what changed upstream:

```bash
# in the process repository
git diff 4a726f3 main -- process/task-command.md
git diff 4a726f3 main -- process/task-status-command.md     # no changes
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

## 6. Migrate open Issues to the new state machine

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

## 7. Registers

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

## 8. New files and settings

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

## 9. Recalibrate before trusting the reports

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

## 10. Confirm on one task

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
