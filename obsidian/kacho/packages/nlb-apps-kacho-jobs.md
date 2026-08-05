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
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов, ручки периода тиков и их значения по умолчанию, место дренажа outbox; текст записки построчно не пересматривался"
---

# kacho-nlb/internal/apps/kacho/jobs

**Каталог**: `services/nlb/internal/apps/kacho/jobs/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/internal/apps/kacho/jobs/`)
**Imports**: [[nlb-domain]], [[nlb-repo-kacho-pg]], [[corelib-operations]], [[corelib-outbox]]

Background workers — periodic jobs running в отдельных goroutines от main API loop.

## Files

| File | Содержание |
|---|---|
| `doc.go` | overview + scheduling pattern |
| `target_drain_runner.go` | **Phase B of 2-phase RemoveTargets**: периодически удаляет `DRAINING`-таргеты, у которых истёк `deregistration_delay` группы, → outbox.Emit UPDATED. Период — ключ конфига `jobs.target-drain.interval`, default **10s** |
| `target_drain_runner_integration_test.go` | testcontainers integration test — RemoveTargets Phase A → wait → drain-runner deletes |
| `free_ip_runner.go` | **живой**, не «future»: реконсайлер застрявших балансировщиков — create-сирота в `CREATING` и незавершённый Delete в `DELETING`. Ключи `jobs.free-ip.interval` (default 30s) и `jobs.free-ip.age-threshold` (default 5m — свежий in-flight не трогается, пока легитимный worker дорабатывает). Сканирует только балансировщики |
| `testmain_pgtest_test.go` | общий TestMain под testcontainers |

> [!note] Дренажа outbox в этом пакете нет — он корелибовый и провязан в composition root
> Прежняя редакция называла здесь отдельный файл-дренажер. Его нет: дренаж — общий
> `pkg/outbox/drainer` из corelib, а провязывается он в composition root
> (`services/nlb/cmd/kacho-loadbalancer/`), вместе с backstop'ом и bootgate.
> Дренится при этом **очередь регистраций** (`fga_register_outbox`), а не тот outbox,
> из которого читает lifecycle-стрим, — это две разные таблицы с разной судьбой.

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

`time.NewTicker(r.interval)` → for-loop с context cancellation; период приезжает из
`cfg.Jobs.TargetDrain.Interval` (и, для второго раннера, `cfg.Jobs.FreeIP.Interval`).
Обе величины валидируются как `> 0` в `Config.Validate()`.

Своих метрик у drain-runner'а нет — он ведёт только structured-log. Из счётчиков nlb
к фоновым путям относятся `nlb_free_ip_poisoned_total`, `nlb_outbox_poisoned_total` и
`nlb_outbox_oldest_pending_age_seconds`; пара «сколько удалено за тик» в дереве **не
заведена**, и прежняя редакция называла два счётчика, которых нет. Это не косметика:
на такую пару естественно завести алерт, а алерт на несуществующий счётчик молчит
всегда — форма наблюдаемости без содержания.

## Test pattern

Integration test (testcontainers Postgres):
1. Seed TG + target with `status='DRAINING'`, `drain_started_at=now()-1h`
2. Run one tick of drain-runner
3. Assert target row removed + outbox row emitted

## See also

[[../rpc/nlb-target-group-service]] [[../resources/nlb-target]] [[corelib-outbox]]

#packages #kacho-nlb #jobs #worker
