---
title: NetworkInterface
aliases:
  - NetworkInterface (vpc)
  - NIC
  - vpc NetworkInterface
category: resource
domain: vpc
id_prefix: enp
owner_table: kacho_vpc.network_interfaces
owner_db: kacho_vpc
folder_level: true
status: stable
related_rpc:
  - "[[rpc/vpc-networkinterface-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-networkinterface]]"
related_edges:
  - "[[edges/compute-to-vpc-nic-validate]]"
related_tickets:
  - "[[KAC/KAC-94]]"
tags:
  - resource
  - kacho-vpc
  - ni
  - ni
---

# NetworkInterface (NIC)

**Domain**: vpc
**ID prefix**: `enp` (KAC-2 первый-класс)
**Owner table**: `kacho_vpc.network_interfaces`
**Folder-level**: yes

NIC — first-class ресурс в Kachō (расходимся со YC, где NIC inline в Instance). Owner = vpc, consumer = compute. См. эпик KAC-2.

## Fields (после 0023 — без data-plane)

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | |
| `project_id` | TEXT | |
| `subnet_id` | TEXT | FK → subnets(id) RESTRICT (0012 → inline в baseline 0001) |
| `network_id` | TEXT | derived from subnet |
| `name`, `description`, `labels` | | |
| `security_group_ids` | JSONB array | |
| `mac_address` | TEXT | auto-generate (0014 → inline в baseline 0001) или explicit |
| `primary_v4_address` / `primary_v6_address` | TEXT | IP-аллокация через [[../rpc/vpc-internal-address-service]] |
| `address_ids` | JSONB | связанные Address ресурсы (cardinality 0018) |
| `used_by_id` | TEXT | `'' \| instance-id` — CAS-protected attach/detach |
| `used_by_kind` | TEXT | `instance` (на момент индексации) |

(Бывшие data-plane поля `hv_id`, `sid`, `sid_seq`, `host_iface`, `netns`, `gateway_ip`, `container_id`, `dataplane_revision`, `status_error`, `dataplane_updated_at` — **удалены до squash** (historical migration 0023, теперь baseline просто без этих полей) post-kube-ovn.)

## Attach race (CAS, KAC-52)

```sql
UPDATE network_interfaces
   SET used_by_id = $new_instance_id, used_by_kind = 'instance'
 WHERE id = $ni_id
   AND (used_by_id = '' OR used_by_id = $new_instance_id)
RETURNING ...;
```

0 rows → `FailedPrecondition`. Single-statement → row-level lock в Postgres защищает concurrent writers. Миграция 0016 пыталась добавить `UNIQUE(used_by_id) WHERE used_by_id <> ''` — оказалось семантически неверно (multi-NIC instance), откачена 0017.

## FK contract

- `network_interfaces.subnet_id → subnets(id) ON DELETE RESTRICT` (0012, после 0011 cascade).
- Address-cardinality CHECK (0018 → inline в baseline 0001).
- MAC (0014 → inline в baseline 0001).

## Lifecycle

DETACHED (`used_by_id=''`) ↔ ATTACHED (`used_by_id=<instance>`). Delete → FailedPrecondition если attached.

## Gotchas

- compute должен **сначала** вызвать `AttachToInstance` через vpc, **потом** проводить compute-side. См. [[../edges/compute-to-vpc-nic-validate]].
- Address с `used_by={kind=ni, id=<ni-id>}` — внутренние IP NIC'а.


> [!note] После KAC-111 (squash migrations)
> Specific migration numbers (0001–0034) свёрнуты в single baseline `0001_initial.sql`.
> Ссылки на исторические migration N сохраняются как archeology, но физически их нет —
> весь финальный state в `internal/migrations/0001_initial.sql` (kacho-vpc PR #97).

## See also

[[../packages/vpc-apps-kacho-api-networkinterface]] [[../rpc/vpc-networkinterface-service]] [[../edges/compute-to-vpc-nic-validate]]

#resource #vpc #ni #nic
