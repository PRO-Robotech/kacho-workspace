---
title: Gateway
aliases:
  - Gateway (vpc)
  - vpc Gateway
category: resource
domain: vpc
id_prefix: enp
owner_table: kacho_vpc.gateways
owner_db: kacho_vpc
folder_level: true
status: stable
related_rpc:
  - "[[rpc/vpc-gateway-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-gateway]]"
tags:
  - resource
  - kacho-vpc
  - gateway
---

# Gateway

**Domain**: vpc
**ID prefix**: `enp` (общий VPC prefix)
**Owner table**: `kacho_vpc.gateways`
**Folder-level**: yes

## Fields

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | |
| `project_id` | TEXT | |
| `name`, `description`, `labels` | | |
| `type` | enum | `SHARED_EGRESS_GATEWAY` (только tier-1 на момент индексации) |
| `shared_egress_gateway` | nested JSONB | type-specific config |

CHECK (0030).

## FK (in-bound)

- `route_tables.static_routes[].gateway_id → gateways(id)` — валидируется в pre-update SQL (JSONB), не строгий FK.

## Gotchas

- Delete Gateway → FailedPrecondition если используется в RouteTable static_route.
- Cross-folder/cross-project **Move удалён** в [[KAC-266]] (RPC `GatewayService.Move` снят).

## See also

[[../packages/vpc-apps-kacho-api-gateway]] [[../rpc/vpc-gateway-service]] [[vpc-routetable]]

#resource #vpc #gateway
