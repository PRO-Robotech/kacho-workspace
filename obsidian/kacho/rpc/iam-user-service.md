---
title: UserService
aliases:
  - UserService (iam)
proto_file: kacho/cloud/iam/v1/user_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-user]]"
methods_count: 5
async_methods: 2
status: done
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[sub-phase-1.2-iam-operations]]"
  - "[[sub-phase-1.3-subject-privileges]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - mirror
---

# UserService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/user_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public — read (`Get`/`List`) + label-write `Update` (DIVERGENCE-A); identity-mirror write — через [[iam-internal-user-service]].
**Status**: backend в [[KAC-112]]; `Update` (label-write) merged DIVERGENCE-A (proto#89 / iam#249 `b4164e0f` / api-gateway#102).

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetUserRequest | User | sync | по id (`usr…`). **Authz (flat Design B): self OR `v_get` на `iam_user:<id>` OR cluster-admin (`authzguard.AllowsVGet` + self fast-path); non-authz → NotFound (hide).** См. [[rbac-explicit-model-2026]] read-authz trail. |
| List | ListUsersRequest | ListUsersResponse | sync | filter (email-prefix), page_token. **`viewer ∪ v_list`** (эталон role.List; DIVERGENCE-A): anonymous→empty, FGA error→`Unavailable`, self-floor, admin/owner/cluster-admin через viewer-tier; **membership-over-show устранён** (член аккаунта не видит всех — только себя + viewer/v_list). `Get == List` resolver. |
| Update | UpdateUserRequest | operation.Operation | **async** | **новый публичный label-write RPC** (DIVERGENCE-A, [[sub-phase-T3.3-unify-iam-label-scope-acceptance]]). **Flat request** `{user_id, update_mask, labels}` (паритет с UpdateRole/SA/AB — НЕ вложенный `User`). `labels` — единственное mutable; `external_id` (и иные IdP-mirror) в `update_mask` → `INVALID_ARGUMENT "external_id is immutable after User.Create"`; unknown mask-поле → `INVALID_ARGUMENT`; пустой mask = full-PATCH над `labels`. AuthZ — `v_update` на `iam_user:<id>` + cluster-admin short-circuit. label-change co-commit'ит reconcile-event в writer-tx (eager re-материализация). REST `PATCH /iam/v1/users/{user_id}`. |
| Delete | DeleteUserRequest | operation.Operation | **async** | admin-only на E0; E2 — self-delete тоже |
| ListOperations | ListUserOperationsRequest | ListUserOperationsResponse | sync | per-resource ops history (sub-phase 1.2; filter `resource_id`, viewer-tier на gateway). Был дырой → UI таб «Операции» бил в 404. |

> **НЕТ Create** — User создаётся только через OIDC callback ([[iam-internal-user-service]] `UpsertFromIdentity`).
> **Update — только `labels`** (см. таблицу). `email`/`displayName`/`external_id` остаются IdP-mirror'ом из Zitadel (immutable локально); editable — только tenant-facing `labels`.

## REST mapping

| HTTP | Method |
|---|---|
| `GET /iam/v1/users/{id}` | Get |
| `GET /iam/v1/users` | List |
| `PATCH /iam/v1/users/{user_id}` | Update (label-write) |
| `DELETE /iam/v1/users/{id}` | Delete |
| `GET /iam/v1/users/{user_id}/operations` | ListOperations |

## Notes

- Delete blocked → `FailedPrecondition "User <id> owns accounts and cannot be deleted"` (FK `accounts_owner_fk` RESTRICT).
- GroupMember и AccessBinding на user — soft-ref, не блокируют delete на DB-уровне; service-слой блокирует sentinel'ом (см. acceptance §7.5).
- **ListOperations (sub-phase 1.2, iam #160)** — `WithListOperations` mirror существующих 5 ресурсов; фильтрует `operations` по `resource_id`. Privacy: per-scope-viewer, не per-creator (см. `docs/architecture/operations-visibility-privacy.md`). См. [[sub-phase-1.2-iam-operations]].
- **Привилегии-таб (sub-phase 1.3)** — детальная страница User в kacho-ui получила таб «Привилегии» через [[iam-access-binding-service]] `ListSubjectPrivileges` (subject=этот user) + кнопку «добавить привилегии» → AccessBindingCreatePage с locked subject. См. [[sub-phase-1.3-subject-privileges]].

## See also

[[../packages/iam-domain]] [[../resources/iam-user]] [[iam-internal-user-service]] [[../edges/iam-to-zitadel-oidc]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam #mirror
