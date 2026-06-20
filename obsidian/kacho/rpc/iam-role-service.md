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
| Get | GetRoleRequest | Role | sync | по id (`rol…`) |
| List | ListRolesRequest | ListRolesResponse | sync | filter: `is_system=true\|false`, `account_id="..."` |
| Create | CreateRoleRequest | operation.Operation | **async** | **только custom**; account_id required |
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
- **update_mask**: `rules`(+name/description) mutable; `permissions` → `INVALID_ARGUMENT
  "permissions is immutable after Role.Create"`; OCC через `resource_version` (xmin) при
  изменении rules.
- **Delete (A-16)**: custom-роль с активными биндингами → `Operation.error
  FAILED_PRECONDITION "role is in use by active access bindings"` (FK 23503 RESTRICT,
  не software TOCTOU).
- Новые proto-поля (через `kacho-proto` main): `Role.rules`/`resource_version`/
  `created_by_user_id`/`updated_at`; `Rule` message; `Create/UpdateRoleRequest.rules`.
  REST camelCase: `rules`/`matchLabels`/`resourceNames`/`resourceVersion`/`createdByUserId`.
  api-gateway — без правок (только поля на существующих сообщениях, RPC-набор не менялся).
- Осталось на **sub-phase B**: FGA-эмиссия из rules (`scope_grant`, per-verb relations).

## See also

[[../packages/iam-domain]] [[../resources/iam-role]] [[iam-access-binding-service]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
