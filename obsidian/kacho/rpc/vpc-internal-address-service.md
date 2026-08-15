---
title: InternalAddressService
aliases:
  - InternalAddressService (vpc)
proto_file: kacho/cloud/vpc/v1/internal_address_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
related_resource: "[[resources/vpc-address]]"
methods_count: 7
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - ipam
verified_against: "перечень RPC сверен с proto ствола redesign/integration в ОБЕ стороны 2026-08-05 (методы контракта против методов записки); координата логики аллокации пересверена с деревом продукта 1653387b (2026-08-06); поля запросов и семантика построчно не пересматривались"
status: stable
---

# InternalAddressService (vpc)

**Proto**: `proto/kacho/cloud/vpc/v1/internal_address_service.proto`
**Backend**: `kacho-vpc:9091` (internal-port)
**Public/Internal**: **cluster-internal-only** (не на TLS edge, см. CLAUDE.md «Запреты» #6)

IPAM allocate-API для **эфемерных** адресов + reference-management. Сама логика аллокации IP — **in-process в kacho-vpc** (request-path,
`services/vpc/internal/apps/kacho/api/address/allocate.go` +
`services/vpc/internal/apps/kacho/api/address/alloc_shared.go`; нет отдельного
data-plane/IPAM-сервиса). Прежняя координата называла файл под плоским слоем сервисов —
такой раскладки у vpc нет: use-case'ы лежат по ресурсу под `apps/kacho/api/`. Этот gRPC `InternalAddressService`-endpoint — лишь cluster-internal-фасад над той же in-process логикой, **потребляется compute** (NIC primary IP, см. [[../edges/compute-to-vpc-nic-validate]]), NLB (target-binding), api-gateway-restmux только на internal-listener.

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| AllocateInternalIP | AllocateInternalIPRequest | AllocateIPResponse | sync | IPAM из Subnet (v4) |
| AllocateInternalIPv6 | AllocateInternalIPRequest | AllocateIPResponse | sync | IPAM из Subnet (v6) |
| AllocateExternalIP | AllocateExternalIPRequest | AllocateIPResponse | sync | IPAM из AddressPool |
| SetAddressReference | SetAddressReferenceRequest | AddressReference | sync | mark `used_by={id,kind}` — **CAS** |
| ClearAddressReference | ClearAddressReferenceRequest | ClearAddressReferenceResponse | sync | release reference |
| GetAddressReference | GetAddressReferenceRequest | AddressReference | sync | inspect used_by |
| MarkAddressEphemeralInUse | MarkAddressEphemeralInUseRequest | MarkAddressEphemeralInUseResponse | sync | для compute NIC flow |

## REST mapping

Internal-mux пробрасывает на `/vpc/v1/internalAddresses:*` (только cluster-internal listener). См. [[../edges/apigw-internal-vs-tls]].


## Сверка со стволом (2026-08-05)

В контракте `proto/kacho/cloud/vpc/v1/internal_address_service.proto` — **восемь** RPC.
**Не был назван в записке**: `AllocateExternalIPv6` — внешний v6 выделяется отдельным
глаголом, как и внутренний (`AllocateInternalIP` / `AllocateInternalIPv6`), а не флагом
семейства в одном запросе.

Полный набор: `AllocateInternalIP`, `AllocateInternalIPv6`, `AllocateExternalIP`,
`AllocateExternalIPv6`, `SetAddressReference`, `ClearAddressReference`,
`GetAddressReference`, `MarkAddressEphemeralInUse`.

`AllocateIPResponse` несёт `already_allocated` — идемпотентность повтора выражена **полем
ответа**, а не молчаливым «как будто выделили заново».

`SetAddressReferenceRequest` несёт `owned`: `true` — ссылающийся владеет адресом
(освобождение = снять ссылку **и** удалить адрес), `false` (умолчание) — тенант создал
адрес заранее и лишь залинковал (освобождение = только снять ссылку). Колонка
`address_references.owned` заведена миграцией `0013_address_reference_owned.sql`.

## See also

[[../packages/vpc-apps-kacho-services-addressref]] [[vpc-address-service]] [[../resources/vpc-address]]

#rpc #kacho-vpc #internal #ipam
