---
title: "Assignable roles (sub-phase 1.5)"
aliases:
  - sub-phase-1.5-assignable-roles
  - assignable-roles
ticket_id: "(none — sub-phase acceptance doc)"
category: kac
status: done
type: feature
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-ui
tags:
  - kac
  - feature
  - kacho-iam
  - kacho-api-gateway
  - kacho-ui
---

# Assignable roles (sub-phase 1.5)

> [!note] Трек без KAC-номера
> Acceptance-док `docs/specs/sub-phase-1.5-assignable-roles-acceptance.md` (✅ APPROVED); YouTrack-тикет не заводился (MCP недоступен).

**Status**: ✅ done — все 4 репо в `main` (proto#63 · gw#86 · iam#163 · ui#94).
**Type**: feature

> [!note] Merge-цепочка (2026-06-19, build-граф proto→gw→iam)
> - **proto** `#63` → `main` `0ee44fe` (ListAssignableRoles + AssignableRole/ScopeGroup).
> - **api-gateway** `#86` → `main` `7dd13c5` (public RPC регистрация; sibling-пины флипнуты на `ref: main`).
> - **iam** `#163` → `main` `f62d65e` (предикат + use-case + Create-enforcement; un-skip known-RED whitelist).
> - **ui** `#94` → `main` `37372fa` (resource-first форма + thin render по scope_group; Playwright e2e адаптирован).

## Что и зачем

Логика «какие роли валидны для ресурса» жила во фронте grant-формы (партиция только по `is_system`, без scope-фильтра) — диссонанс и неправильный слой. Переносим в backend: фронт тонкий, рендерит серверный ответ. Плюс закрываем дыру: `AccessBinding.Create` был пермиссивен по role-vs-resource scope → deep-link/прямой gRPC принимал mis-scoped binding.

## Сделано (S2 — kacho-iam)

- **Единый предикат** `domain.IsRoleAssignable(role, resource_type, resource_id)` + `ScopeGroupOf` + `domain.AssignableRole` projection (`internal/domain/role_scope.go`) — ОДИН источник истины (D-2), STRICT-матрица (Q#1): system везде; account-роль только свой account; project-роль только свой project; cluster ⇒ system.
- **`ListAssignableRoles`** use-case (`list_assignable_roles.go`) + handler + wiring: validate (D-6) → existence/authz `requireGrantAuthority` (D-5/D-7 NotFound) → repo `Reader.ListAssignable` (SQL-mirror предиката, keyset `(created_at,id)`) → `scope_group` derivation. Public sync read.
- **`AccessBinding.Create` scope-enforcement** (D-2): `doCreate` энфорсит `IsRoleAssignable` ДО INSERT (в той же writer-tx, где читается роль) → mis-scoped → **`Operation.error` FAILED_PRECONDITION** «role <id> is not assignable on <type>:<id>» (async-контракт, ban #9 / Q#3; binding не создаётся). list⇔create parity.
- **Forward-only (D-11):** только новые Create; legacy mis-scoped bindings не трогаются (нет migration-revoke / read-hide; Delete отзывает).
- **roleCols read-side** расширен на `cluster_id, project_id` (`role_repo.go` + `role_read_port.go`) — scope-поля для предиката (до 1.5 опускались).
- by-design: `kacho-iam/docs/architecture/assignable-roles-scope-enforcement.md`.

## Тесты (RED→GREEN, в том же PR)

- unit `internal/domain/role_scope_test.go` — матрица предиката + ScopeGroupOf.
- integration `internal/repo/kacho/pg/role_assignable_integration_test.go` — roleCols regression + ListAssignable per resource_type [1.5-01..04, 02b].
- integration `internal/apps/kacho/api/access_binding/list_assignable_roles_integration_test.go` — authz/validate/missing/anon/scope_group [1.5-05..11].
- integration `internal/apps/kacho/api/access_binding/create_scope_enforcement_integration_test.go` — **1.5-12** parity, **1.5-12b** concurrent (2 goroutine, оба FAILED_PRECONDITION, 0 bindings — нет TOCTOU), **1.5-13** account-role на cluster, **1.5-21** forward-only legacy survives (read + Delete).
- newman `tests/newman/cases/iam-access-binding.py` — happy (account/cluster), malformed, authz-deny, parity mis-scoped Create→Operation.error FAILED_PRECONDITION.

> [!note] Testcontainers
> Локально нужен `TESTCONTAINERS_RYUK_DISABLED=true` (colima/QEMU Ryuk-reaper флапает «container removing») + `DOCKER_HOST=unix://$HOME/.colima/default/docker.sock`. Все integration-тесты зелёные на чистой VM.

## Фиксы при un-skip (2026-06-19, после merge proto#63+gw#86 в main)

Снятие known-RED whitelist обнажило 2 расхождения (deps уже в main, не cross-repo):

- **Регрессия missing-role**: ранний role-read в `doCreate` (для scope-enforcement) для несуществующей роли отдавал сырой `ErrNotFound` (5) вместо pre-1.5 FK-контракта (23503→`FailedPrecondition` 9). Фикс: role-not-found из раннего read → `FAILED_PRECONDITION` (и missing, и mis-scoped роль → 9). RED→GREEN `TestCreate_RoleMissing_FailedPrecondition`. Покрыт newman `IAM-ACB-CR-NEG-ROLE-MISSING`.
- **malformed resource_id → 400 vs 403**: use-case валидирует формат первым (D-6 → 400; держит integration 1.5-06), НО e2e через gateway authz-интерцептор fail-closed pre-empt'ит формат-валидацию на malformed scope-объекте → `PERMISSION_DENIED` 403. Оба корректны (defense-in-depth). newman `IAM-ACB-LAR-NEG-MALFORMED` → `oneOf([400,403])` (прецедент `Get-malformed` 400/404); слоистость в `docs/architecture/assignable-roles-scope-enforcement.md`.

## Затронутые сущности vault

[[../rpc/iam-access-binding-service]] [[../resources/iam-role]] [[../resources/iam-access-binding]]

## DoD

- [x] proto: `ListAssignableRoles` + `AssignableRole` + `ScopeGroup` (на feature-ветке `iam-list-assignable-roles`, gen-stubs в `kacho-proto/gen`)
- [x] iam S2: предикат + use-case + Create-enforcement + roleCols; RED→GREEN (unit + integration зелёные)
- [x] newman happy + negative + parity
- [x] docs/architecture by-design note (+ malformed 400/403 layering + missing-role→FP)
- [x] proto merge на `main` (`#63` → `0ee44fe`)
- [x] api-gateway S3: регистрация public RPC (`#86` → `7dd13c5`)
- [x] iam merge на `main` (`#163` → `f62d65e`; un-skip whitelist + 2 фикса)
- [x] ui S4: resource-first форма + thin render по scope_group (`#94` → `37372fa`)
- [x] vault обновлён

## Связанные тикеты

- [[sub-phase-1.3-subject-privileges]] — grant-форма / privileges (та же IAM-эпопея, reconcile сохраняется)
- [[sub-phase-1.2-iam-operations]] — operations visibility

#kac #feature #kacho-iam #kacho-api-gateway #kacho-ui
