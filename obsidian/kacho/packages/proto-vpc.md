---
title: proto-vpc
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - kacho-vpc
---

# proto/vpc

**Path**: `kacho-proto/proto/kacho/cloud/vpc/v1/`
**Package**: `kacho.cloud.vpc.v1`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/vpc/v1`
**Owner service**: [[../README#kacho-vpc|kacho-vpc]]

## Resource protos

- `network.proto` — [[../resources/vpc-network|Network]]
- `subnet.proto` — [[../resources/vpc-subnet|Subnet]]
- `address.proto` — [[../resources/vpc-address|Address]]
- `route_table.proto` — [[../resources/vpc-routetable|RouteTable]]
- `security_group.proto` — [[../resources/vpc-securitygroup|SecurityGroup]]
- `gateway.proto` — [[../resources/vpc-gateway|Gateway]]
- `private_endpoint.proto` — [[../resources/vpc-privateendpoint|PrivateEndpoint]]
- `network_interface.proto` — [[../resources/vpc-networkinterface|NetworkInterface]]

## Service protos (public)

- [[../rpc/vpc-network-service]] — `network_service.proto`
- [[../rpc/vpc-subnet-service]] — `subnet_service.proto`
- [[../rpc/vpc-address-service]] — `address_service.proto`
- [[../rpc/vpc-routetable-service]] — `route_table_service.proto`
- [[../rpc/vpc-securitygroup-service]] — `security_group_service.proto`
- [[../rpc/vpc-gateway-service]] — `gateway_service.proto`
- [[../rpc/vpc-privateendpoint-service]] — `private_endpoint_service.proto`
- [[../rpc/vpc-networkinterface-service]] — `network_interface_service.proto`

## Service protos (Internal — admin / cluster-internal only)

- [[../rpc/vpc-internal-address-service]] — `internal_address_service.proto` (IPAM allocate ephemeral)
- [[../rpc/vpc-internal-address-pool-service]] — `internal_address_pool_service.proto` (AddressPool CRUD)
- [[../rpc/vpc-internal-network-service]] — `internal_network_service.proto` (full Network с `vpn_id`)
- [[../rpc/vpc-internal-cloud-service]] — `internal_cloud_service.proto` (cloud-level admin)
- [[../rpc/vpc-internal-watch-service]] — `internal_watch_service.proto` (LISTEN/NOTIFY stream; deprecated с 1.0)

> [!warning] Внимание
> Internal NIS (ReportNiDataplane) — **в proto ещё нет** (KAC-2 в работе). См. CLAUDE.md.

## Shared

- `package_options.proto` — `option go_package = "...";` для всех файлов.
- `privatelink/` — sub-package для будущих PE-extensions (zonal endpoints).

#proto #kacho-vpc
