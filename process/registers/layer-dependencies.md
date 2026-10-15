# Layer dependencies

> Template. The task command reads it through `scripts/layer-check.sh` (`../task-command.md`,
> step 10a, "Layer check"). Each row names one layer: where its files live, how other code
> refers to it, and which layers it **must not depend on**. A reference added on a line of a task's
> diff that crosses one of those rules is a finding for the Architect. A layer missing from this
> list is a layer nobody checks — when in doubt, add it.

| Layer | Path (glob) | Referenced as | Must not depend on | Why |
|---|---|---|---|---|
| `<domain>` | `<src/Domain/**>` | <`Acme.Domain`, `@/domain`> | <infrastructure, api> | <ADR-0003: the domain knows no storage and no transport> |
| `<application>` | `<src/Application/**>` | <`Acme.Application`, `@/application`> | <api> | <ADR-0003> |
| `<infrastructure>` | `<src/Infrastructure/**>` | <`Acme.Infrastructure`, `@/infrastructure`> | <api> | <ADR-0004: adapters are called, they don't call in> |
| `<api>` | `<src/Api/**>` | <`Acme.Api`, `@/api`> | — | <the outermost layer> |

**One layer and one glob per row.** A layer whose files live in several places gets one row per
glob, with the same name. `*` and `**` both match across directories, as in
`architecture-sensitive-paths.md`.

**Referenced as** lists, comma-separated, the prefixes other code uses for the layer: a namespace
(C# `using Acme.Domain.Pricing;`), a module (Python `from acme.domain import …`) or an import alias
(TS/JS `from '@/domain/price'`). A prefix matches on a boundary — `Acme.Domain` matches
`Acme.Domain.Pricing`, not `Acme.DomainEvents` — and the longest one wins. A relative import
(`'../domain/price'`) is resolved against the importing file and matched by the glob instead, so
it needs no prefix. `—` means the layer is reached only by path.

**Must not depend on** lists layer names from this table, or `—`. A name the table doesn't define
fails the check (exit 2) instead of being ignored. So does a table with only placeholder rows, and
a changed file that falls under the globs of two different layers.

The check reads **added lines only**. A rule broken before the task is not reported until
someone touches that line, and a one-off scan of the whole tree is a task of its own.
