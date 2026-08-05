---
title: vpc-apps-kacho-api-subnet
category: packages
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - subnet
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога против перечня RPC в proto домена; текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/api/subnet

**Каталог**: `services/vpc/internal/apps/kacho/api/subnet/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/api/subnet/`)
**Implements**: [[../rpc/vpc-subnet-service|SubnetService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | CIDR validation, host-bits check |
| `create.go` | EXCLUDE-constraint catch (SQLSTATE 23P01 → FailedPrecondition) |
| `delete.go` | RESTRICT-FK check via repo error mapping |
| `update.go` | name/labels/desc; CIDR — separate RPCs |
| `add_cidr_blocks.go` | extra v4/v6 CIDRs (KAC-71) |
| `remove_cidr_blocks.go` | sub'subnet check (no Address in removed CIDR) |
| `get.go` | sync |
| `list.go` | filter + pagination |
| `list_used_addresses.go` | IPAM-utilization (sync) |
| `*_test.go` | unit-тесты пакета |

> [!warning] Перемещения подсети — ни между проектами, ни между зонами — не существует
> Записка называла два файла: один под перенос в другой контейнер, другой под смену зоны.
> Ни одного из них в каталоге нет, и RPC под них в контракте домена тоже нет. Полный
> перечень методов `SubnetService` — `Get`, `List`, `Create`, `Update`, `AddCidrBlocks`,
> `RemoveCidrBlocks`, `Delete`, `ListOperations`, `ListUsedAddresses`: девять, и ни один
> не переносит подсеть.
>
> Это не пропуск, а следствие модели размещения: подсеть — **якорь** placement'а
> (`placement_type` ∈ ZONAL/REGIONAL, закреплено DB-CHECK), а адреса и интерфейсы
> наследуют зону через неё. Сменить зону подсети значило бы разом рассогласовать всё,
> что на неё ссылается, — поэтому операции нет, а не «пока не сделана».
>
> Второй слой ошибки — в скобке: валидация зоны идёт **не через compute**. Geography
> вынесена в отдельный домен (эпик #82), и подсеть проверяет `zone_id` peer-вызовом к
> geo — см. [[../edges/vpc-to-geo-zone-validate]]. Ребра «vpc → compute ради зоны»
> в графе больше нет.

## See also

[[../rpc/vpc-subnet-service]] [[../resources/vpc-subnet]] [[../edges/vpc-to-geo-zone-validate]]

#packages #kacho-vpc #handler #subnet
