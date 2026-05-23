---
title: "outbox/drainer (kacho-corelib)"
category: packages
repo: kacho-corelib
layer: infrastructure
tags:
  - packages
  - kacho-corelib
  - outbox
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
  `BEGIN → SELECT … FOR UPDATE SKIP LOCKED LIMIT N → UPDATE attempt_count++ → apply → markSuccess/markFailure/markPoisoned → COMMIT`.
  Row-lock держится до commit'а → HA exactly-once (W1.1-10 verified).
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

## Imported by (current)

- `kacho-iam/internal/clients/fga_applier.go` — первый concrete consumer (W1.1 KAC-137)

## Planned (по master plan)

- W1.2: `subject_change_outbox` drainer (cache invalidation на revoke)

## Связано

- [[../KAC/KAC-137]] — W1.1 implementation
- [[../KAC/KAC-136]] — W1 parent
- [[../KAC/KAC-134]] — epic
- [[../edges/iam-to-openfga-grant-write]] — usage

#packages #kacho-corelib #outbox
