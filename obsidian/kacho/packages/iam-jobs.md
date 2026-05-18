---
title: "iam internal/apps/kacho/jobs"
aliases:
  - iam jobs
  - iam-jobs
  - fga_outbox_drainer
category: packages
repo: kacho-iam
layer: app
status: done
related_tickets:
  - "[[KAC-108]]"
tags:
  - packages
  - kacho-iam
  - done
  - outbox
---

# iam `internal/apps/kacho/jobs`

Фоновые worker'ы kacho-iam. Запускаются в composition root `cmd/kacho-iam/main.go` как parallel tasks в `parallel.ExecAbstract`.

## Worker'ы

### `FGAOutboxDrainer` (KAC-108 closeout)

Дренирует `kacho_iam.fga_outbox` → openfga.Write/Delete. Реализует acceptance E3 §4.2 / D-5 (atomic AccessBinding write + async FGA tuple-write через outbox-pattern).

**Контракт:**
- LISTEN на `kacho_iam_fga_outbox` (push-wake) + ticker fallback (`KACHO_IAM_FGA_OUTBOX_INTERVAL_MS`, default 100ms).
- На каждом tick'е / NOTIFY: `FetchPending(limit)` → per row → `openfga.Write/Delete` → `MarkProcessed` или `MarkFailed (attempt_count++)`.
- Idempotent CAS update: `WHERE sent_at IS NULL` — двойной drainer не делает double-write на одну row (openfga само idempotent).
- Max 5 immediate retries; дальше skip с warning (production: DLQ + alert).

**Env config:**

| ENV | Default | Effect |
|---|---|---|
| `KACHO_IAM_OPENFGA_STORE_ID` | — (drainer disabled) | activate drainer |
| `KACHO_IAM_OPENFGA_ENDPOINT` | `kacho-umbrella-openfga:8080` | OpenFGA REST URL |
| `KACHO_IAM_OPENFGA_MODEL_ID` | — | auth-model-id |
| `KACHO_IAM_FGA_OUTBOX_INTERVAL_MS` | 100 | drainer tick |
| `KACHO_IAM_FGA_OUTBOX_BATCH_SIZE` | 50 | FetchPending limit |

**Latency** (integration test'ом подтверждена):
- enqueue → tuple-applied: **6-50ms** обычно, **≤200ms** worst-case (1 tick + 1 HTTP RTT).
- recovery after fail: 1 tick (~50-100ms).

## Exported API

- `NewFGAOutboxDrainer(pool, drainer, fga, logger) → *FGAOutboxDrainer`
- `(*FGAOutboxDrainer).WithTickInterval(d time.Duration) → *FGAOutboxDrainer`
- `(*FGAOutboxDrainer).WithBatchSize(n int) → *FGAOutboxDrainer`
- `(*FGAOutboxDrainer).Run(ctx) error` — главный цикл (graceful через ctx).

## Imports

- `internal/clients` — `OpenFGAClient` (HTTP-impl или stub)
- `internal/repo/kacho/outbox` — `DrainerIface` (port)
- `internal/repo/kacho/pg` — реальный `OutboxDrainer` (adapter)

## Imported by

- `cmd/kacho-iam/main.go` — composition root (4-й parallel task)

## See also

[[../edges/iam-to-openfga-check]] [[../resources/iam-access-binding]] [[../KAC/KAC-108]]

#packages #kacho-iam #outbox
