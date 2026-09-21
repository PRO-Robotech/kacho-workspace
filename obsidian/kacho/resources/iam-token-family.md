---
title: token_families
aliases:
  - TokenFamily (kaname)
  - token_family
category: resource
domain: iam
id_prefix: tfm-
owner_table: kaname.token_families
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

# token_families (kaname)

**Schema**: `kaname.token_families` · **Owner**: kaname · **Visibility**: internal —
номер (`tfm-…`) наружу не выходит, семейство адресуется только изнутри церемонии.

> [!warning] Состояние — `test`: предмета на стволе нет
> Таблица заведена полосой `kn-313` и в `main` не влита (сверено 2026-09-21). Всё ниже
> описывает полосу, а не поднятую посадку.

## Назначение

Семейство выданного по **одному** коду авторизации. Несёт контекст церемонии — клиента,
человека, сессию, область — и отметку отзыва. Отзыв семейства снимает всё выданное по нему.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `id` | text | **PK**, форма `tfm-` + 17 знаков алфавита без похожих букв |
| `client_id` | text | FK `interactive_clients(client_id)` CASCADE |
| `user_id` | text | FK `users(id)` CASCADE |
| `session_id` | text | FK `human_sessions(id)` CASCADE — сессия **обязательна** |
| `scope` | text[] | непуста, без `NULL` и без пустых имён |
| `created_at` | timestamptz | `now()` |
| `revoked_at` | timestamptz | NULL, пока семейство живо |
| `revoked_reason` | text | закрытый словарь, см. ниже |

## Инварианты, которые держит схема

- `token_families_context_uk` UNIQUE (`id`, `client_id`, `user_id`, `session_id`, `scope`) —
  **составной ключ, на который ссылаются код и обновляющий токен**. Он и делает согласие
  контекста свойством схемы: контекст на строке семейства и на строке выданного молча
  разойтись не может, расхождение отвергает база.
- `token_families_scope_ck` — пустая область не «все права», а отсутствие решения, и хранить
  её как область нельзя.
- `token_families_revoked_pair_ck` — отметка и причина появляются и исчезают вместе.
- `token_families_revoked_reason_ck` — словарь причин **закрыт**, корзины «прочее» нет.

## Словарь причин отзыва

`code-replay` · `refresh-replay` · `logout` · `session-ended` · `consent-withdrawn` ·
`client-removed`.

Писателей на `229a0693` имеют три из шести — см. [[KAC/issue-339-kaname]].

## Чего схема НЕ держит

Признак отзыва (`revoked_at`) **не входит** в уникальный ключ, и движок не разводит замок
отзыва с замком вставки выданного. Состояние «живая запись в отозванном семействе» потому
представимо, и сегодня его держит порядок операторов в писателе, а не схема:
[[edges/kaname-family-revoke-vs-token-issue]], класс — [[lessons/invariant-held-by-the-package-not-the-schema]].

## See also

[[resources/iam-authorization-code]] · [[resources/iam-refresh-token]] ·
[[resources/iam-human-session]] · [[KAC/issue-339-kaname]]

#resource #kacho-iam #iam #internal #migrations
