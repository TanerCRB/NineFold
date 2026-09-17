# Gaps between repositories — the only channel

`<repo-backend>` and `<repo-frontend>` evolve at different paces and constantly find gaps in each
other. The frontend needs an endpoint that doesn't exist. The backend exposes a field nobody
shows. A contract has the wrong shape and it only comes out at the first call.

**The only channel through which one repository asks another for work is an Issue filed in the
repository that has to do that work.**

Nothing else counts. A gap-register entry doesn't count, a code comment doesn't count, an
agreement reached in conversation doesn't count, nor does a note in an architecture document. If
there's no Issue where the work is, the work has not been ordered — it has been noticed.

## Why exactly this way

A gap register without corresponding Issues in the other repository is a list the other side
doesn't know about. The same gap can end up found independently on both sides — once as a local
entry, once by a role reading the other repository's code — which is two paths leading to the
same defect and zero work ordered. This is not a documentation failure. It is the absence of a
channel.

## Direction: the Issue goes where the work is

| Who found it | Who must fill the gap | Where the Issue is created |
|---|---|---|
| `<repo-frontend>` | backend | **`<repo-backend>`** |
| `<repo-backend>` | frontend | **`<repo-frontend>`** |

Not the other way around, and not both at once. An Issue in the reporting repository describes
work that repository won't perform — i.e. it just hangs until someone closes it for age.

## What is not allowed

An AI role or a human working in one repository does **not**:

1. **Open a pull request in the other repository.** Not even a small one, not even an obvious
   one. A change in someone else's repository bypasses its gates, its Invariant Guardian, and its
   decision register.
2. **Edit the other repository's documentation** — including its architectural decisions, its
   plan, and its activity log. A request to change a decision is also an Issue.
3. **Report a gap only on its own side.** An entry in the gap register without an Issue is a note
   to oneself.
4. **Set priority in someone else's repository.** The reporter describes the **cost of the gap**;
   the order of work is set by the Product Owner of the repository where the work must happen.
   Otherwise the frontend plans the backend's schedule and the backend plans the frontend's — and
   both are right, and nothing comes of it.
5. **Treat an agreement reached in conversation as an order.** "We agreed they'd add the field"
   leaves no trace that survives a week.

## What remains on the reporting side

The gap register (e.g. `docs/BACKEND-GAPS.md` and its counterpart on the other side) **doesn't go
away and isn't a channel**. It has a different job, worth stating explicitly:

> The gap register answers the question **"why does this repository look the way it looks"**.
> The Issue answers the question **"what must the other repository do"**.

The first is needed locally, when reading code: someone looks at a field that always shows a dash
and needs to find the reason in one place. The second is needed wherever someone is planning
work.

So that the two don't drift apart within a month, **every entry in the gap register carries a
link to its Issue** — and the documentation validator checks this. An entry without a link must
instead have an explicit line saying there is no report and why. Silence is not acceptable: it
allows not reporting and forgetting about it.

```markdown
**Reported:** [<repo-backend>#42](https://github.com/<owner>/<repo-backend>/issues/42)
```

```markdown
**Reported:** no — waiting on ADR-0015 to be resolved; reporting earlier would be premature
```

## What the Issue must contain

The `4-gap-from-the-other-repo.yml` template enforces seven fields. Two of them are unusual, and
they're what decides whether a report is an order or a wish:

**"What I will remove on my side once this exists".** The reporter states what they will remove
or replace — client-side aggregation, a workaround, a grayed-out field. Without this sentence
there's no way to know whether anyone actually needs the gap filled, and the recipient has no way
to check whether their work has been acknowledged as received.

**"Closing condition".** Observable, on the recipient's side — a test name, a response shape, an
error code. Not "the frontend will be able to show history". A report without a closing condition
closes whenever someone decides it's enough.

Plus five ordinary ones: what's missing in contract terms (endpoint, field, error code — not
screen terms), where this shows up for the reporter, with a file and lines, what the impact on the
user is today, a proposed shape **as a proposal**, and a link to the entry in the gap register.

## Closing is two-sided

Closing the Issue in the recipient's repository **does not close the gap**. There's a second
half left: the reporter must do what they committed to — remove the workaround. Until they do,
the system has two paths to the same thing, which is worse than one bad one.

Hence the gap register entry has two states, not one:

| State | Meaning |
|---|---|
| `reported` | The Issue exists, the link is in the entry |
| `delivered` | The Issue is closed on the recipient's side |
| `closed on our side` | The workaround has been removed — only now does the entry leave the register |

An entry leaves the register only in the third state.

**An entry does not update itself the moment the other side delivers.** This is the most common
pitfall with this register: someone reads a reason like "we're mocking this because the other side
doesn't have it yet," treats it as a current fact, and builds a decision on it — while the Issue on
the other side was closed a week ago and nobody came back to update the entry. Before you treat
something as a gap, check the current state of the Issue in the other repository — don't trust the
entry's text alone.

## Labels

An Issue from this path gets `gap:reported-by-frontend` or `gap:reported-by-backend` — so a
single filter can show how much work in this repository comes from the other side. Until the
recipient has agreed to the contract's shape, it carries `gap:awaiting-contract`: this is the
state where such reports most often die quietly, so it gets its own name.

Otherwise the Issue lives through this repository's normal cycle, with its gates — because from
the moment it's filed, it's its own work, not someone else's.
