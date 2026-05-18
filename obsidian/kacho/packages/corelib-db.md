---
title: corelib-db
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - db
  - postgres
---

# corelib/db

**Path**: `kacho-corelib/db/`
**Imports**: `context`, `github.com/jackc/pgx/v5`, `github.com/jackc/pgx/v5/pgxpool`
**Imported by**: `kacho-vpc` (27 files), `kacho-resource-manager` (2)

`pgxpool.Pool` factory + Transactor для composable transactions.

## Exported

- `NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error)` — единая точка создания pool; задаёт ConnConfig (search_path, statement_cache, parsetime), регистрирует pgx-tracer. DSN — `postgres://...?application_name=kacho-<svc>`.
- `Transactor struct{ ... }` — обёртка с методом `Do(ctx, fn func(ctx) error) error`, ставит pgx.Tx в context (ключ pgx.Tx). Service-слой использует `Transactor.Do(...)` для группировки выпуск-операций и outbox-эмита в одной TX.
  - `NewTransactor(p *pgxpool.Pool) *Transactor`

## Pattern

```go
err := tx.Do(ctx, func(ctx context.Context) error {
    if err := repo.CreateNetwork(ctx, n); err != nil { return err }
    if err := outbox.Emit(ctx, ..., "network.created", ...); err != nil { return err }
    return nil
})
```

`outbox.Emit` подхватывает `pgx.Tx` из context — атомарность гарантирована.

## See also

[[corelib-outbox]] [[vpc-repo-kacho-pg]]

#packages #kacho-corelib #db #postgres
