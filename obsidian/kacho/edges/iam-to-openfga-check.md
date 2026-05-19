---
title: "iam ↔ openfga: REBAC tuple sync + Check"
aliases:
  - iam to openfga
  - openfga check
category: edge
caller_repo: kacho-iam
callee_repo: openfga
sync_async: mixed
protocol: gRPC
status: done
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-108]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - done
  - rebac
---

# iam ↔ openfga: REBAC tuple sync + Check

**Caller(s)**:
- `kacho-iam` — write-path: sync AccessBinding/Group changes → OpenFGA tuples (Write/Delete API)
- `kacho-api-gateway` (auth-interceptor) — read-path: `Check(user, verb, resource)` на каждый запрос
**Callee**: `openfga` (external REBAC; tuple-store + Zanzibar Check-API)
**Protocol**: gRPC (OpenFGA native API)
**Sync/Async**: mixed — Check sync (per-request); tuple-sync async (best-effort из outbox)
**Status**: **planned** — появится в E3 ([[KAC-108]]).

## When invoked (E3)

- **Write-path (KAC-108 closeout, outbox-pattern, async ≤200ms)**: AccessBindingService.Create/Delete в writer-TX enqueue'ит row в `kacho_iam.fga_outbox` (event_type=`fga.tuple.write` или `fga.tuple.delete`) одной транзакцией с `access_bindings` INSERT/DELETE — atomic. trigger AFTER INSERT шлёт `pg_notify('kacho_iam_fga_outbox', id)`. Drainer `internal/apps/kacho/jobs/fga_outbox_drainer.go` дренит pending row'ы → `openfga.Write/Delete` с retry + exponential backoff (max 5 immediate retries). Idempotent (openfga 409 = success). См. [[../packages/iam-jobs]].
- **Read-path (sync на запрос)**: api-gateway interceptor вызывает `openfga.Check(user=usr<id>, relation=<verb>, object=<resource_type>:<resource_id>)`. На `allowed=false` → `PermissionDenied`.
- **Реактивность (DoD #5, ≤10s)**: outbox drain ≤200ms + cache TTL=5s + LISTEN-invalidate ≤1s = укладывается в ≤10s.

## Error handling (E3)

| Result | gRPC code | Note |
|---|---|---|
| allowed=true | (continue) | |
| allowed=false | `PermissionDenied` | normal authz reject |
| OpenFGA недоступен | **fail-closed** → `Unavailable` для мутаций; для read — может fail-open behind flag (TBD в acceptance) | |
| tuple-sync diverged | reconciliation job (E3 §10) | детектится eventual-consistency проверкой |

## E0/E1/E2 status (текущий)

- OpenFGA **не деплоится**.
- AccessBinding'и хранятся в `kacho_iam.access_bindings` (см. [[../resources/iam-access-binding]]) — **не enforce'ятся**.
- Любой запрос проходит interceptor без auth-check.

## See also

[[../rpc/iam-access-binding-service]] [[../rpc/iam-internal-iam-service]] [[../resources/iam-access-binding]] [[../KAC/KAC-104]] [[../KAC/KAC-108|KAC-108 (E3)]] [[../KAC/KAC-122]] (authz-deny matrix newman suite)

#edge #kacho-iam #cross-service #planned #rebac
