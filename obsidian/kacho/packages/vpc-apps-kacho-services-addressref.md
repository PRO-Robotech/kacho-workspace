---
title: vpc-apps-kacho-services-addressref
category: package
repo: kacho-vpc
layer: service
tags:
  - packages
  - kacho-vpc
  - service
  - internal
  - ipam
---

# kacho-vpc/internal/apps/kacho/services/addressref

**Path**: `kacho-vpc/internal/apps/kacho/services/addressref/`
**Implements**: subset of [[../rpc/vpc-internal-address-service|InternalAddressService]] (SetAddressReference, ClearAddressReference, GetAddressReference, MarkAddressEphemeralInUse).

Внутренний сервис управления `used_by` ссылками Address — IPAM-side. Вызывается из:
- compute NIC bind/unbind ([[../edges/compute-to-vpc-nic-validate]])
- NLB target binding (когда NLB-сервис появится)
- internal vpc-handlers (PE.Create bind address)

## Files

- `service.go` — реализация use-cases.
- `service_test.go` — unit-тесты против [[vpc-repo-kacho-kachomock]].

## CAS pattern

Все mutate-методы — single-statement conditional UPDATE с CAS на `used_by` (см. CLAUDE.md «Запреты» #10 + within-service refs). Concurrent SetAddressReference → second получает FailedPrecondition.

## See also

[[../rpc/vpc-internal-address-service]] [[../resources/vpc-address]] [[../edges/compute-to-vpc-nic-validate]]

#packages #kacho-vpc #service #internal #ipam
