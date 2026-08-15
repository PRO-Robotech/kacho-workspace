---
title: vpc-apps-kacho-api-routetable
category: packages
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - routetable
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/api/routetable

**Каталог**: `services/vpc/internal/apps/kacho/api/routetable/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/api/routetable/`)
**Implements**: [[../rpc/vpc-routetable-service|RouteTableService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | static_routes validation (next_hop_address vs gateway_id) |
| `create.go` | network FK check; auto-association (миграция 0019) |
| `update.go` | replace static_routes; gateway_id validate |
| `delete.go` | FailedPrecondition если subnet ссылается |
| `get.go` | |
| `list.go` | |
| `move.go` | cross-folder |
| `usecase_test.go` | |

## See also

[[../rpc/vpc-routetable-service]] [[../resources/vpc-routetable]] [[vpc-apps-kacho-api-gateway]]

#packages #kacho-vpc #handler #routetable
