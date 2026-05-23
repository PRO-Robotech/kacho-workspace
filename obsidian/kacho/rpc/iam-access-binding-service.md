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
  - "[[KAC-129]]"
  - "[[KAC-131]]"
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
| Create | CreateAccessBindingRequest | operation.Operation | **async** | UNIQUE → идемпотентный re-create; пишет FGA grant-tuple |
| Delete | DeleteAccessBindingRequest | operation.Operation | **async** | по id; **удаляет FGA grant-tuple** (revoke) |
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

- UNIQUE (subject_type, subject_id, role_id, resource_type, resource_id) ловит дубликаты; `maperr.go` mapping для этого constraint — `success (no-op)` либо `AlreadyExists` (см. acceptance §6 / §13.4). **KAC-128 BUG-7 fix**: Operation metadata `access_binding_id` теперь содержит СУЩЕСТВУЮЩИЙ id (pre-resolved через `FindExisting` до создания Operation) — не кандидат-id. DB ON CONFLICT остаётся safety-net.
- `subject_id` / `resource_id` хранятся **без FK** (полиморфно, cross-DB) — software-validation отложена в E3 (OpenFGA tuple sync через [[../edges/iam-to-openfga-check]]).
- Удаление Role с активным binding → `FailedPrecondition "Role <id> is in use by access bindings"` (FK RESTRICT).
- **Auth-matrix (KAC-123)** для ListBySubject в handler:
  - explicit `service_account` principal → bypass (admin-tooling).
  - `user` principal → разрешено ТОЛЬКО запрашивать **свои** bindings (`subject_type=user && subject_id=<self>`); иначе 403 `PermissionDenied`.
  - anonymous / system-bootstrap fallback → empty list.
- **Create/Delete authority** (KAC review 2026-05-21 #8/#13): и Create, и Delete авторизуются через общий `requireGrantAuthority` — caller обязан быть owner владеющего Account/Project ИЛИ держать FGA `admin` на scope. Delete больше **не** self-only (`subject_id==principal` убран) — account-owner может отзывать чужие grants.
- **FGA sync (KAC-129 fix #8/#16/#47/#48)**: `Delete.doDelete` после DB-commit удаляет те же tuple'ы, что записал `Create` — через общий `accessBindingTuples(b, relation)` + `OpenFGAClient.DeleteTuples`. Побайтовая идентичность ключей гарантирует, что FGA действительно удаляет (мисматч = silent no-op). До KAC-129 Delete не имел FGA-клиента → туплы оставались, Check → `allowed:true` после Delete. Verified live: 55→53 tuples, Check → `allowed:false`.
- **KAC-131 authz catalog (2026-05-23)**: `Get`, `Delete`, `ListByResource`, `ListBySubject` переведены в `<exempt>` в permission_catalog.json. Причина: (a) account-scoped AB не получал FGA иерархический тупл (только `project`-тип — BUG-6); (b) ListByResource/ListBySubject имели неверный `scope_extractor` → FGA всегда "no path" (BUG-8). Authz теперь — handler-level scope-filter: `Get` — subject/owner check; `Delete` — `requireGrantAuthority`; List* — `RequireAuthenticated`. `Create` остаётся FGA-gated.
- **KAC-131 existence-leak prevention**: `Get` и `Delete` для несуществующего ID возвращают `PermissionDenied` (не `NotFound`) — предотвращает ID-enumeration. `garbage-perresource` authz-deny тест проходит для всех субъектов (403+code 7).

## See also

[[../packages/iam-domain]] [[../resources/iam-access-binding]] [[iam-role-service]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
