---
title: CAEPSubscriber
aliases:
  - CAEPSubscriber (iam)
  - caep_subscriber
  - iam CAEP subscriber
category: resource
domain: iam
id_prefix: cps
owner_table: kacho_iam.caep_subscribers
owner_db: kacho_iam
project_level: false
status: deprecated
related_rpc:
  - "[[rpc/iam-organization-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
verified_against: "ствол redesign/integration, сверено 2026-08-05"
---

> [!warning] Предмета в дереве продукта НЕТ — записка оставлена как история
> Все три таблицы конвейера — `caep_subscribers`, `caep_outbox`, `caep_event_delivery` — **дропнуты** миграцией `0007_drop_caep_pipeline.sql`. Идентификатора `CaepSubscriber` в дереве нет.
>
> Читать как след прежнего замысла, а не как описание сегодняшнего дня.
> Сверено по стволу `redesign/integration` 2026-08-05.

# CAEPSubscriber

**Domain**: iam — per-Account webhook registration для CAEP push (RFC 8417 SET — Security Event Token). Account-scoped, CASCADE при удалении Account.
**ID prefix**: `cps_` + 17-char crockford → `^cps_[0-9a-hjkmnp-tv-z]{17}$`.
**Owner table**: `kacho_iam.caep_subscribers` (migration 0013).
**Phase 1**: schema-only. CAEP push pipeline — Phase 8.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^cps_[0-9a-hjkmnp-tv-z]{17}$` | |
| `account_id` | TEXT | FK → accounts(id) CASCADE | NOT NULL |
| `endpoint_url` | TEXT | length 8..1024, `^https://` | webhook receiver URL |
| `signing_kid` | TEXT | length 1..128 | KID для SET signing verification на subscriber side |
| `expected_audience` | TEXT | length 1..512 | expected `aud` claim |
| `event_types` | TEXT[] | array | filter — какие event types слать (`session.revoked`, `credentials.changed`, ...) |
| `enabled` | BOOL | | |
| `failure_count` | INTEGER | CHECK `>=0` | счётчик ошибок (exponential backoff на subscriber-side) |
| `last_success_at` | TIMESTAMPTZ NULL | | |
| `last_failure_at` | TIMESTAMPTZ NULL | | |
| `last_failure_reason` | TEXT NULL | length <=2048 | |
| `created_at` | TIMESTAMPTZ | server-set | |
| `created_by_user_id` | TEXT | length <=64 | |

## Constraints / indexes

- `caep_subscribers_pkey` PRIMARY KEY (id)
- `caep_subscribers_account_fk` FK → `accounts(id)` ON DELETE CASCADE
- CHECK: id-regex, `endpoint_url ~ '^https://'`, length, `failure_count >= 0`

## Lifecycle (Phase 8)

- **Create**: admin регистрирует endpoint, указывает signing_kid + expected_audience.
- **Deliver**: drainer reads `caep_outbox` → POST SET to endpoint_url (signed JWT с CAEP event-payload) → expect 2xx → update `last_success_at` либо `last_failure_at` + `failure_count`.
- **Disable**: enabled=false → drainer skip'ает; `failure_count > N` → auto-disable (Phase 8 policy).
- **Delete**: cascade — удаление Account автоматически удалит subscribers.

## Gotchas

- `endpoint_url ~ '^https://'` — DB-enforced (NEVER http в production).
- CAEP-SET — JWS-signed JWT по RFC 8417; subscriber должен validate с issuer JWKS ([[iam-oidc-jwks-key]]).
- Phase 8 idempotency: SET содержит `jti` — subscriber обязан dedupe.
- `event_types` filter позволяет subscriber subscribe только на нужные events (e.g. только `session.revoked`).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-organization-service]] [[iam-account]] [[iam-session-revocation]] [[iam-oidc-jwks-key]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
