---
title: NetworkLoadBalancer
aliases:
  - LoadBalancer (nlb)
  - nlb NetworkLoadBalancer
category: resource
domain: nlb
id_prefix: nlb
owner_table: kacho_nlb.load_balancers
owner_db: kacho_nlb
folder_level: true
status: stable
related_rpc:
  - "[[rpc/nlb-network-load-balancer-service]]"
  - "[[rpc/nlb-internal-resource-lifecycle-service]]"
related_packages:
  - "[[packages/nlb-domain]]"
  - "[[packages/nlb-repo-kacho-pg]]"
  - "[[packages/nlb-apps-kacho-api-loadbalancer]]"
tags:
  - resource
  - kacho-nlb
  - loadbalancer
---

# NetworkLoadBalancer (nlb)

**Domain**: nlb
**ID prefix**: `nlb`
**Owner table**: `kacho_nlb.load_balancers` (database `kacho_nlb`)
**Folder-level**: yes (per-project unique name)

## Fields (domain)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("nlb")` | |
| `project_id` | TEXT NOT NULL | cross-service ref → iam.Project | dangling-ref грациозен |
| `region_id` | TEXT NOT NULL | cross-service ref → compute.Region | sync `RegionService.Get` |
| `name` | TEXT | DNS-1123 regex `^[a-z]([-a-z0-9]{1,61}[a-z0-9])?$` | partial UNIQUE per project |
| `description` | TEXT | `<=256` chars | |
| `labels` | JSONB | `kacho_labels_valid` (≤64 pairs) | CHECK constraint inline |
| `type` | TEXT | `EXTERNAL` \| `INTERNAL` | **immutable** |
| `status` | TEXT | enum CHECK | auto-recompute trigger |
| `session_affinity` | TEXT | `FIVE_TUPLE` \| `CLIENT_IP_ONLY` | default `FIVE_TUPLE` |
| `cross_zone_enabled` | BOOL | default `true` | |
| `deletion_protection` | BOOL | default `false` | sync precheck в Delete |
| `created_at` / `updated_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- PK `load_balancers_pkey (id)`
- Partial UNIQUE `(project_id, name) WHERE name <> ''` (GWT-DB-005)
- CHECK на name regex / labels valid / type enum / status enum / session_affinity
- GIN `labels_gin` (`jsonb_path_ops`) — для `labels @> '{...}'` фильтра
- Keyset index `(project_id, created_at DESC, id)`

## FK contract (in-bound)

- `listeners.load_balancer_id → load_balancers(id) ON DELETE RESTRICT`
- `attached_target_groups.load_balancer_id → load_balancers(id) ON DELETE RESTRICT`

→ Delete LB → `FailedPrecondition "load balancer has listeners"` или `"... has attached target groups"` (sync precheck до RESTRICT).

## Lifecycle (status state machine)

`INACTIVE → CREATING → INACTIVE → ACTIVE → STOPPING → STOPPED → STARTING → ACTIVE → DELETING`. Auto-recompute trigger `lb_status_recompute` (DB-side): `ACTIVE` если есть `listener` + `attached_target_group`, иначе `INACTIVE`. Триггер сохраняет explicit-transitions (CREATING/STARTING/STOPPING/STOPPED/DELETING).

## Gotchas

- `type` immutable после Create (`InvalidArgument`).
- `region_id` immutable (`InvalidArgument`); Move меняет только `project_id`.
- `Move` blocked если есть attached TG (`FailedPrecondition`).
- Outbox-event `nlb_load_balancer:<id> UPDATED` эмитится триггером recompute (D-13 stream).

## See also

[[../packages/nlb-domain]] [[../packages/nlb-repo-kacho-pg]] [[../rpc/nlb-network-load-balancer-service]] [[nlb-listener]] [[nlb-target-group]]

#resource #kacho-nlb #loadbalancer
