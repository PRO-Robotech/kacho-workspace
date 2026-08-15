---
title: "iam internal/handler/iamhooks"
aliases:
  - iam iamhooks
  - token hook
  - refresh hook
  - caep ingress
category: packages
path: services/iam/internal/handler/iamhooks
repo: kacho-iam
layer: handler
status: done
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - handler
  - oauth
verified_against: "координаты записки (переменные окружения, пути пакетов) сверены с деревом продукта 1653387b (2026-08-06); текст записки построчно не пересматривался"
---

# iam `internal/handler/iamhooks`

HTTP listener `0.0.0.0:9092` для **Hydra OAuth lifecycle hooks** + **CAEP ingress** (incoming events from upstream IdPs). НЕ gRPC — Hydra-spec REST callbacks.

**Phase 2 implemented (KAC-127 `da2d627e` kacho-iam)** + **Phase 8 ingress planned**.

## Endpoints

| HTTP | Description | Status |
|---|---|---|
| `POST /token_hook` | Hydra OAuth2 token-issuance hook — invoked при каждой ::token:: issuance из Hydra. | Phase 2 done |
| `POST /refresh_hook` | Hydra refresh-token-rotation hook — invoked при refresh-token grant. | Phase 2 done |
| `POST /caep/ingress` | Receives CAEP SET (RFC 8417) from upstream IdPs (Phase 8). | Phase 8 planned |
| `POST /dpop_replay` | (Internal) DPoP jti replay cache HTTP API (api-gateway co-reads). | Phase 2 done |

## token_hook (Phase 2)

Hydra POSTs JSON; kacho-iam adds claims:
```json
{
  "request": {
    "client_id": "kacho-ui",
    "granted_scopes": ["openid", "profile", "kacho.vpc.read"],
    "session": {
      "id_token": { "id_token_claims": { "sub": "usr_xxx" } }
    }
  },
  "session": {
    "kacho": {
      "account_id": "acc_yyy",
      "project_id": "prj_zzz",
      "principal_id": "usr_xxx",
      "groups": ["grp_aaa"],
      "mfa_fresh": true,
      "acr": "aal2",
      "dpop_cnf": { "jkt": "<jwk-thumbprint>" }
    }
  }
}
```

Hydra includes these claims в issued JWT. api-gateway middleware ([[api-gateway-middleware-authz]]) consumes `kacho.account_id` / `kacho.acr` для downstream authz.

## refresh_hook

Re-checks user/SA status:
- User soft-disabled → deny refresh.
- Session revoked (`session_revocations` row) → deny.
- Rotate detected → emit CAEP event (Phase 8).

## DPoP replay cache (Phase 2)

- Insert `jti` + `cnf.jkt` → если duplicate → reject (replay attack).

> [!note] Кэш повторов живёт НЕ в iam — координата поправлена по дереву (1653387b, 2026-08-06)
> Переменной окружения с прежним именем в дереве нет ни в одном читателе (Go, чарты,
> скрипты, Makefile). Энфорсмент повторов `jti` стоит **на крае**, а не в iam:
> `gateway/internal/middleware/dpop_replay_cache.go` — per-pod LRU с TTL на запись,
> ручки `KACHO_DPOP_REPLAY_CACHE_TTL_SECONDS` (умолчание **120 c**, вдвое к окну
> свежести `iat`) и `KACHO_DPOP_REPLAY_CACHE_SIZE` (умолчание 100000) в
> `gateway/internal/config/config.go`. Прежняя редакция называла и другое значение TTL,
> и другой дом кэша, и шардирование, которого у этой реализации нет.
>
> Таблица `dpop_replay_jti` в `services/iam/internal/migrations/0001_initial.sql`
> объявлена, но писателя в прод-коде iam у неё нет — то есть «переживает рестарт»
> сегодня не обеспечено ничем: кэш края переживает ровно жизнь пода.

## CAEP ingress (Phase 8)

Verify signed SET → process event:
- `session.revoked` from upstream → mark `session_revocations` row → propagate downstream subscribers.
- `iam.user.disabled` upstream → soft-disable user mirror.

## Auth

- Hydra → kacho-iam: shared secret — ключ конфигурации `authn.hook-shared-secret`,
  в развёртывании приезжает переменной `KACHO_IAM_HOOK_TOKEN` (Secret `kacho-iam-hook-token`,
  `deploy/helm/umbrella/charts/kacho-iam/templates/deployment.yaml`); заголовок
  `X-Kacho-Hook-Token` (либо `Authorization: Bearer`), сверка
  `subtle.ConstantTimeCompare`, пустой secret → **fail-closed 500**, не bypass
  (`services/iam/internal/handler/iamhooks/hook_auth.go`).
- CAEP ingress: SET signature verified против issuer JWKS.

## Imports

- `net/http`, `encoding/json`, `crypto/subtle` — stdlib
- ровно три внутренних пакета продукта (перепись non-test файлов пакета, 1653387b):
  `services/iam/internal/domain`, `services/iam/internal/errors`,
  `services/iam/internal/service`

> [!note] Двух прежних строк «Imports» в дереве нет — координаты сняты (1653387b, 2026-08-06)
> Первая называла подкаталог-порт под слоем сервисов: подкаталогов там нет вовсе,
> `services/iam/internal/service` — **плоский** пакет. Сам порт при этом жив, но
> объявлен **самим** пакетом хуков (`UserRevocationLookup` в
> `services/iam/internal/handler/iamhooks/ports.go`), то есть импортом никогда и не был;
> use-case отзыва сессий живёт отдельно —
> `services/iam/internal/apps/kacho/api/session_revocations`.
> Вторая называла подкаталог клиента OpenFGA как импорт «Phase 3». Клиент существует
> (`services/iam/internal/clients`, файлы `openfga_*.go`), но подкаталога с таким именем
> нет, и пакет хуков его **не импортирует** — заявленной работы Phase 3 в дереве нет.

## Imported by

- `cmd/kacho-iam/main.go` — wired as 5th parallel task (HTTP server on 9092)

## See also

[[iam-domain]] [[iam-jobs]] [[../edges/iam-to-hydra-admin]] [[../edges/iam-caep-to-subscriber]] [[../rpc/iam-caep-subscriber-service]] [[../KAC/KAC-127]]

#packages #kacho-iam #handler #oauth
