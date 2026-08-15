---
title: vpc-apps-kacho-api-addresspool
category: packages
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - addresspool
  - admin
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога против перечня RPC в proto домена; текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/api/addresspool

**Каталог**: `services/vpc/internal/apps/kacho/api/addresspool/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/api/addresspool/`)
**Implements**: [[../rpc/vpc-internal-address-pool-service|InternalAddressPoolService]]

Admin-only — все RPC только на internal-listener (9091).

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | CIDR validation, family check |
| `create.go` | split v4/v6 (KAC-71 миграция 0022); zone validate |
| `update.go` | replace_cidrs семантика |
| `delete.go` | RESTRICT если есть active bindings |
| `get.go` / `list.go` | std |
| `bindings.go` | `BindAsNetworkDefault` / `UnbindNetworkDefault` — привязка пула как умолчания сети. Парной привязки «на конкретный адрес» здесь больше нет (см. предупреждение ниже) |
| `resolve.go` | `ResolverService` — каскад-резолв пула. **Не RPC**: движок, который зовут напрямую use-case'ы адреса (через порт в их `iface.go`), когда `Address.Create`/`Allocate*IP` выясняют, из какого пула брать IP |
| `add_cidr_blocks.go` / `remove_cidr_blocks.go` | правка набора CIDR пула отдельными RPC |
| `utilization.go` | `GetUtilization` — free/used count per CIDR |
| `*_test.go` | unit-тесты пакета |

> [!warning] Двух файлов из прежней редакции нет — и соответствующих RPC тоже нет
> Записка называла файл под «быструю проверку доступности пула» и файл под «трассировку
> цепочки резолва для отладки». Ни того, ни другого в каталоге нет, и это не переезд:
> в контракте домена (`proto/kacho/cloud/vpc/v1/internal_address_pool_service.proto`)
> **нет соответствующих RPC**, поэтому и файлов быть не может. Полный перечень методов — `Create`, `Get`,
> `List`, `Update`, `Delete`, `AddCidrBlocks`, `RemoveCidrBlocks`, `BindAsNetworkDefault`,
> `UnbindNetworkDefault`, `ListAddresses`, `GetUtilization` — одиннадцать, и оба
> названных среди них не значатся.
>
> Каскад резолва в записке тоже описан по снятой схеме: ступени «per-Address» и
> «cloud-selector» **удалены миграцией** `services/vpc/internal/migrations/0002_drop_override_and_cloud_pool_selector.sql`
> вместе со своими таблицами. Действующий каскад — network-default → zone-default →
> global-default (см. [[vpc-repo-kacho]], где снята и соответствующая пара портов).

## See also

[[../rpc/vpc-internal-address-pool-service]] [[../resources/vpc-addresspool]] [[../rpc/vpc-internal-cloud-service]]

#packages #kacho-vpc #handler #addresspool #admin
