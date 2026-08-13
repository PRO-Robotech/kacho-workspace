---
title: InstanceService
aliases:
  - InstanceService (compute)
  - compute InstanceService
proto_file: kacho/cloud/compute/v1/instance_service.proto
category: rpc
backend: kacho-compute
backend_port: 9090
visibility: public
domain: compute
related_resource: "[[resources/compute-instance]]"
methods_count: 23
async_methods: 17
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
tags:
  - rpc
  - kacho-compute
  - compute
---

# InstanceService (compute)

**Контракт**: `proto/kacho/cloud/compute/v1/instance_service.proto`
**Backend**: сервис `kacho-compute`, публичный листенер **:9090**
**Ресурс**: [[../resources/compute-instance]]

Записка заведена 2026-08-05: до этого на неё ссылались две записки ресурсов, а самой её
не существовало.

## Методы (сверено по proto — RPC, ответ, REST, отношение)

| Метод | Ответ | Sync/Async | REST |
|---|---|---|---|
| `Get` | `Instance` | sync | `GET /compute/v1/instances/{instance_id}` |
| `List` | `ListInstancesResponse` | sync | `GET /compute/v1/instances` |
| `Create` | `Operation` | async | `POST /compute/v1/instances` |
| `Update` | `Operation` | async | `PATCH /compute/v1/instances/{instance_id}` |
| `Delete` | `Operation` | async | `DELETE /compute/v1/instances/{instance_id}` |
| `UpdateMetadata` | `Operation` | async | `POST …/{id}/updateMetadata` |
| `GetSerialPortOutput` | `GetInstanceSerialPortOutputResponse` | sync | `GET …/{id}:serialPortOutput` |
| `Stop` / `Start` / `Restart` | `Operation` | async | `POST …/{id}:stop` \| `:start` \| `:restart` |
| `AttachDisk` / `DetachDisk` | `Operation` | async | `POST …/{id}:attachDisk` \| `:detachDisk` |
| `AttachNetworkInterface` / `DetachNetworkInterface` | `Operation` | async | `POST …/{id}:attachNetworkInterface` \| `:detachNetworkInterface` |
| `AddOneToOneNat` / `RemoveOneToOneNat` | `Operation` | async | `POST …/{id}/addOneToOneNat` \| `/removeOneToOneNat` |
| `UpdateNetworkInterface` | `Operation` | async | `PATCH …/{id}/updateNetworkInterface` |
| `Relocate` | `Operation` | async | `POST …/{id}:relocate` |
| `SimulateMaintenanceEvent` | `Operation` | async | `POST …/{id}:simulateMaintenanceEvent` |
| `ListOperations` | `ListInstanceOperationsResponse` | sync | `GET …/{id}/operations` |
| `ListAccessBindings` | `access.ListAccessBindingsResponse` | sync | `GET …/{resource_id}:listAccessBindings` |
| `SetAccessBindings` / `UpdateAccessBindings` | `Operation` | async | `POST …/{resource_id}:setAccessBindings` \| `:updateAccessBindings` |

Форма выдержана: чтение синхронно, **любая** мутация возвращает `Operation` (ban #9).

## Отношения и scope (из `kacho.iam.authz.v1` в том же proto)

- `Get` → `compute.instances.get`, отношение `v_get`;
- `List` → `compute.instanceses.list`, отношение `viewer`;
- `GetSerialPortOutput` → `v_get`; `ListOperations` → `v_list`;
  `ListAccessBindings` → `viewer`.

Мутации записей `permission`/`required_relation` в самом proto не несут — их гейт
описан записями каталога прав на стороне сервиса и края
(`services/compute/internal/…/permission_map.go` и встроенная копия каталога у gateway;
`make -C gateway permission-catalog-check` роняет сборку при расхождении копий).

## Соседи по рантайму

`compute → geo` (валидация `zone_id`), `compute → vpc` (NIC/подсеть/IPAM, привязка через
internal-ручку vpc), `compute → storage` (boot-источник, attach/detach тома),
`compute → iam` (`ProjectService.Get`, `InternalIAMService.Check`, регистрация владельца).
Обратно compute не зовут — ацикличность держится.

## Gotcha

- **`InternalInstanceService` не существует.** Из internal-поверхности compute живы
  `InternalMachineTypeService` и `InternalWatchService`. Двухпроекционный
  `GetInternal` для Instance — замысел COMP-4, а не контракт.
- **`Relocate` и `SimulateMaintenanceEvent`** живут на публичной поверхности; их
  метаданные — `RelocateInstanceMetadata`, `SimulateInstanceMaintenanceEventMetadata`.
- **Attach-состояние принадлежит владельцу**, а не compute: том — у storage
  (`volume_attachments`), NIC — у vpc (`network_interfaces.used_by_*`). На Instance это
  read-only зеркало, которое обязано грациозно переживать висячую ссылку.

## См. также

[[../resources/compute-instance]] · [[compute-machinetype-service]] · [[vpc-internal-network-interface-service]] · [[../resources/vpc-networkinterface]]

#rpc #kacho-compute #compute
