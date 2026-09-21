---
title: refresh_tokens
aliases:
  - RefreshToken (kaname)
  - refresh_token
category: resource
domain: iam
id_prefix: (token_digest)
owner_table: kaname.refresh_tokens
owner_db: kaname
project_level: false
status: test
related_rpc: []
related_packages:
  - "[[packages/kaname-repo-pg]]"
  - "[[packages/kaname-migrations]]"
related_tickets:
  - "[[KAC/issue-339-kaname]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
  - migrations
verified_against: "DDL прочитан в `internal/migrations/20260920175117_authorization_code_is_our_record.sql` на ревизии 229a0693 продукта PRO-Robotech/kaname (2026-09-21); на origin/main таблицы нет — полоса не влита, поведение на стенде не наблюдалось"
---

# refresh_tokens (kaname)

**Schema**: `kaname.refresh_tokens` · **Owner**: kaname · **Visibility**: internal.

> [!warning] Состояние — `test`: предмета на стволе нет
> Таблица заведена полосой `kn-313` и в `main` не влита (сверено 2026-09-21).

## Назначение

Обновляющий токен собственной церемонии. Хранится **свёрткой** (SHA-256, 64 знака), как и
код авторизации.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `token_digest` | text | **PK**, `^[0-9a-f]{64}$` |
| `family_id` · `client_id` · `user_id` · `session_id` · `scope` | | контекст, составным FK на семейство |
| `generation` | integer | ≥0; UNIQUE (`family_id`, `generation`) |
| `issued_at` · `expires_at` | timestamptz | `expires_at > issued_at` |
| `active` | boolean | условие одноинструкционной ротации |
| `deactivated_at` · `deactivated_reason` | | `rotated` либо `family-revoked` |
| `successor_digest` | text | есть **ровно** у ротации |

## Ротация — тот же механизм, что обмен кода

Один оператор с условием на прежнее состояние и возвратом строки. Отротированный токен
помечается неактивным и живёт до истечения: повтор обязан отличаться от неизвестного.

## Инварианты, которые держит схема

- `refresh_tokens_generation_uk` UNIQUE (`family_id`, `generation`) — две строки одного
  номера означали бы разветвление семейства, то есть двойную выдачу на ротации.
- `refresh_tokens_successor_pair_ck` — преемник есть ровно тогда, когда причина снятия
  `rotated`: снятый отзывом токен преемника не имеет, а ротация без преемника означала бы
  потерянное поколение.
- `refresh_tokens_active_pair_ck` · `refresh_tokens_deactivated_pair_ck` — одно состояние,
  записанное дважды, сводит база.

## Чего схема НЕ держит

Отзыв семейства и выдачу нового поколения движок сегодня не разводит — см.
[[edges/kaname-family-revoke-vs-token-issue]].

## See also

[[resources/iam-token-family]] · [[resources/iam-authorization-code]] ·
[[resources/iam-human-session]]

#resource #kacho-iam #iam #internal #migrations
