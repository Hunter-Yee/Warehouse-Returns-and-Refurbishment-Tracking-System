# Midterm Scorecard: What We Looked For

Every project was reviewed on the same 10 dimensions. This scorecard is the course's definition of a professionally built database system — and it is also your roadmap for the final project (due Dec 18).

 

1. Audit table process

2. Build script idempotency & logging

3. Role-based entitlements

4. Scalable workflow management & enforcement

5. Scaled performance testing

6. ER diagram in draw.io

7. Exception handling — warning vs. critical hierarchy, meaningful messages to callers

8. Lineage from functional requirements → implementation → testing results

9. Version tags that feed into the build

10. Versioning of DB objects

 

What the best work in this class did:

 

- Audit: the Vehicle Service System keeps an append-only audit with full-row JSON — including rejected operations, which survive rollback — so even failed attempts leave evidence.

 

- Workflow: the Hair Salon platform models status transitions as data — a transition table with per-role permissions and one choke-point procedure. Adding a workflow step is a data change, not a code change.

 

- Entitlements: the Volunteer System has the strongest model: a locked definer account, least-privilege grants, and a mapping from login to person, with roles provisioned by default.

 

- Reproducible builds: Warehouse Returns clones the exact release tag, verifies the commit SHA, and validates a manifest before building. Digital Documents and the E-Commerce Dashboard committed real verification output.

 

- Diagrams & traceability: (draw.io source + exports); TDD carries a full traceability matrix, and specification discipline ( requirements, each mapped to objects and tests) is the model to copy.

 

Three gaps almost everyone shared:

 

1. Scaled performance testing. Most seeds were toy-sized (six appointments, seven users). Only one team ran real performance studies with captured output. A system that has never seen 100,000 rows has not been tested.

 

2. Warning vs. critical errors. Nobody distinguished "retry/ignore" warnings from "stop everything" critical errors for the calling application.

 

3. Identity by assertion. Several systems accept an actor ID as a procedure parameter and trust it. If the caller can simply claim to be an administrator, your entitlements are decoration. Resolve the actor from the database session (USER())

 

Your individual scores and feedback are in your project evaluations. Read the principle posts that follow — each one ends with what to do about it in your final project. Two extra posts go beyond the scorecard to the architecture model from lecture: 3A, "Two identities, always" (the system ID and the person it acts on behalf of — the same pattern that governs AI agents) and Principle 11, the Indicator Value pattern (reference data as data). Together with the generated audit tables (Principle 2) and metadata-driven workflow (Principle 4), they are one idea applied four ways: behavior lives in data; code just interprets it.

# Model first: the ER diagram is a contract

Principle 1 of 10 — Start with the model.

Your ER diagram is not documentation you draw after the fact; it is the contract your schema, procedures, and tests are built against. The strongest midterms kept a draw.io *source* file in the repo, exported PNG/SVG for readers, modeled weak entities correctly (the Digital Document portal's DocumentVersion), and wrote down keys and participation rules.

For the final: keep the .drawio source under version control, regenerate exports from it (never edit the picture), and when the schema and the diagram disagree, treat that as a bug.

# Audit from day one

Principle 2 of 10 — If it isn't audited, it didn't happen.

An audit table is not a log file. Done right (the standard: the Vehicle Service System), it is append-only, written in the *same transaction* as the business change, captures old and new values — and records *rejected* attempts too, in a way that survives the rollback of the operation that failed. That last point separates evidence from decoration: when something goes wrong, the failed attempt is exactly what you need to see.

The model we use — generated audit tables. Hand-maintaining an audit table for every transaction table does not scale: developers forget, schemas drift, and the audit table quietly stops matching the table it audits. In the model from lecture, the audit tables are *dynamically built from the transaction table's own definition* — the generator reads the main table's schema and produces (and maintains) the matching audit table. Developers never maintain audit tables by hand. Change the main table — add a column, change a type — and the audit table's schema is regenerated to pick the change up automatically. Audit becomes infrastructure, not a chore each developer re-implements (or skips).

For the final: audit every state-changing table, including who acted, when (from the database clock, not the caller — see Principle 3), and what changed. Test it: make an operation fail on purpose and show the audit row. Bonus: generate your audit DDL from the base table rather than hand-writing it.

# Identity comes from the session, never from the caller

Principle 3 of 10 — Authenticate the actor inside the database.

The most common security flaw in this class's midterms: procedures that accept an actor ID as a parameter and check *that ID's* role. The check is real, but the identity is asserted — anyone connected with the application account can pass the administrator's ID. Proper procedures resolve the actor from USER() — the actual MySQL session — and check the session's active role.

For the final: no procedure should trust a caller-supplied identity. Derive the actor from the session, map the login to a person, and grant the application account EXECUTE on procedures — never direct table writes.

# Two identities, always: the system and the person it acts for

Best practice — Acting on behalf of someone.

In a real architecture there are always *two* identities in every call, and a well-built system tracks both:

1. The system identity. The application service connects to the database under its own system ID. That ID is authenticated, least-privilege, and identifies *which system* is acting.

2. The on-behalf-of identity. The system is acting *for* an end user. That user's identity travels with the call, is recorded in the audit trail, and is the identity entitlements are checked against.

Conflating the two is how systems end up either wide open (the service account can do anything, for anyone, untraceably) or useless (no record of which human a change belongs to). Separate them, and both audit (Principle 2) and entitlements (Principle 3) become meaningful: the audit row answers "which system, acting for which person, did what."

This is the AI-agent problem. An AI agent acting on behalf of a user is the same pattern: the agent has its own identity and credentials, but it must never have *more* authority than the person it acts for, every action must be attributable to both the agent and the person, and the person's entitlements bound what the agent may do. If you learn to build this pattern for an application service, you already know how to govern an agent.

Entitlements as data. The companion practice: manage entitlements as *mappings* — roles mapped to the assets (tables, procedures, functions) they may access — stored in one place, in the database. Granting a role access to a new asset is then a data change in one place, not a code change scattered across the application. When entitlements live in code, every access change is a release; when they live in mapping tables, it's an administrative act — reviewed, audited, and reversible.

For the final: show both identities in your audit design, and put your role-to-asset mappings in tables you can query — "show me everything Role X can touch" should be one SELECT.

# Put the workflow in the database, as data

Principle 4 of 10 — The database enforces the workflow; the application asks permission.

Business rules that live only in application code can be bypassed by anyone with another client. The best midterm design stores allowed status transitions in a *table*, with per-role permission flags, and routes every change through one choke-point procedure guarded by a final-state trigger. Adding a step or a role means inserting rows — not rewriting code.

For the final: model your status lifecycle explicitly (states, transitions, who may take each), enforce it in the database, and prove enforcement: attempt an illegal transition and an unauthorized one, and show both being rejected.

Why this pays off beyond the database: when workflow is metadata, everything downstream can be metadata-driven too. In the model from lecture, the GUI reads the workflow metadata — change the transitions or steps in the metadata and *the interface adjusts automatically*: new states appear, illegal actions disappear, no front-end release required. The same idea drives Principle 3A's entitlement mappings and Principle 11's indicator values — one pattern, applied everywhere: behavior lives in data; code just interprets it.

# Errors are an interface

Principle 5 of 10 — Distinguish warnings from critical errors, and say something meaningful.

This was the weakest dimension in the class. Most systems SIGNAL errors — good — but the calling application receives an undifferentiated stream of failures. A caller needs to know: Is this a *warning* (the operation completed; something deserves attention)? A *retryable* failure (deadlock, timeout)? Or *critical* (stop; data integrity is at stake)? The E-Commerce Dashboard's prefixed taxonomy (invalid: / forbidden: / not_found: / conflict:) is a good start — but the mapping was never documented for callers.

For the final: define your error taxonomy in the TDD, use it consistently, and document what the caller should *do* with each class. An error message is part of your API.

# The build is part of the product

Principle 6 of 10 — If a stranger can't rebuild it, it isn't finished.

A professional build is idempotent or explicitly rebuild-safe, manifest-ordered, fail-fast, and logged — and the log is committed as evidence. An example good build clones a tagged release, verifies its SHA, and refuses to overwrite an existing database. Several midterms, by contrast, only build from inside one folder, or carry duplicated script copies that can drift apart.

For the final: one entry point, one manifest, timestamped logs, and a committed run from a clean clone.

# A tag is a release

Principle 7 of 10 — Version tags feed the build; the build proves the tag.

A git tag that nothing consumes is a label. A tag becomes a release when the build *takes the tag as input*, checks out exactly that commit, and verifies it.

For the final: tag your release, build from the tag, and run your verification suite against the tagged commit. The counts in your evidence file should be the counts for the release you submit.

# Version the database itself

Principle 8 of 10 — Git versions your files; something must version your schema.

Almost nobody could answer: "Which version of this procedure is running, and what changed since last release?" Git history alone doesn't answer that for objects already deployed. The baseline is a schema_version / migration table in the database, version stamps on routines, and a recorded path from version N to N+1.

For the final: add a schema-version mechanism, stamp your objects, and show an upgrade: build v1, apply the v2 migration, prove the data survived.

# Prove it at scale

Principle 9 of 10 — Toy data proves the demo, not the system.

Six appointments and seven users cannot reveal a missing index, a locking problem, or a pagination blow-up. Only one midterm ran genuine performance studies — a covering-index study, a range-filter study, and audit pagination by keyset — with SQL and captured output committed. Everyone else's performance story was one EXPLAIN at toy scale, or none.

For the final: write a data generator, load a realistic volume (state your target: rows, concurrent users), and report at least one before/after: the same query with and without the index or design change you claim helps.

# Traceability: requirements → build → evidence

Principle 10 of 10 — Every claim traces to a requirement, and every requirement to a result.

The strongest documentation in this class maintained a living chain: functional requirements → design decisions → implemented objects → tests → *executed results*, in a traceability matrix. The failure mode to avoid: a beautiful test plan whose results were never run, or a test report that predates the code it claims to verify.

For the final: keep the matrix current as you build. We will pick requirements at random and follow the chain — FR → object → test → result. Make sure the chain holds, and that the results correspond to the tagged release (Principle 7).

From the database up: model (1) → audit (2) → identity (3) → workflow (4) → errors (5) → build (6) → tags (7) → schema versioning (8) → scale (9) → traceability (10). Build your final in that order and most grading questions answer themselves.

# Reference data is data: the Indicator Value pattern

Principle 11 — Never hard-code a domain of values.

Every system has coded domains: statuses, types, categories — status_ind = 'A'/'I'/'P', and dozens like it. The beginner's move is to hard-code them: in CHECK constraints nobody updates, in validation code, and worst of all as literal options in the GUI. Then the business adds "Prospect" and three codebases need a release.

The Indicator Value pattern (from yesterday's lecture demo) puts every coded domain in one table — indicator name, value, description, display order — and makes everything read from it:

- Validation checks a code against the table: is this value a member of its indicator's domain?

- Combo boxes load from the table through one generic service endpoint — the page contains *no hard-coded options at all*.

- Reports decode through the table, so a stored code always renders as its current description — and a code that *isn't* in the table surfaces visibly as invalid instead of silently meaning something.

The classroom moment: insert one row — ('status_ind', 'P', 'Prospect', 3) — refresh the page, and the new option is simply *there*. Zero code changes, zero redeploys. Adding a 