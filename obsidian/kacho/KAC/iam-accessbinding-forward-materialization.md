---
title: iam AccessBinding forward-fast-path materialization
category: kac
tags: [kacho-iam, kac, refactor, architecture, cqrs]
ticket_id: TBD
status: in-progress
type: refactor
repos: [kacho-iam]
prs: []
opened: 2026-07-23
---

# iam AccessBinding forward-fast-path materialization

> [!note] Decision A (owner-delegated 2026-07-23)
> Owner делегировал выбор с вектором «максимально перспективно (best-practices 2026)
> + максимально производительно» → выбран **A** (product forward-fast-path), НЕ
> B (accept-documented red) и НЕ C (fixture-pace, режет stress-покрытие).

## Проблема

AccessBinding-CREATE материализует v_* tuple'ы через **FULL-path `ReconcileBinding`**
(EXCLUSIVE per-binding advisory-lock + FOR UPDATE, O(scope) per binding). EXCLUSIVE
нужен для exactly-once под **Role.Update fan-out** (concurrent re-materialization того
же binding при смене role-rules — там обязателен delete-stale). Под mass-binding burst
(тысячи bindings back-to-back) EXCLUSIVE сериализует → grant не поспевает → read-your-
writes окно превышает даже generous client-retry → 404. Класс: **O(N²) AccessBinding-
reconcile** под stress-scale (не missing fast-path — намеренно-full-path).

Симптом: mega-rbac stress-коллекции `rbac-subject-channel-equivalence` (1742) +
`rbac-visibility-set` (973) — generous `poll_op`/`read_account_appears` retry
**исчерпывается** (не «0 retries», как ошибочно диагностировалось ранее).

## Решение (A)

Ввести **forward-fast-path для AccessBinding-CREATE**: create — чисто **ADDITIVE**
(binding новый → stale-tuple'ов для delete нет) → **SHARE-lock** forward-fast
(write-missing-only, идемпотентно) post-commit best-effort + `fga_outbox` drainer
backstop. Аналог уже-залендённого resource `ReconcileObjectForward` (SHARE, additive)
и leaf sync-registrar (#102). **FULL-path EXCLUSIVE `ReconcileBinding` ОСТАЁТСЯ** для
Role.Update fan-out + sweep. De-risk: `AcquireBindingLockShared` уже существует в коде.

create-vs-concurrent-revoke race: forward читает CURRENT role-rules на момент
материализации + reconciler-backstop delete-stale добивает; SHARE/EXCLUSIVE на одном
binding-key конфликтуют → сериализуются (no lost-update). Ключевой предмет
system-design review.

`Operation.done` НЕ ждёт видимость tuple ([[opgate-eventual-consistency-lesson]],
ban #9) — forward best-effort, не confirm-gate.

## Затронутые сущности vault

- [[grant-materialization-omirror-root]] — корень: owner-tuple grant O(mirror); этот
  форвард распространяет fix-паттерн на сам binding-create.
- [[openfga-replica-lag-flaky-authz]] — смежный EC-класс (read-after-write lag).
- `data-integrity.md` §«Authz-материализация owner-доступа — flat Contract-A».

## Артефакты

- Acceptance (DRAFT → pending acceptance-reviewer):
  `docs/specs/sub-phase-iam-accessbinding-forward-materialization-acceptance.md`
  (15 сценариев / 5 групп: happy/throughput · concurrency · backstop/idempotency ·
  fan-out/revoke · negative/edge).

## Реализация (rpc-implementer, 2026-07-23)

Метод **`Reconciler.ReconcileBindingForward(ctx, bindingID)`** — binding-side twin уже-
залендённого `ReconcileObjectForward` (тот же файл `reconcile/forward.go`):

- peek `CurrentMembers` → **delete-stale guard (D-4)**: непусто ⇒ delegate to FULL
  `ReconcileBinding` (EXCLUSIVE+delete-stale);
- иначе `AcquireBindingLockShared` (SHARE, **не** EXCLUSIVE) → `LoadBindingUnlocked`
  (без FOR UPDATE) → `desiredMembers` (SHARED verdict `desiredMemberForObject`) →
  materialize **только** `VerificationActive` через существующий `materializeForwardMember`
  (UpsertMember + EmitTupleWrite fga_outbox + ledger `RecordEmittedTuples`, one writer-tx,
  ban #10) → post-commit best-effort `applyAfterCommit` (sync OpenFGA read-delta);
- REJECTED/PENDING **пропускаются** (additive-only; audit оставлен FULL-backstop, D-6).

Create-path (`api/access_binding/create.go`): `SelectorReconciler` получил
`ReconcileBindingForward`; post-commit hook `ReconcileBinding(created.ID)` →
`ReconcileBindingForward(created.ID)`. FULL EXCLUSIVE `ReconcileBinding` **не тронут** —
остаётся для Role.Update fan-out + sweep. **Ни миграции, ни proto/gateway** — оптимизация
целиком внутри реконсайлера (`AcquireBindingLockShared` уже существовал).

### Файлы

- `services/iam/internal/apps/kacho/api/access_binding/reconcile/forward.go` (+ метод)
- `services/iam/internal/apps/kacho/api/access_binding/create.go` (iface + call-swap)
- `services/iam/internal/apps/kacho/api/access_binding/reconcile/forward_binding_test.go` (unit)
- `services/iam/internal/repo/kacho/pg/reconcile_binding_forward_integration_test.go` (integration)

### RED→GREEN

- **Unit RED**: `TestReconcileBindingForward_MaterializesDesired_NoExclusiveLock`
  (`f.locks==0 && f.sharedLocks>=1`) падал против FULL-стаба (create-path брал EXCLUSIVE:
  `locks==1`); `ForeignScope_SkipsNoTuple` падал (FULL писал REJECTED member+audit). **GREEN**
  после SHARE-forward. Integration: 04/05 (`-race`), 07, 03, 10, 08, 01, 12 — все зелёные.

## Lifecycle-гейты

- [x] acceptance-reviewer ✅ APPROVED (2026-07-23; ground-truth verified — все claims подтверждены)
- [x] TDD RED: unit lock-mode (SHARE≠EXCLUSIVE) + additive-skip падали ДО кода; concurrency integration (`-race`) 04/05 зелёные
- [x] impl: SHARE-forward on create + fga_outbox backstop (EXCLUSIVE full-path сохранён)
- [x] system-design-reviewer (обязателен) + go-style-reviewer ✅ APPROVED; db-architect-reviewer — n/a (без миграции)
- [ ] deploy → stress `rbac-subject-channel-equivalence` + `rbac-visibility-set` зеленеют **без cap-widen** (throughput-гейт; НЕ лёгкая `grant-check-propagation`) — координатор post-deploy
- [ ] O(N²)-note закрыт этим форвардом; vault-trail + KAC-ticket номер

## DoD

Обязательные exactly-once + idempotency integration; newman happy (grant fast under
burst) + negative; stress-коллекции green без cap-widen; dual-review APPROVED.

#kacho-iam #kac #refactor #architecture
