# Wave 1 — AuthZ critical path (Implementation Plan / Tracker)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Each
> chunk follows CLAUDE.md §Запреты #1 + memory `feedback-acceptance-tests-only-not-code`:
> acceptance-doc (GWT) **first**, then RED integration-tests, then GREEN implementation, then
> two-stage review. Bite-sized tasks per chunk live in the chunk's acceptance-doc, NOT in this
> tracker.

**Goal:** Make authz actually enforce. After W1 closes: grant→allow / revoke→deny end-to-end on
kind; 87 newman failures → 0; fga_outbox drainer working; gateway fail-closed; principal
propagated cross-service. This unblocks W2 (parallel streams) and W3 (finalize).

**Architecture:** 6 sequential chunks, each its own acceptance-doc + integration tests + impl +
two-stage review. W1.1 (drainer) is foundational — without it the in-place sync FGA writes that
KAC-127 left behind continue to split-brain DB and FGA. Subsequent chunks build on the drainer.

**Tech Stack:** Go (kacho-corelib + kacho-iam + kacho-api-gateway), Postgres (LISTEN/NOTIFY),
OpenFGA HTTP SDK, sqlc + handwritten pgx, testcontainers-go, Newman E2E.

**Branch:** `KAC-136` in all affected repos.

**Parent epic:** [[KAC-134]] · **YT:** https://prorobotech.youtrack.cloud/issue/KAC-136

---

## Baseline entering W1 (post-W0 closure 2026-05-23)

| Метрика | Значение |
|---|---|
| Newman GREEN | 1057/1144 (92.4%) — 87 failures `iam-jit-pending`(33) + `iam-user`(25) + `iam-compliance-report`(10) + `iam-internal-only-check`(10) + `iam-access-binding`(8) + `authz-deny`(1) |
| Coverage | 57/117 RPCs (49%) |
| AuthZ-finding closed | 2/44 (#8/#13 в KAC-128/131) |
| `fga_outbox`-drainer | **не существует** (foundational gap) |
| `subject_change_outbox` (cache invalidation на revoke) | не реализован |
| Gateway authz-middleware fail-closed | выключен на dev |
| Principal propagation cross-service | сломан (vpc видит `user:bootstrap` для всех вызовов) |

## Chunks (sequential)

Each chunk = own subtask of KAC-136 (will be created on start), own acceptance-doc, own PR-set,
test-first per CLAUDE.md §Запреты #11.

### W1.1 — `fga_outbox` drainer (kacho-corelib) — **foundational, start here**

**Why first:** Bootstrap-admin grant tuples already go into `fga_outbox` (migration 0002 + NOTIFY
trigger exist in kacho-iam), but nothing drains them. Without drainer no W1.5/W1.6 fix using
outbox can land. Without drainer cluster-admin role doesn't propagate to OpenFGA → almost every
authz check fails.

**Scope:**
- New package `github.com/PRO-Robotech/kacho-corelib/outbox/drainer` (or extend existing
  `kacho-corelib/outbox/` if there's a writer-side that's halfway there)
- Generic `Drainer[T]` interface that LISTENs on a Postgres channel + polls the outbox table on
  startup/fallback; applies row to target system via injected `Applier[T]` function; marks row as
  consumed (or deletes) on success; respects idempotency (409=ok); retries with exp backoff on
  transient errors; respects ctx cancellation for graceful shutdown.
- Concrete `FGAApplier` in kacho-iam wiring that translates `fga_outbox` row → OpenFGA Write/Delete
  HTTP call.
- Integration test (testcontainers Postgres + real OpenFGA container if feasible, else fake):
  insert outbox row → LISTEN/NOTIFY fires drainer → row applied to FGA → row marked consumed;
  concurrent inserts → exactly-once application; FGA 409 conflict → treated as success (idempotent).
- Wiring in kacho-iam `cmd/kacho-iam/main.go` to start the drainer goroutine.

**Acceptance-doc location:** `docs/specs/sub-phase-W1.1-fga-outbox-drainer-acceptance.md`

### W1.2 — `subject_change_outbox` + gateway authz-cache invalidation on revoke

**Why:** After `AccessBinding.Delete` (or JIT/break-glass revoke), gateway authz-cache still
returns ALLOW until TTL expires (KAC-127 round-3 caught this: `authz-deny.py` suite passed
post-revoke check ALLOW where DENY was expected for ~5-30s).

**Scope:**
- New outbox `subject_change_outbox` (kacho-iam migration 0023) with rows `op=binding_delete |
  jit_revoke | bg_revoke`, `subject_type/id`, `resource_type/id`.
- Revoke paths emit `subject_change_outbox` row inside the same tx that does the DB-delete +
  fga_outbox.
- New drainer (reuse W1.1 generic) → posts to gateway internal endpoint `/internal/v1/authz-cache:invalidate`
  with `{subject, resource}` body.
- Gateway endpoint drops cache entries matching subject OR resource.
- Integration: revoke binding → within 1s, gateway Check returns DENY (no 5s wait).

**Acceptance-doc:** `docs/specs/sub-phase-W1.2-subject-change-cache-invalidation-acceptance.md`

### W1.3 — Gateway authz-middleware fail-closed

**Scope:** kacho-api-gateway middleware — current dev config skips authz on disabled flag. Enable
on all environments (dev + prod). If OpenFGA unreachable → return `Unavailable` (not allow).
Make authz-middleware **mandatory** on all mutating RPC paths.

**Acceptance-doc:** `docs/specs/sub-phase-W1.3-gateway-authz-fail-closed-acceptance.md`

### W1.4 — Principal propagation сервис→сервис

**Scope:** When kacho-vpc calls `kacho-iam.InternalIAMService.Check`, the principal (caller user)
must be propagated, not replaced with `user:bootstrap`. Wire ctx metadata extraction in
api-gateway (set principal as gRPC metadata header `x-kacho-principal`) + corelib helpers
(`auth.ExtractFromContext`, `auth.PropagateToOutgoing`) + iam middleware accepts header.

**Acceptance-doc:** `docs/specs/sub-phase-W1.4-principal-propagation-acceptance.md`

### W1.5 — Remediation Chunk 1 (DB/FGA grant-write desync)

**Findings (7):** #8, #16, #47, #48, #50, #51, #52 — see
`2026-05-21-iam-authz-review-remediation-plan.md` Chunk 1.

**Scope (high-level — detailed in acceptance-doc):**
- #47/#48 — permission-based relation mapping (custom roles with granular permissions don't
  collapse to viewer)
- #16 — FGA-write atomic with binding-row via fga_outbox (uses W1.1)
- #8 — Delete writes revoke into fga_outbox (uses W1.1)
- #50 — JIT auto-grant writes fga_outbox grant (uses W1.1)
- #51 — JIT approve/expiry: grant/revoke (not erasure)
- #52 — Break-glass approve writes cluster_admin_grants + fga_outbox

**Acceptance-doc:** `docs/specs/sub-phase-W1.5-chunk1-fga-grant-write-acceptance.md`

### W1.6 — Remediation Chunk 2 (in-service authz + identity spoofing)

**Findings (10):** #9, #11, #12, #13, #35, #36, #37, #39, #43, #53 — see remediation plan Chunk 2.

This is the chunk that **closes the 87 newman failures** because most of them stem from
ListBySubject scope-filter (#12), JitPending caller-scoping (#36), AccessReview reviewer spoofing
(#35), ComplianceReport scope (#37), JITEligibility CreatedBy (#39), SAKey CreatedByUserID (#53),
anti-anonymous interceptor (#43).

**Acceptance-doc:** `docs/specs/sub-phase-W1.6-chunk2-in-service-authz-acceptance.md`

---

## W1 Definition of Done

- [ ] All 6 chunk acceptance-docs APPROVED by acceptance-reviewer
- [ ] All 6 chunks merged in 3 repos (kacho-corelib, kacho-iam, kacho-api-gateway), CI green
- [ ] `fga_outbox` drainer running in kacho-iam, integration test on testcontainers GREEN
- [ ] Revoke → DENY enforced within 1s end-to-end (subject_change_outbox + cache invalidation)
- [ ] Gateway authz-middleware fail-closed on all envs (verified via integration: stop OpenFGA → 503)
- [ ] Principal propagated cross-service (no `user:bootstrap` for tenant requests)
- [ ] **87 newman failures → 0** (newman E2E green on main, coverage stays ≥30, ideally rises as
      side-effect of fixes)
- [ ] Vault: W1 trail in KAC-136.md + new packages note for corelib outbox/drainer + edges note
      updates (iam→OpenFGA sync→async)
- [ ] Coverage measurement: re-run `coverage.py` baseline (likely unchanged since W1 doesn't add
      new RPCs)

---

## Tracker — chunk subtasks (each will be new YT issue, child of KAC-136)

| Chunk | Subtask (YT) | Status | Acceptance-doc | Branch |
|---|---|---|---|---|
| W1.1 fga_outbox drainer | [[../../obsidian/kacho/KAC/KAC-137\|KAC-137]] | ✅ DONE (3 PRs merged 2026-05-23) | sub-phase-W1.1-fga-outbox-drainer-acceptance.md | KAC-136 + KAC-137 |
| W1.2 subject_change_outbox + cache | [[../../obsidian/kacho/KAC/KAC-138\|KAC-138]] | 🟡 proto merged; iam+gateway CI re-running | sub-phase-W1.2-subject-change-cache-invalidation-acceptance.md | KAC-138 |
| W1.3 gateway fail-closed | (TBD) | ⏳ pending | sub-phase-W1.3-*.md | KAC-136 |
| W1.4 principal propagation | (TBD) | ⏳ pending | sub-phase-W1.4-*.md | KAC-136 |
| W1.5 Remediation Chunk 1 (7 findings) | (TBD) | ⏳ pending | sub-phase-W1.5-*.md | KAC-136 |
| W1.6 Remediation Chunk 2 (10 findings) | (TBD) | ⏳ pending | sub-phase-W1.6-*.md | KAC-136 |

## Open decisions (before start of relevant chunk)

| ID | Question | Chunk | Recommendation |
|---|---|---|---|
| OQ-W1-1 | drainer location: new `kacho-corelib/outbox/drainer` или extend existing `kacho-corelib/outbox/` (если writer-side есть)? | W1.1 | Subagent investigates corelib structure first; extend if writer-side exists, else new package |
| OQ-W1-2 | drainer model: dedicated goroutine per outbox table или generic switch? | W1.1 | Generic with `Drainer[T any]` + injected `Applier[T]` — reused для subject_change_outbox в W1.2 |
| OQ-W1-3 | gateway `/internal/v1/authz-cache:invalidate` — REST или gRPC internal? | W1.2 | Existing internal listener (gRPC on 9091); REST adds nothing |
| OQ-W1-4 | #7 (`/iam/v1/roles` anonymous): обновить acceptance KAC-121 или enable anon в gateway? | W1.6 (Chunk 2) | Update acceptance — anon role-catalog read не нужен; ввод от user'а |
| OQ-W1-5 | #40 SAML: реализовать verify-assertion в W1 или guard ACS (501)? | W1.6 (Chunk 2) | По умолчанию guard — verify в W3; не оставлять latent-P0 |
