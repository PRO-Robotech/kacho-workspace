---
title: authorization_codes
aliases:
  - AuthorizationCode (kaname)
  - authorization_code
category: resource
domain: iam
id_prefix: (code_digest)
owner_table: kaname.authorization_codes
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

# authorization_codes (kaname)

**Schema**: `kaname.authorization_codes` · **Owner**: kaname · **Visibility**: internal.

> [!warning] Состояние — `test`: предмета на стволе нет
> Таблица заведена полосой `kn-313` и в `main` не влита (сверено 2026-09-21).

## Назначение

Код авторизации собственной церемонии. До этой полосы собственной церемонии в схеме не было
ни одной строки — выдача шла через внешнего поставщика.

**Сам код не хранится**: хранится его свёртка (SHA-256, шестнадцатерично, 64 знака). Копия
таблицы не даёт ни одного годного кода. Та же форма, что у свёртки носителя сессии.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `code_digest` | text | **PK**, `^[0-9a-f]{64}$`; `SET STATISTICS 0` |
| `family_id` · `client_id` · `user_id` · `session_id` · `scope` | | контекст, составным FK на семейство |
| `redirect_uri` | text | только `https://`, без фрагмента, ≤512 |
| `code_challenge` | text | 43 знака base64url без выравнивания |
| `code_challenge_method` | text | **только** `S256` |
| `issued_at` · `expires_at` | timestamptz | `expires_at > issued_at` |
| `active` | boolean | условие гашения; читателем не вычисляется |
| `deactivated_at` · `deactivated_reason` | | `redeemed` либо `family-revoked` |

## Форма подчинена одному требованию: гашение ОДНОЙ инструкцией

Обмен выражается одним оператором с условием на прежнее состояние и возвратом затронутой
строки. Ноль затронутых строк — отказ, и он один на всех проигравших. Пары «прочитать,
затем записать» здесь нет: условие и запись исполняет сам движок под строчным замком
(запрет #10).

Почему требование именно такое: реализация, у которой чтение кода и его гашение —
**две** операции, на положительном пути неотличима от верной. Последовательная проба её
зелёная, и цена расхождения наступает только под конкуренцией. Потому форма закреплена
схемой и оператором, а не договорённостью писателя.

Разбор того, чем это отличается от прежнего пути выдачи, в записке не воспроизводится:
адрес такого разбора — дифф самого перехода, а не публичный пересказ
(`security-disclosure.md` §«признак восстановимости»).

## Снятие — отметка, а не удаление

Использованный код помечается неактивным и **живёт до истечения**. Обнаружение повторного
использования строится на различении «неактивен» и «не найден»: первое — повтор, и по нему
отзывается всё семейство; второе — неизвестный код. Удалённая строка неотличима от никогда
не существовавшей. Строки после истечения убирает уборка.

## Инварианты, которые держит схема

- `authorization_codes_family_fk` — **составной** FK по всем пяти столбцам контекста сразу.
- `authorization_codes_family_uk` UNIQUE (`family_id`) — одно семейство заводится одним кодом.
- `authorization_codes_active_pair_ck` — признак активности и отметка снятия суть одно
  состояние, записанное дважды; согласие держит база, а не писатель.
- `authorization_codes_challenge_method_ck` — `plain` не заводится: значение, которое не
  станет законным ни одним решением, не получает колонки, куда однажды ляжет.

## See also

[[resources/iam-token-family]] · [[resources/iam-refresh-token]] ·
[[resources/iam-human-session]] · [[edges/kaname-session-end-vs-code-issue]]

#resource #kacho-iam #iam #internal #migrations
