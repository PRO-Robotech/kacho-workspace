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
folder_level: true
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
---

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
| `health_check` | JSONB | embedded, см. ниже | mutable |
| `deregistration_delay_seconds` | INT | `0..3600`, default `300` | mutable |
| `slow_start_seconds` | INT | `0..900`, default `0` | mutable |
| `status` | TEXT | `ACTIVE` \| `DELETING` | enum CHECK |

## HealthCheck (JSONB embedded)

```json
{
  "name": "<lb-name>",
  "interval": "2s",      // default
  "timeout": "1s",
  "unhealthy_threshold": 2,    // 2..10
  "healthy_threshold": 2,
  "tcp":   {"port": 80}                       // exactly one of
  "http":  {"port": 80, "path": "/health"}
  "https": {"port": 443, "path": "/health"}
  "grpc":  {"port": 50051, "service_name": ""}
}
```

Validation в `domain.HealthCheck.Validate()` — exactly-one TCP/HTTP/HTTPS/GRPC.

## Targets (child table)

`targets` (см. [[nlb-target]]) — embedded children через `target_group_id` FK RESTRICT. Operations Add/Remove — отдельные RPC; embed-в-TG-payload только при Create.

## Constraints / indexes

- PK + GIN `labels_gin`
- Partial UNIQUE `(project_id, name) WHERE name<>''` (TGR-014)
- Keyset `(project_id, created_at DESC, id)`
- CHECK на dereg-delay (0..3600), slow-start (0..900), status enum

## FK contract (in-bound)

- `targets.target_group_id → target_groups(id) ON DELETE RESTRICT`
- `attached_target_groups.target_group_id → target_groups(id) ON DELETE RESTRICT`

→ Delete TG → `FailedPrecondition "target group has targets"` или `"... attached to load balancer"` (sync precheck).

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
