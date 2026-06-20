---
title: RBAC rules-model 2026 — sub-phase A (iam)
ticket_id: gh-kacho-iam-182
status: test
type: feature
repos:
  - kacho-iam
  - kacho-proto
prs: []
yt_url: https://github.com/PRO-Robotech/kacho-iam/issues/182
opened: 2026-06-20
tags:
  - kac
  - kacho-iam
  - feature
  - domain
  - migrations
---

# RBAC rules-model 2026 — sub-phase A (iam)

**Status**: test (code-complete on branch `rbac-rules-a-iam`, not committed)
**Type**: feature (epic «RBAC rules-model 2026», sub-phase A — compile/validate/store/serve)
**Repos**: kacho-iam (this), kacho-proto (stubs already in main)
**Issue**: PRO-Robotech/kacho-iam#182
**Acceptance**: `docs/specs/rbac-rules-model-2026-acceptance.md` (APPROVED, раунд 2) — A-01..A-16, §2.1/§2.4/§2.5

## Что и зачем

K8s-style rules-in-role. Role обзаводится `rules[]` (authored authority + публичная API),
`permissions[]` → internal compiled. Sub-phase A = **только** compile/validate/store/serve —
**БЕЗ изменения FGA-эмиссии** (это sub-phase B).

## Сделано (A)

- **proto** (already in main): `Rule` message, `Role.rules=11`/`resource_version=12`/
  `created_by_user_id=13`/`updated_at=14`, `Create/UpdateRoleRequest.rules`. `Get` остаётся `returns (Role)`.
- **domain** (`internal/domain/`): `Rule` + `Validate(systemCtx)` (wildcard policy R-3,
  XOR selector, cardinality, feed-gate), `CompileRules` (anchor/names→4-seg permissions;
  matchLabels НЕ компилируется; verb-`*`→`m.r.*.*`; cap ≤1024), `feed_registry.go`
  (closed label-selectable set, O-4). `Permissions.Validate` cap 256→1024.
- **migration 0025** (`0025_role_rules_and_cap_raise.sql`): `roles.rules jsonb NOT NULL
  DEFAULT '[]'` + `iam_rules_valid` shape CHECK (≤64; modules/resources/verbs 1..16;
  resourceNames≤256 XOR matchLabels≤16) + cap-raise `iam_permissions_valid` 256→1024.
- **repo** (`role_repo.go`): persist/scan `rules` + compiled `permissions`; `Delete`
  переписан на FK RESTRICT (23503→FailedPrecondition, A-16) — software TOCTOU удалён (ban #10).
  `errors.go`: `access_bindings_role_fk` direction-sensitive (kindHint `Role.Delete` →
  "role is in use by active access bindings").
- **use-case/handler**: Create/Update принимают `rules`, валидируют+компилируют+хранят оба
  в одной writer-tx; `permissions` на входе → reject (A-02); update_mask `rules` mutable,
  `permissions` immutable; OCC через resource_version. Get/List → `Role` с `rules[]`,
  `permissions` пустое (DTO).
- **api-gateway**: без правок (поля на существующих сообщениях, RPC-набор не менялся).

## Затронутые сущности vault

- [[../resources/iam-role]] — rules-форма, cap 1024, permissions internal-only, A-16 RESTRICT
- [[../rpc/iam-role-service]] — Create/Update accept rules, Get→Role, A-02/A-16

## RED → GREEN proof

- **domain unit**: RED `domain.Rule`/`CompileRules` undefined → GREEN `go test ./internal/domain/`.
- **handler unit**: RED `rulesFromProto` undefined / A-02 not rejected → GREEN.
- **repo integration** (testcontainers, NOT -short): A-01 round-trip RED (rules len 0) →
  GREEN; A-16 RED (old text) → GREEN ("role is in use by active access bindings");
  A-12/A-13 DB-CHECK GREEN; Delete regressions 30b/30c/30d GREEN.
- **newman**: migrated 4 case-files permissions→rules; +A-02/A-04/A-05/A-10/A-12/A-13 cases;
  rewrote A-16 in-use (real custom-role+binding flow, removed TODO probe). gen.py exit 0.

## DoD

- [x] proto (stubs in main)
- [x] migration 0025 (rules CHECK + cap-raise lockstep)
- [x] domain compiler + feed-gate (pure Go)
- [x] repo persist/read + FK-RESTRICT Delete
- [x] use-case/handler + DTO
- [x] RED→GREEN integration + newman в том же diff
- [ ] commit/push (НЕ делалось по инструкции)
- [ ] reviews: db-architect (migration), proto-api (proto), go-style (compiler)

## Осталось на sub-phase B

FGA-эмиссия из rules: `scope_grant`-примитив (type-scoped anchor, fix F1 #177),
per-verb FGA relations (R-2), arm-tagged emit (ANCHOR→scope_grant, NAMES→per-object,
LABELS→suppress-anchor), verb-`*` разворот в полный per-verb набор типа, revoke по
`access_binding_emitted_tuples`. matchLabels-материализация (reconciler) — sub-phase C.

#kac #kacho-iam #feature
