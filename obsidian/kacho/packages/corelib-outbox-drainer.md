---
title: "outbox/drainer (kacho-corelib)"
category: packages
repo: kacho-corelib
layer: infrastructure
tags:
  - packages
  - kacho-corelib
  - outbox
  - race-fix
---

# outbox/drainer

Generic LISTEN/NOTIFY outbox-drainer in `kacho-corelib/outbox/drainer/`, sub-package расширяющий
существующий writer-side `outbox/` (`emit.go` / `event.go` / `writer.go`). Драинер — generic,
переиспользуется W1.2 для `subject_change_outbox` cache-invalidation.

## Exported API

```go
type Config struct {
    Table        string         // table name to claim from
    Channel      string         // pg NOTIFY channel
    BatchSize    int            // default 32
    PollFallback time.Duration  // default 30s — wakes if no NOTIFY (catch missed events)
    MaxAttempts  int            // default 10 — после force-poison row
    BackoffMin   time.Duration  // default 1s
    BackoffMax   time.Duration  // default 30s
    ApplyTimeout time.Duration  // default 5s — per-row apply + DB-mark deadline
}

type Decoder[T any] func(payload []byte) (T, error)
type Applier[T any] func(ctx context.Context, eventType string, payload T) error

type Drainer[T any] struct { /* private */ }

func New[T any](pool *pgxpool.Pool, cfg Config, dec Decoder[T], app Applier[T], log *slog.Logger) (*Drainer[T], error)
func (d *Drainer[T]) Run(ctx context.Context) error  // blocking until ctx-done

var ErrAlreadyApplied = errors.New("drainer: row already applied")  // idempotent success
var ErrPermanent      = errors.New("drainer: permanent error")      // poison row (force MaxAttempts)
```

## Mechanics (acceptance §4)

- **Atomic CAS-claim в одной tx** (per CLAUDE.md §запрет #10):
  `BEGIN → SELECT … FOR UPDATE SKIP LOCKED ORDER BY attempt_count, id LIMIT N → UPDATE attempt_count++ → apply → markSuccess/markFailure/markPoisoned → COMMIT`.
  Row-lock держится до commit'а → HA exactly-once (W1.1-10 verified).
  - **Claim-order `ORDER BY attempt_count, id`** (sub-phase 1.4, corelib #26) — НЕ просто `ORDER BY id`.
    Иначе backlog transient-застрявших low-id rows навечно затеняет свежие higher-id intent'ы
    (head-of-line starvation → at-least-once нарушен). См. ниже инцидент A07.
- **LISTEN/NOTIFY conn** — `pool.Acquire().Hijack()` (separate from pool, не возвращается).
  Auto-reconnect с exp-backoff при conn drop (W1.1-08).
- **Startup catch-up** — `drainBatch(ctx)` ДО main select-loop (W1.1-02, W1.1-15).
- **Graceful shutdown** — in-flight apply + mark защищены `context.WithoutCancel + WithTimeout(ApplyTimeout)`.
  `tx.Commit/Rollback` используют bounded `shutdownCtx` (защита от unreachable Postgres).

## Error semantics

| Applier return | Drainer action |
|---|---|
| `nil` | `markSuccess` (sent_at = now, last_error = NULL) |
| `errors.Is(err, ErrAlreadyApplied)` | `markSuccess` (idempotent — target уже has change) |
| `errors.Is(err, ErrPermanent)` | `markPoisoned` (force attempt_count = MaxAttempts, continue) |
| other (transient) | `markFailure` + exp-backoff retry на следующей claim итерации |

## Imports

stdlib (`context`, `errors`, `fmt`, `log/slog`, `time`, `crypto/rand`) + `github.com/jackc/pgx/v5` + `pgxpool`.

## S0 hardening (sub-phase 1.4, corelib #25 — at-least-once гарантии)

- **transient-no-poison** — `markTransientFailure` кэпит `attempt_count` на `MaxAttempts-1`,
  чтобы transient-сбой (peer `Unavailable`) НИКОГДА сам по себе не достигал poison-порога;
  poison — только явный `ErrPermanent`. Закрывает «outage дольше MaxAttempts → intent отравлен → tuple потерян».
- **reconciler** — `RedrivePoisoned` / `BackfillFromState` / `GCOrphans` (фон-задача целостности outbox↔state).
- **fail-closed bootgate** — drainer не стартует, если outbox в несогласованном состоянии (метрики + bootgate).

## ⚠️ Инцидент A07 — head-of-line starvation (sub-phase 1.4, corelib #26)

> [!warning] Регрессия at-least-once от S0 attempt_count-cap + `ORDER BY id`
> S0-кэп (transient row застревает с высоким `attempt_count`, но НЕ poison) в паре со старым
> claim-`ORDER BY id` дал **starvation**: backlog transient-застрявших **low-id** строк
> навсегда затенял свежие **higher-id** intent'ы → под длительным outage новый intent НЕ доставлялся
> → **нарушение at-least-once**. Поймано как red `kacho-iam/TestRegisterResource_A07_FGADownIntentPersistsAcrossRestart` на main.
> **Фикс (corelib #26)**: claim `ORDER BY attempt_count, id` — свежие (низкий attempt_count) идут первыми.
> Гард: новый тест `Test_1_4_24_TransientBacklog_DoesNotStarveFreshIntent`.

## Imported by (current)

- `kacho-iam/internal/clients/fga_applier.go` — concrete consumer для `fga_outbox` (W1.1 KAC-137; idempotent FGA-409→success). Также применяет owner/hierarchy-tuple для **собственных** iam-ресурсов (sub-phase 1.4 S2 — co-commit через `Writer.EmitFGARelationWrite`, см. [[../edges/iam-to-openfga-grant-write]]).

## Planned (по master plan)

- W1.2: `subject_change_outbox` drainer (cache invalidation на revoke)

## Связано

- [[../KAC/KAC-137]] — W1.1 implementation
- [[../KAC/KAC-136]] — W1 parent
- [[../KAC/KAC-134]] — epic
- [[sub-phase-1.4-tuple-resource-guarantee]] — S0/S2/S3 (100% tuple↔resource при Create)
- [[corelib-outbox]] — writer-side (`Emit` в TX)
- [[iam-pg-fga-outbox]] — iam concrete fga_outbox emitter
- [[../edges/iam-to-openfga-grant-write]] — usage

#packages #kacho-corelib #outbox
