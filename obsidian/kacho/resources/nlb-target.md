---
title: Target
aliases:
  - Target (nlb)
  - nlb Target
category: resource
domain: nlb
owner_table: kacho_nlb.targets
owner_db: kacho_nlb
folder_level: false
status: stable
related_rpc:
  - "[[rpc/nlb-target-group-service]]"
related_packages:
  - "[[packages/nlb-domain]]"
tags:
  - resource
  - kacho-nlb
  - target
---

# Target (nlb)

**Domain**: nlb
**ID prefix**: none (composite child of [[nlb-target-group|TargetGroup]])
**Owner table**: `kacho_nlb.targets`
**Folder-level**: no (через TG → Project)

## Fields (domain — 4-way oneof identity)

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | UUID-based |
| `target_group_id` | TEXT FK RESTRICT | |
| `instance_id` | TEXT NULL | (1) cross-service → compute.Instance |
| `nic_id` | TEXT NULL | (2) cross-service → vpc.NetworkInterface |
| `ip_ref_subnet_id` + `ip_ref_address` | TEXT NULL | (3) in-cloud raw IP в subnet |
| `external_ip_address` + `external_ip_zone_id` | TEXT NULL | (4) out-of-cloud raw IP |
| `weight` | INT | `0..1000`, default `100` |
| `status` | TEXT | `ACTIVE` \| `DRAINING` |
| `drain_started_at` | TIMESTAMPTZ NULL | NOT NULL когда `DRAINING` |

## 4-way oneof identity

`exactly-one` из: `instance_id` / `nic_id` / `(ip_ref_subnet_id + ip_ref_address)` / `(external_ip_address + external_ip_zone_id)`. DB CHECK `targets_identity_exactly_one` (GWT-DB-009) + `ip_ref_both_or_neither` + `external_ip_address_present` — defense-in-depth поверх domain.Target.Validate().

## External-IP bogon-check (sync)

Domain валидирует `external_ip.address` (sync, no peer-call):
- `127.0.0.0/8` loopback → InvalidArgument
- `169.254.0.0/16` link-local
- `224.0.0.0/4` multicast
- `::ffff:0:0/96` IPv4-mapped IPv6
- `unspecified` (`::` / `0.0.0.0`)

Public unicast — разрешено. Cross-service resolve НЕ выполняется (out-of-cloud).

## Cross-service resolve (worker)

- `instance_id` → `compute.InstanceService.Get` → primary NIC primary IP
- `nic_id` → `vpc.NetworkInterfaceService.Get` → primary IP
- `ip_ref` → `vpc.SubnetService.Get` + IP ∈ CIDR check
- `external_ip` → нет resolve, только bogon-check (sync)

См. [[../edges/nlb-to-vpc-nic-resolve]] [[../edges/nlb-to-compute-instance-resolve]] [[../edges/nlb-to-vpc-subnet-validation]].

## Constraints / indexes

- PK `targets_pkey`
- FK `target_group_id → target_groups(id) RESTRICT`
- CHECK identity-exactly-one (4-way)
- CHECK weight 0..1000, status enum, drain consistency (status=DRAINING ↔ drain_started_at NOT NULL)
- Partial UNIQUE NULLS NOT DISTINCT per identity-type (GWT-DB-008):
  - `(target_group_id, instance_id) WHERE instance_id IS NOT NULL`
  - `(target_group_id, nic_id) WHERE nic_id IS NOT NULL`
  - `(target_group_id, ip_ref_subnet_id, ip_ref_address) WHERE ip_ref_subnet_id IS NOT NULL`
  - `(target_group_id, external_ip_address, external_ip_zone_id) WHERE external_ip_address IS NOT NULL`
- Partial index `(target_group_id) WHERE status='DRAINING'` — для drain-runner scan

## Lifecycle

`ACTIVE` (default) → `DRAINING` (Phase A RemoveTargets) → `DELETE` (Phase B drain-runner after `deregistration_delay`).

`AddTargets` использует `INSERT ... ON CONFLICT DO NOTHING` per identity-key — idempotent.

## See also

[[nlb-target-group]] [[../packages/nlb-domain]] [[../edges/nlb-to-vpc-nic-resolve]] [[../edges/nlb-to-compute-instance-resolve]]

#resource #kacho-nlb #target
