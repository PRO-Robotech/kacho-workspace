---
title: nlb-apps-kacho-jobs
aliases:
  - nlb workers
  - nlb drain runner
category: packages
repo: kacho-nlb
layer: jobs
tags:
  - packages
  - kacho-nlb
  - jobs
  - worker
---

# kacho-nlb/internal/apps/kacho/jobs

**Path**: `kacho-nlb/internal/apps/kacho/jobs/`
**Imports**: [[nlb-domain]], [[nlb-repo-kacho-pg]], [[corelib-operations]], [[corelib-outbox]]

Background workers — periodic jobs running в отдельных goroutines от main API loop.

## Files

| File | Содержание |
|---|---|
| `doc.go` | overview + scheduling pattern |
| `target_drain_runner.go` | **Phase B of 2-phase RemoveTargets**: periodic (~5s) `DELETE FROM targets WHERE status='DRAINING' AND drain_started_at < now() - <tg.dereg_delay>::interval` → outbox.Emit UPDATED. Tick configurable via `KACHO_NLB_JOBS__DRAIN_TICK=5s`. |
| `target_drain_runner_integration_test.go` | testcontainers integration test — RemoveTargets Phase A → wait → drain-runner deletes |
| `free_ip_runner.go` (future) | retry-runner для failed `vpc.FreeIP` calls (compensation) |
| `outbox_drainer.go` | corelib `outbox.Drainer` wired для nlb_outbox table (lifecycle subscribers consume через D-13 stream, не нужен active drainer — но для metrics/back-pressure используется) |

## Drain-runner SQL

```sql
DELETE FROM kacho_nlb.targets t
USING kacho_nlb.target_groups tg
WHERE t.target_group_id = tg.id
  AND t.status = 'DRAINING'
  AND t.drain_started_at < now() - (tg.deregistration_delay_seconds::text || ' seconds')::interval
RETURNING t.id, t.target_group_id;
```

## Scheduling

`tick := time.NewTicker(cfg.Jobs.DrainTick)` → for-loop с context cancellation. Метрики: `nlb_drain_runner_deleted_total`, `nlb_drain_runner_tick_duration_seconds`.

## Test pattern

Integration test (testcontainers Postgres):
1. Seed TG + target with `status='DRAINING'`, `drain_started_at=now()-1h`
2. Run one tick of drain-runner
3. Assert target row removed + outbox row emitted

## See also

[[../rpc/nlb-target-group-service]] [[../resources/nlb-target]] [[corelib-outbox]]

#packages #kacho-nlb #jobs #worker
