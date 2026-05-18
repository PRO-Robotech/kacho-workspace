---
title: AccountService
aliases:
  - AccountService (iam)
proto_file: kacho/cloud/iam/v1/account_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-account]]"
methods_count: 6
async_methods: 3
status: done
related_tickets:
  - "[[KAC-105]]"
tags:
  - rpc
  - kacho-iam
  - iam
---

# AccountService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/account_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC) + `:9091` (internal)
**Visibility**: public (registered на обоих listener'ах api-gateway)
**Status**: реализован в [[KAC-105]] (E0).

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetAccountRequest | Account | sync | NotFound → 404; malformed id → InvalidArgument |
| List | ListAccountsRequest | ListAccountsResponse | sync | filter (YC-syntax) + page_token |
| Create | CreateAccountRequest | operation.Operation | **async** | metadata: CreateAccountMetadata{account_id} |
| Update | UpdateAccountRequest | operation.Operation | **async** | UpdateMask; `owner_user_id` immutable |
| Delete | DeleteAccountRequest | operation.Operation | **async** | FailedPrecondition если есть projects/SA/groups/custom roles |
| ListOperations | ListAccountOperationsRequest | ListAccountOperationsResponse | sync | per-account ops history |

## REST mapping (api-gateway)

| HTTP | Method |
|---|---|
| `GET /iam/v1/accounts/{id}` | Get |
| `GET /iam/v1/accounts` | List |
| `POST /iam/v1/accounts` | Create |
| `PATCH /iam/v1/accounts/{id}` | Update |
| `DELETE /iam/v1/accounts/{id}` | Delete |
| `GET /iam/v1/accounts/{id}/operations` | ListOperations |

## Notes

- E0 stub: `Operation.principal_*` = `('system','bootstrap','kacho-iam-bootstrap')`. E2 заменит реальным JWT principal.
- Account name **глобально** уникальна (UNIQUE без partial).
- FK на user RESTRICT — `owner_user_id` обязан существовать.

## See also

[[../packages/iam-domain]] [[../resources/iam-account]] [[iam-internal-iam-service]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
