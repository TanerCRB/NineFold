# Deployment artifact versioning — pattern

> Anonymized, generalized version of a real rollout plan. Specific fields (ADR numbers, Issue
> numbers, dates, repository names) removed — what remains is the decision schema and the
> principles derived from it, together with the rejected variants and the reason for rejection,
> because the reason for rejection is part of the decision, not material to discard.

Scope: **deployment artifacts** (images/packages built and deployed), not API contract versioning
(that's usually a separate architectural decision, with a separate schema — e.g. a major version
in the resource path).

---

## 1. Questions that must be settled as a single architectural decision

Release versioning touches multiple repositories at once (typically: backend and frontend
separately) and has consequences for the health/readiness API, the container image, and the user
interface — this is a decision requiring gate 1, not a setting to slip in quietly alongside
another task.

**Q1. Version scheme.**
Recommendation: **SemVer, a separate line for each repository/component.** Alternatives and their
cost: one shared version for the whole product requires releasing everything at once even when
only one component changed, and lies about a partial release; CalVer (date-based versioning) is
cheap to maintain, but carries no statement about backward compatibility, and that's often half
the reason for doing this at all.

**Q2. Source of truth.**
Recommendation: **a file in the repository** (e.g. a version field in the project file/package
manifest), not `git describe` nor a tag as the sole source. Reason: if the image build context
doesn't have access to git history (a common case — `.dockerignore` excludes `.git`), the value
"from git" would have to arrive from outside as a build argument, i.e. it could be given
arbitrarily — exactly the failure mode usually already ruled out for the revision identifier
(SHA). The file travels to the artifact together with the code and is visible in the pull request
diff, so bumping the version is a **decision made in review**, not a side effect of the build.

**Q3. When to start `1.0.0`.**
Recommendation: **only at the point the environment class changes to pre-production/production**,
not after an arbitrary number of commits. `1.0.0` should mean something real about readiness, not
be a badge.

**Q4. Artifact tag/label.**
Recommendation: **`<version>-<revision>`**, not the version alone. The version alone lets two
different builds land under the same name; the revision alone has no ordering (you can't say
which is newer). The tag carries both facts at once.

**Q5. Who bumps the version.**
Recommendation: **a human at gate 2, the production role/agent only proposes** the value in the
PR description. Consistent with the framework's general principle: the executor of a change does
not raise the status/version. Automatically deriving the version from commit message format is
faster, but then the version stops being a decision and starts being a side effect of a text
format.

**Q6. Compatibility between components (e.g. backend ↔ frontend).**
Recommendation for low risk: the dependent component **declares the required version/major of the
other side and compares it at runtime**; a mismatch is logged and shown in the UI, but **does not
refuse to start** — as long as the environment is pre-production. The alternative (refusing to
start on a mismatch) protects against silent incompatibility, but takes down the dependent
component every time the other side simply isn't responding — enable it only on an environment
where that cost is justified.

---

## 2. Where the version needs to be visible (surface)

Regardless of the stack, the same set of places recurs in practice:

- **A version source file** in the repository (package manifest, build properties file) — one
  place, everything else quotes it.
- **The health/readiness endpoint** (`/health` or equivalent) returns version **and** revision as
  separate fields — adding a field to an existing contract is usually a backward-compatible
  change, but name it explicitly as part of this decision, so there's no doubt.
- **The image or package tag/label.**
- **A visible spot in the UI** (footer, diagnostic screen) — for a person checking what's running
  on an environment without access to the repository.
- **A changelog** (`CHANGELOG.md` or equivalent) — one entry per version, with a short description
  and a link to the tracking Issue, if you have an issue tracker.

### Invariants worth guarding regardless of stack

- **The version is baked into the artifact at BUILD time, never at RUNTIME.** The ability to
  supply it at process startup is the ability to lie about the artifact's contents.
- **A missing version does not silently abort the build — it publishes an explicit
  "unknown".** The same principle as for every other boundary value in this framework: silence is
  worse than an explicit "don't know".
- **The revision (SHA/commit) remains independent of the version.** The version doesn't replace
  it — an artifact without a revision stops being unambiguously tied to a specific state of the
  code.
- **One place for delivery status.** Neither the changelog nor the architectural decision record
  should themselves drive tracking of what's actually been deployed — a separate, narrower
  capability/readiness register serves that purpose (see `FrameworkDoc.md`, section 7).

---

## 3. Mechanical enforcement, not discipline

**Bumping the version in the source file without a corresponding changelog entry breaks the CI
pipeline.** "We replace manual upkeep with an assertion" — this is a project rule, not
decoration, and applies here to exactly the same mechanism as elsewhere in the framework.

Testing this check via **mutation** is especially instructive here — two documented cases where
the first version of the check survived mutation despite looking complete:

1. **Contrast on the helper function, not on its call site.** The test removed the version field
   from one place and checked that the comparison function detects it — but the comparison
   function then received the value `unknown` on both sides of the comparison, so formally they
   "matched". General conclusion: a contrast test proves the mechanism **can** answer correctly,
   not that anyone actually **calls** it in the real flow — you have to test both things
   separately.
2. **A check running on every module import, not just where it was meant to.** Discovered only
   when trying to remove the rule from the tool — it turned out that the import side effect broke
   the entire test file before a single test in it ran, which masked a check that was working
   (or not working) correctly.

Conclusion worth repeating for any similar check in another project: **a contrast test at the
level of a single function is not enough if that function is called from somewhere other than the
test assumes — verify the call path too, not just the logic itself.**

---

## 4. Rollout order

Versioning touches more than one repository at once, so roll it out in stages, each as a separate
pull request, in dependency order (e.g. first the source of truth and surface in each component
separately, then the point of contact between components, and finally enforcement in the pipeline
and the deployment procedure) — the stage checking compatibility between components has nothing
to check before both components actually expose a version, and enforcement in CI makes no sense
before all the surfaces exist.

Explicitly name in the decision document what the rollout **does not** prove at a given point
(e.g. "the deployment procedure has not yet been exercised with the new tags" or "the labels on
built artifacts are not yet proven by a test, only by intent in the build file") — consistent with
the framework's general principle that the "what this doesn't prove" section is a mandatory
field, not an optional caveat.

---

## 5. Out of scope for this pattern (name this explicitly in your own version of the decision)

- The artifact registry and promoting the same artifact between environments (that's a separate
  decision — identification by digest, not by tag, if you have a registry).
- API contract versioning (major version in the resource path) — usually a separate, earlier
  decision.
- Database schema version — a separate register, with a different meaning than the release
  artifact version.
- Automatically generating the changelog from commit messages.
- Signing artifacts and a software bill of materials (SBOM).
