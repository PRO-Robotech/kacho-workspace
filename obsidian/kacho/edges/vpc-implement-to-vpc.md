---
title: "vpc-implement → vpc: ReportNiDataplane (deprecated)"
aliases:
  - vpc implement to vpc
category: edge
caller_repo: kacho-vpc-implement
callee_repo: kacho-vpc
sync_async: async
protocol: grpc-cluster-internal
status: deprecated
tags:
  - edge
  - cross-service
  - kacho-vpc
  - kacho-vpc-implement
  - deprecated
---

# vpc-implement → vpc: ReportNiDataplane (DEPRECATED)

**Caller**: `kacho-vpc-implement` (impl-controller / per-node agent)
**Callee**: `kacho-vpc` (`InternalNetworkInterfaceService.ReportNiDataplane`)
**Protocol**: gRPC cluster-internal
**Status**: **deprecated/removed** — больше не используется

## History

KAC-2 эпик (control-plane resource model) ввёл writeback из vpc-implement: после программирования SRv6 data-plane (`hv_id`, `sid_seq`, `host_iface`, `netns`, `gateway_ip`, `container_id`, `status`) agent сообщал vpc через `ReportNiDataplane`.

После **KAC-36/79/80 (purge kube-ovn-эпохи data-plane control-plane-слоя)**:
- Миграция **0023** удалила все data-plane колонки из `network_interfaces` (см. [[../resources/vpc-networkinterface]]).
- RPC `ReportNiDataplane` исчез вместе с ними.
- Сервис `InternalNetworkInterfaceService` в proto не commit'нут (см. [[../rpc/vpc-internal-network-interface-service]]).

## Current state

Это ребро **удалено**. Будущий SRv6 data-plane (`kacho-vpc-implement`) — spec-only: networking-дизайн остаётся в `docs/specs/09-implementation-strategy.md` (зафиксированный план), но прежняя control-plane-привязка к kacho-vpc (writeback NI-состояния) не действует.

## See also

[[../rpc/vpc-internal-network-interface-service]] [[../resources/vpc-networkinterface]]

#edge #cross-service #kacho-vpc #kacho-vpc-implement #deprecated
