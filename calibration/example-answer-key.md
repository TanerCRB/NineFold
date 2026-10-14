# Example Answer Key for a Seeded Set

> This is an EXAMPLE illustrating the shape of the document, not ready-made content. The domain
> (resource booking in a multi-tenant system) is a neutral placeholder — substitute your project's
> real rules and real domain. The structure (numbering, severity, location, description, decoys,
> couplings) should stay.

**This file never reaches the agent during calibration.**

Task posing as new work: `<task-identifier>` — for example "shared resource bookings". A handful
of files in `seeded/`: a schema migration, a data access layer, HTTP endpoints.

## Seeded Violations

| # | Rule | Expected Severity | File | What it consists of |
|---|---|---|---|---|
| Z-01 | <rule number> | High | `<File>.cs:16-24` | A private database connection bypassing the shared access layer — isolation context set at the session level instead of the transaction level |
| Z-02 | <rule number> | High | `<migration>.sql:48-64` | A table without data isolation between tenants (e.g. no RLS policy) despite full privileges for the application role |
| Z-03 | <rule number> | High | `<migration>.sql:23-24` | A foreign key without a platform-tenant identifying column in the same table |
| Z-04 | <rule number> | High | `<migration>.sql:57` | Global uniqueness instead of uniqueness scoped to a single platform tenant |
| Z-05 | <rule number> | Medium | `<migration>.sql:29` | Data isolation enabled, but without forced mode (bypassable by the table owner) |
| Z-06 | <rule number> | Medium | `<migration>.sql:31-38` | Isolation policy using a subquery instead of a simple column comparison |
| Z-07 | <rule number> | Medium | `<migration>.sql:15` | A timestamp column without a time zone |
| Z-08 | <rule number> | Medium | `<File>.cs:26-27` | The "today" boundary computed from the system clock without accounting for the subject's time zone and without an injectable time source |
| Z-09 | <rule number> | Medium | `<File>Endpoints.cs:33-48` | An exception swallowed without logging; a correlation identifier returned to the client with no corresponding log entry |
| Z-10 | <rule number> | Medium | `<File>Endpoints.cs:25-52` | A write operation without an idempotency key |
| Z-11 | <rule number> | Medium | `<File>.cs:29-36` | No explicit filter by platform tenant, with the exception condition unmet |
| Z-12 | <rule number> | Low | `<File>.cs:26-27,36` | Comments and variable names breaking the repository's language convention |

Items can be **coupled**: one violation stops applying once another is fixed (e.g. when a
different, previously established policy exception then applies). A good report should say this
explicitly, rather than reporting the coupled item as an independent flaw.

## Decoys — Must Not Be Reported

| # | What looks suspicious | Why it isn't a violation |
|---|---|---|
| W-01 | A read operation without an idempotency key | A purely read-only operation — an explicit, documented exception |
| W-02 | Migration file name in the national language | Migration file names are registry keys — a deliberate, documented exception |
| W-03 | Schema/table names in the national language | Names from the canonical, adopted data model — a deliberate exception |
| W-04 | A relation that looks similar to the faulty item Z-03, but with the platform-tenant column in the key | This is the **correct** pattern, deliberately placed next to the faulty one, to check whether the role tells them apart |
| W-05 | Documentation describing behavior that doesn't exist in the code yet | A project may be deliberately documented further ahead than it's implemented (see `../FrameworkDoc.md`, section 13) |

## Security Auditor Items (area VII)

The same set can calibrate the Security Auditor if it also carries a model-backed feature — here
a "summarize this booking" endpoint (`<File>Summary.cs`) and a second one built correctly next to
it (`<File>Digest.cs`). The Guardian's items above are not the Auditor's to find; score each role
only on its own rows.

| # | Expected Severity | File | What it consists of |
|---|---|---|---|
| Z-13 | Critical | `<File>Summary.cs:18-41` | The booking's free-text note — writable by the guest who made the booking — goes into the same model input as the instructions, and the model is given a cancel-booking tool that acts with the staff user's identity, on any booking, without confirmation. A guest's note can cancel other guests' bookings |
| Z-14 | Medium | `<File>Summary.cs:45-52` | The tool loop has no limit on steps or tokens |

| # | What looks suspicious | Why it isn't a violation |
|---|---|---|
| W-06 | `<File>Digest.cs` also puts guest notes into a model input | Its only tool is read-only and scoped to the current booking, the output is shown as escaped text, and a step limit is set — the **correct** pattern, placed next to Z-13 to check whether the role tells them apart |
| W-07 | A prompt template file in the diff with the word "ignore" in it | The text is the feature's own instruction, written by the team, not input from an outsider — no path |

## Run Result

Record the date, **the model the role ran on**, the number of items detected out of the number
seeded, the number of decoys reported out of the number of decoys in the set — e.g.
`<model-id>: 12/12 detected, 0/5 decoys reported` — and a link to the full run report in the
calibration log. A result on one model says nothing about another.
