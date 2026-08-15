---
title: vpc-apps-kacho-services-networkinternal
category: packages
repo: kacho-vpc
layer: service
tags:
  - packages
  - kacho-vpc
  - service
  - internal
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/services/networkinternal

**Каталог**: `services/vpc/internal/apps/kacho/services/networkinternal/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/services/networkinternal/`)
**Implements**: [[../rpc/vpc-internal-network-service|InternalNetworkService]] (SetDefaultSecurityGroupId).

Internal admin для Network — admin/admin-UI only. Сейчас тонкий — один RPC. Прежние data-plane-id-related RPC'ы (kube-ovn-эпоха) удалены в KAC-36/79/80 (см. миграция 0023).

## Files

- `service.go` — `SetDefaultSecurityGroupId` use-case.

## See also

[[../rpc/vpc-internal-network-service]] [[../resources/vpc-network]] [[../resources/vpc-securitygroup]]

#packages #kacho-vpc #service #internal
