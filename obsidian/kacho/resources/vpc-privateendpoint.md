---
title: PrivateEndpoint
aliases:
  - PrivateEndpoint (vpc)
  - vpc PrivateEndpoint
  - PE
category: resource
domain: vpc
id_prefix: enp
owner_table: kacho_vpc.private_endpoints
owner_db: kacho_vpc
folder_level: true
status: stable
related_rpc:
  - "[[rpc/vpc-privateendpoint-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-privateendpoint]]"
tags:
  - resource
  - kacho-vpc
  - privateendpoint
  - privatelink
---

# PrivateEndpoint

**Domain**: vpc
**ID prefix**: `enp` (общий VPC prefix)
**Owner table**: `kacho_vpc.private_endpoints`
**Folder-level**: yes (через Subnet → Network → Folder)

## Fields

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | |
| `project_id` | TEXT | |
| `subnet_id` | TEXT | FK → subnets(id) RESTRICT |
| `address_id` | TEXT | FK → addresses(id) RESTRICT (0024) |
| `name`, `description`, `labels` | | |
| `service_kind` | enum | object-storage, container-registry, ... (Kachō-only список) |

## FK contract (0024 private_endpoint_fks)

- `private_endpoints.subnet_id → subnets(id) ON DELETE RESTRICT`.
- `private_endpoints.address_id → addresses(id) ON DELETE RESTRICT` — нельзя удалить Address, пока есть PE.

См. `private_endpoint_fk_integration_test.go`.

## Lifecycle

PROVISIONING → ACTIVE (sync — после bind address) → DELETING. State enum в proto, но в БД может быть упрощённо.

## See also

[[../packages/vpc-apps-kacho-api-privateendpoint]] [[../rpc/vpc-privateendpoint-service]] [[vpc-address]] [[vpc-subnet]]

#resource #vpc #privateendpoint #privatelink
