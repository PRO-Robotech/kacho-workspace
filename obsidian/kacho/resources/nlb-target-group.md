---
title: TargetGroup
aliases:
  - TargetGroup (nlb)
  - nlb TargetGroup
category: resource
domain: nlb
id_prefix: tgr
owner_table: kacho_nlb.target_groups
owner_db: kacho_nlb
project_level: true
status: stable
related_rpc:
  - "[[rpc/nlb-target-group-service]]"
related_packages:
  - "[[packages/nlb-domain]]"
  - "[[packages/nlb-apps-kacho-api-targetgroup]]"
tags:
  - resource
  - kacho-nlb
  - targetgroup
verified_against: "ствол redesign/integration, сверено 2026-08-05"
---

> [!note] Сверка со стволом (2026-08-05)
> Контракт — `proto/kacho/cloud/loadbalancer/v1/target_group.proto` (там же `message Target`),
> таблицы `kacho_nlb.target_groups` и `kacho_nlb.targets` живы. `TargetGroupService` несёт
> девять RPC, включая `AddTargets` / `RemoveTargets` (мутация состава — отдельными
> глаголами, не через `Update`) и `Move`.
>
> Порт таргет-группы заведён миграцией `0015_target_group_port.sql`. Регион для
> instance-таргетов резолвится у geo (`ZoneService.Get` → регион зоны), а для nic/ip-таргетов
> берётся из авторитетного `Subnet.RegionID` в ответе vpc — **никогда** не выводится
> разбором имени зоны (снятая деривация `regionFromZone` — прецедент в `data-integrity.md`).

# TargetGroup (nlb)

**Domain**: nlb
**ID prefix**: `tgr`
**Owner table**: `kacho_nlb.target_groups`
**Folder-level**: yes (per-project)

## Fields (domain)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("tgr")` | |
| `project_id` | TEXT NOT NULL | cross-service ref → iam.Project | **immutable** |
| `region_id` | TEXT NOT NULL | cross-service ref → compute.Region | **immutable** |
| `name`, `description`, `labels` | TEXT/JSONB | DNS-1123, ≤256, ≤64 labels | partial UNIQUE per project |
| `health_check` | JSONB | embedded, см. ниже | mutable (oneof-replace дисциплина) |
| `port` | INT | `1..65535` (CHECK), required | **LIVE-mutable** (NLB-1c); echoed by `Listener.resolved_backend_port°` |
| `deregistration_delay` | Duration | `0s..3600s`, default `300s` | mutable (B8; DB col `deregistration_delay_seconds` INT — convert at repo boundary) |
| `slow_start` | Duration | `0s..900s`, default `0s` | mutable (B8; DB col `slow_start_seconds` INT) |
| `status` | TEXT | `ACTIVE` \| `DELETING` | enum CHECK |

## HealthCheck (JSONB embedded) — NLB-1c redesigned

`name`/id **сняты** (embedded value-object, не ресурс). Probe-`port` опционален
(0 → наследует `TG.port`); резолв в output-only `effective_port°`.

```json
{
  "interval": "2s",      // [1s,600s] default 2s
  "timeout": "1s",       // >0, <= interval
  "unhealthy_threshold": 2,    // 2..10
  "healthy_threshold": 2,
  "effective_port": 8080,      // output-only: probe.port override || TG.port
  // exactly one probe:
  "tcp":   {"port": 0}                                              // 0 = inherit
  "http":  {"port": 0, "path": "/health", "expected_codes": "200-299", "host": "", "headers": {}}
  "https": {"port": 8443, "path": "/health", "expected_codes": "200,204", "host": "", "headers": {}}
  "grpc":  {"port": 0, "service_name": "grpc.health.v1.Health"}
}
```

Validation `domain.HealthCheck.Validate()` — exactly-one TCP/HTTP/HTTPS/GRPC.
**Update oneof-replace дисциплина** (NLB-1c): dotted `health_check.<scalar>` mask →
merge-validated PATCH (проба и sibling-скаляры целы); dotted `health_check.<probe>`
→ atomic-replace пробы с сохранением sibling-скаляров; probe-путь без дискриминатора
→ `INVALID_ARGUMENT` (не silent-clear).

## Targets (child table)

`targets` (см. [[nlb-target]]) — embedded children через `target_group_id` FK RESTRICT. Operations Add/Remove — отдельные RPC; embed-в-TG-payload только при Create.

## Constraints / indexes

- PK + GIN `labels_gin`
- Partial UNIQUE `(project_id, name) WHERE name<>''` (TGR-014)
- Keyset `(project_id, created_at DESC, id)`
- CHECK на dereg-delay (0..3600), slow-start (0..900), status enum

## FK contract (in-bound)

- `targets.target_group_id → target_groups(id) ON DELETE RESTRICT`
- `listeners.default_target_group_id → target_groups(id) ON DELETE RESTRICT` (0018; NLB-1b direct FK, заменил M:N pivot)

→ Delete TG teardown-precheck (NLB-1-41): референсящие listener'ы перечисляются
→ `FailedPrecondition "target group is referenced by listeners: [lst-...]"` (repo
`ReferencingListenerIDs`, ORDER BY id; DB FK RESTRICT — authoritative backstop).
Targets-present → `"TargetGroup has N target(s)..."`.

## 2-phase RemoveTargets drain

Phase A (immediate worker): `UPDATE targets SET status='DRAINING', drain_started_at=now()` → ops.MarkDone (client gets fast `done=true`).
Phase B (`jobs/target_drain_runner.go`, periodic): `DELETE FROM targets WHERE status='DRAINING' AND drain_started_at < now() - deregistration_delay::interval`.

`dereg_delay=0` → Phase B на следующем tick (~5s).

## Lifecycle

Single `ACTIVE` state. `DELETING` — terminal, transient.

## Gotchas

- Same-region constraint: TG.region_id обязан совпадать с LB.region_id при AttachTargetGroup (DB CHECK).
- Move blocked если есть attached LB.

## See also

[[../packages/nlb-apps-kacho-api-targetgroup]] [[../rpc/nlb-target-group-service]] [[nlb-target]] [[nlb-load-balancer]]

#resource #kacho-nlb #targetgroup
