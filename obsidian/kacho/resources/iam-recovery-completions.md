---
title: recovery_completions
category: resource
domain: iam
owner_table: kacho_iam.recovery_completions
project_level: ledger
status: done
related_rpc:
  - "[[rpc/iam-internal-user-service]]"
related_packages: []
tags:
  - resource
  - kacho-iam
  - iam
  - internal
  - migrations
verified_against: "таблица-владелец подтверждена живой переписью миграций сервиса (ствол redesign/integration, 2026-08-05); столбец external_id и второй источник сверены с веткой issue-1271-recovery от release/iam-lines@af0ca8f3 (kaname), 2026-09-17"
---

# recovery_completions (iam)

**Schema**: `kacho_iam.recovery_completions` (migration `0015_recovery_completions.sql`)
**Owner**: kacho-iam · **Visibility**: internal (idempotency ledger, не tenant-facing)

## Назначение

Idempotency-ledger завершений восстановления доступа. **Источника события два, запись одна**
(Ф5 Р4, `PRO-Robotech/kacho#1271`):

- webhook поставщика личности `InternalUserService.OnRecoveryCompleted` (KAC-127 Phase 2 /
  sub-phase 5.3) — доставляется **at-least-once**, дубль НЕ должен повторно выполнять
  side-effects (revoke-all cutoff / audit); называет внешнего субъекта;
- наш поток восстановления кодом по почте (Ф5, `humansession`) — ключ потока чеканим мы: это
  `id` строки [[resources/iam-recovery-code]]; внешнего субъекта поток не несёт (столбец NULL).

Дедуп — на DB-уровне (запрет #10). Снятие блокировки восстановлением **не выполняется** ни
одним источником: восстановление возвращает учётные данные, а не право ими пользоваться.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `recovery_jti` | text | **PK** — Kratos recovery-flow id (flow-scoped, не per-user). CHECK len 1..128 |
| `external_id` | text | внешний субъект поставщика; **NULL у нашего потока** (миграция `20260917015400`, Ф5 Р4). CHECK len 1..128 на заданном значении |
| `user_id` | text | детерминированный primary row (first by created_at ASC). CHECK len 1..64 |
| `revoked_session_count` | int | для idempotent-replay metadata. CHECK >= 0 |
| `completed_at` | timestamptz | DEFAULT now() |

## Контракт

- Глобальная таблица (НЕ scoped по account_id): один recovery-flow = одна row.
- Writer-gate (tx-scoped, в той же writer-tx что re-enable+revoke+audit):
  `INSERT … ON CONFLICT (recovery_jti) DO NOTHING` + backstop SELECT.
  1 row → inserted=true (новый flow, выполняем side-effects); 0 rows →
  inserted=false (idempotent no-op, side-effects НЕ выполняются).
- PK row-lock сериализует конкурентные доставки одного `recovery_jti`
  (ровно один writer выигрывает INSERT).
- Нет FK на user_id (identity = N rows; ledger хранит primary для replay).
- Mid-tx rollback откатывает и ledger-row → нет «застрявшего» ключа (5.3-07).

## See also

[[rpc/iam-internal-user-service]] · [[resources/iam-user]] · [[resources/iam-recovery-code]] · [[KAC/KAC-127]] · [[KAC/issue-1271]]

#resource #kacho-iam #iam #internal #migrations
