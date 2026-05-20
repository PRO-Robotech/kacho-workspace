---
title: "iam → hydra-admin: OAuth2 client lifecycle"
aliases:
  - iam to hydra
  - hydra admin
category: edge
caller_repo: kacho-iam
callee_repo: ory-hydra
sync_async: sync
protocol: REST/JSON (Hydra Admin API v2)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - oauth
---

# iam → hydra-admin: OAuth2 client lifecycle

**Caller**: `kacho-iam` (token_hook + sa-key service + federation-exchange).
**Callee**: ORY Hydra (`hydra-admin:4445` cluster-internal listener).
**Protocol**: REST/JSON (Hydra Admin API v2).
**Sync/Async**: sync per-call. Some calls async из workers (FGAOutboxDrainer pattern для CAEP revocation).
**Status**: **Phase 2 (token_hook + refresh_hook) implemented**; **Phase 5 (SA OAuth client CRUD) planned**.

## Calls (Phase 2 + Phase 5)

### Phase 2 (implemented)

- `POST /admin/oauth2/auth/requests/login/accept` — после Kratos session verify → tell Hydra "user logged in".
- `POST /admin/oauth2/auth/requests/consent/accept` — token issuance hook + claims (DPoP cnf binding, MFA freshness, project_id).
- `POST /admin/oauth2/auth/requests/logout/accept` — Back-Channel Logout propagation.
- `DELETE /admin/oauth2/auth/sessions/login?subject={user_id}` — session-revoke (CAEP push trigger).

### Phase 5 (planned — SA Class A OAuth clients)

- `POST /admin/clients` — INSERT `ServiceAccountOAuthClient` ([[../resources/iam-service-account-oauth-client]]). 1:1 c SA.
- `GET /admin/clients/{id}` — read metadata (НЕ secret).
- `PUT /admin/clients/{id}` — rotate secret / update redirect_uris.
- `DELETE /admin/clients/{id}` — revoke.

## Authentication kacho-iam → Hydra

- mTLS optional (Phase 11) — internal cluster network.
- Hydra Admin port `4445` НЕ exposed на api.kacho.cloud (cluster-internal only) — analog kacho `Internal*` listeners.

## Error handling

| Hydra response | kacho action |
|---|---|
| 200/201/204 | success |
| 404 (client not found) | INSERT (idempotent recover) |
| 409 (duplicate) | upsert / read existing |
| 5xx | retry exp-backoff; circuit-break после 3 fails (FederationExchange fail-closed) |
| timeout | `Unavailable` propagate caller |

## Notes

- Hydra issues access_token; kacho-iam **only** ходит через Admin API. Public OAuth2 endpoints (`/oauth2/token`, `/oauth2/authorize`) на api.kacho.cloud отдельный listener (kacho-deploy Phase 2 Helm: `api.kacho.cloud/oauth2/*` → Hydra public port `4444`).
- token_hook ([[../packages/iam-handler-iamhooks]]) — invoked sync by Hydra при каждом token issuance. Слой `iam-iamhooks:9092` HTTP listener.
- Phase 8 CAEP push: `session.revoked` → outbox row → drainer → CAEP subscribers ([[iam-caep-to-subscriber]]).

## History

- 2026-05-19 — Phase 2 (KAC-127): token_hook + refresh_hook + BCL propagation implemented (commit `da2d627e`).
- Phase 5 (planned) — SA OAuth client CRUD.

## See also

[[iam-to-kratos-admin]] [[iam-caep-to-subscriber]] [[../packages/iam-handler-iamhooks]] [[../packages/iam-service-federation]] [[../resources/iam-service-account-oauth-client]] [[../rpc/iam-sa-key-service]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #oauth
