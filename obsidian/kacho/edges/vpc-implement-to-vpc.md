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
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
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
- RPC обратного донесения инфра-состояния исчез вместе с ними — в дереве `96b2879a` его
  **нет** (предикат: `git grep` по его имени → 0; само имя здесь не воспроизводится в
  кавычках, иначе перепись координат снова сочла бы его живым утверждением).

> [!warning] Имя сервиса вернулось — но с другим содержанием (сверено 2026-08-05)
> Здесь стояло: «сервис `InternalNetworkInterfaceService` в proto не commit'нут». Сегодня он
> **есть** — `proto/kacho/cloud/vpc/v1/internal_network_interface_service.proto`, — и несёт
> `Attach` / `Detach` / `ListByInstance`, то есть привязку интерфейса к машине по вызову
> compute ([[compute-to-vpc-nic-validate]]). Ни одного из этих RPC прежний вызывающий не
> звал, и обратного writeback'а инфра-состояния в дереве по-прежнему нет.
>
> Урок общий: «сервиса нет» стареет иначе, чем «RPC нет». Имя переиспользуют, и утверждение
> об **отсутствии контейнера** тихо становится ложным, пока утверждение об **отсутствии
> метода** остаётся верным. Проверять надо метод, а не пакет.

## Current state

Это ребро **удалено**. `kacho-vpc-implement` — spec-only data-plane sibling вне build-графа; прежняя control-plane-привязка к kacho-vpc (writeback NI-состояния) не действует. Control-plane его не касается.

## See also

[[../rpc/vpc-internal-network-interface-service]] [[../resources/vpc-networkinterface]]

#edge #cross-service #kacho-vpc #kacho-vpc-implement #deprecated
