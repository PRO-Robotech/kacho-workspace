---
title: vpc-apps-migrator
category: package
repo: kacho-vpc
layer: migrations
tags:
  - packages
  - kacho-vpc
  - migrations
---

# kacho-vpc/internal/apps/migrator

**Path**: `kacho-vpc/internal/apps/migrator/`
**Imported by**: [[vpc-cmd-migrator]] (bin entrypoint)

Migration runner — dialect-aware (Postgres + CockroachDB).

## Files

| File | Содержание |
|---|---|
| `runner.go` | core loop: parse SQL files, apply up/down |
| `runner_test.go` | |
| `dialect.go` | dialect-detection helpers |
| `dialect_test.go` | |
| `postgres.go` | Postgres-specific tweaks (pg_advisory_lock для concurrent migrator) |
| `cockroach.go` | CockroachDB-specific (DDL transactions, SKIP LOCKED differences) |

## Migration files

Source: `kacho-vpc/internal/migrations/*.sql` (numbered `0001_...sql`). См. список миграций — там 30+ файлов (последняя на момент индексации — 0030).

## See also

[[vpc-cmd-migrator]] [[corelib-db]]

#packages #kacho-vpc #migrations
