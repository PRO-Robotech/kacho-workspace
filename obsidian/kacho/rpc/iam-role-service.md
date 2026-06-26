---
title: RoleService
aliases:
  - RoleService (iam)
proto_file: kacho/cloud/iam/v1/role_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-role]]"
methods_count: 6
async_methods: 3
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - rpc
  - kacho-iam
  - iam
---

# RoleService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/role_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public
**Status**: backend custom-CRUD в [[KAC-112]]; system-роли seed-нуты миграцией E0 ([[KAC-105]]).

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetRoleRequest | Role | sync | по id (`rol…`); **system → exempt (catalog floor, served to all); custom → per-object `viewer`-tier enforce (#193), ungranted → `NOT_FOUND` no-leak** (D-1, read==enforce с List) |
| List | ListRolesRequest | ListRolesResponse | sync | **scope-filtered per-object** (R-10/§11): system roles (catalog floor) ∪ FGA `viewer`-tier custom (#193); `account_id` field (#185) scopes to system + that account; `page_size>1000`→`INVALID_ARGUMENT` (#184) |
| Create | CreateRoleRequest | operation.Operation | **async** | **только custom**; scope = account_id **XOR** project_id (#212, proto tag 6); both/neither → `INVALID_ARGUMENT`. account-scoped → FGA owner-tuple `iam_role:<id>#account@account:<acc>`; project-scoped → no owner-tuple (FGA `iam_role` has no `project` ancestor) |
| Update | UpdateRoleRequest | operation.Operation | **async** | system-role → `FailedPrecondition` |
| Delete | DeleteRoleRequest | operation.Operation | **async** | system-role → FailedPrecondition; FK от AccessBinding RESTRICT |
| ListOperations | ListRoleOperationsRequest | ListRoleOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /iam/v1/roles/{id}` | Get |
| `GET /iam/v1/roles` | List |
| `POST /iam/v1/roles` | Create |
| `PATCH /iam/v1/roles/{id}` | Update |
| `DELETE /iam/v1/roles/{id}` | Delete |
| `GET /iam/v1/roles/{id}/operations` | ListOperations |

## Notes

- System-role immutable — sentinel в service-слое до DB-CHECK (`is_system=true` rows запрещено меняться).
- 12 default system-roles (см. [[../resources/iam-role]]) seed-нуты `0001_initial.sql`; добавление новой system-role — только новой миграцией (запрет #5).
- Wildcard permissions хранятся as-is, не разворачиваются — expansion в E3 через OpenFGA Check.

## RBAC rules-model 2026 — sub-phase A (gh#182)

- **Create/Update принимают `rules`** (authored policy), валидируют + компилируют в
  internal `permissions` (`domain.CompileRules`) + хранят оба в одной writer-tx.
  Client-sent `permissions` → sync `INVALID_ARGUMENT "Illegal argument permissions
  (compiled/output-only)"` (A-02, первым стейтментом handler'а).
- **Get → `Role`** (как и раньше, без `GetRoleResponse`-обёртки) с `rules[]`;
  `permissions` в ответе **пустое** (internal compiled, R-7). List — то же.
- **update_mask**: `rules`(+name/description/**labels**) mutable; `permissions` → `INVALID_ARGUMENT
  "permissions is immutable after Role.Create"`; OCC через `resource_version` (xmin) при
  изменении rules.
- **Own-resource `labels` (T3.3)**: `Create/UpdateRoleRequest.labels` (own-resource метки
  Role, ≠ `Rule.matchLabels` object-selector) → `roles.labels` jsonb; полный annotation-set
  (паритет account/project). Изменение labels co-commit'ит reconcile-event `iam.role`
  (label-grant на `iam.role` материализует `v_list` — Role стал label-selectable).
- **Delete (A-16)**: custom-роль с активными биндингами → `Operation.error
  FAILED_PRECONDITION "role is in use by active access bindings"` (FK 23503 RESTRICT,
  не software TOCTOU).
- Новые proto-поля (через `kacho-proto` main): `Role.rules`/`resource_version`/
  `created_by_user_id`/`updated_at`; `Rule` message; `Create/UpdateRoleRequest.rules`.
  REST camelCase: `rules`/`matchLabels`/`resourceNames`/`resourceVersion`/`createdByUserId`.
  api-gateway — без правок (только поля на существующих сообщениях, RPC-набор не менялся).
- Осталось на **sub-phase B**: FGA-эмиссия из rules (`scope_grant`, per-verb relations).

## RBAC rules-model 2026 — sub-phase H (Rule.module scalar) — proto#80/iam#210/gw#95/ui#107, LIVE fe3455

- **`Rule.modules` (repeated) → `Rule.module` (scalar)** — ровно ОДИН модуль на правило (proto
  tag 6; `modules` tag 1 tombstoned `reserved`). Create/Update `rules[]` несут `module` (camelCase
  REST). Роль на несколько модулей = несколько правил. Убирает декартов modules×resources с невалидными парами.
- **`Validate` reject'ит unknown module** на request-path (`INVALID_ARGUMENT "Illegal argument module
  (unknown module '<m>')"`; грамматика-fail → `invalid token`). Closed-set владеет domain
  (`IsKnownModule`: iam/vpc/compute/loadbalancer); authzmap lockstep-drift-test.
- **Migration 0033** (live fe3455): rewrite 64 ролей `modules:[x]`→`module:x` + `CREATE OR REPLACE
  iam_rules_valid` scalar-shape (drop-constraint→rewrite→replace-fn→re-add `roles_rules_valid`, одна tx);
  идемпотентна; reversible Down. Применена (`version: 33`), 0 legacy `modules`.
- **#1 labelSelectable**: PermissionCatalog несёт `label_selectable` (=`domain.IsLabelSelectableType`);
  UI гейтит арм matchLabels только label-selectable ресурсами.
- Trail: [[rbac-rules-model-2026-subphase-H-rule-module-scalar]].

## RBAC rules-model 2026 — sub-phase D (§11 per-object filtered List)

- **`List` is per-object scope-filtered** (R-10 / acceptance D-40..D-46). The use-case
  resolves the caller's FGA `ListObjects(subject, "viewer", "iam_role")` set (#193 — see below;
  the `viewer` tier cascades from account-tier → owner sees own roles; read==enforce with Get/Check, D-45)
  and pushes it into the repo as `ListFilter.VisibleIDs` → `WHERE (is_system OR id = ANY($visible))`. So
  **pagination runs AFTER the filter** at the SQL layer (dense keyset, no leaky pages, D-46).
- **System roles bypass the filter** (tenant-wide reference catalog floor; `RoleService.Get`
  stays `<exempt>` in proto). Only **custom** roles are filtered per-object (ungranted custom → absent, LST-5).
- **`Get` enforces custom roles too (BLOCKER D-1 fix).** `RoleService.Get` was `<exempt>` and the
  use-case did NO per-object Check → `Get(<ungranted-custom-id>)` returned the FULL body incl.
  `rules[]` (snapshot of another account's policy) while List hid it → read≠enforce (D-45) +
  existence-leak (D-44/LST-5). Fix (`api/role/get.go`): **system** role (`is_system=true`) →
  served to all (catalog floor, FGA NOT consulted); **custom** role → enforced via the SAME
  `resolveVisibleRoleIDs` (FGA `ListObjects(subject,"viewer","iam_role")`, #193) that backs List
  (single source of truth). `id ∉ set` → `NOT_FOUND "Role <id> not found"` (NOT `PERMISSION_DENIED`
  — no existence-leak), `rules[]` NOT returned. Enforcement stays in the use-case (RPC must keep
  `<exempt>` so system-role Get passes the interceptor), mirroring `list.go`.
- **Fail-closed (D-47/security.md):** a nil FGA port or an FGA error on a *custom*-role Get →
  `UNAVAILABLE` (never a body leak). System-role Get never needs FGA.
- **read==enforce parity (D-45):** `{role : Get(role) success} == {role : role ∈ List}` for custom
  roles (system → both always succeed). Proven by `api/role/get_authz_test.go` parity test +
  real-OpenFGA `api/access_binding/get_role_fga_integration_test.go` (Get-set ⇔ List-set ⇔ Check).
- **`#185 account_id`** (proto `ListRolesRequest.account_id=4`, append-only): scopes the catalog
  to system + that Account's custom roles at the SQL layer (`(is_system OR account_id=$acc)`);
  a foreign Account's custom roles never appear.
- **`#184 page_size>1000`** → `INVALID_ARGUMENT` (no silent clamp) — repo `effectivePageSize`,
  parity with kacho-vpc `corevalidate.PageSize`. Applies to ALL iam public List RPCs.
- **Fail-closed** (D-47): nil FGA port / FGA error → `UNAVAILABLE` (never an unfiltered catalog leak).

## #212 — Create project-scoped custom role (CreateRoleRequest.project_id)

- **Gap**: public `Role.Create` could mint only **account-scoped** custom roles — `CreateRoleRequest`
  had no `project_id` and the handler dropped it. So the RC-1 **project-anchor** path
  (`project:<P>#viewer@<subject>`, AccessBinding.Create emitAnchorRule with anchorType=project)
  was unreachable: `IsRoleAssignable` (STRICT) needs a project-scoped role to bind on a `project`.
- **Fix** (kacho-proto PR#81 + kacho-iam PR#215):
  - proto: `CreateRoleRequest.project_id = 6` (append-only); `account_id` loses `(required)`.
  - handler `roleFromCreateReq`: maps account_id **XOR** project_id.
  - use-case: scope XOR (both/neither → `INVALID_ARGUMENT`); per-scope id-format check;
    FGA owner-tuple emitted **only** for account-scoped (no `iam_role.project` relation in FGA model).
  - repo `Insert`: persists `project_id`; account_id/project_id via `NULLIF($,'')` → NULL (CHECK/UNIQUE/FK).
- **Follow-up**: T-E4 (`iam-invite-grant-fga.py`, #211) goes GREEN → un-whitelist `bind-project-anchor`
  in `scripts/assert-suites-green.sh`. project-scoped `iam_role` admin/editor authz-cascade needs an
  `iam_role.project` relation in the deploy FGA model (not in scope of #212).

## Fix #193 — read-enforce relation `v_list` → `viewer` (owner sees own role)

- **Bug** (regression on sub-phase D): `Role.Get`/`List` filtered custom roles via FGA
  `ListObjects(subject,"v_list","iam_role")`, but in the canonical model `iam_role.v_list`
  has **no tier bridge** (`[user,...] or g_vlist_iam_role from account` — resolves only from a
  direct tuple or `scope_grant`). `Role.Create` writes only the hierarchy tuple
  `iam_role:<id>#account@account:<acc>` (no v_*), so a role's creator/account-admin held
  `admin` (tier) on their own role but NOT `v_list` → own role hidden → **404 on own Get,
  absent from own List**.
- **Root cause asymmetry**: `account.List`/`project.List` filter via the `viewer` **tier**
  relation (which DOES cascade admin→editor→viewer from account); role wrongly chose the
  `v_list` **verb** relation (which does not).
- **Fix**: `resolveVisibleRoleIDs` (api/role/list.go) now queries
  `ListObjects(subject,"viewer","iam_role")` — the `viewer` tier on `iam_role`
  (`viewer from account or editor or g_viewer_iam_role from account`) cascades from the
  account tier, so the owner resolves their own roles; foreign accounts still resolve none
  (Get→404, absent from List — no-leak preserved). Single source of truth for Get + List
  (read==enforce). **No model change, no migration.**
- **AccessBinding** list-RPCs were audited — they gate via the `admin` tier `Check` + `IsSelf`,
  never `ListObjects(v_*)`, so they were never affected (no fix needed).
- **Scope note**: per-verb `v_list`-based filtering is deferred to #188 (when the Check-path
  migrates to v_*); today the role read-surface "can read" == `viewer`, like all of iam.
- Verified: real-OpenFGA `api/access_binding/list_objects_role_owner_fga_integration_test.go`
  (owner viewer-cascade ✓, v_list non-cascade ✓, foreign no-leak ✓, read==enforce parity ✓).

## See also

[[../packages/iam-domain]] [[../resources/iam-role]] [[iam-access-binding-service]] [[iam-permission-catalog-service]] [[../KAC/KAC-105]] [[../KAC/rbac-rules-model-2026-subphase-D-iam]] [[../KAC/rbac-rules-model-2026-subphase-G-iam]]

> [!note] Grantable role-rule taxonomy (rules-model G)
> The set of grantable `(module,resource)` tokens + closed verbs + wildcard policy a role-rule author may pick is served by the **public** [[iam-permission-catalog-service]] (`GET /iam/v1/permissionCatalog`) — backend-driven projection of `authzmap.objectTypes`, replacing the old UI-hardcoded catalog. Two-way set-equality with `authzmap.Catalog()`.

#rpc #kacho-iam #iam
