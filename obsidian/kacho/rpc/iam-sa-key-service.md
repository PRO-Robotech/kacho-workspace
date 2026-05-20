---
title: SAKeyService
aliases:
  - SAKey (iam)
  - SA OAuth Client CRUD
proto_file: kacho/cloud/iam/v1/sa_key_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-service-account-oauth-client]]"
methods_count: 6
async_methods: 4
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - federation
  - oauth
---

# SAKeyService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/sa_key_service.proto` (Phase 5).
**Backend**: `kacho-iam:9090`. Public — workload owner управляет своими SA OAuth clients.
**Status**: **Phase 5 planned**. Class A static credentials через Hydra OAuth2 client. `ServiceAccountOAuthClient` 1:1 c ServiceAccount.

## Methods (Phase 5)

| Method | Sync/Async | Description |
|---|---|---|
| CreateOAuthClient | async | INSERT в `service_account_oauth_clients` + Hydra Admin `POST /clients` ([[../edges/iam-to-hydra-admin]]). Returns `client_id` + `client_secret` (показывается ОДИН раз). |
| GetOAuthClient | sync | by `service_account_id`. Secret never returned после Create. |
| RotateSecret | async | новый client_secret + revoke старого через Hydra. Returns new secret one-time. |
| UpdateOAuthClient | async | mutable: `redirect_uris`, `grant_types`, `audience`. Immutable: `client_id`, `service_account_id`. |
| RevokeOAuthClient | async | Hydra `DELETE /clients/{id}` + cascade revoke active tokens (Phase 8 CAEP push). |
| ListOAuthClients | sync | per-Project filter |

## REST mapping (public mux)

| HTTP | Method |
|---|---|
| `POST /iam/v1/serviceAccounts/{sa_id}/oauthClients` | CreateOAuthClient |
| `GET /iam/v1/serviceAccounts/{sa_id}/oauthClients/current` | GetOAuthClient |
| `POST /iam/v1/serviceAccounts/{sa_id}/oauthClients:rotate` | RotateSecret |
| `PATCH /iam/v1/serviceAccounts/{sa_id}/oauthClients/{client_id}` | UpdateOAuthClient |
| `DELETE /iam/v1/serviceAccounts/{sa_id}/oauthClients/{client_id}` | RevokeOAuthClient |
| `GET /iam/v1/projects/{project_id}/oauthClients` | ListOAuthClients |

## Token flow (issued via Hydra, not this service)

После Create — workload использует `POST https://api.kacho.cloud/oauth2/token` (Hydra):

```
grant_type=client_credentials
client_id=<sa_client_id>
client_secret=<sa_client_secret>
scope=<scopes>
dpop=<jwk-thumbprint-proof>
```

Hydra → token_hook ([[../packages/iam-handler-iamhooks]]) → final access_token (DPoP-bound, JWT).

## Notes

- 1:1 enforced DB-уровне (`sva_id` UNIQUE).
- Client_secret hashed (Hydra side); kacho-iam хранит метаданные only.
- Rotation: новый secret valid immediately; старый remains valid 1h grace (configurable) → soft-rotation для CI/CD.
- Revoke → CAEP push `iam.token.revoked` → ≤10s downstream invalidation.

## See also

[[iam-federation-exchange-service]] [[../resources/iam-service-account-oauth-client]] [[../resources/iam-service-account]] [[../edges/iam-to-hydra-admin]] [[../packages/iam-service-federation]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #federation #oauth
