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

## See also

[[../packages/iam-domain]] [[../resources/iam-role]] [[iam-access-binding-service]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
