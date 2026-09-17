---
title: user_login_methods
aliases:
  - LoginMethod (iam)
  - user_login_methods
  - iam-user-login-methods
category: resource
domain: iam
id_prefix: ""
owner_table: kaname.user_login_methods
owner_db: kaname
project_level: false
status: done
related_rpc:
  - "[[rpc/iam-login-lane]]"
  - "[[rpc/iam-user-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC/issue-1281-kaname]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
  - migrations
verified_against: "ветка issue-1281-second-factor (kaname) на 1d1bd21a: миграция 20260917160000 и адаптер `PRO-Robotech/kaname:internal/repo/kaname/pg/login_method_repo.go` прочитаны, пробы того же каталога прогнаны на настоящей базе"
---

# user_login_methods (iam)

**Schema**: `kaname.user_login_methods` (Ф2 — `PRO-Robotech/kaname:internal/migrations/20260915111233_login_methods_live_in_their_own_rows.sql`;
Ф12 — `PRO-Robotech/kaname:internal/migrations/20260917160000_second_factor_rows_carry_state_and_step.sql`)
**Owner**: kaname · **Visibility**: internal (материал способа входа, не tenant-facing)

## Назначение

Способы входа человека — по строке на пару «человек × вид». Виды закрыты словарём базы и
совпадают с `internal/assurance`: `password` (Ф2), `totp` и `lookup_secret` (Ф12, приёмка
`PRO-Robotech/kaname:docs/engineering/acceptance/second-factor-totp-and-recovery-codes.md`).
Материал (`verifier`) не читается никем, кроме проверяющего: статический и схемный гейты
сдерживания перечисляют разрешённые файлы и ограничения поимённо.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `user_id` | text | FK `users(id)` ON DELETE CASCADE; с `kind` — PK |
| `kind` | text | CHECK `password` · `totp` · `lookup_secret` |
| `verifier` | text | материал: хеш пароля; обёрнутый секрет TOTP (base64 AES-GCM под кольцом `authn.second-factor-encryption-key-hex`); набор запасных кодов `$argon2id$…$<соль>$,e1,…,eN,` |
| `state` | text | `pending` · `active`; CHECK `pending` только у `totp` (Р1) |
| `last_accepted_step` | bigint | последний принятый шаг кода по времени (Р5) — свойство строки, не сессии |
| `created_at` | timestamptz | у `pending` — момент заведения; срок = окно `authn.self-service-freshness` |

## Контракт

- **Заведение** — `INSERT … ON CONFLICT DO UPDATE WHERE state <> 'active'`: новый `enroll`
  заменяет `pending`, при `active` — ноль строк (409). **Подтверждение** — CAS по `created_at`
  строки `pending`: из двух одновременных активирует ровно одно.
- **Принятый шаг** — `UPDATE … WHERE state='active' AND (last_accepted_step IS NULL OR < $3)`:
  повтор и младшая ступень не проходят; арбитр гонки двух одинаковых кодов — эта запись.
- **Набор запасных кодов** — сравнение под `SELECT … FOR UPDATE`, потребление —
  `replace(verifier, ','||$3||',', ',')` по элементу, вычисленному до замка; каждый код
  проходит однажды.
- **Снятие** — CTE: `totp` в состоянии `active` и `lookup_secret` одной операцией; `pending`
  не трогается ни снятием, ни сбросом распорядителем.
- Уборка — предмет реестра `retention` (`second_factor_enrollments`, порог = окно свежести):
  `pending` старше окна `confirm` уже не примет.

## See also

[[rpc/iam-login-lane]] · [[rpc/iam-user-service]] · [[KAC/issue-1281-kaname]]

#resource #kacho-iam #iam #internal #migrations
