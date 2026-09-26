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
verified_against: "DDL прочитан в `internal/migrations/20260920175117_authorization_code_is_our_record.sql` и словарь причин — в `internal/migrations/20260923225650_consent_leaves_the_schema.sql`, оба на ветке эпика 357 (fc9f5aff) продукта PRO-Robotech/kaname (2026-09-26); колонки и ограничения сверены построчно; на origin/main (cbbac984) таблицы нет, поведение на стенде не наблюдалось"
---

# token_families (kaname)

**Schema**: `kaname.token_families` · **Owner**: kaname · **Visibility**: internal —
номер (`tfm-…`) наружу не выходит, семейство адресуется только изнутри церемонии.

> [!warning] Состояние — `test`: предмета на стволе нет
> Таблица заведена полосой `kn-313`, живёт в ветке эпика `357` и в `main` не влита
> (сверено 2026-09-26). Всё ниже описывает ветку эпика, а не поднятую посадку.

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
| `live` | boolean | `true`, пока семейство живо; колонка существует ради ключа живости |

## Инварианты, которые держит схема

- `token_families_context_uk` UNIQUE (`id`, `client_id`, `user_id`, `session_id`, `scope`) —
  **составной ключ контекста, на который ссылаются код и обновляющий токен**. Он и делает
  согласие контекста свойством схемы: контекст на строке семейства и на строке выданного
  молча разойтись не может, расхождение отвергает база. Каскада на обновлении у этой ссылки
  нет: контекст выданного неизменяем.
- `token_families_live_uk` UNIQUE (`id`, `live`) — **ключ живости**, на который выданное
  ссылается отдельно, с каскадом на обновлении. Вставку в отозванное семейство отвергает
  база, отзыв доезжает до выданного каскадом — [[edges/kaname-family-revoke-vs-token-issue]].
- `token_families_live_pair_ck` — живость и отметка отзыва суть одно состояние, записанное
  дважды; согласие держит база.
- `token_families_scope_ck` — пустая область не «все права», а отсутствие решения, и хранить
  её как область нельзя.
- `token_families_revoked_pair_ck` — отметка и причина появляются и исчезают вместе.
- `token_families_revoked_reason_ck` — словарь причин **закрыт**, корзины «прочее» нет.

## Словарь причин отзыва

`code-replay` · `refresh-replay` · `logout` · `session-ended` · `client-removed`.

Значение `consent-withdrawn` снято миграцией `20260923225650_consent_leaves_the_schema.sql`
вместе с таблицей согласий ([[KAC/issue-404-kaname]]). Какие причины имеют писателя —
предмет [[KAC/issue-339-kaname]]; перепись там сделана на ревизии `229a0693`, когда значений
было шесть.

## История

- 2026-09-21 — заведена по ревизии полосы `229a0693`.
- 2026-09-26 (#778) — пересверена на ветке эпика `357`: добавлены колонка `live`, ключ
  живости и пара живости, словарь приведён к пяти значениям. Снят раздел о том, чего схема
  на `229a0693` не держала: живость с тех пор держит ключ, а разбор прежнего состояния
  адресуется диффом фикса, а не записке (`security-disclosure.md` §«Публичные артефакты»).

## See also

[[resources/iam-authorization-code]] · [[resources/iam-refresh-token]] ·
[[resources/iam-human-session]] · [[KAC/issue-339-kaname]]

#resource #kacho-iam #iam #internal #migrations
