# Invariant assertions — moving the Guardian's mechanical rules into CI

> Pattern to adapt. The SQL below is an EXAMPLE for PostgreSQL with a `tenant_id` isolation
> column — substitute your engine, your boundary column name, and your own rule list. The
> structure (a silent-zero guard, one query per rule, a contrast fixture, dated exceptions) is what
> should stay.

## Why

The Invariant Guardian costs on the order of 100–160k tokens per run and runs at least twice on a
task with one corrective round (measured numbers: `../FrameworkDoc.md`, section 6, and your own
cost register).
A good part of its checklist doesn't need judgment at all: "does every foreign key on a tenant table
carry the tenant column" has one correct answer that a catalog query gives in milliseconds, the
same way every time, on every commit — not only on the ones someone remembered to audit.

This is the framework's own rule applied to the Guardian: **manual upkeep is replaced by an
assertion** (`../FrameworkDoc.md`, section 13). The Guardian keeps what really needs reading —
and for the mechanical rules it checks one thing: that the assertion ran on this commit and was
green.

## Step 1 — classify the checklist

Go through the Guardian's list and mark each rule:

- **[M] mechanical** — decidable from the schema, the file tree, or a search, with no knowledge of
  intent. These move to CI.
- **[J] judgment** — needs to understand what the code is meant to do (is this one command against
  the whole aggregate? does this path log personal data?). These stay with the Guardian.

Classify by what can be checked **reliably**, not by what can be approximated. A grep that catches
80% of cases and misses the rest silently is worse than leaving the rule to the Guardian — it
produces a green check that reads as full coverage. `../agents/invariant-guardian.md` carries an
example classification of its example list.

## Step 2 — one query or script per [M] rule

Tested example for PostgreSQL. Each query returns **violations**; an empty result means the rule
holds. Query `A0` is not a rule — it's the guard against a silent zero: a run against an empty or
wrong database returns no violations for every rule, and must fail on `A0` instead of passing.

```sql
-- Scope: ordinary and partitioned tables outside system schemas.
-- A0. Guard against a silent zero: the run must have looked at something. Fail if 0.
SELECT 'A0 tables in scope' AS assertion, count(*)::text AS object
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%';

-- A1. Row-level security enabled AND forced on every table.
SELECT 'A1 RLS not enabled+forced' AS assertion, format('%I.%I', n.nspname, c.relname) AS object
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
  AND NOT (c.relrowsecurity AND c.relforcerowsecurity);

-- A2. No point-in-time column without a time zone.
SELECT 'A2 timestamp without time zone' AS assertion,
       format('%I.%I.%I', table_schema, table_name, column_name) AS object
FROM information_schema.columns
WHERE data_type = 'timestamp without time zone'
  AND table_schema NOT IN ('pg_catalog', 'information_schema');

-- A3. Every foreign key from a tenant table to a tenant table pairs the local tenant column with
--     the referenced tenant column, position by position. Checking only that the local key
--     contains tenant_id is not enough: FOREIGN KEY (parent_id, tenant_id) REFERENCES
--     parent (tenant_id, id) contains it, and compares the local tenant with the parent's id.
--     A reference to a table without a tenant column (global reference data) is out of scope.
SELECT 'A3 FK does not pair tenant with tenant' AS assertion,
       format('%s %I', c.conrelid::regclass, c.conname) AS object
FROM pg_constraint c
WHERE c.contype = 'f'
  AND EXISTS (SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.conrelid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
  AND EXISTS (SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.confrelid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
  AND NOT EXISTS (
    SELECT 1
    FROM unnest(c.conkey, c.confkey) AS k(local_attnum, referenced_attnum)
    JOIN pg_attribute la ON la.attrelid = c.conrelid  AND la.attnum = k.local_attnum
    JOIN pg_attribute ra ON ra.attrelid = c.confrelid AND ra.attnum = k.referenced_attnum
    WHERE la.attname = 'tenant_id' AND ra.attname = 'tenant_id');

-- A4. Every unique index on a tenant table (constraints included — they are backed by one) starts
--     with the tenant column. Expression indexes (indkey[0] = 0) are reported too: the rule can't
--     be verified for them mechanically, so they need a named exception, not silence.
SELECT 'A4 unique index not led by tenant column' AS assertion,
       format('%s %s', i.indrelid::regclass, i.indexrelid::regclass) AS object
FROM pg_index i
LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
WHERE i.indisunique
  AND EXISTS (SELECT 1 FROM pg_attribute t
              WHERE t.attrelid = i.indrelid AND t.attname = 'tenant_id' AND NOT t.attisdropped)
  AND a.attname IS DISTINCT FROM 'tenant_id';
```

Run them in CI **against a database migrated from scratch by the same migrations as production**
— not against a hand-made schema, which drifts from the migrations within weeks.

Rules outside the schema get the same shape as a script: e.g. "no business code reads the system
clock" as a search for the forbidden calls outside an allowlist of files; "every endpoint declares
a permission" as a test that enumerates the registered endpoints. Each such script reports how
many files/endpoints it looked at, and fails on zero.

## Step 3 — a contrast fixture, checked on every run

An assertion that has stopped checking anything (a changed column name, a typo, a wrong schema)
keeps returning "no violations" — the same failure as a tool that returns success while being
wrong (`../FrameworkDoc.md`, section 9). So each run first applies a fixture where every `bad_`
object must be reported and every `good_` object must not (`../calibration/README.md`, Method 3).
The fixture the queries above were verified against (PostgreSQL 16) — `good_*` objects produced
no rows, `bad_*` objects produced exactly one row per seeded violation:

```sql
CREATE TABLE good_parent (tenant_id uuid NOT NULL, id uuid NOT NULL, code text NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, id), UNIQUE (tenant_id, code));
ALTER TABLE good_parent ENABLE ROW LEVEL SECURITY; ALTER TABLE good_parent FORCE ROW LEVEL SECURITY;

-- A global reference table (no tenant column) is out of scope of the tenant rules.
CREATE TABLE good_country (code text PRIMARY KEY, created_at timestamptz NOT NULL);
ALTER TABLE good_country ENABLE ROW LEVEL SECURITY; ALTER TABLE good_country FORCE ROW LEVEL SECURITY;

-- Three correct references: the composite key, the same key with its columns listed in another
-- order (still tenant to tenant), and a reference to global data.
CREATE TABLE good_child (tenant_id uuid NOT NULL, id uuid NOT NULL, parent_id uuid NOT NULL,
  country text NOT NULL,
  PRIMARY KEY (tenant_id, id),
  CONSTRAINT good_child_parent_fk FOREIGN KEY (tenant_id, parent_id) REFERENCES good_parent (tenant_id, id),
  CONSTRAINT good_child_reordered_fk FOREIGN KEY (parent_id, tenant_id) REFERENCES good_parent (id, tenant_id),
  CONSTRAINT good_child_country_fk FOREIGN KEY (country) REFERENCES good_country (code));
ALTER TABLE good_child ENABLE ROW LEVEL SECURITY; ALTER TABLE good_child FORCE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX good_child_parent_ux ON good_child (tenant_id, parent_id);

-- A1: RLS enabled but not forced
CREATE TABLE bad_not_forced (tenant_id uuid NOT NULL, id uuid NOT NULL, PRIMARY KEY (tenant_id, id));
ALTER TABLE bad_not_forced ENABLE ROW LEVEL SECURITY;

-- A4: a tenant table whose id is unique on its own
CREATE TABLE bad_parent (tenant_id uuid NOT NULL, id uuid NOT NULL, PRIMARY KEY (tenant_id, id),
  CONSTRAINT bad_parent_id_uq UNIQUE (id));
ALTER TABLE bad_parent ENABLE ROW LEVEL SECURITY; ALTER TABLE bad_parent FORCE ROW LEVEL SECURITY;

-- A1 (no RLS), A2 (timestamp without zone), A3 (FK without tenant), A4 (unique index)
CREATE TABLE bad_child (tenant_id uuid NOT NULL, id uuid NOT NULL, parent_id uuid NOT NULL,
  code text NOT NULL, happened_at timestamp NOT NULL,
  PRIMARY KEY (tenant_id, id),
  CONSTRAINT bad_child_parent_fk FOREIGN KEY (parent_id) REFERENCES bad_parent (id));
CREATE UNIQUE INDEX bad_child_code_ux ON bad_child (code);

-- A3: the tenant column is in the key, but paired with the parent's id
CREATE TABLE bad_swapped (tenant_id uuid NOT NULL, id uuid NOT NULL, parent_id uuid NOT NULL,
  PRIMARY KEY (tenant_id, id),
  CONSTRAINT bad_swapped_fk FOREIGN KEY (parent_id, tenant_id) REFERENCES good_parent (tenant_id, id));
ALTER TABLE bad_swapped ENABLE ROW LEVEL SECURITY; ALTER TABLE bad_swapped FORCE ROW LEVEL SECURITY;
```

Expected result: `bad_not_forced` and `bad_child` under A1, `bad_child.happened_at` under A2,
`bad_child_parent_fk` and `bad_swapped_fk` under A3, `bad_parent_id_uq` and `bad_child_code_ux`
under A4 — and nothing else. Run the fixture in a separate, throwaway schema or database, never in
the one the real assertions check.

### A catalog check is not the claim — test the behavior too

A3 says the keys are *shaped* right. The claim is that a row of one tenant can't reference another
tenant's row. Prove that directly, once per isolated relation, in the same throwaway database:

```sql
INSERT INTO good_parent (tenant_id, id, code, created_at)
  VALUES ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000b1', 'P', now());
INSERT INTO good_country (code, created_at) VALUES ('PL', now());
DO $$
BEGIN
  INSERT INTO good_child (tenant_id, id, parent_id, country)
    VALUES ('00000000-0000-0000-0000-00000000000a', gen_random_uuid(),
            '00000000-0000-0000-0000-0000000000b1', 'PL');   -- tenant A pointing at tenant B's parent
  RAISE EXCEPTION 'BEHAVIOR FAILED: a cross-tenant reference was accepted';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'behavior ok: cross-tenant reference rejected';
END $$;
```

Its contrast: the same insert through a single-column key (`FOREIGN KEY (parent_id) REFERENCES
parent (id)`) is accepted and the block fails — verified on PostgreSQL 16, so the test can fail
for the reason it exists.

## Step 4 — exceptions with an owner and a date

A real schema has legitimate exceptions (a global reference table, a deliberate expression index).
They go into one exceptions file read by the assertion runner — each with the object, the reason,
an owner, and a date after which the exception stops applying and the check blocks again
(`../FrameworkDoc.md`, section 8). An exception without a date is not accepted by the runner.

## Step 5 — what changes for the Guardian

For each [M] rule the Guardian no longer reads the code. It confirms that the assertion job ran
**on the commit under review** and was green, and cites it in "Checked and clean". A [M] rule
without an assertion yet is still checked by reading — and the missing assertion is reported as a
low-severity finding, so the gap closes instead of becoming permanent.
