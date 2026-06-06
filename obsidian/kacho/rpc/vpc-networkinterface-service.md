---
title: NetworkInterfaceService
aliases:
  - NetworkInterfaceService (vpc)
  - NIC Service
proto_file: kacho/cloud/vpc/v1/network_interface_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-networkinterface]]"
methods_count: 6
async_methods: 3
tags:
  - rpc
  - kacho-vpc
  - ni
---

# NetworkInterfaceService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/network_interface_service.proto`
**Backend**: `kacho-vpc:9090`
**Public/Internal**: public

NIC — first-class ресурс (AWS-ENI-стиль, **расходимся** с YC где NIC inline в Instance). Эпик KAC-2.

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetNetworkInterfaceRequest | NetworkInterface | sync | |
| List | ListNetworkInterfacesRequest | ListNetworkInterfacesResponse | sync | |
| Create | CreateNetworkInterfaceRequest | operation.Operation | **async** | subnet+SG validation |
| Update | UpdateNetworkInterfaceRequest | operation.Operation | **async** | name/labels/desc/sg-list |
| Delete | DeleteNetworkInterfaceRequest | operation.Operation | **async** | FailedPrecondition если `used_by_id` непустой |
| ListOperations | ListNetworkInterfaceOperationsRequest | ListNetworkInterfaceOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /vpc/v1/networkInterfaces/{network_interface_id}` | Get |
| `GET /vpc/v1/networkInterfaces` | List |
| `POST /vpc/v1/networkInterfaces` | Create |
| `PATCH /vpc/v1/networkInterfaces/{network_interface_id}` | Update |
| `DELETE /vpc/v1/networkInterfaces/{network_interface_id}` | Delete |
| `GET /vpc/v1/networkInterfaces/{network_interface_id}/operations` | ListOperations |

## Attach/Detach RPC — REMOVED (KAC-266)

> [!warning] `AttachToInstance` / `DetachFromInstance` удалены в [[KAC-266]]
> Публичные RPC + `:attach`/`:detach` REST-маршруты сняты (contract-removal). `used_by_id`
> больше **не** выставляется этими методами. Инстанс создаётся **без авто-NIC** (compute
> `materializeNICs` удалён, см. [[../edges/compute-to-vpc-nic-validate]]). NIC остаётся
> first-class CRUD-ресурсом. CAS-история ниже — archeology.

См. `internal/repo/network_interface_attach_race_integration_test.go` (KAC-52). Старый софт-`if used_by_id != ""` был race-prone — заменялся на single-statement CAS:
```sql
UPDATE network_interfaces SET used_by_id = $new
 WHERE id = $id AND (used_by_id = '' OR used_by_id = $new)
RETURNING ...
```

## Internal NIS (removed)

Прежняя internal data-plane-проекция NIC и writeback-RPC (kube-ovn-эпоха) **удалены в KAC-36/79/80** и в proto никогда не commit'нулись. Публичный `NetworkInterfaceService` — живой. См. [[vpc-internal-network-interface-service]].

## See also

[[../packages/vpc-apps-kacho-api-networkinterface]] [[../resources/vpc-networkinterface]] [[../edges/compute-to-vpc-nic-validate]] [[../edges/vpc-implement-to-vpc]]

#rpc #kacho-vpc #ni
