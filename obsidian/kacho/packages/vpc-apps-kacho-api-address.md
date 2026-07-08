---
title: vpc-apps-kacho-api-address
category: package
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - address
  - ipam
  - race-fix
---

# kacho-vpc/internal/apps/kacho/api/address

**Path**: `kacho-vpc/internal/apps/kacho/api/address/`
**Implements**: [[../rpc/vpc-address-service|AddressService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports (AddressRepo + AddressPoolReader для IPAM) |
| `helpers.go` | address-value validation, IPv4/v6 parsing |
| `create.go` | IPAM-allocate (external/internal v4/v6); pool-resolution chain |
| `allocate.go` | dedicated allocate-from-pool path (low-level) |
| `update.go` | name/labels/desc/reserved-flag |
| `delete.go` | check `used_by == ''` |
| `get.go` | sync; lookup by id or by-value |
| `list.go` | filter + list-by-subnet |
| `move.go` | cross-folder |
| `usecase_test.go` | |

## Gotcha — nested reader-conn под held writer-TX (race-fix, PR #41)

`AllocateUseCase` больше НЕ держит `SubnetReader`-порт. Internal-IPAM путь
(`alloc_shared.go` `allocateInternalV{4,6}IntoTx`) читает subnet через **собственную
TX writer'а** (`w.Subnets().Get`), НЕ через второй pool-conn. Отдельный reader-conn
под уже-держащимся writer-conn = nested-conn deadlock под нагрузкой: `pool.MaxConns`
исчерпан writer'ами → каждый ждёт reader-conn, которого нет; `FOR UPDATE` row-lock
queue → `statement_timeout` (SQLSTATE 57014). Зеркалит external-путь (пул резолвится
ДО writer-TX). **Не возвращать `SubnetReader` в `AllocateUseCase`.** SubnetReader
остаётся в `CreateAddressUseCase` (external pre-checks — чтение ДО writer-TX) и
`ListBySubnetUseCase`. Reproduce: N ≥ pool.MaxConns concurrent `AllocateInternalIP`
(CI 2-core → MaxConns=4; локально `taskset -c 0,1`). Regression:
`TestAllocateInternalIP{,v6}_ConcurrentIdempotent` (`-race`).

## See also

[[../rpc/vpc-address-service]] [[../rpc/vpc-internal-address-service]] [[../resources/vpc-address]] [[vpc-apps-kacho-services-addressref]]

#packages #kacho-vpc #handler #address #ipam
