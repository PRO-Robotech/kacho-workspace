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
verified_against: "kaname release/iam-lines@4b674bf5 — миграция 20260917221000_access_keys_are_our_record.sql, приёмка access-keys-are-ours.md (APPROVED, круг 6); 2026-10-03 — ветка эпика 296@d2f6f182: запись ревью Ф7 на отпечаток 5ea26ad0 — APPROVED (sha256sum документа → docs/specs/reviews/access-keys-are-ours/), кейс tests/newman/cases/kaname-access-keys.py есть (git ls-tree); схема построчно не пересматривалась"
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
уборка — пятый предмет реестра полосы; порог — срок испытания (в ветке эпика `296`, см. History).

## Что снято намеренно

- **аттестация не читается** (Р4): формат `none`; обещание «проверка аттестации ключа» снято с
  документации и деривации `kaname_device_compliance` (Ф7-32/39);
- **перенос ключей прежнего поставщика** — снят вместе с предметом (kaname#269).
- **регистрация личности ключом без пароля** — её не будет: обещание снято с Ф1, Ф7 и Ф13, а не
  исполнено ([[KAC/issue-2703]]).

## Gotchas

- гейт формы имени требует посева потолка **до** вставки: иначе триггер списания отвергает
  строку (`KQ002`) раньше проверки формы, и проба судит не то;
- отказ утверждения побайтово один на все четырнадцать полос — правя текст, правь пробу
  `refusal_bytes_test.go`, а не наоборот.

## History

- 2026-10-03 — волна-1 эпика `296` ([[KAC/issue-535-kaname]], ветка эпика @`d2f6f182`, в `main` службы не
  влито): приёмка Ф7 сведена из двух одобренных ветвей в ред. 15 — запись ревью `APPROVED` на отпечаток
  `5ea26ad0` ([[KAC/issue-269-kaname]]; закрыты и [[KAC/issue-345-kaname]], [[KAC/issue-346-kaname]],
  [[KAC/issue-347-kaname]]); сквозной набор newman шести глаголов ([[KAC/issue-268-kaname]]); снято
  обещание регистрации ключом ([[KAC/issue-2703]]).
- 2026-10-04 — волна-2 эпика `296` ([[KAC/issue-536-kaname]], `77dae639`, в `main` службы не влито): уборка
  `access_key_challenges` снимает испытание не раньше его срока (`ChallengeTTL`), а не первым проходом —
  [[KAC/issue-590-kaname]]; ошибка чтения ключей на отзыве — внутренняя ошибка ([[KAC/issue-586-kaname]]).

#resource #kacho-iam #iam
