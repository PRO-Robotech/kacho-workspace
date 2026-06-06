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

KAC-2 эпик (control-plane resource model) ввёл writeback из vpc-implement: после программирования инфра-слоя agent сообщал vpc инфра-состояние NI через `ReportNiDataplane`.

После **KAC-36/79/80 (purge инфра-control-plane-слоя)**:
- Миграция **0023** удалила все инфра-колонки из `network_interfaces` (см. [[../resources/vpc-networkinterface]]).
- RPC `ReportNiDataplane` исчез вместе с ними.
- Сервис `InternalNetworkInterfaceService` в proto не commit'нут (см. [[../rpc/vpc-internal-network-interface-service]]).

## Current state

Это ребро **удалено**. `kacho-vpc-implement` — spec-only data-plane sibling вне build-графа; прежняя control-plane-привязка к kacho-vpc (writeback NI-состояния) не действует. Control-plane его не касается.

## See also

[[../rpc/vpc-internal-network-interface-service]] [[../resources/vpc-networkinterface]]

#edge #cross-service #kacho-vpc #kacho-vpc-implement #deprecated
