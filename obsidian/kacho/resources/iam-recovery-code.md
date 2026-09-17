---
title: recovery_codes
aliases:
  - RecoveryCode (iam)
  - recovery_code
category: resource
domain: iam
id_prefix: rcv-
owner_table: kaname.recovery_codes
owner_db: kaname
project_level: false
status: done
related_rpc: []
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC/issue-1271]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
  - migrations
verified_against: "ветка issue-1271-recovery от release/iam-lines@af0ca8f3 (kaname): миграция и адаптер `PRO-Robotech/kaname:internal/repo/kaname/pg/recovery_code_repo.go` прочитаны, пробы того же каталога прогнаны на настоящей базе"
---

# recovery_codes (iam)

**Schema**: `kaname.recovery_codes` (миграция `PRO-Robotech/kaname:internal/migrations/20260917015400_recovery_code_is_our_record.sql`)
**Owner**: kaname · **Visibility**: internal (запись кода, не tenant-facing)

## Назначение

Код восстановления доступа — **предъявитель** (Ф5 Р1, приёмка
`PRO-Robotech/kaname:docs/engineering/acceptance/recovery-of-access.md`): обладание им даёт
право задать новый пароль. Заводится запросом восстановления для подтверждённого адреса,
живёт срок настройки (`authn.login.recovery-code-ttl`, перенос Ф1 §4.1 — 5 минут),
применяется однажды.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `id` | text | **PK** — идентификатор ПОТОКА (`rcv-…`); он же ключ идемпотентности журнала [[resources/iam-recovery-completions]] |
| `user_id` | text | FK `users(id)` ON DELETE CASCADE |
| `code_digest` | text | SHA-256 значения, шестнадцатерично; UNIQUE; статистика планировщика выключена (`SET STATISTICS 0`) |
| `issued_at` | timestamptz | момент чеканки (часы полосы) |
| `expires_at` | timestamptz | абсолютный срок, один столбец; CHECK `> issued_at` |
| `consumed_at` | timestamptz | момент применения; NULL — не применён; CHECK `>= issued_at` |
| `created_at` | timestamptz | DEFAULT now() |

## Контракт

- Значение кода **не хранится** — только свёртка; прочитанное из строки предъявлением не
  является (Ф5-07). Форма кода — 10 знаков алфавита Крокфорда (без I, L, O, U), для
  человека две группы через дефис; ввод нормализуется (регистр, разделители, I/L → 1, O → 0).
- **Применение — один оператор базы** (ban #10, Ф5-05): `UPDATE … SET consumed_at WHERE
  user_id AND code_digest AND consumed_at IS NULL AND expires_at > $now RETURNING …`; под
  конкуренцией проходит ровно одно предъявление. Неверный, чужой, истёкший и применённый код
  различаются только тем, что оператор их не находит, — отказ один.
- Новый запрос **вытесняет** неприменённые коды личности (`DELETE … WHERE consumed_at IS
  NULL`): живой код у личности один.
- Строка кода и намерение письма (`kaname.invite_mail_outbox`, вид `mail.recovery.send`)
  пишутся **одной транзакцией** (Ф5-09); при откате нет ни того, ни другого.
- Уборка — предмет реестра `retention` (`recovery_codes`, порог 0): применённые и истёкшие
  строки, которые оператор применения уже не обслужит.

## See also

[[resources/iam-recovery-completions]] · [[rpc/iam-internal-user-service]] · [[KAC/issue-1271]]

#resource #kacho-iam #iam #internal #migrations
