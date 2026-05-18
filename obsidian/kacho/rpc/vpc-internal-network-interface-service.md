---
title: InternalNetworkInterfaceService
aliases:
  - InternalNetworkInterfaceService (vpc)
  - Internal NIS
proto_file: kacho/cloud/vpc/v1/internal_network_interface_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
status: deprecated
related_resource: "[[resources/vpc-networkinterface]]"
methods_count: 0
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - deprecated
---

# InternalNetworkInterfaceService (vpc)

**Proto**: **deprecated / removed** — больше не нужен.
**Backend**: `kacho-vpc:9091` (если бы был)

Раньше (KAC-2) — internal-projection NetworkInterface с data-plane полями (`sid`, `sid_seq`, `hv_id`, `host_iface`, `netns`, `gateway_ip`, `container_id`, `dataplane_revision`) + writeback-RPC `ReportNiDataplane` из vpc-implement.

## Status (после KAC-79/KAC-36)

Underlay управляется **kube-ovn**, не vpc-implement. Миграция **0023** (`drop_network_vpn_id_and_ni_dataplane`) убрала data-plane колонки из `network_interfaces`. Сервис `ReportNiDataplane` исчез вместе с ними. NIC в публичном API остаётся, но инфра-проекции больше нет.

## See also

[[vpc-networkinterface-service]] [[../resources/vpc-networkinterface]] [[../edges/vpc-implement-to-vpc]]

## See also

[[vpc-networkinterface-service]] [[../resources/vpc-networkinterface]] [[../edges/vpc-implement-to-vpc]]

#rpc #kacho-vpc #internal #planned
