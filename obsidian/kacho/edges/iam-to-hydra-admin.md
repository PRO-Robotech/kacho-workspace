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
status: active
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - oauth
---

> [!warning] Ребро ЖИВОЕ — статус `planned` и разбивка «Phase 2 / Phase 5» устарели (сверено 2026-08-05)
> В дереве `96b2879a` у iam **шесть** файлов клиента Hydra
> (`services/iam/internal/clients/hydra_{admin_client,interactive_clients,login_sessions,oauth_clients,token_exchange,trust_grants}.go`).
> Фактически используемые административные пути — `/admin/clients`, `/admin/clients/{client_id}`,
> `/admin/oauth2/auth/sessions/login`, `/admin/trust/grants`,
> `/admin/trust/grants/jwt-bearer/issuers` (предикат: перечисление литералов путей по этим
> шести файлам). То есть **создание и жизненный цикл OAuth-клиентов — landed**, а не «Phase 5
> planned»; появилось то, чего в записке не было вовсе, — доверительные гранты
> (`jwt-bearer` issuer'ы) для обмена утверждениями.
>
> Что осталось верным и несущим: **iam — единственный фасад к Hydra**. Клиенты, сервисы и
> e2e идут в iam (зеркало JWKS, выпуск токенов, docker-токен), а не в Hydra напрямую;
> `iam → Hydra` внутри фасада законно. Единственное допустимо-прямое — финальный обмен
> `client_assertion → JWT` (`security.md` §Production-mode п.4).
>
> Раздел «Phase 8 CAEP push … → CAEP subscribers» опирается на исходящую доставку событий,
> которой нет ([[iam-caep-to-subscriber]]).

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

## Транспорт перехода (2026-07-30, SEC-HAT)

Переход идёт **по TLS через терминатор-соседа в поде провайдера**, а не напрямую
к его административному листенеру. Потребители адресуют отдельный ClusterIP
Service терминатора и проверяют его сертификат против внутреннего центра; якорь
(`ca.crt` того же секрета) не менялся.

Административный листенер провайдера слушает **только петлю** пода, его
собственный Service снят, а его имена убраны из SAN сертификата — забытый
потребитель обязан падать на разрешении имени, громко и сразу, а не получать
однажды действительный сертификат по адресу, который ничего не терминирует.

Готовность пода читается **через терминатор до эндпоинта здоровья провайдера**,
поэтому она краснеет и когда мёртв терминатор, и когда не отвечает провайдер.

Причина, по которой TLS даёт сосед, а не сам провайдер, записана координатой в
`deploy/PROVIDER-LISTENER-PREMISE.md` и перемеряется одной командой; гейт посадки
краснеет на смене версии провайдера и называет её. Trail —
[[sec-hat-provider-admin-hop-terminator]].
