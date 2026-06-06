---
title: "kacho-vpc — ресурсы и RPC"
category: repo-doc
repo: kacho-vpc
tags:
  - kacho-vpc
  - resources
  - rpc
  - cqrs
---

# kacho-vpc — ресурсы и RPC

## 8 public ресурсов

### Network ([[README#Network]])

- ID prefix: `enp`
- Folder-level. `name` unique per folder (`networks_folder_id_name_key`).
- (Прежнее internal-only data-plane-id-поле удалено в KAC-36/79/80.)
- Inline default-SG creation при Create (управляется `KACHO_VPC_DEFAULT_SG_INLINE=true`). После KAC-94 — atomic в одной writer-TX через `CreateDefaultSGUseCase` composition.
- RPCs: `Get / List / Create / Update / Delete / ListOperations` (+ ListSubnets/SecurityGroups/RouteTables nav). `Move` удалён в [[../KAC/KAC-266]].

### Subnet

- ID prefix: `e9b`
- Belongs to Network + Zone. CIDR EXCLUDE constraint (no overlap within Network).
- Auto-association с RouteTable (DB-trigger, миграция 0019).
- RPCs: standard 7 + `AddCidrBlocks / RemoveCidrBlocks / Relocate / ListUsedAddresses`.
- Specifics: Relocate always returns FailedPrecondition "Invalid subnet state" (verbatim YC).

### Address

- ID prefix: `e9b`
- External / Internal IPv4 / Internal IPv6 (oneof spec).
- IPAM inline allocate в `address.go::doCreate` (раньше — отдельный `kacho-vpc-controllers`).
- RPCs: standard 7 + `GetByValue / ListBySubnet`.
- Cardinality on NIC: ≤ 1 v4 + ≤ 1 v6 (KAC-55).

### RouteTable

- ID prefix: `enp`
- Belongs to Network. StaticRoutes [].
- Auto-assoc с Subnet через PL/pgSQL триггеры (KAC-56).

### SecurityGroup

- ID prefix: `enp`
- Belongs to Network. Rules (Ingress/Egress, oneof source).
- OCC через Postgres `xmin::text` для UpdateRules (read-modify-write, zero-overhead).
- RPCs: standard 7 + `UpdateRules / UpdateRule`.
- Default SG auto-создаётся при Network.Create (см. [[#Network]]).

### Gateway

- ID prefix: `enp`
- Folder-level (НЕ привязан к Network — `shared_egress` scope).
- Strict-name `corevalidate.NameGateway` (lowercase only, no underscore — verbatim YC).
- Frozen scope: только `shared_egress` тип; `nat_egress` не реализован.

### PrivateEndpoint

- ID prefix: `enp`
- Belongs to Network + Subnet + опц. Address.
- Service-type: `object_storage` (single scope).
- FK на Network/Subnet/Address с ON DELETE RESTRICT (миграция 0024).

### NetworkInterface (NIC)

- ID prefix: `e9b` (reuse Subnet prefix)
- AWS-ENI-style first-class (вариант А KAC-2). НЕ встроена в Instance как в YC.
- Belongs to Subnet (FK ON DELETE RESTRICT).
- v4_address_ids[] / v6_address_ids[] cardinality ≤ 1 (CHECK constraint миграция 0018).
- security_group_ids[].
- mac_address — output-only, output-only, allocated by Kachō (prefix `0e:` + 40-bit), unique across cloud.
- used_by — denormalized Reference (`{compute_instance, <instance_id>}`). `AttachToInstance`/`DetachFromInstance` удалены ([[../KAC/KAC-266]] — инстанс без авто-NIC); `used_by_id` этими RPC больше не выставляется. CAS-история — KAC-52 (см. [[../resources/vpc-networkinterface]]).
- (Прежняя internal data-plane-проекция NIC — kube-ovn-эпоха — удалена в KAC-36/79/80.)

## 2 admin (internal-only)

### AddressPool

- ID prefix: `apl` (литерал, не из `ids.PrefixXxx`).
- **Global** (без folder_id). Один pool на всю установку для (zone_id, kind, family).
- Family-split (KAC-71): `v4_cidr_blocks` + `v6_cidr_blocks` отдельные fields.
- 3-step cascade resolve: `network_default → zone_default → global_default` (override + label-selector сняты в [[../KAC/KAC-266]]).
- DB-level: partial UNIQUE (zone_id, kind) WHERE is_default.

### AddressPoolBinding

- Per-network default binding (`BindAsNetworkDefault`). Per-address override удалён в [[../KAC/KAC-266]].

(`CloudPoolSelector` ресурс + `InternalCloudService` удалены в [[../KAC/KAC-266]].)

## Operation

- ID prefix: `enp` (== Network — это умышленно для api-gateway routing).
- Все мутации возвращают `*operation.Operation` (async LRO).
- Worker baggage-preserved (closes skill evgeniy I.3).

См. [[README]], [[dependencies]].

#kacho-vpc #resources #rpc #cqrs
