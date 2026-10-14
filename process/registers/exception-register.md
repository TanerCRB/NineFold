# Exception register

> Template. Holds every **recorded exception** that outlived the pull request it was accepted in:
> a finding the human let through gate 2 on purpose, with an owner and a date after which it
> blocks again (`../../TEAM-CONTRACT-TEMPLATE.md`, §3a). Without this file, an exception lives
> only in a merged PR description, and nobody reads that again once the date passes.

Rules:

- **One exception per line, in the §3a format** — `scripts/exception-check.sh` reads this file,
  and a line in any other shape counts as no exception at all.
- An entry arrives through the gate-3 documentation PR, like every other register entry. It leaves
  through the gate-3 documentation PR of the task that fixed the finding. A renewal — a new date
  and a new reason — is the human's own edit, in a PR they merge.
- An agent never changes a date here. An expired entry is reported, not repaired.

Check:

```bash
scripts/exception-check.sh docs/exception-register.md
```

## Exceptions

<!-- The two lines below are a worked example: with "today" at 2026-10-14, the first one is live
and the second one expired on 2026-10-01. Replace them with your own; delete both if you have
none. -->

- Exception B1-07/R-02 — owner: @anna — reason: the retry storm on the export endpoint needs the shared queue that B1-09 builds; until then exports are rate-limited by the gateway — blocks again: 2026-11-30
- Exception B1-03/weakening-1 — owner: @bo — reason: the old invoice-number tests were removed with the numbering scheme; the replacement tests wait for the tax-office format in B1-05 — blocks again: 2026-10-01

What `/task-status exceptions` reports for them on 2026-10-14:

```
LIVE       B1-07/R-02  docs/exception-register.md:29  holds through 2026-11-30, owner @anna
EXPIRED    B1-03/weakening-1  docs/exception-register.md:30  blocks again since 2026-10-01 (13 days ago), owner @bo
exception-check: 1 finding(s) — as of 2026-10-14: 1 live, 0 expiring within 14 days, 1 expired, 0 malformed
```

The second line is the finding the weakening check raised on B1-03, open again: `@bo` either
renews the exception with a new date and reason, or it becomes a Story.
