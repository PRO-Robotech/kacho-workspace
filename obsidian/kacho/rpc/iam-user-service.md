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
methods_count: 3
async_methods: 1
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - mirror
---

# UserService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/user_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public read-only — write только через [[iam-internal-user-service]].
**Status**: backend в [[KAC-112]].

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetUserRequest | User | sync | по id (`usr…`) |
| List | ListUsersRequest | ListUsersResponse | sync | filter (email-prefix), page_token |
| Delete | DeleteUserRequest | operation.Operation | **async** | admin-only на E0; E2 — self-delete тоже |

> **НЕТ Create** — User создаётся только через OIDC callback ([[iam-internal-user-service]] `UpsertFromIdentity`).
> **НЕТ Update** — `email`/`displayName` синхронизируются только из Zitadel (E2). Локально editable не предусмотрено.

## REST mapping

| HTTP | Method |
|---|---|
| `GET /iam/v1/users/{id}` | Get |
| `GET /iam/v1/users` | List |
| `DELETE /iam/v1/users/{id}` | Delete |

## Notes

- Delete blocked → `FailedPrecondition "User <id> owns accounts and cannot be deleted"` (FK `accounts_owner_fk` RESTRICT).
- GroupMember и AccessBinding на user — soft-ref, не блокируют delete на DB-уровне; service-слой блокирует sentinel'ом (см. acceptance §7.5).

## See also

[[../packages/iam-domain]] [[../resources/iam-user]] [[iam-internal-user-service]] [[../edges/iam-to-zitadel-oidc]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam #mirror
