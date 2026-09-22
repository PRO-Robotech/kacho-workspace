---
title: user_access_keys
aliases:
  - AccessKey (iam)
  - user_access_keys
  - kaname-access-key
category: resource
domain: iam
id_prefix: "ak-"
owner_table: kaname.user_access_keys
owner_db: kaname
project_level: false
status: test
related_rpc:
  - "[[rpc/iam-access-key-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC/issue-1273]]"
tags:
  - resource
  - kacho-iam
  - iam
verified_against: "kaname release/iam-lines@4b674bf5 — миграция 20260917221000_access_keys_are_our_record.sql, приёмка access-keys-are-ours.md (APPROVED, круг 6)"
---

# `user_access_keys` — ключ доступа человека (WebAuthn), наш ресурс

**Предмет.** Открытый ключ аутентификатора, привязанный к человеку. Ключ — путь входа
целиком: срока у него нет by construction, снять за спиной владельца нельзя, поэтому число
ключей ограничивает **потолок** `iam.user.accessKey` (ручка `own-ceilings.access-keys-per-user`,
триггер списания в той же транзакции).

## Схема (что держит база, а не код)

| колонка / ограничение | смысл |
|---|---|
| `id` — `CHECK ~ '^ak-[crockford]{17}$'` | дефисная форма, префикс в каноне фундамента (corelib v1.9.0) |
| `user_id` → `users(id) ON DELETE CASCADE` | владелец; каскад внутри одной базы |
| `credential_id` — `UNIQUE`, 16…1023 байт | идентификатор аутентификатора: один ключ — одна строка во всей базе |
| `public_key` — непустой | COSE-ключ |
| `algorithm ∈ {-7, -8, -257}` | ES256 · EdDSA · RS256 — словарь закрыт базой |
| `sign_count` — 0…2³²−1 | односторонний счётчик (Р6): откат — признак клона |
| `user_handle` — NULL либо 1…64 байт | как выдал аутентификатор |
| `name` — RFC 1123 label, `description` ≤ 256 | как у всех ресурсов |

`access_key_challenges` — испытание: `purpose ∈ {registration, assertion}`, `challenge` ровно
32 байта, `expires_at > issued_at`, привязано к человеку; одноразовое, гасится только успехом;
уборка — пятый предмет реестра полосы.

## Что снято намеренно

- **аттестация не читается** (Р4): формат `none`; обещание «проверка аттестации ключа» снято с
  документации и деривации `kaname_device_compliance` (Ф7-32/39);
- **перенос ключей прежнего поставщика** — снят вместе с предметом (kaname#269).

## Gotchas

- гейт формы имени требует посева потолка **до** вставки: иначе триггер списания отвергает
  строку (`KQ002`) раньше проверки формы, и проба судит не то;
- отказ утверждения побайтово один на все четырнадцать полос — правя текст, правь пробу
  `refusal_bytes_test.go`, а не наоборот.

#resource #kacho-iam #iam
