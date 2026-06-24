---
title: "RBAC-2026 review fixes — Pass 1: ledger revoke-correctness (#1/#7/#15/#16)"
ticket_id: rbac-2026-review-fixes-pass1
status: in-progress
type: fix
repos:
  - kacho-iam
prs: []
yt_url: ""
opened: 2026-06-24
tags:
  - kac
  - kacho-iam
  - fix
  - usecase
  - repo
  - domain
  - race-fix
---

# RBAC-2026 review fixes — Pass 1: ledger / revoke / backfill / verify

**Status**: in-progress (branch `rbac-2026-review-fixes` in kacho-iam, NOT pushed — passes 2/3 assembled separately)
**Type**: fix — confirmed code-review findings (RBAC-2026 final sweep), ledger/revoke subsystem
**Scope**: review findings #1 (BLOCKER), #7 / #15 / #16 (IMPORTANT/NIT). No proto/schema migration; no api-gateway.

## #1 [BLOCKER] dual-member-same-object revoke стрипал доступ выжившего

Два desired-члена одного binding на ОДНОМ FGA-объекте с ИДЕНТИЧНЫМИ tuples (owner
scope-self `scope_self` + wildcard-expanded `iam.account` content; либо два ARM_LABELS
rule на одном объекте с теми же verbs) делят ОДНУ ledger-строку — PK
`(binding_id, fga_user, relation, object)` без `rule_fp` (mig 0024). Fell-out одного
члена → `revokeTuplesFor`→`LedgerTuplesForObject(binding,object)` возвращал общую строку
→ `EmitTupleDelete`+`ForgetEmittedTuples` снимали живой tuple выжившего; `applyDiff`
(`existed && prevStatus==Status → continue`) не переэмитил → тихая standing-privilege-loss.

**Фикс — подход (b)** (set-difference, БЕЗ PK-миграции на проде): в `applyDiff`
вычисляется `survivingClaims = desiredActiveTupleSet(desired)` (union tuples всех desired
ACTIVE-членов). `revokeMemberTuples(... survivingClaims)` удаляет ТОЛЬКО set-difference
(ledger члена МИНУС survivingClaims) → общий tuple живёт пока не уйдёт ПОСЛЕДНИЙ
владеющий член. Race-free: весь pass под `pg_advisory_xact_lock(binding)` + `SELECT FOR
UPDATE` — параллельного прохода того же binding нет. `ExpireBinding` передаёт `nil`
(все члены снимаются). co-commit (ban #10) сохранён. Подход (b) выбран т.к. чище, без
PK-миграции и без невосстановимого rule_fp-backfill (в ledger нет member-lineage).
Файл: `internal/apps/kacho/api/access_binding/reconcile/reconcile.go`.

## #7 [IMPORTANT] owner-binding FGA-tuples не в ledger → asymmetric revoke

`account/create.go doCreate` эмитил owner self-grant (`user:<o>#owner@account:<A>`) +
hierarchy-pointer (`account:<A>#account@iam_access_binding:<id>`) в fga_outbox, но НЕ
писал в emitted-tuple ledger → revoke owner-binding (delete.go SelectEmittedTuples) их
не снимал; FGA `define admin: … or owner` → revoked owner сохранял admin (нарушение C-03).
**Фикс**: `InsertEmittedTuples(createdBinding.ID, ownerBindingLedgerTuples)` в той же
writer-tx (как обычный AccessBinding.Create, source='binding'). SEC-L cluster-pointer
СОЗНАТЕЛЬНО НЕ пишется в ledger (account-lifecycle, переживает revoke). Не дублирует
reconciler-материализацию scope-self (source='member', distinct relations).

## #15 [NIT] revoked owner-binding блокировал re-grant на backfill

`backfillOwnerBindingsSQL` — детерминир. id `'acb'||md5('owner-binding:'||a.id)` +
`ON CONFLICT (id) DO NOTHING`: revoked tombstone (тот же id) глушил нужный re-grant.
**Фикс**: свежий non-deterministic id + `ON CONFLICT (subject_id,subject_type,role_id,
resource_type,resource_id) WHERE revoked_at IS NULL DO NOTHING` (active-grant partial-UNIQUE
mig 0003). Tombstone (`revoked_at NOT NULL`) не в partial-index → не глушит re-grant;
конкурентный double-insert ACTIVE — чистый no-op. Только Go boot-path
(`internal/apps/kacho/seed/migrate_backfill.go`); applied mig 0036 НЕ трогался (ban #5).

## #16 [NIT] Verify слеп к binding с 0 материализованных членов

`Verify`/`ListActiveBindingMaterialization` ловил «ACTIVE member, но ledger пуст», но НЕ
«должен был дать ≥1 член, а дал 0». **Фикс**: sentinel `ListOwnerBindingsMissingMembers`
(ACTIVE account-scoped owner-binding с 0 ACTIVE members — owner `*.*` всегда даёт ≥1
scope-self member, поэтому без ложных срабатываний). `Verify` флагует их; doc-comment
limitation задокументирован. Файлы: `seed/verify_gate.go`, `repo/kacho/pg/backfill_adapter.go`.

## TDD RED→GREEN (testcontainers / unit)

- #1 integration `reconcile_dual_member_revoke_integration_test.go` — dual-rule survivor
  (RED: survivor tuples deleted + 2 FGA-delete) → GREEN; + owner scope_self/content collision doc-test.
- #7 unit `account/create_test.go::TestCreate_RecordsOwnerBindingTuplesInLedger` — RED (ledger пуст) → GREEN.
- #15 integration `migrate_backfill_p8...::TestReview15_RevokedOwnerBinding_BackfillRecreatesActive` — RED → GREEN.
- #16 integration `...::TestReview16_Verify_FlagsOwnerBindingWithZeroMembers` — RED → GREEN.
- Регрессия: C20-C26 / Test224 / TestP8 / emitted-tuples / owner-binding suites — GREEN. `-race` чисто.

## Затронутые сущности vault

- [[resources/iam-access-binding]] — owner-binding ledger симметричен revoke; shared-tuple survivor invariant.
- [[KAC/rbac-2026-224-owner-wildcard-content]] — тот же owner scope_self+content collision-класс.

## DoD

- [x] RED→GREEN (#1/#7/#15/#16); go build / vet / gofmt clean; unit + targeted integration GREEN; `-race` clean
- [ ] commit на ветке `rbac-2026-review-fixes` (НЕ пуш — passes 2/3 assembled then single push)
- [ ] go-style + system-design review
