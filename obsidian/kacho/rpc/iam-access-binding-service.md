---
title: AccessBindingService
aliases:
  - AccessBindingService (iam)
proto_file: kacho/cloud/iam/v1/access_binding_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-access-binding]]"
methods_count: 5
async_methods: 2
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - rpc
  - kacho-iam
  - iam
---

# AccessBindingService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/access_binding_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public
**Status**: backend в [[KAC-112]]. E0 хранит binding'и, **не** enforce'ит authz — E3 ([[KAC-108]]) добавит Check-interceptor.

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Create | CreateAccessBindingRequest | operation.Operation | **async** | UNIQUE → идемпотентный re-create |
| Delete | DeleteAccessBindingRequest | operation.Operation | **async** | по id |
| Get | GetAccessBindingRequest | AccessBinding | sync | |
| ListByResource | ListAccessBindingsByResourceRequest | ListAccessBindingsResponse | sync | filter (resource_type, resource_id) |
| ListBySubject | ListAccessBindingsBySubjectRequest | ListAccessBindingsResponse | sync | filter (subject_type, subject_id) |

## REST mapping

| HTTP | Method |
|---|---|
| `POST /iam/v1/accessBindings` | Create |
| `GET /iam/v1/accessBindings/{id}` | Get |
| `DELETE /iam/v1/accessBindings/{id}` | Delete |
| `POST /iam/v1/accessBindings:listByResource` | ListByResource |
| `POST /iam/v1/accessBindings:listBySubject` | ListBySubject |

## Notes

- UNIQUE (subject_type, subject_id, role_id, resource_type, resource_id) ловит дубликаты; `maperr.go` mapping для этого constraint — `success (no-op)` либо `AlreadyExists` (см. acceptance §6 / §13.4).
- `subject_id` / `resource_id` хранятся **без FK** (полиморфно, cross-DB) — software-validation отложена в E3 (OpenFGA tuple sync через [[../edges/iam-to-openfga-check]]).
- Удаление Role с активным binding → `FailedPrecondition "Role <id> is in use by access bindings"` (FK RESTRICT).
- **Auth-matrix (KAC-123)** для ListBySubject в handler:
  - explicit `service_account` principal → bypass (admin-tooling).
  - `user` principal → разрешено ТОЛЬКО запрашивать **свои** bindings (`subject_type=user && subject_id=<self>`); иначе 403 `PermissionDenied`.
  - anonymous / system-bootstrap fallback → empty list.

## See also

[[../packages/iam-domain]] [[../resources/iam-access-binding]] [[iam-role-service]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
