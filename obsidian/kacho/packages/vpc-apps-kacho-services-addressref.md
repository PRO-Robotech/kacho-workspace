---
title: vpc-apps-kacho-services-addressref
category: packages
repo: kacho-vpc
layer: service
tags:
  - packages
  - kacho-vpc
  - service
  - internal
  - ipam
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/services/addressref

**Каталог**: `services/vpc/internal/apps/kacho/services/addressref/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/services/addressref/`)
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
