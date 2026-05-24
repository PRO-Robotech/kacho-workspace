# kacho-iam Production-Cleanup Refactor — Design

> **Status**: DRAFT (brainstorming output — design.md). Next: `writing-plans` skill → per-wave implementation plans.
> **Date**: 2026-05-24
> **Author**: orchestrator (brainstorming session with user)
> **Tracking**: KAC-194 (master), KAC-195..KAC-206 (per-wave)
> **Target service**: `project/kacho-iam/` (405 Go files / 75 699 LOC / 22 migrations / 13 newman suites)
> **Sibling effects**: `project/kacho-proto/` (proto stubs naming), `project/kacho-deploy/` (helm + dev DB reset), `project/kacho-workspace/` (specs + vault)

## 0. Why this refactor

`kacho-iam` evolved through dense per-sprint deliveries (Phase 1, E0..E5, Phase 6/7/7b/8, W1.1..W1.6, W2.A..W2.D, W3.1..W3.4, KAC-127, KAC-138, KAC-163, KAC-178, KAC-188 …) and the journey is permanently visible in code comments, file names, struct names, test names, migration filenames and vault entries. A new developer reading the service today has to learn that journey *before* they can understand the design — comments explain «когда» добавили («Phase 7b deferred from Phase 7 base») rather than «зачем» (the business capability and architectural intent).

Goal: a service that reads like a production-launched codebase where the on-disk artefacts describe **what** + **why** without the **when**. Selected end-goal mode: **production launch readiness** (strictest — full `evgeniy`-skill compliance, complete architecture documentation, audit-trail-clean source tree).

The refactor is purely cosmetic + structural; no behavioural changes. Newman e2e baseline (currently GREEN, run `26363068423`, 13 suites) is the regression gate for every wave.

## 1. Scope discipline

### In scope
- Strip phase markers (`Phase \d+[a-z]?`, `\bE[0-9]\b`, `\bW[0-9]\.[0-9]\b`, `Phase 7b`, «известно как KAC-127» etc) from all `*.go` (production + tests), `*.py` newman cases, migration `--` comments, `cmd/` files and `internal/`.
- Strip historical `KAC-N` ticket references from production-code comments where they served as «когда добавили». Keep `# verifies <issue-url>` test annotations (workspace §«Запреты» #13 finding pattern) and keep `KAC-N` in commit messages + vault entries (history artefacts, not source-of-truth).
- Rename `phase*` Go files to capability-named files (`phase7_jit_service.go` → `jit_service.go`, `phase8_caep_*` → `caep_*`, etc; 30+ files).
- Author full product architecture documentation (12 docs + ADRs in `kacho-iam/docs/architecture/`).
- Pass full `evgeniy`-skill 48-rule review with no remaining violations.
- Squash all 22 migrations into a single fresh `0001_initial.sql` baseline (greenfield-style; dev DB reset acceptable since service is pre-prod).

### Out of scope
- Behavioural changes to RPCs (proto + observable behaviour stays identical).
- API surface changes (no new RPCs, no removed RPCs in this refactor — KAC-178 et al continue separately).
- Cross-repo changes beyond `kacho-iam`, except: (a) `kacho-proto` if proto comments mirror IAM phase markers (audit + fix); (b) `kacho-deploy` for dev DB reset script; (c) `kacho-workspace` for spec + vault.
- Commit history rewrite (`git filter-repo`) — git log stays as it is; it is the historical artefact, not the source-of-truth seen by readers of the present-day code.
- Parallel actor (KAC-178 prod-readiness epic) work — coordinated via tracking issue, not merged into.

## 2. Decomposition — 5 waves + tracking

```
KAC-194 (master tracking)
├── KAC-195 — Wave A: comment + KAC + phase cleanup (S, ~3 days)
├── KAC-196 — Wave C: architecture documentation (M, ~1 week)
│    ↑ A and C run in parallel
├── KAC-197 — Wave B: phase*-file renaming  ← blocked by A merged
├── KAC-198..KAC-205 — Wave D: evgeniy 48-rule refactor (XL, ~3-5 weeks)
│    Per evgeniy rule-group:
│    KAC-198: rule-group A (mechanical, 15 rules)
│    KAC-199: rule-group B (layering, 12 rules)
│    KAC-200: rule-group C (domain newtypes, 8 rules)
│    KAC-201: rule-group D (DTOs, 6 rules)
│    KAC-202: rule-group E (infra, 7 rules)
│    KAC-203..205: integration test reshape + mock regen + final review pass
│    ↑ all blocked by B merged
└── KAC-206 — Wave M: migrations squash to fresh 0001_initial.sql (S, ~2 days)
       ↑ blocked by all D done
```

**Critical path**: A → B → D → M. **Slack**: C runs parallel with A. **Total wall-clock**: 6-8 weeks.

Each KAC ticket: own acceptance doc in `docs/specs/sub-phase-cleanup-<kac-tag>-acceptance.md`, own implementation plan in `docs/superpowers/plans/<date>-<kac-tag>-plan.md`, own PR train, own vault entry. The DoD for the parent KAC-194 is the union of all child DoDs.

## 3. Wave A — Comment + KAC + Phase cleanup

### Surface
- ~230 `.go` files in `internal/` + `cmd/` containing `Phase`, `E\d`, `W\d.\d` or `KAC-N` (mostly comments / docstrings; some test names).
- 13 newman case files in `tests/newman/cases/*.py`.
- 22 `migrations/*.sql` (cosmetic SQL `-- KAC-127 added X` comments only — filenames stay until Wave M).

### Reword vs strip
Mechanical `sed` is insufficient: many comments such as `// Phase 7b: deferred from Phase 7 base because the eligibility aggregator wasn't stable yet` carry architectural rationale. The «WHY» must be preserved; only the «WHEN» disappears. Pattern per occurrence:

| Before | After |
|---|---|
| `// Phase 7b: ComplianceReport service (KAC-127 sub-phase 3.7b)` | `// ComplianceReport service — aggregates governance data into signed S3 artefacts for auditor self-service.` |
| `// W1.5 / KAC-163 (finding #51 approve-path): emit fga_outbox GRANT…` | `// Emit fga_outbox GRANT in the same writer-tx as the binding mint + pending Decide CAS — bridges DB commit and OpenFGA tuple write.` |
| `// KAC-127 phase wiring` | `// JIT, break-glass, access-review, compliance, GDPR — Phase 7 governance wiring.` ← **bad** (still says Phase). Reword to: `// Governance wiring — JIT, break-glass, access-review, compliance, GDPR.` |
| `// E2 will replace OIDC stub with Zitadel; E3 will add OpenFGA Check` | drop the «E2/E3» dating; rewrite as `// OIDC callback integration is owner-of-truth for user identity; FGA Check is the runtime authorisation gate.` |

Comments that genuinely describe future work move to `docs/architecture/adr/` ADRs (Wave C) and become design records, not stale code annotations.

### Preserved
- `// verifies https://github.com/PRO-Robotech/kacho-iam/issues/N` annotations on RED-pinned newman cases (workspace §13 finding pattern).
- Commit history (`git log`).
- Vault entries `obsidian/kacho/KAC/KAC-N.md` (these are explicitly historical).
- KAC-N in PR titles / descriptions (these are ticket-tracking artefacts, not source code).

### Test-name renaming
Some test functions carry phase markers in their names: `Test_Phase7b_JIT_Approve_*`, `Test_W1_6_ANON_TABLE_*`. Rename to capability-named: `Test_JIT_Activation_Approval_*`, `Test_Authzguard_AnonymousMethodTable_*`. This is technically file edits (allowed in Wave A) — but the *file* renames (Wave B) are deferred.

### Acceptance
- `grep -rln 'Phase [0-9]\|\bE[0-9]\b\|\bW[0-9]\.[0-9]\b' --include='*.go' internal/ cmd/ tests/` → 0 matches.
- `grep -rln 'KAC-[0-9]' --include='*.go' internal/ cmd/` → ≤ 10 matches (only legitimate `// verifies KAC-N` lines, manually counted and listed in PR description).
- All existing unit + integration tests GREEN.
- Newman e2e GREEN on iam main.
- No file renamed yet.
- No behavioural change.

### How
PR train of ~10 batched commits (per logical concern: handlers / services / repos / clients / tests / migrations-comments / cmd / docstrings / etc), each ≤ 300 lines diff for reviewability. Author: dedicated `general-purpose` agent in `/tmp/wt-KAC-195-iam` worktree.

## 4. Wave B — Phase*-file renaming

### Targets (30+ files)

| Subdirectory | Old | New (proposed) |
|---|---|---|
| `internal/service/` | `phase7_jit_service.go` + `_test.go` + `_mocks_test.go` | `jit_service.go` + `_test.go` + `mocks_test.go` |
| | `phase7_access_review_service.go` + `_test.go` | `access_review_service.go` + `_test.go` |
| | `phase7_break_glass_service.go` + `_test.go` | `break_glass_service.go` + `_test.go` |
| | `phase7_gdpr_service.go` + `_test.go` | `gdpr_service.go` + `_test.go` |
| | `phase7_workers.go` + `_test.go` | `governance_workers.go` + `_test.go` |
| | `phase7_ports.go` | `governance_ports.go` |
| | `phase7_mocks_test.go` | `governance_mocks_test.go` |
| | `phase7b_workers.go` | split into `compliance_worker.go` + `jit_expirer.go` (decided — file currently mixes both concerns) |
| | `phase7b_ports.go` | split into `compliance_ports.go` + `jit_pending_ports.go` (mirror the worker split) |
| | `phase7b_mocks_test.go` | split into `compliance_mocks_test.go` + `jit_pending_mocks_test.go` (mirror the port split) |
| | `phase8_caep_drainer.go` + `_test.go` | `caep_drainer.go` + `_test.go` |
| | `phase8_caep_dlq.go` + `_test.go` | `caep_dlq.go` + `_test.go` |
| | `phase8_caep_subscriber_service.go` + `_test.go` | `caep_subscriber_service.go` + `_test.go` |
| | `phase8_caep_mocks_test.go` | `caep_mocks_test.go` |
| | `phase8_caep_ports.go` | `caep_ports.go` |
| | `phase8_rate_limit.go` | `caep_rate_limit.go` |
| | `phase8_set_signer.go` + `_test.go` | `caep_set_signer.go` + `_test.go` |
| `cmd/kacho-iam/` | `phase6_listeners.go` | `listeners.go` (or fold into `main.go` if small) |
| | `phase7_wiring.go` | `governance_wiring.go` |
| | `phase7b_wiring.go` | merge into `governance_wiring.go` if reasonable size, else `compliance_wiring.go` + `jit_pending_wiring.go` |
| | `phase8_wiring.go` | `caep_wiring.go` |

### How
All renames via `git mv` to preserve `git blame`. Same Go package, no import changes needed. Per-file commits where possible for clean blame. Verify build + tests after each rename.

### Risks
- GitHub PR diff treats large file renames as add+delete (display only) — review tooling shows blame correctly. Splitting into per-file commits mitigates.
- External imports of `kacho-iam` Go packages — verified none (kacho-iam exports nothing; consumers use generated proto stubs).

### Acceptance
- `ls internal/service/ cmd/kacho-iam/ | grep -E '^phase'` returns empty.
- `go build ./...` clean.
- All tests GREEN.
- Newman e2e GREEN.
- `git log --follow` on each renamed file shows continuous history.

## 5. Wave C — Product architecture documentation

### Deliverables in `kacho-iam/docs/architecture/`

| File | Content (1-3 pages each) |
|---|---|
| `README.md` | service overview, scope boundaries, principal counterparties (caller graph), repo links |
| `er-diagram.md` | mermaid ER for 22-table schema (existing skeleton; refresh post-Wave A) |
| `package-graph.md` | mermaid: `domain` ← `service` ← `repo/handler/clients` ← `cmd`; import-cycle proof |
| `rpc-surface.md` | table of every public + Internal RPC with: REST mapping, sync/async, scope-extractor, required FGA relation, ACR step-up |
| `error-taxonomy.md` | sentinel → gRPC code; SQLSTATE → sentinel; verbatim error text catalogue |
| `transactions.md` | tx boundaries per use-case; outbox emit invariants (which outbox writes to which table inside which tx) |
| `authz-model.md` | OpenFGA model overview; RBAC patterns; acr step-up; anti-leak gate |
| `outbox-flows.md` | `fga_outbox`, `subject_change_outbox`, `caep_outbox`, `audit_outbox` lifecycle + drainer mechanics + retry budgets |
| `runtime-topology.md` | pods, listeners (public 8080, internal 9091, metrics), peer-call graph, mTLS plan stub |
| `operations-and-lro.md` | Operation entity lifecycle; ActivateJIT / Approve finalise pattern; Operation principal + W1.6 anti-leak |
| `migrations-policy.md` | squash-baseline doctrine + per-change procedure + rollback rules |
| `adr/0001-account-project-replace-resource-manager.md` | Decision record |
| `adr/0002-openfga-vs-keto.md` | Decision record |
| `adr/0003-jit-approval-flow-pim-style.md` | Decision record |
| `adr/0004-compliance-report-hsm-signed-s3.md` | Decision record |
| `adr/0005-rebac-direct-bindings-only-no-implicit.md` | Decision record |
| `adr/0006-internal-vs-external-listener-split.md` | Decision record |
| `adr/0007-operations-table-iam-extension-fields.md` | Decision record |
| `adr/0008-subject-change-push-drainer-vs-poll.md` | Decision record |
| `adr/0009-permission-catalog-source-of-truth.md` | Decision record |
| `adr/0010-spire-svid-future-mtls.md` | Decision record (planned, marks current insecure cluster-internal as known acceptance) |

### Source material
- Existing `kacho-iam/CLAUDE.md` § business model.
- Existing `docs/architecture/er-diagram.md` (refresh).
- Acceptance docs in `kacho-workspace/docs/specs/sub-phase-2.0-iam-*.md` and `sub-phase-3.*-iam-*.md` (10+ docs).
- Vault entries in `obsidian/kacho/KAC/KAC-127.md` et al.
- Code reading (one pass per package boundary).

### Acceptance
- All 12 docs + 10 ADRs present in `docs/architecture/`.
- Each doc ≤ 3 KB unless mermaid + tables (then ≤ 5 KB).
- Mermaid renders in GitHub preview.
- No `Phase`, `E0..E5`, `W1..W3`, `KAC-N` markers (these docs describe present-state, not history).
- ADRs reference each other where appropriate; each has status (Proposed/Accepted/Superseded).

## 6. Wave D — evgeniy 48-rule structural refactor

### Audit-then-remediate

**Phase D.0 — Audit** (1-2 days, KAC-198 sub-task):
Run `evgeniy`-skill rule-by-rule against current `kacho-iam` (post-Wave-B base). Output: `docs/architecture/evgeniy-compliance-report.md` listing each rule + status (PASS / VIOLATIONS: file:line list) + suggested remediation per violation.

**Phase D.1..D.5 — Remediation** (3-5 weeks total, KAC-198..KAC-205):

| Group | Rules | Effort | Examples |
|---|---|---|---|
| **D.1 — Mechanical** (KAC-198) | naming, var decl, error wrapping, `slog` vs `log`, no panics in production paths, generics justification | S each (~5 days total) | `log.Printf` → `slog.With(...).InfoContext`; `id string` → typed `domainID`; `fmt.Errorf("%v")` → `fmt.Errorf("%w")` |
| **D.2 — Layering** (KAC-199) | CQRS Reader/Writer split, narrow ports, slice-per-RPC use-case, thin gRPC handler, no business logic in handler | M each per resource (~10 days total, 12 resources) | Each `phase7_*_service.go` split into per-RPC use-case files (`approve_jit.go`, `deny_jit.go`, …); ports become per-port interfaces (skill evgeniy §6) |
| **D.3 — Domain** (KAC-200) | self-validating newtypes, `multierr` validation, immutability, no string aliases | M each (~7 days total) | `type UserID string` → `type UserID struct{v string}` with `Validate()` |
| **D.4 — DTOs** (KAC-201) | generic DTO registry, `toproto/` pattern, no ad-hoc proto-mapping in handler | M each (~5 days total) | Centralise in `internal/dto/registry.go` |
| **D.5 — Infra** (KAC-202) | `cmd/migrator` separate binary, YAML config via viper/koanf, observability spans, no `init()` side-effects, no global singletons outside `cmd/` | M each (~3 days total) | Already mostly compliant; tighten remaining gaps |

**Phase D.6 — Integration + mock regen** (KAC-203, ~2 days):
- `repomock/` regen against new narrow ports.
- All `*_test.go` updated for new layered structure.
- Coverage measurement: `go test ./... -coverprofile=cover.out`; target ≥ 80 % on touched files.

**Phase D.7 — Final evgeniy-reviewer pass** (KAC-204, ~1 day):
- Re-run audit checklist post-remediation.
- Zero violations report.

**Phase D.8 — newman regression confirm** (KAC-205, ~0.5 day):
- Full newman e2e on iam main GREEN.
- Performance regression check (no RPC latency regression > 20 %).

### Risks
- Test-fixture incompatibility post-port narrowing: mitigated by regenerating mocks per chunk.
- Behavioural regression: every chunk merges only after integration + newman pass.
- Scope creep on rule interpretation: each rule has a fixed pass/fail criterion in the audit report; reviewers cannot expand scope mid-stream.

### Acceptance
- `docs/architecture/evgeniy-compliance-report.md` shows all 48 rules PASS.
- `go test ./... -race -count=1 -short` GREEN with coverage ≥ 80 % on touched files.
- Newman e2e GREEN.
- No performance regression > 20 % on p95 of any RPC (smoke-tested via k6 if Wave D2 changes are non-trivial).

## 7. Wave M — Migrations squash

### Procedure (KAC-206)

1. Spin a fresh Postgres-16 container.
2. Run `goose up` with all 22 current migrations → resulting schema.
3. `pg_dump --schema-only kacho_iam` → cleaned-up output → save as new `internal/migrations/0001_initial.sql`. Manual review to:
   - Remove autogenerated noise (sequence start values, default ACL stanzas).
   - Reorganise by domain (Account / Project / User / SA / Group / Role / AccessBinding / Operations / FGA-outbox / SubjectChange-outbox / CAEP-outbox / Audit-outbox / JIT / BreakGlass / AccessReview / Compliance / SCIM / SAML / OIDC / CAEP-ingress).
   - Inline helper-function definitions (`kacho_iam.iam_permissions_valid` etc.).
   - Add header section pointing to `docs/architecture/migrations-policy.md`.
4. Archive old migrations to `docs/architecture/migrations-history/` (single tarball plus index README) — not deleted, preserved as historical artefact for auditors who need to reconstruct the past timeline.
5. Update `cmd/migrator/` if any per-migration custom logic must be preserved (none expected — all 22 are pure SQL).
6. Update `kacho-deploy/helm/umbrella/templates/pg-iam.yaml` init job to reset dev DB on fresh deploy (idempotent — if database empty, run `goose up`; if database has rows, error out demanding manual squash-cutover).
7. CI: add `migrations-squash-verify` job — starts fresh PG, runs `goose up`, dumps schema, diffs against committed `0001_initial.sql` (must be empty diff).
8. Update `docs/architecture/er-diagram.md` to reflect new single-baseline source.

### Risks
- All dev environments require DB reset. Coordinate with kacho-deploy + announce to any other developer using a long-lived dev stack.
- Production: kacho-iam not yet deployed to production (per user's «production launch readiness» stance = preparing for launch) — squash is safe. If this assumption changes (production data exists), Wave M aborts and migrations stay (we accept their messy filenames).

### Acceptance
- Single `internal/migrations/0001_initial.sql` file exists; all `0002_*` … `0022_*` gone from active migrations dir.
- `docs/architecture/migrations-history/` contains the original 22 files + README index.
- `goose up` from empty DB produces schema byte-identical to integration-tests' expected schema.
- Integration tests GREEN.
- Newman e2e GREEN.
- `kacho-deploy` dev DB init updated and verified by `dev-up` + `dev-down` + `dev-up` cycle.

## 8. Cross-cutting concerns

### 8.1 Branching + PR

- Branch per KAC ticket: `KAC-195` (Wave A), `KAC-196` (Wave C), `KAC-197` (Wave B), `KAC-198..205` (Wave D), `KAC-206` (Wave M).
- All branches off latest `main` (rebased frequently — main moves due to other KAC-178 work).
- Each PR rebased + force-pushed before merge; no merge commits in iam main (squash-merge policy).
- Parallel-actor coordination: KAC-194 tracking issue body lists in-flight KAC-178 PRs; refactor agents must rebase if KAC-178 merge lands inside their working window.

### 8.2 Regression gates

After every PR merge:
1. iam main CI green (build / vet / test / lint / integration / newman / docker-build).
2. Specific to refactor: spot-check grep for re-introduced phase markers (catches reverts).
3. Specific to Wave M: schema diff check.

### 8.3 Vault discipline

Per workspace `CLAUDE.md` §«Obsidian vault — обязательно»:
- `obsidian/kacho/KAC/KAC-194.md` (master) + one entry per child KAC.
- After each merge: update entry status + PR URL.
- Affected vault categories: `packages/iam-*.md`, `rpc/iam-*.md`, `resources/iam-*.md`, `edges/iam-*-to-*.md` — refreshed after Wave D + Wave M to reflect cleaned naming.

### 8.4 YouTrack

Create KAC-194 (epic) first; create child tickets in waves as previous wave starts. Sprint: «Первый спринт» (board `kacho`, agile `183-12`, sprint `186-22`) or successor sprint if rolled over.

### 8.5 Spec docs

Each wave produces:
- `docs/specs/sub-phase-cleanup-<wave>-acceptance.md` (Given-When-Then under `acceptance-author` agent).
- `docs/superpowers/plans/<date>-<wave>-plan.md` (under `writing-plans` skill).

### 8.6 Test discipline preserved
- Workspace §«Запреты» #11 (no TODO/FIXME) — strictly enforced; refactor must not introduce any.
- Workspace §«Запреты» #12 (test-first RED→GREEN) — for any product behaviour change discovered en-route, falls under follow-up KAC, not folded into refactor wave.
- Workspace §«Запреты» #13 (test-only PR ≠ product fix) — Wave A includes test files but is not a test-only PR (also touches production code comments); Wave B is test+product structural; Wave D mixes; Wave M is migrations.
- Workspace §«Запреты» #2 (no «yandex» mentions) — re-audit during Wave A.
- Workspace §«Запреты» #6 (Internal vs external listener split) — preserved by Wave B file renames (caep / governance / etc are still internal-only); Wave D may re-check.
- Workspace §«Запреты» #10 (DB-level refs only for within-service invariants) — Wave D D.2 layering re-audits.

## 9. Definition of Done — parent KAC-194

All of the following must hold simultaneously for KAC-194 to be marked Done:

1. All 5 waves merged into `kacho-iam:main`.
2. `grep` checks return zero for phase markers, ≤ 10 for `verifies KAC-N` annotations.
3. No `phase*` files in `internal/service/` or `cmd/kacho-iam/`.
4. `docs/architecture/` contains the 12 docs + 10 ADRs.
5. `docs/architecture/evgeniy-compliance-report.md` shows 48/48 rules PASS.
6. `internal/migrations/` has a single `0001_initial.sql` file; old migrations archived in `docs/architecture/migrations-history/`.
7. Full integration test suite GREEN with coverage ≥ 80 % on touched files.
8. Newman e2e GREEN on iam main.
9. Vault entries `obsidian/kacho/KAC/KAC-194.md` and KAC-195..KAC-206 all Status = Done.
10. `kacho-deploy` `make dev-up` from clean → fresh DB → all newman suites pass.

## 10. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Behaviour regression introduced by rename / refactor | high | newman e2e gate per PR; integration tests + concurrent-race coverage |
| Parallel-actor (KAC-178) merge collision | high | rebase frequently; tracking issue KAC-194 lists in-flight refs; defer agents to next free slot |
| Migration squash breaks dev environments | medium | per-wave announcement; clean wipe documented in migrations-policy |
| `evgeniy` rule interpretation drift mid-stream | medium | audit report locks per-rule criteria before remediation; no scope expansion |
| Scope creep into KAC-178 territory | medium | KAC-178 explicitly out-of-scope; coordination via tracking issue |
| Comment reword changes intent of carefully-worded explanation | low | reviewer must verify «WHY» preserved; sample audit during Wave A code review |
| Test-fixture incompatibility post-port-narrowing (Wave D) | medium | regenerate mocks per sub-chunk; integration tests gated per chunk |
| Performance regression from layered rewrite | low | k6 smoke for non-trivial chunks; baseline numbers in `docs/architecture/runtime-topology.md` |
| Audit-time misalignment (auditor expects historical artefacts but they're hidden in migrations-history/) | low | migrations-history index README + dedicated audit-guidance section in `migrations-policy.md` |

## 11. Open questions ratified during brainstorming

| Question | Answer | Source |
|---|---|---|
| Decomposition strategy | 4 independent waves (Recommended) — became 5 with Wave M | user, 2026-05-24 |
| End-goal | Production launch readiness (strictest) | user, 2026-05-24 |
| Migration handling | Squash to fresh `0001_initial.sql` (greenfield) | user, 2026-05-24 |

## 12. Next step

After this design doc is approved by the user (gate per brainstorming flow):

1. `writing-plans` skill for **Wave A** (KAC-195) — produces `docs/superpowers/plans/2026-05-24-wave-a-cleanup-plan.md` with step-by-step implementation.
2. `acceptance-author` agent — produces `docs/specs/sub-phase-cleanup-wave-a-acceptance.md` with Given-When-Then scenarios for the cleanup.
3. `acceptance-reviewer` agent — approves the acceptance doc.
4. Implementation via `rpc-implementer` / `general-purpose` agents in `/tmp/wt-KAC-195-iam` worktree.
5. Newman e2e GREEN — Wave A merged.
6. Repeat for Wave C (parallel), then Wave B, then D.1..D.8, then Wave M.

Per workspace `CLAUDE.md` §«Запреты» #1, no implementation code lands before each wave's acceptance doc is APPROVED by `acceptance-reviewer`.
