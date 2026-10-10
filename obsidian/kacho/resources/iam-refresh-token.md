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
verified_against: "DDL прочитан в `internal/migrations/20260920175117_authorization_code_is_our_record.sql` на ветке эпика 357 (fc9f5aff) продукта PRO-Robotech/kaname (2026-09-26); колонки и ограничения сверены построчно; на origin/main (cbbac984) таблицы нет, поведение на стенде не наблюдалось"
---

# refresh_tokens (kaname)

**Schema**: `kaname.refresh_tokens` · **Owner**: kaname · **Visibility**: internal.

> [!warning] Состояние — `test`: предмета на стволе нет
> Таблица заведена полосой `kn-313`, живёт в ветке эпика `357` и в `main` не влита
> (сверено 2026-09-26).

## Назначение

Обновляющий токен собственной церемонии. Хранится **свёрткой** (SHA-256, 64 знака), как и
код авторизации.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `token_digest` | text | **PK**, `^[0-9a-f]{64}$` |
| `family_id` · `client_id` · `user_id` · `session_id` · `scope` | | контекст, составным FK `refresh_tokens_family_context_fk` на семейство |
| `generation` | integer | ≥0; UNIQUE (`family_id`, `generation`) |
| `issued_at` · `expires_at` | timestamptz | `expires_at > issued_at` |
| `family_live` | boolean | живость семейства, снесённая сюда каскадом; писателем не выставляется |
| `deactivated_at` · `deactivated_reason` | | только `rotated` |
| `successor_digest` | text | есть **ровно** у ротации |
| `active` | boolean | **вычисляемая**: нет отметки снятия и семейство живо; условие одноинструкционной ротации, писателем не записывается |

## Ротация — тот же механизм, что обмен кода

Один оператор с условием на прежнее состояние и возвратом строки. Отротированный токен
помечается неактивным и живёт до истечения: повтор обязан отличаться от неизвестного.

## Инварианты, которые держит схема

- `refresh_tokens_family_live_fk` (`family_id`, `family_live`) → ключ живости семейства, с
  каскадом на обновлении: нового поколения в отозванном семействе база не заводит, а отзыв
  гасит живые поколения, не трогая их отметок —
  [[edges/kaname-family-revoke-vs-token-issue]].
- `refresh_tokens_generation_uk` UNIQUE (`family_id`, `generation`) — две строки одного
  номера означали бы разветвление семейства, то есть двойную выдачу на ротации.
- `refresh_tokens_successor_pair_ck` — преемник есть ровно тогда, когда причина снятия
  `rotated`: ротация без преемника означала бы потерянное поколение.
- `refresh_tokens_deactivated_pair_ck` — отметка и причина снятия появляются вместе.

## История

- 2026-09-21 — заведена по ревизии полосы `229a0693`.
- 2026-09-26 (#778) — пересверена на ветке эпика `357`: живость семейства приходит ключом,
  `active` стал вычисляемым, причина `family-revoked` и `refresh_tokens_active_pair_ck`
  сняты, FK контекста назван по дереву. Снят раздел о том, чего схема на `229a0693` не
  держала: адрес разбора прежнего состояния — дифф фикса, а не записка.

## See also

[[resources/iam-token-family]] · [[resources/iam-authorization-code]] ·
[[resources/iam-human-session]]

#resource #kacho-iam #iam #internal #migrations
