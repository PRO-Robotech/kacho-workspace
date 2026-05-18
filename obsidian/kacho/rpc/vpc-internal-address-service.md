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
---

# InternalAddressService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/internal_address_service.proto`
**Backend**: `kacho-vpc:9091` (internal-port)
**Public/Internal**: **cluster-internal-only** (не на TLS edge, см. CLAUDE.md «Запреты» #6)

IPAM allocate-API для **эфемерных** адресов + reference-management. Вызывается compute (NIC primary IP), NLB (target-binding), api-gateway-restmux только на internal-listener.

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

## See also

[[../packages/vpc-apps-kacho-services-addressref]] [[vpc-address-service]] [[../resources/vpc-address]]

#rpc #kacho-vpc #internal #ipam
