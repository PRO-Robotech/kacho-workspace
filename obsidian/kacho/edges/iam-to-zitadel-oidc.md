---
title: "iam → zitadel: OIDC identity"
aliases:
  - iam to zitadel
  - zitadel oidc
category: edge
caller_repo: kacho-iam
callee_repo: zitadel
sync_async: sync
protocol: HTTPS+OIDC
status: planned
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-107]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - planned
---

# iam → zitadel: OIDC identity

**Caller**: `kacho-iam` (E2: `InternalUserService.UpsertFromIdentity` вызывается из api-gateway OIDC-callback handler)
**Callee**: `zitadel` (external IdP — отдельный deployment)
**Protocol**: HTTPS + OIDC (Authorization Code + PKCE, JWT с JWKS rotation)
**Sync/Async**: **sync** на login-path (auth-interceptor блокирует до резолва Principal)
**Status**: **planned** — появится в E2 ([[KAC-107]]).

## When invoked

- **E2 (login-flow)**: UI делает redirect в Zitadel → callback в api-gateway → `UpsertFromIdentity(external_id=sub, email, display_name)` в kacho-iam.
- **E2 (interceptor)**: каждый запрос с `Authorization: Bearer <JWT>` — api-gateway валидирует JWT через Zitadel JWKS, извлекает `sub`, резолвит User через `InternalIAMService.LookupSubject(external_id=sub)`.

## Error handling (E2)

| Result | gRPC code / HTTP | Note |
|---|---|---|
| JWT валидный, user найден | (continue, Principal в ctx) | |
| JWT валидный, user не найден | call `UpsertFromIdentity` → создать row → continue | self-service signup E4 |
| JWT истёк / invalid signature | `Unauthenticated` / HTTP 401 | refresh-flow на UI |
| Zitadel JWKS недоступен | `Unavailable` / HTTP 503 | retry; fail-closed |

## E0 status (текущий)

- Zitadel **не деплоится**. `InternalUserService.UpsertFromIdentity` вызывается через `grpcurl` (admin-bootstrap).
- `principal_*` в `operations` = `('system','bootstrap','kacho-iam-bootstrap')`.

## See also

[[../rpc/iam-internal-user-service]] [[../resources/iam-user]] [[../KAC/KAC-104]] [[../KAC/KAC-107|KAC-107 (E2)]]

#edge #kacho-iam #cross-service #planned
