---
title: nlb-tests-k6
aliases:
  - nlb k6 load
category: packages
repo: kacho-nlb
layer: tests
tags:
  - packages
  - kacho-nlb
  - tests
  - k6
  - load
---

# kacho-nlb/tests/k6

**Path**: `kacho-nlb/tests/k6/`
**Tooling**: k6 (HTTP/gRPC scripts) + ghz (gRPC-specific). Run against deployed kacho-nlb (real Postgres + peer-services).

## Files

| File | Содержание |
|---|---|
| `scripts/` | k6 entry-point scripts |
| `scenarios/` | declarative scenario configs (RPS, VUs, duration) |
| `lib/` | shared utilities (auth bootstrap, project seed, helpers) |
| `data/` | test data fixtures (sample LBs/TGs/Targets) |
| `ghz/` | ghz configs для gRPC load |
| `Makefile` | targets: `make load-baseline`, `make load-stress`, `make load-soak` |
| `results/` | output dir (gitignored) |
| `README.md` | scenario catalog + SLO targets |

## Scenarios (5)

1. **baseline** — 500 RPS mixed read/write, 5min ramp → 30min hold. SLO: p95 ≤ 100ms, p99 ≤ 300ms.
2. **read-heavy** — 1000 RPS sync reads (Get/List/GetTargetStates), 10min. SLO: p95 ≤ 50ms.
3. **write-heavy** — 200 RPS mutations (Create/Update/AddTargets/RemoveTargets). SLO: ops queue depth < 50; Operation.done≤2s.
4. **stress** — RPS ramp 100 → 2000, find break point. Report saturation curve.
5. **soak** — 300 RPS for 6h. Assert no memory leak, no connection exhaustion, no error rate creep.

## SLO targets (KAC-141 DoD)

- p95 latency ≤ 100ms @ 500 RPS (baseline) — **MUST pass для DoD**
- p99 latency ≤ 300ms @ 500 RPS
- Error rate < 0.01% (excluding intentional 4xx)
- pgx pool utilization < 80%

## CI integration

`.github/workflows/k6-baseline.yml` — nightly run baseline scenario; results → S3 + Grafana dashboard. Stress/soak — manual trigger.

## See also

[[nlb-tests-newman]] [[../KAC/KAC-141]]

#packages #kacho-nlb #tests #k6 #load
