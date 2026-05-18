---
title: InternalUserService
aliases:
  - InternalUserService (iam)
proto_file: kacho/cloud/iam/v1/internal_user_service.proto
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-user]]"
methods_count: 2
async_methods: 1
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
  - mirror
---

# InternalUserService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_user_service.proto`
**Backend**: `kacho-iam:9091` (**internal-only**; запрет #6)
**Visibility**: internal — частично через api-gateway internal mux.
**Status**: backend в [[KAC-112]]; реальный заполнятель — OIDC-callback в E2.

## Methods

| Method | Request | Response | Sync/Async | Transport (E0) | Transport (E2) |
|---|---|---|---|---|---|
| **UpsertFromIdentity** | UpsertFromIdentityRequest | operation.Operation | **async** | **gRPC direct only** (admin через `grpcurl -plaintext kacho-iam:9091`) | REST `/iam/v1/internal/users:upsertFromIdentity` (вызывается OIDC-callback handler в api-gateway) |
| Get | GetUserRequest | User | sync | internal REST + gRPC | (same) — нужен E2 auth-interceptor для резолва principal без auth |

## REST mapping (internal mux only)

| HTTP | Method | Available since |
|---|---|---|
| `GET /iam/v1/internal/users/{id}` | Get | E0 |
| `POST /iam/v1/internal/users:upsertFromIdentity` | UpsertFromIdentity | **E2** (на E0 — только gRPC direct) |

## UpsertFromIdentity семантика

- Key — `external_id` (Zitadel `sub`).
- UPSERT: если row с `external_id` есть → UPDATE `email`, `display_name`; иначе INSERT новой row.
- ID-генерация — `ids.NewID("usr")` при INSERT.

## Notes

- E0: stub-заполнение admin'ом для bootstrap (создать User → создать Account). E2 переключит на OIDC-callback автоматически после первого успешного логина.
- `external_id` UNIQUE — UPSERT атомарен; CAS не нужен (PK insert либо UPDATE matched).
- Newman кейс `iam-internal-only-check` проверяет, что REST endpoint не доступен на external TLS.

## See also

[[../packages/iam-domain]] [[../resources/iam-user]] [[../edges/iam-to-zitadel-oidc]] [[iam-user-service]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam #internal #mirror
