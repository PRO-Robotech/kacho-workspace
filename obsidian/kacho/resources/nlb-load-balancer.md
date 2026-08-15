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
project_level: true
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
verified_against: "ствол redesign/integration, сверено 2026-08-05"
---

> [!note] Сверка со стволом (2026-08-05)
> Контракт — `proto/kacho/cloud/loadbalancer/v1/network_load_balancer.proto`, схема —
> `services/nlb/internal/migrations/` (двадцать девять миграций). Описание выше сверено и
> **соответствует** дереву: `placement` как единственный авторитетный вход режима (0017),
> `admin_state` вместо снятых `:start`/`:stop` (0016), `vip_origin_v4/v6` со значением
> `linked` вместо прежнего `byo` (0011), `security_group_ids` (0020), партийные UNIQUE на
> VIP в регионе с самолечением прерванного `CONCURRENTLY`-построения (0012).
>
> Что стоит держать в голове при чтении proto: у `NetworkLoadBalancer` **много
> зарезервированных слотов**, и часть имён вернулась под другими номерами. Так,
> `cross_zone_enabled` жив полем 42, а не слотом 19 (тот зарезервирован); `security_group_ids`
> — поле 43. Слоты 30–39 отложены под будущий составной слой. Из `enum Status` вычеркнуты
> `STARTING`/`STOPPING`/`STOPPED` вместе с глаголами старта и остановки.
>
> **Привязка групп таргетов ушла с балансировщика на слушателя**: слот 13
> (`attached_target_groups`) зарезервирован, авторитетная ссылка — `Listener.target_group_id`
> (миграции `0018_listener_target_group_direct_fk.sql`,
> `0022_drop_attached_tg_pivot_and_transitional_statuses.sql`,
> `0023_listener_target_group_same_project_fk.sql`). Таблица-связка дропнута.

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
| `region_id` | TEXT NOT NULL | cross-service ref → geo.Region | sync `RegionService.Get`, **immutable** |
| `name` | TEXT | DNS-1123 regex `^[a-z]([-a-z0-9]{1,61}[a-z0-9])?$` | partial UNIQUE per project |
| `description` | TEXT | `<=256` chars | |
| `labels` | JSONB | `kacho_labels_valid` (≤64 pairs) | CHECK constraint inline |
| `placement` | TEXT | `EXTERNAL_REGIONAL` \| `INTERNAL_REGIONAL` \| `INTERNAL_ZONAL` | **единственный authoritative input режима**, immutable |
| `type` | TEXT | `EXTERNAL` \| `INTERNAL` | derived из `placement`, output-only (запись → InvalidArgument) |
| `placement_type` | TEXT | `ZONAL` \| `REGIONAL` \| `''` (EXTERNAL) | derived из `placement`, output-only; CHECK связывает с `type` |
| `address_v4` / `address_v6` | TEXT | резолвленный VIP-IP | **не выходит на публичный wire** |
| `address_id_v4` / `address_id_v6` | TEXT | cross-service ref → vpc.Address | на wire как `v4AddressId°`/`v6AddressId°` |
| `vip_origin_v4` / `vip_origin_v6` | TEXT | `''` \| `auto` \| `linked` (CHECK) | дискриминатор release-ветки; internal-only |
| `ip_families` | TEXT[] | `IPV4`/`IPV6` | заявленные семейства; CHECK «непустой address ⟹ семейство объявлено» |
| `admin_state` | TEXT | `ENABLED` \| `DISABLED` | LIVE-mutable; заменяет `:start`/`:stop` |
| `disabled_announce_zones` | TEXT[] | зоны ∈ регион | REGIONAL-only (CHECK) |
| `status` | TEXT | enum CHECK | auto-recompute trigger |
| `session_affinity` | TEXT | `FIVE_TUPLE` \| `CLIENT_IP_ONLY` | default `FIVE_TUPLE` |
| `cross_zone_enabled` | BOOL | default `true` | |
| `deletion_protection` | BOOL | default `false` | sync precheck в Delete |
| `created_at` / `updated_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- PK `load_balancers_pkey (id)`
- Partial UNIQUE `(project_id, name) WHERE name <> ''` (GWT-DB-005)
- **Partial UNIQUE `(region_id, address_v4) WHERE address_v4 <> ''`** + v6-близнец — VIP-уникальность
  в регионе на семейство. Строятся `CONCURRENTLY`; миграция `0012` — self-heal INVALID-остатка +
  assert валидности (прерванный `CONCURRENTLY`-build оставил бы индекс, который молча не энфорсит)
- Partial `load_balancers_reconcile_idx (updated_at) WHERE status IN ('CREATING','DELETING')` — скан
  застрявших handle'ов free-ip-reconciler'ом
- CHECK на name regex / labels valid / type enum / status enum / session_affinity
- GIN `labels_gin` (`jsonb_path_ops`) — для `labels @> '{...}'` фильтра
- Keyset index `(project_id, created_at DESC, id)`

## VIP — якорь здесь, не на листенере

Один `vpc.Address` на семейство на весь LB; листенеры делят его. Источник — **per-family input на
Create** (`v4_source`/`v6_source`, `VipSource` oneof: `subnet_id` auto-alloc INTERNAL | `public {}`
auto-alloc EXTERNAL | `address_id` link), immutable, в ответе не эхается. Наружу идёт только
`v4AddressId°`/`v6AddressId°`. Полный flow acquire/release — [[../edges/nlb-to-vpc-vip-allocation]].

Within-service инварианты (ban #10, оба на DB):

- **single-VIP-per-LB** — `AttachVIP` CAS: `UPDATE … WHERE id=$1 AND (address_v4='' OR address_v4=$2)
  RETURNING`; 0 rows → `FailedPrecondition "load balancer already has an address for this family"`;
  повтор того же адреса — no-op (retry идемпотентен).
- **один адрес на (регион, семейство)** — partial UNIQUE выше; 23505 → **generic**
  `FailedPrecondition "could not assign address to load balancer"` (анти-oracle: владельца адреса не раскрываем).

**Placement-coherence источника** (sync, ДО Operation): `placement_type` подсети == `placement_type` LB;
подсеть region-coherent; dualstack — одна сеть и (для ZONAL) одна зона. Отдельного `zone_id` у LB нет —
зона ZONAL-LB задана подсетью VIP-источника, поэтому order-dependence отсутствует by construction.
Через `address_id`-линк любой mismatch сворачивается в анти-oracle `InvalidArgument "Illegal argument addressId"`.

## FK contract (in-bound)

- `listeners.load_balancer_id → load_balancers(id) ON DELETE RESTRICT`
(Pivot `attached_target_groups` снят миграцией `0022` — TG привязывается через `Listener.target_group_id`.)

→ Delete LB → `FailedPrecondition` со списком блокирующих листенеров (sync precheck до RESTRICT);
только после их удаления Delete доходит до release VIP.

## Lifecycle (status state machine)

Legacy explicit path (present до CONTRACT): `CREATING → INACTIVE → ACTIVE → STOPPING → STOPPED → STARTING → DELETING`.

**Auto-recompute trigger `lb_status_recompute` (DB-side) — NLB-1b F3 глоссарий (миграция 0023, @1887f3c):**
- `DISABLED` ⟺ `admin_state=DISABLED` (админ-выключен, конфиг цел; feed через `AFTER UPDATE OF admin_state`-триггер);
- `INACTIVE` ⟺ enabled ∧ нет listeners;
- `DEGRADED` ⟺ enabled ∧ ≥1 listener с пустым `default_target_group_id` (misconfigured, не маскируется под ACTIVE);
- `ACTIVE` ⟺ enabled ∧ ≥1 listener ∧ **каждый** резолвит `targetGroupId` (direct FK, НЕ pivot `attached_target_group`).

CAS-guard сохраняет explicit-transitions (CREATING/STARTING/STOPPING/STOPPED/DELETING) и не делает never-auto-ENABLE. Recompute-eligible set: `{INACTIVE,ACTIVE,DEGRADED,DISABLED}`. (AS-IS `has_attached`-pivot gate удалён из ACTIVE — 0013→0023.)

## Gotchas

- Режим задаётся **только** `placement`; передача `type`/`placement_type` на Create → `InvalidArgument "<field> is derived output-only; the load balancer mode is set solely by placement"`.
- Сам VIP-IP (`address_v4/_v6`) на публичный wire **не выходит** — наружу только `v4AddressId°`/`v6AddressId°`; IP тенант читает у владельца (`vpc.AddressService.Get`). Так же скрыты `vip_origin`, derived network, underlay-зона.
- VIP-конфликт — **не** `ALREADY_EXISTS`, а generic `FAILED_PRECONDITION` (анти-oracle).
- `region_id` immutable (`InvalidArgument`); Move меняет только `project_id`.
- `Move` blocked если есть attached TG (`FailedPrecondition`).
- Outbox-event `nlb_load_balancer:<id> UPDATED` эмитится триггером recompute (D-13 stream).

## See also

[[../packages/nlb-domain]] [[../packages/nlb-repo-kacho-pg]] [[../rpc/nlb-network-load-balancer-service]] [[nlb-listener]] [[nlb-target-group]] [[../edges/nlb-to-vpc-vip-allocation]]

#resource #kacho-nlb #loadbalancer
