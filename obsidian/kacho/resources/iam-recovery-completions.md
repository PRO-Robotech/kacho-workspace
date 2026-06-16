---
title: recovery_completions
category: resource
domain: iam
owner_table: kacho_iam.recovery_completions
folder_level: ledger
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
---

# recovery_completions (iam)

**Schema**: `kacho_iam.recovery_completions` (migration `0015_recovery_completions.sql`)
**Owner**: kacho-iam · **Visibility**: internal (idempotency ledger, не tenant-facing)

## Назначение

Idempotency-ledger для Kratos recovery-webhook
`InternalUserService.OnRecoveryCompleted` (KAC-127 Phase 2 / sub-phase 5.3).
Ory Kratos доставляет webhook **at-least-once** — дубль НЕ должен повторно
выполнять side-effects (re-enable / revoke-all cutoff / audit). Дедуп — на
DB-уровне (запрет #10).

## Колонки

| Column | Type | Notes |
|---|---|---|
| `recovery_jti` | text | **PK** — Kratos recovery-flow id (flow-scoped, не per-user). CHECK len 1..128 |
| `external_id` | text | Kratos sub. CHECK len 1..128 |
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

[[rpc/iam-internal-user-service]] · [[resources/iam-user]] · [[KAC/KAC-127]]

#resource #kacho-iam #iam #internal #migrations
