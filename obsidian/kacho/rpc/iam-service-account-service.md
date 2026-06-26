---
title: ServiceAccountService
aliases:
  - ServiceAccountService (iam)
proto_file: kacho/cloud/iam/v1/service_account_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-service-account]]"
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

# ServiceAccountService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/service_account_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public
**Status**: backend в [[KAC-112]].

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetServiceAccountRequest | ServiceAccount | sync | |
| List | ListServiceAccountsRequest | ListServiceAccountsResponse | sync | filter account_id. **`viewer ∪ v_list`** (эталон role.List; DIVERGENCE-A): anonymous→empty, FGA error→`Unavailable`, self-floor, admin/owner/cluster-admin через viewer-tier; **membership-over-show устранён** (член аккаунта не видит все SA). `Get == List` resolver. |
| Create | CreateServiceAccountRequest | operation.Operation | **async** | account_id required; принимает own-resource `labels` (DIVERGENCE-A; полный annotation-set, паритет account/project — раньше SA request-`labels` были без аннотаций). |
| Update | UpdateServiceAccountRequest | operation.Operation | **async** | UpdateMask; account_id immutable; `labels` mutable через `update_mask` (DIVERGENCE-A) — label-change co-commit'ит reconcile-event `iam.serviceAccount`. |
| Delete | DeleteServiceAccountRequest | operation.Operation | **async** | |
| ListOperations | ListServiceAccountOperationsRequest | ListServiceAccountOperationsResponse | sync | |

> **НЕТ key-credentials RPC на E0**. CreateKey/ListKeys/DeleteKey появятся в E2 через Zitadel `client_credentials` grant.

## REST mapping

| HTTP | Method |
|---|---|
| `GET /iam/v1/serviceAccounts/{id}` | Get |
| `GET /iam/v1/serviceAccounts` | List |
| `POST /iam/v1/serviceAccounts` | Create |
| `PATCH /iam/v1/serviceAccounts/{id}` | Update |
| `DELETE /iam/v1/serviceAccounts/{id}` | Delete |
| `GET /iam/v1/serviceAccounts/{id}/operations` | ListOperations |

## Notes

- Без E2 SA остаётся identity-stub: не может «логиниться» (нет credentials).
- Delete SA с активной GroupMember/AccessBinding — на E0 sentinel `FailedPrecondition` от service-слоя.

## See also

[[../packages/iam-domain]] [[../resources/iam-service-account]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
