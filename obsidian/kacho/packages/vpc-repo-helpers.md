---
title: vpc-repo-helpers
category: package
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - sql
---

# kacho-vpc/internal/repo/helpers

**Каталог**: `services/vpc/internal/repo/helpers/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/repo/helpers/`)
**Imported by**: [[vpc-repo-kacho-pg]] (все pg-репозитории)

Общие SQL helpers — переиспользуются между entity-repo'шками.

## Files

| File | Содержание |
|---|---|
| `errors.go` | `mapPgErr(err) error` — SQLSTATE → service.Err* (23503→FailedPrecondition, 23505→AlreadyExists, 23514→InvalidArgument, 23P01→FailedPrecondition) |
| `sql.go` | builder-helpers (timestamps, RETURNING wrappers) |
| `scans.go` | `pgx.RowToStructByName`-like scanners для entity'ев |
| `jsonb.go` | JSONB marshal/unmarshal helpers (labels, rules, address_value) |
| `paging.go` | seek-pagination + offset-pagination helpers |
| `payloads.go` | typed payload-structs для outbox events |
| `outbox.go` | thin-wrapper [[corelib-outbox]] для vpc-specific event kinds |
| `unique.go` | partial UNIQUE constraint test-helpers |
| `freelist_sql.go` | `FOR UPDATE SKIP LOCKED` queries для AddressPool freelist (миграция 0015) |
| `sg.go` | SG rule-list normalisation (sort + dedupe) |
| `nic.go` | NIC-specific helpers (mac auto-gen 0014, CAS attach 0017+) |

## See also

[[vpc-repo-kacho-pg]] [[corelib-outbox]] [[../resources/vpc-addresspool]]

#packages #kacho-vpc #repo #sql
