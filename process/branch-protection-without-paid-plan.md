# Protecting `main` without a paid plan

A record of a limitation almost every private project on GitHub's free plan runs into, and what
to do instead.

## What happens

```
gh api -X PUT repos/<owner>/<repo-backend>/branches/main/protection --input ...
{
  "message": "Upgrade to GitHub Pro or make this repository public to enable this feature.",
  "status": "403"
}
```

**Branch protection and rulesets are not enforced on private repositories on the free plan.**
This applies to both mechanisms — classic branch protection and the newer rulesets.

## Why not "switch to public, set it up, switch back to private"

This is the first reflex and it's wrong for two reasons.

**The rules stop being enforced, but they don't disappear.** After switching back to private,
GitHub leaves the configuration in place and stops applying it, signaling this with a message in
the interface. You're left with the worst possible state: protection looks set up, and a direct
push goes through. This is exactly the class of defect this framework names explicitly — *a
security mechanism that doesn't work despite appearances*.

**A public repository, even for a minute, is irreversible.** Crawlers, forks, cached copies. If
the repository holds a data model, architectural decisions, and business logic — that is the
entirety of the product's edge.

## The choice

| Variant | What it gives | Cost |
|---|---|---|
| **Paid team plan** | Real server-side protection: required checks, push ban, linear history | Subscription per person; at 2–3 people, on the order of a dozen or so dollars a month |
| **`pre-push` hook** | Denies a direct push to `main` on this machine | Zero |
| Nothing | Discipline | Zero, until the first mistake |

Check whether the repository belongs to a personal account or to an organization
(`gh api users/<owner> --jq .type`) — a plan that raises limits for a personal account doesn't
apply to an organization, and the API's error message can be misleading in this context.

**A second, independent argument for the paid plan: Actions minutes.** Removing path filters from
the `pull_request` trigger (see [`ci-and-branch-protection.md`](ci-and-branch-protection.md))
means every pull request — including purely documentation-only ones — runs the full test suite.
The free plan gives a limited pool of minutes per month for private repositories. At a dozen or so
PRs a month, the pool usually suffices, but it's a number to watch in the log, not to assume.

Recommendation: **the hook now, the paid plan before letting in the first client.** The hook is
enough as long as the only one committing is you and agents operating on your account. It stops
being enough the moment a second person shows up or agents get their own technical account —
because at that point protection must live server-side, not in the configuration of one clone.

## The hook — what it gives, and what it doesn't

**Gives:** a refusal of `git push origin main` with a message pointing to a pull request. Catches
the most common real-world mistake — being mistaken about the current branch.

**Doesn't give:** anything server-side. `git push --no-verify` goes through. Another clone
without `core.hooksPath` doesn't have it at all. It doesn't enforce green checks before merging.

This is a **guard, not a gate**, and is described that way in the file itself. A person who types
`--no-verify` has made a decision and knows it. A person who forgot which branch they were on
made no decision at all — and that's the case the hook catches.

## Installation

The file is at [`hooks/pre-push`](hooks/pre-push). Copy it into the target repository and enable
it:

```powershell
Set-Location <path-to-product-repo>
New-Item -ItemType Directory -Force .githooks | Out-Null
Copy-Item <path-to-process-repo>\process\hooks\pre-push .githooks\ -Force
git add .githooks/pre-push
git update-index --chmod=+x .githooks/pre-push
git config core.hooksPath .githooks
```

**Into the target repository's `.gitattributes` — this is the load-bearing half:**

```
.githooks/** text eol=lf
```

Without this entry, under the rule `* text=auto`, a script written on Windows gets CRLF, and
`#!/bin/sh` with a returned carriage return ends up with a `bad interpreter`. The hook is then
**present, wired up, and lets every push through** — exactly the class of failure it stands
against. It's worth having this same entry in the process source repository too, because the file
is sometimes copied manually from there, and then CRLF enters the product repository's content
before its `.gitattributes` normalizes anything.

`git config core.hooksPath` is **local to the clone** and isn't versioned — every new clone needs
this one line.

## Verification

Checked on a dummy repository, four cases:

| Case | Expected | Result |
|---|---|---|
| `git push origin main` | refusal | exit code 1, hook message, **no branch appeared on the remote repository** |
| `git push origin feature/x` | pass | passed |
| `git push --no-verify origin main` | pass | passed, as described |
| without `core.hooksPath` | no protection | passed — the file alone in the repository isn't enough |

The last row is why you need to do **both** checks on your own machine:

```powershell
git config --get core.hooksPath      # should return: .githooks
git push origin main                 # should be refused
```

The first without the second proves nothing — a hook present but not wired up looks identical to
a working one. And conversely: `git push origin main` on a branch already up to date ends with
`Everything up-to-date` before git even runs the hook — the response looks like success and says
nothing about protection. Without a commit, test the logic directly, feeding the hook the
reference lines git gives it:

```bash
printf 'refs/heads/x 1 refs/heads/main 2\n'       | .githooks/pre-push origin url; echo "code=$?"   # 1
printf 'refs/heads/x 1 refs/heads/feature/x 2\n'  | .githooks/pre-push origin url; echo "code=$?"   # 0
```

The second line is a counter-test: without it, "denies on `main`" would also be satisfied by a
hook that always denies.

## What this means for the criterion "a direct push to main is rejected"

It's satisfiable by the hook, but **in a narrower scope than on the server** — locally instead of
server-side. That's a deviation, not a full realization, and needs to be recorded as such in the
log, if your process has a decision log.

What the hook does **not** replace from full server-side protection: required checks before
merging, linear history, a force-push ban, the requirement to resolve comments. Those come back
only with the paid plan.

In practice, this means that **gate 2 remains a decision, not an assertion**: a PR with red CI
can technically still be merged; only your attention prevents it.
