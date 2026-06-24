---
title: "RBAC explicit-model 2026 #224 — owner *.* materializes per-object content + verify-gate owner-content check"
ticket_id: rbac-2026-224
status: test
type: fix
repos:
  - kacho-iam
prs:
  - https://github.com/PRO-Robotech/kacho-iam/pull/226
yt_url: https://github.com/PRO-Robotech/kacho-iam/issues/224
opened: 2026-06-24
tags:
  - kac
  - kacho-iam
  - fix
  - domain
  - usecase
  - repo
  - migrations
  - race-fix
---

# RBAC explicit-model 2026 #224 — owner `*.*` per-object content (contract-blocker)

**Status**: test (branch `rbac-224-owner-wildcard-content` in kacho-iam)
**Type**: fix — contract-phase BLOCKER for the RBAC explicit-model 2026 expand→migrate→contract sequencing
**Acceptance**: `docs/specs/rbac-explicit-model-2026-acceptance.md` — D-8a / C-01b (owner per-object content forward), КФ-4 / H-06 (verify-gate forward-aware), D-3 (bounded vs GLOBAL `*.*`), D-9 (cluster short-circuit)
**Issue**: PRO-Robotech/kacho-iam#224

## Что и зачем

Owner-роль `*.*.*` @ ACCOUNT раньше материализовала ТОЛЬКО scope-self member на `account:<A>`
(verb-bearing + admin tier), но НИ ОДНОГО per-object content tuple: `domain.dottedTypes`
скипал wildcard module/resource для ВСЕХ scope (не только GLOBAL). Owner-контент держался
ТОЛЬКО FGA-derivation-каскадом → contract-фазу нельзя было запустить (снятие каскада = потеря
owner-доступа). System-design: verify-gate структурно маскировал gap (`ExpectsTuples` из
`active_members`, который для owner-content всегда 0 — scope-self member давал non-empty ledger).

## Фикс (single reconciler path, КФ-3)

1. **Wildcard-энумерация (scope-aware)** — `domain.dottedTypes(rule, expandWildcard)` + новые
   `Rules.MaterializingSelectorsInScope(scope)` (binding-level, gate по scope) и
   `Rules.MaterializingSelectors()` (role-level persist, всегда expand).
   - BOUNDED scope (ACCOUNT/PROJECT) → wildcard `*.*` разворачивается в полный набор
     `domain.AllMaterializableTypes()` (mirror-fed vpc/compute/nlb + iam-direct project/account),
     ARM_ANCHOR → существующий `MatchAllInScope` + `IsContainedIn` (scope-граница сохранена).
   - GLOBAL/CLUSTER → пустые ObjectTypes → D-9 flat short-circuit (НЕ per-object, Q-2 anti-pattern).
   - `reconcile_adapter.LoadBinding` → `MaterializingSelectorsInScope(b.Scope)` (per-binding gate).
2. **Forward fast-path** — owner anchor selector в `role_rule_selectors` (system-роль не идёт
   через Role.Create, поэтому её selector-строку надо засеять отдельно). Без неё
   `SelectorBindingsMatchingObject` не находил owner binding для свежесозданного объекта →
   C-01b сходился только на periodic sweep.
   - **migration 0038** (`0038_owner_role_rule_selectors.sql`) — DB-level seed (детерминированные
     rule_fp + object_types из `OwnerRoleRules().MaterializingSelectors()`), present сразу после
     `goose up`, до трафика. Закрывает system-design КФ-1 (boot-backfill параллельно с листенером
     не гарантировал наличие строки для свежего аккаунта).
   - **`seed.syncOwnerRoleSelectorsTx`** (в `BackfillOwnerBindings`) — идемпотентный self-heal
     (тот же UPSERT) для типов/аккаунтов, появившихся после миграции.
   - lockstep guard `TestOwnerRoleSelector_MigrationLockstep` (domain) — SQL-константы == Go-проекция.
   Канонические owner-rules — `domain.OwnerRoleRules()` (lockstep с migration 0035 JSON).
3. **Verify-gate extension (КФ-4)** — `verify_gate.go` `ForwardSmoke` теперь гоняется и против
   OWNER binding (позитивный owner-content no-access-loss check). КФ-БАГ-1 NOTE → CLOSED.

## Cross-check (contract unblock)

После фикса owner-content есть per-object (backfill через sweep + forward через worker/sweep)
→ contract сможет снять FGA derivation-каскад без потери owner-доступа. Каскад в этом PR НЕ
трогается (contract — отдельная фаза).

## TDD RED→GREEN

- **unit** `internal/domain/rule_wildcard_scope_test.go` — RED (undefined) → GREEN.
- **integration** `internal/repo/kacho/pg/reconcile_owner_wildcard_content_integration_test.go`
  (testcontainers): Backfill (D-8a), Forward (C-01b), ScopeBoundary (D-3), VerifyGate owner-content (КФ-4).
  RED: 3 demonstrating-теста FAIL (0 content tuple) → GREEN после фикса.

## Затронутые сущности vault

- [[resources/iam-access-binding]] — owner-binding теперь материализует per-object content tuples.
- [[resources/iam-role]] — owner `*.*` rule → ARM_ANCHOR selector над AllMaterializableTypes (bounded).
- [[rpc/iam-internal-iam-service]] — RegisterResource forward-path покрывает owner binding.

## DoD

- [x] RED→GREEN (unit + integration)
- [x] go build / go vet / gofmt clean; domain + apps unit GREEN
- [ ] db-architect + system-design review
- [ ] CI green → merge → contract phase unblocked
