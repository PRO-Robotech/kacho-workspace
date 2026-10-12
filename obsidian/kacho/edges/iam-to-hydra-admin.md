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
status: superseded
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - oauth
verified_against: "kacho e801c0f7 и kaname 8a84dcff6 (2026-10-03): административного клиента поставщика нет ни в одном стволе — путей `/admin/clients`, `/admin/trust`, `/admin/oauth2` в не-тестовом Go нет, кроме гейтов, судящих их отсутствие; файл предпосылки слушателя снят 37932ab90dd. Текст ниже первой врезки — прошлое, построчно не пересматривался"
---

> [!warning] Ребро СНЯТО — записка описывает прошлое (сверено 2026-10-03)
> Поставщик OAuth снят из продукта: служба доступа выдаёт токены сама, а
> административного клиента поставщика нет ни в стволе kacho (`e801c0f7`), ни в стволе
> kaname (`8a84dcff6`). Вехи снятия: съём OAuth-сервера со службы — kacho `f8aa4eb3078`
> (2026-09-10); служба переехала в отдельный продукт — kacho `0cc1cd54c38` (#2598);
> терминатор перехода и предпосылка его слушателя сняты с предметом — kacho
> `37932ab90dd` (#1276, 2026-09-30). Отсутствие поставщика на поднятом стенде сегодня
> судит `deploy/scripts/assert-identity-provider-absent.sh` в стволе kacho.
>
> Ниже — ребро таким, каким оно было: врезка сверки 2026-08-05 (дерево `96b2879a`, шесть
> файлов клиента у iam, пути жизненного цикла клиентов и доверительных грантов) верна как
> прошлое. Ход снятия и его остаток — [[KAC/identity-provider-retirement-2026-08]] и
> [[KAC/issue-1276]].

# iam → hydra-admin: OAuth2 client lifecycle

**Caller**: `kacho-iam` (token_hook + sa-key service + federation-exchange).
**Callee**: ORY Hydra (`hydra-admin:4445` cluster-internal listener).
**Protocol**: REST/JSON (Hydra Admin API v2).
**Sync/Async**: sync per-call. Some calls async из workers (FGAOutboxDrainer pattern для CAEP revocation).
**Status**: **Phase 2 (token_hook + refresh_hook) implemented**; **Phase 5 (SA OAuth client CRUD) planned**.


> [!note] Так шло снятие (история): линия `release/identity-3` снимала ребро полоса за полосой
> Ф4б/Ф4г: платформа перестаёт заводить у поставщика клиента-зеркало для собственных полос
> выдачи — бутстрап, ключ служебной учётки, персональный токен, контур докер-токена; перечень
> доверенных издателей становится нашей таблицей. Остаётся единственное задокументированное
> прямое обращение — административный обмен утверждения на токен
> (`security.md` §Production-mode, п.4).
>
> Полосы переводятся **поштучно**, непереведённая посадка не трогается, а окно сосуществования
> двух издателей выразимо запросом, а не оценкой. Числа, предикаты и открытый остаток —
> [[KAC/identity-provider-retirement-2026-08]].

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
- 2026-09-10 — kacho `f8aa4eb3078`: OAuth-сервер снят со службы доступа.
- 2026-09-30 — kacho `37932ab90dd` (#1276): терминатор перехода и файл предпосылки слушателя сняты с предметом.
- 2026-10-03 — workspace#905: записка переведена в историю (`status: superseded`), сверено kacho `e801c0f7`, kaname `8a84dcff6`.

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

Причина, по которой TLS давал сосед, а не сам провайдер, была записана отдельным
файлом предпосылки в `deploy/` и перемерялась одной командой; гейт посадки краснел на
смене версии провайдера. Файл предпосылки, перемерщик и половина гейта о переходе сняты
вместе с терминатором коммитом kacho `37932ab90dd` (#1276); вторую половину гейт
сохранил — отсутствие поставщика. Trail — [[KAC/SEC-HAT-provider-admin-hop-tls]].
