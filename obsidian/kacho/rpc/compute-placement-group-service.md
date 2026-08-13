---
title: PlacementGroupService (compute)
aliases:
  - PlacementGroupService
proto_file: kacho/cloud/compute/v1/placement_group_service.proto
category: rpc
backend: kacho-compute
backend_port: 9090
visibility: public
domain: compute
related_resource: "[[resources/compute-placementgroup]]"
methods_count: 6
async_methods: 3
status: done
verified_against: "ветка release/compute-production-api @ 451a56cd, сверено 2026-08-13"
tags:
  - rpc
  - kacho-compute
  - compute
  - done
---

# PlacementGroupService

Правила взаимного размещения машин.

| RPC | REST | Форма | Право |
|---|---|---|---|
| `Get` | `GET /compute/v1/placementGroups/{id}` | sync | `v_get` @ группа |
| `List` | `GET /compute/v1/placementGroups` | sync | `viewer` @ проект |
| `Create` | `POST /compute/v1/placementGroups` | операция | `editor` @ проект |
| `Update` | `PATCH /compute/v1/placementGroups/{id}` | операция | `v_update` @ группа |
| `Delete` | `DELETE /compute/v1/placementGroups/{id}` | операция | `v_delete` @ группа |
| `ListOperations` | `GET …/{id}/operations` | sync | `v_list` @ группа |

**Правка меняет имя, описание и метки.** Стратегия и якорь размещения НЕИЗМЕНЯЕМЫ: смена
любого из них поменяла бы смысл размещения уже стоящих машин, а перекладывать их задним
числом продукт не будет. Нужна другая стратегия — заводится другая группа.

**Координата якоря подтверждается у владельца Geography** на пути запроса: зона — у службы
зон, регион — у службы регионов, fail-closed на недоступности.

Ресурс и его инварианты — [[resources/compute-placementgroup]]. Задача — [[KAC/issue-158]].
